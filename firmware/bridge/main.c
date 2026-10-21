// Bridge board: plugs into the Controller Mac as a USB serial port and
// passes bytes through to/from the target board over the UART link.
// It does not parse frames; the target validates everything.
#include "pico/stdlib.h"
#include "tusb.h"
#include "link.h"
#include "protocol.h"

int main(void) {
    tusb_init();
    link_init(SHD_LINK_BAUD);

    while (true) {
        tud_task();

        uint8_t buf[64];

        // app -> target
        if (tud_cdc_available()) {
            uint32_t n = tud_cdc_read(buf, sizeof(buf));
            link_write(buf, n);
        }

        // target -> app
        size_t n = 0;
        uint8_t c;
        while (n < sizeof(buf) && link_getc(&c)) buf[n++] = c;
        if (n && tud_cdc_connected()) {
            tud_cdc_write(buf, (uint32_t)n);
            tud_cdc_write_flush();
        }
    }
}

// App closed the port: make sure nothing stays pressed on the Sharer Mac
void tud_cdc_line_state_cb(uint8_t itf, bool dtr, bool rts) {
    (void)itf; (void)rts;
    if (!dtr) {
        uint8_t frame[SHD_MAX_FRAME];
        link_write(frame, shd_encode(SHD_RELEASE_ALL, NULL, 0, frame));
    }
}
