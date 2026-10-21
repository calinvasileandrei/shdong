// Wire protocol between controller app, bridge board and target board.
//
// Frame: [SOF 0xAA][type][len][payload: len bytes][crc8]
// CRC-8 (poly 0x07, init 0x00) covers type, len and payload.
// Multi-byte fields are little-endian.
#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define SHD_PROTO_VERSION 1
#define SHD_LINK_BAUD     1000000

#define SHD_SOF           0xAA
#define SHD_MAX_PAYLOAD   32
#define SHD_MAX_FRAME     (SHD_MAX_PAYLOAD + 4)

enum shd_type {
    // controller -> target
    SHD_KEY         = 0x01, // u8 hid_usage, u8 pressed
    SHD_MOUSE_ABS   = 0x02, // u16 x, u16 y (0..32767), u8 buttons, i8 wheel, i8 pan
    SHD_MOUSE_REL   = 0x03, // i16 dx, i16 dy, u8 buttons, i8 wheel, i8 pan
    SHD_CONSUMER    = 0x04, // u16 usage, u8 pressed
    SHD_RELEASE_ALL = 0x05, // (empty)
    SHD_PING        = 0x10, // u32 token

    // target -> controller
    SHD_PONG        = 0x11, // u32 token, u8 proto_version, u8 kbd_leds, u8 usb_mounted
    SHD_STATUS      = 0x12, // u8 kbd_leds, u8 usb_mounted
};

typedef struct {
    uint8_t type;
    uint8_t len;
    uint8_t payload[SHD_MAX_PAYLOAD];
} shd_frame_t;

typedef struct {
    uint8_t state;
    uint8_t idx;
    uint8_t crc;
    shd_frame_t frame;
} shd_parser_t;

uint8_t shd_crc8(uint8_t crc, uint8_t byte);

// Writes a complete frame to out (must hold SHD_MAX_FRAME bytes). Returns its length.
size_t shd_encode(uint8_t type, const uint8_t *payload, uint8_t len, uint8_t *out);

void shd_parser_init(shd_parser_t *p);

// Feeds one byte. Returns true when p->frame holds a complete, valid frame.
bool shd_parser_feed(shd_parser_t *p, uint8_t byte);

static inline uint16_t shd_rd16(const uint8_t *p) { return (uint16_t)(p[0] | (p[1] << 8)); }
static inline uint32_t shd_rd32(const uint8_t *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}
static inline void shd_wr16(uint8_t *p, uint16_t v) { p[0] = (uint8_t)v; p[1] = (uint8_t)(v >> 8); }
