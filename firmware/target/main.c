// Target board: plugs into the Sharer Mac and acts as a USB keyboard + mouse.
// Receives input frames over the UART link and turns them into HID reports.
#include <string.h>
#include "pico/stdlib.h"
#include "tusb.h"
#include "config.h"
#include "link.h"
#include "protocol.h"
#include "usb_descriptors.h"

//--------------------------------------------------------------------
// Report queue: every state change becomes one HID report, so a quick
// press+release is never collapsed away. Pure mouse moves are coalesced.
//--------------------------------------------------------------------

typedef struct {
    uint8_t instance;
    uint8_t report_id;
    uint8_t len;
    uint8_t data[8];
} pending_report_t;

#define QUEUE_SIZE 64

static pending_report_t queue[QUEUE_SIZE];
static uint8_t q_head, q_tail;

static bool queue_empty(void) { return q_head == q_tail; }

static pending_report_t *queue_last(void) {
    return queue_empty() ? NULL : &queue[(q_head + QUEUE_SIZE - 1) % QUEUE_SIZE];
}

static void queue_push(uint8_t instance, uint8_t report_id, const uint8_t *data, uint8_t len) {
    uint8_t next = (q_head + 1) % QUEUE_SIZE;
    if (next == q_tail) return; // full: drop newest, the link timeout will release anything stuck
    pending_report_t *r = &queue[q_head];
    r->instance = instance;
    r->report_id = report_id;
    r->len = len;
    memcpy(r->data, data, len);
    q_head = next;
}

//--------------------------------------------------------------------
// Input state
//--------------------------------------------------------------------

static uint8_t kbd_modifiers;
static uint8_t kbd_keys[6];
static uint8_t mouse_buttons;
static uint16_t consumer_usage;
static uint8_t kbd_leds;
static uint32_t last_rx_ms;

static void link_send(uint8_t type, const uint8_t *payload, uint8_t len) {
    uint8_t buf[SHD_MAX_FRAME];
    link_write(buf, shd_encode(type, payload, len, buf));
}

static void send_status(void) {
    uint8_t p[2] = { kbd_leds, tud_mounted() };
    link_send(SHD_STATUS, p, sizeof(p));
}

static void push_keyboard(void) {
    uint8_t r[8] = { kbd_modifiers, 0 };
    memcpy(&r[2], kbd_keys, 6);
    queue_push(HID_INST_KEYBOARD, 0, r, sizeof(r));
}

static void push_mouse_rel(int16_t dx, int16_t dy, int8_t wheel, int8_t pan) {
    // HID relative fields are i8; split large moves into several reports
    do {
        int8_t sx = (int8_t)(dx > 127 ? 127 : dx < -127 ? -127 : dx);
        int8_t sy = (int8_t)(dy > 127 ? 127 : dy < -127 ? -127 : dy);
        uint8_t r[5] = { mouse_buttons, (uint8_t)sx, (uint8_t)sy, (uint8_t)wheel, (uint8_t)pan };
        queue_push(HID_INST_MOUSE, RID_MOUSE_REL, r, sizeof(r));
        dx -= sx;
        dy -= sy;
        wheel = pan = 0;
    } while (dx || dy);
}

static void push_consumer(void) {
    uint8_t r[2];
    shd_wr16(r, consumer_usage);
    queue_push(HID_INST_MOUSE, RID_CONSUMER, r, sizeof(r));
}

static bool anything_held(void) {
    if (kbd_modifiers || mouse_buttons || consumer_usage) return true;
    for (int i = 0; i < 6; i++)
        if (kbd_keys[i]) return true;
    return false;
}

static void release_all(void) {
    kbd_modifiers = 0;
    memset(kbd_keys, 0, sizeof(kbd_keys));
    mouse_buttons = 0;
    consumer_usage = 0;
    push_keyboard();
    push_mouse_rel(0, 0, 0, 0);
    push_consumer();
}

static void on_key(uint8_t usage, bool pressed) {
    if (usage >= HID_KEY_CONTROL_LEFT && usage <= HID_KEY_GUI_RIGHT) {
        uint8_t bit = (uint8_t)(1u << (usage - HID_KEY_CONTROL_LEFT));
        if (pressed) kbd_modifiers |= bit;
        else kbd_modifiers &= (uint8_t)~bit;
    } else if (usage == HID_KEY_NONE) {
        return;
    } else if (pressed) {
        int free_slot = -1;
        for (int i = 0; i < 6; i++) {
            if (kbd_keys[i] == usage) return; // already down
            if (!kbd_keys[i] && free_slot < 0) free_slot = i;
        }
        if (free_slot < 0) return; // 6-key rollover limit
        kbd_keys[free_slot] = usage;
    } else {
        for (int i = 0; i < 6; i++)
            if (kbd_keys[i] == usage) kbd_keys[i] = 0;
    }
    push_keyboard();
}

