#include <string.h>
#include "pico/unique_id.h"
#include "tusb.h"
#include "config.h"
#include "usb_descriptors.h"

//--------------------------------------------------------------------
// Device descriptor
//--------------------------------------------------------------------

static tusb_desc_device_t const desc_device = {
    .bLength            = sizeof(tusb_desc_device_t),
    .bDescriptorType    = TUSB_DESC_DEVICE,
    .bcdUSB             = 0x0200,
    .bDeviceClass       = 0x00,
    .bDeviceSubClass    = 0x00,
    .bDeviceProtocol    = 0x00,
    .bMaxPacketSize0    = CFG_TUD_ENDPOINT0_SIZE,
    .idVendor           = SHD_USB_VID,
    .idProduct          = SHD_USB_PID,
    .bcdDevice          = 0x0101,
    .iManufacturer      = 0x01,
    .iProduct           = 0x02,
    .iSerialNumber      = 0x03,
    .bNumConfigurations = 0x01,
};

uint8_t const *tud_descriptor_device_cb(void) {
    return (uint8_t const *)&desc_device;
}

//--------------------------------------------------------------------
// HID report descriptors
//--------------------------------------------------------------------

static uint8_t const desc_hid_keyboard[] = {
    TUD_HID_REPORT_DESC_KEYBOARD()
};

// Absolute mouse report (7 bytes after the report ID):
//   u8 buttons (5 bits), u16 x, u16 y (0..32767), i8 wheel, i8 pan
#define DESC_ABS_MOUSE(rid)                                         \
    0x05, 0x01,       /* Usage Page (Generic Desktop)            */ \
    0x09, 0x02,       /* Usage (Mouse)                           */ \
    0xA1, 0x01,       /* Collection (Application)                */ \
    0x85, (rid),      /*   Report ID                             */ \
    0x09, 0x01,       /*   Usage (Pointer)                       */ \
    0xA1, 0x00,       /*   Collection (Physical)                 */ \
    0x05, 0x09,       /*     Usage Page (Button)                 */ \
    0x19, 0x01,       /*     Usage Minimum (1)                   */ \
    0x29, 0x05,       /*     Usage Maximum (5)                   */ \
    0x15, 0x00,       /*     Logical Minimum (0)                 */ \
    0x25, 0x01,       /*     Logical Maximum (1)                 */ \
    0x95, 0x05,       /*     Report Count (5)                    */ \
    0x75, 0x01,       /*     Report Size (1)                     */ \
    0x81, 0x02,       /*     Input (Data, Var, Abs)              */ \
    0x95, 0x01,       /*     Report Count (1)                    */ \
    0x75, 0x03,       /*     Report Size (3)                     */ \
    0x81, 0x03,       /*     Input (Const) padding               */ \
    0x05, 0x01,       /*     Usage Page (Generic Desktop)        */ \
    0x09, 0x30,       /*     Usage (X)                           */ \
    0x09, 0x31,       /*     Usage (Y)                           */ \
    0x15, 0x00,       /*     Logical Minimum (0)                 */ \
    0x26, 0xFF, 0x7F, /*     Logical Maximum (32767)             */ \
    0x75, 0x10,       /*     Report Size (16)                    */ \
    0x95, 0x02,       /*     Report Count (2)                    */ \
    0x81, 0x02,       /*     Input (Data, Var, Abs)              */ \
    0x09, 0x38,       /*     Usage (Wheel)                       */ \
    0x15, 0x81,       /*     Logical Minimum (-127)              */ \
    0x25, 0x7F,       /*     Logical Maximum (127)               */ \
    0x75, 0x08,       /*     Report Size (8)                     */ \
    0x95, 0x01,       /*     Report Count (1)                    */ \
    0x81, 0x06,       /*     Input (Data, Var, Rel)              */ \
    0x05, 0x0C,       /*     Usage Page (Consumer)               */ \
    0x0A, 0x38, 0x02, /*     Usage (AC Pan)                      */ \
    0x95, 0x01,       /*     Report Count (1)                    */ \
    0x81, 0x06,       /*     Input (Data, Var, Rel)              */ \
    0xC0,             /*   End Collection                        */ \
    0xC0              /* End Collection                          */

