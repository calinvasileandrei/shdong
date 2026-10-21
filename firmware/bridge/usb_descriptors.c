#include <string.h>
#include "pico/unique_id.h"
#include "tusb.h"

// pid.codes test VID/PID: fine for development, replace before shipping.
#define SHD_USB_VID          0x1209
#define SHD_USB_PID          0x0002
#define SHD_USB_MANUFACTURER "shdong"
#define SHD_USB_PRODUCT      "shdong bridge"

//--------------------------------------------------------------------
// Device descriptor (IAD, required for CDC)
//--------------------------------------------------------------------

static tusb_desc_device_t const desc_device = {
    .bLength            = sizeof(tusb_desc_device_t),
    .bDescriptorType    = TUSB_DESC_DEVICE,
    .bcdUSB             = 0x0200,
    .bDeviceClass       = TUSB_CLASS_MISC,
    .bDeviceSubClass    = MISC_SUBCLASS_COMMON,
    .bDeviceProtocol    = MISC_PROTOCOL_IAD,
    .bMaxPacketSize0    = CFG_TUD_ENDPOINT0_SIZE,
    .idVendor           = SHD_USB_VID,
    .idProduct          = SHD_USB_PID,
    .bcdDevice          = 0x0100,
    .iManufacturer      = 0x01,
    .iProduct           = 0x02,
    .iSerialNumber      = 0x03,
    .bNumConfigurations = 0x01,
};

uint8_t const *tud_descriptor_device_cb(void) {
    return (uint8_t const *)&desc_device;
}

//--------------------------------------------------------------------
// Configuration descriptor
//--------------------------------------------------------------------

enum { ITF_NUM_CDC, ITF_NUM_CDC_DATA, ITF_NUM_TOTAL };

#define EPNUM_CDC_NOTIF   0x81
#define EPNUM_CDC_OUT     0x02
#define EPNUM_CDC_IN      0x82
#define CONFIG_TOTAL_LEN  (TUD_CONFIG_DESC_LEN + TUD_CDC_DESC_LEN)

static uint8_t const desc_configuration[] = {
    TUD_CONFIG_DESCRIPTOR(1, ITF_NUM_TOTAL, 0, CONFIG_TOTAL_LEN, 0x00, 100),
    TUD_CDC_DESCRIPTOR(ITF_NUM_CDC, 0, EPNUM_CDC_NOTIF, 8, EPNUM_CDC_OUT, EPNUM_CDC_IN, 64),
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