static void on_mouse_abs(const uint8_t *p) {
    uint16_t x = shd_rd16(&p[0]);
    uint16_t y = shd_rd16(&p[2]);
    if (x > 32767) x = 32767;
    if (y > 32767) y = 32767;
    mouse_buttons = p[4] & 0x1F;
    uint8_t r[7] = { mouse_buttons, (uint8_t)x, (uint8_t)(x >> 8), (uint8_t)y, (uint8_t)(y >> 8), p[5], p[6] };

    // Coalesce plain moves into the last queued move with the same buttons
    pending_report_t *last = queue_last();
    if (last && last->instance == HID_INST_ABS &&
        last->data[0] == r[0] && !last->data[5] && !last->data[6] && !r[5] && !r[6]) {
        memcpy(last->data, r, sizeof(r));
        return;
    }
    queue_push(HID_INST_ABS, RID_MOUSE_ABS, r, sizeof(r));
}

static void on_frame(const shd_frame_t *f) {
    const uint8_t *p = f->payload;
    switch (f->type) {
    case SHD_KEY:
        if (f->len >= 2) on_key(p[0], p[1] != 0);
        break;
    case SHD_MOUSE_ABS:
        if (f->len >= 7) on_mouse_abs(p);
        break;
    case SHD_MOUSE_REL:
        if (f->len >= 7) {
            mouse_buttons = p[4] & 0x1F;
            push_mouse_rel((int16_t)shd_rd16(&p[0]), (int16_t)shd_rd16(&p[2]), (int8_t)p[5], (int8_t)p[6]);
        }
        break;
    case SHD_CONSUMER:
        if (f->len >= 3) {
            consumer_usage = p[2] ? shd_rd16(p) : 0;
            push_consumer();
        }
        break;
    case SHD_RELEASE_ALL:
        release_all();
        break;
    case SHD_PING:
        if (f->len >= 4) {
            uint8_t r[7] = { p[0], p[1], p[2], p[3], SHD_PROTO_VERSION, kbd_leds, tud_mounted() };
            link_send(SHD_PONG, r, sizeof(r));
        }
        break;
    default:
        break;
    }
}

//--------------------------------------------------------------------
// Main loop
//--------------------------------------------------------------------

static void send_next_report(void) {
    static uint32_t last_wakeup_ms;

    if (queue_empty()) return;
    if (!tud_mounted()) {
        q_tail = q_head; // nobody listening
        return;
    }
    if (tud_suspended()) {
        // Input while the Mac sleeps: ask it to wake up (at most every 500 ms)
        uint32_t now = to_ms_since_boot(get_absolute_time());
        if (now - last_wakeup_ms > 500) {
            last_wakeup_ms = now;
            tud_remote_wakeup();
        }
        return;
    }

    pending_report_t *r = &queue[q_tail];
    if (!tud_hid_n_ready(r->instance)) return;
    tud_hid_n_report(r->instance, r->report_id, r->data, r->len);
    q_tail = (q_tail + 1) % QUEUE_SIZE;
}

int main(void) {
    shd_parser_t parser;

    tusb_init();
    link_init(SHD_LINK_BAUD);
    shd_parser_init(&parser);

    while (true) {
        tud_task();

        uint8_t c;
        while (link_getc(&c)) {
            if (shd_parser_feed(&parser, c)) {
                last_rx_ms = to_ms_since_boot(get_absolute_time());
                on_frame(&parser.frame);
            }
        }

        // Failsafe: controller unplugged or app crashed while something was held
        if (anything_held() && to_ms_since_boot(get_absolute_time()) - last_rx_ms > SHD_LINK_TIMEOUT_MS)
            release_all();

        send_next_report();
    }
}

//--------------------------------------------------------------------
// TinyUSB callbacks
//--------------------------------------------------------------------

void tud_mount_cb(void) { send_status(); }
void tud_umount_cb(void) { send_status(); }

uint16_t tud_hid_get_report_cb(uint8_t instance, uint8_t report_id, hid_report_type_t report_type,
                               uint8_t *buffer, uint16_t reqlen) {
    (void)instance; (void)report_id; (void)report_type; (void)buffer; (void)reqlen;
    return 0;
}

void tud_hid_set_report_cb(uint8_t instance, uint8_t report_id, hid_report_type_t report_type,
                           uint8_t const *buffer, uint16_t bufsize) {
    (void)report_id;
    // Keyboard LED state (Caps Lock etc.) from the Mac
    if (instance == HID_INST_KEYBOARD && report_type == HID_REPORT_TYPE_OUTPUT && bufsize >= 1) {
        kbd_leds = buffer[0];
        send_status();
    }
}
