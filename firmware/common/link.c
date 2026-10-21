#include "hardware/gpio.h"
#include "hardware/irq.h"
#include "hardware/uart.h"
#include "link.h"

#define LINK_UART    uart0
#define LINK_IRQ     UART0_IRQ
#define LINK_TX_PIN  0
#define LINK_RX_PIN  1

#define RX_BUF_SIZE  1024 // power of two
#define RX_BUF_MASK  (RX_BUF_SIZE - 1)

static volatile uint8_t rx_buf[RX_BUF_SIZE];
static volatile uint16_t rx_head, rx_tail;

static void on_uart_rx(void) {
    while (uart_is_readable(LINK_UART)) {
        uint8_t c = (uint8_t)uart_getc(LINK_UART);
        uint16_t next = (rx_head + 1) & RX_BUF_MASK;
        if (next != rx_tail) { // drop on overflow
            rx_buf[rx_head] = c;
            rx_head = next;
        }
    }
}

void link_init(uint32_t baud) {
    uart_init(LINK_UART, baud);
    gpio_set_function(LINK_TX_PIN, GPIO_FUNC_UART);
    gpio_set_function(LINK_RX_PIN, GPIO_FUNC_UART);
    gpio_pull_up(LINK_RX_PIN); // keep RX idle-high when the cable is unplugged
    uart_set_hw_flow(LINK_UART, false, false);
    uart_set_format(LINK_UART, 8, 1, UART_PARITY_NONE);
    uart_set_fifo_enabled(LINK_UART, true);

    irq_set_exclusive_handler(LINK_IRQ, on_uart_rx);
    irq_set_enabled(LINK_IRQ, true);
    uart_set_irq_enables(LINK_UART, true, false);
}

bool link_getc(uint8_t *c) {
    if (rx_head == rx_tail) return false;
    *c = rx_buf[rx_tail];
    rx_tail = (rx_tail + 1) & RX_BUF_MASK;
    return true;
}

void link_write(const uint8_t *data, size_t len) {
    uart_write_blocking(LINK_UART, data, len);
}
