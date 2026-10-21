// UART link between the two boards: UART0, TX = GP0, RX = GP1.
#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

void link_init(uint32_t baud);
bool link_getc(uint8_t *c);
void link_write(const uint8_t *data, size_t len);
