#include <string.h>
#include "protocol.h"

enum { ST_SOF, ST_TYPE, ST_LEN, ST_PAYLOAD, ST_CRC };

uint8_t shd_crc8(uint8_t crc, uint8_t byte) {
    crc ^= byte;
    for (int i = 0; i < 8; i++)
        crc = (crc & 0x80) ? (uint8_t)((crc << 1) ^ 0x07) : (uint8_t)(crc << 1);
    return crc;
}

size_t shd_encode(uint8_t type, const uint8_t *payload, uint8_t len, uint8_t *out) {
    if (len > SHD_MAX_PAYLOAD) len = SHD_MAX_PAYLOAD;
    out[0] = SHD_SOF;
    out[1] = type;
    out[2] = len;
    if (len) memcpy(&out[3], payload, len);
    uint8_t crc = 0;
    for (size_t i = 1; i < 3u + len; i++) crc = shd_crc8(crc, out[i]);
    out[3 + len] = crc;
    return 4u + len;
}

void shd_parser_init(shd_parser_t *p) {
    memset(p, 0, sizeof(*p));
    p->state = ST_SOF;
}

bool shd_parser_feed(shd_parser_t *p, uint8_t b) {
    switch (p->state) {
    case ST_SOF:
        if (b == SHD_SOF) p->state = ST_TYPE;
        return false;
    case ST_TYPE:
        p->frame.type = b;
        p->crc = shd_crc8(0, b);
        p->state = ST_LEN;
        return false;
    case ST_LEN:
        if (b > SHD_MAX_PAYLOAD) {
            p->state = ST_SOF;
            return false;
        }
        p->frame.len = b;
        p->crc = shd_crc8(p->crc, b);
        p->idx = 0;
        p->state = b ? ST_PAYLOAD : ST_CRC;
        return false;
    case ST_PAYLOAD:
        p->frame.payload[p->idx++] = b;
        p->crc = shd_crc8(p->crc, b);
        if (p->idx == p->frame.len) p->state = ST_CRC;
        return false;
    case ST_CRC:
    default:
        p->state = ST_SOF;
        return b == p->crc;
    }
}