// The absolute mouse gets its own interface: macOS ignores the buttons of an absolute pointer
// that shares an interface with a relative one.
static uint8_t const desc_hid_abs[] = {
    DESC_ABS_MOUSE(RID_MOUSE_ABS),
};

static uint8_t const desc_hid_mouse[] = {
    TUD_HID_REPORT_DESC_MOUSE(HID_REPORT_ID(RID_MOUSE_REL)),
    TUD_HID_REPORT_DESC_CONSUMER(HID_REPORT_ID(RID_CONSUMER)),
};

uint8_t const *tud_hid_descriptor_report_cb(uint8_t instance) {
    switch (instance) {
    case HID_INST_KEYBOARD: return desc_hid_keyboard;
    case HID_INST_ABS:      return desc_hid_abs;
    default:                return desc_hid_mouse;
    }
}

//--------------------------------------------------------------------
// Configuration descriptor
//--------------------------------------------------------------------

enum { ITF_NUM_KEYBOARD, ITF_NUM_MOUSE, ITF_NUM_ABS, ITF_NUM_TOTAL };

#define EPNUM_KEYBOARD    0x81
#define EPNUM_MOUSE       0x82
#define EPNUM_ABS         0x83
#define CONFIG_TOTAL_LEN  (TUD_CONFIG_DESC_LEN + 3 * TUD_HID_DESC_LEN)

static uint8_t const desc_configuration[] = {
    TUD_CONFIG_DESCRIPTOR(1, ITF_NUM_TOTAL, 0, CONFIG_TOTAL_LEN, TUSB_DESC_CONFIG_ATT_REMOTE_WAKEUP, 100),
    TUD_HID_DESCRIPTOR(ITF_NUM_KEYBOARD, 0, HID_ITF_PROTOCOL_KEYBOARD, sizeof(desc_hid_keyboard),
                       EPNUM_KEYBOARD, CFG_TUD_HID_EP_BUFSIZE, 1),
    TUD_HID_DESCRIPTOR(ITF_NUM_MOUSE, 0, HID_ITF_PROTOCOL_NONE, sizeof(desc_hid_mouse),
                       EPNUM_MOUSE, CFG_TUD_HID_EP_BUFSIZE, 1),
    TUD_HID_DESCRIPTOR(ITF_NUM_ABS, 0, HID_ITF_PROTOCOL_NONE, sizeof(desc_hid_abs),
                       EPNUM_ABS, CFG_TUD_HID_EP_BUFSIZE, 1),
};

uint8_t const *tud_descriptor_configuration_cb(uint8_t index) {
    (void)index;
    return desc_configuration;
}

//--------------------------------------------------------------------
// String descriptors
//--------------------------------------------------------------------

enum { STRID_LANGID, STRID_MANUFACTURER, STRID_PRODUCT, STRID_SERIAL };

static uint16_t desc_str[33];

uint16_t const *tud_descriptor_string_cb(uint8_t index, uint16_t langid) {
    (void)langid;
    char serial[2 * PICO_UNIQUE_BOARD_ID_SIZE_BYTES + 1];
    const char *str;
    size_t chr_count;

    switch (index) {
    case STRID_LANGID:
        desc_str[1] = 0x0409; // English (US)
        chr_count = 1;
        goto done;
    case STRID_MANUFACTURER: str = SHD_USB_MANUFACTURER; break;
    case STRID_PRODUCT:      str = SHD_USB_PRODUCT; break;
    case STRID_SERIAL:
        pico_get_unique_board_id_string(serial, sizeof(serial));
        str = serial;
        break;
    default:
        return NULL;
    }

    chr_count = strlen(str);
    if (chr_count > 32) chr_count = 32;
    for (size_t i = 0; i < chr_count; i++) desc_str[1 + i] = (uint8_t)str[i];

done:
    desc_str[0] = (uint16_t)((TUSB_DESC_STRING << 8) | (2 * chr_count + 2));
    return desc_str;
}
