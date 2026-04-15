#include "../../drivers/uart.h"
#include "../../drivers/irq.h"
#include <stdint.h>

// -------------------------------------------------------------------------
// Hardware Memory Map — use dereferenced macros so the synthesizer
// cannot eliminate the fabric connections as dead logic
// -------------------------------------------------------------------------
#define ACCEL_START_REG     (*((volatile uint32_t *)0x10009000))
#define ACCEL_LAYER_NUM_REG (*((volatile uint32_t *)0x10009004))
#define ACCEL_LAYER_BASE    ((volatile uint32_t *)0x10009008)
#define ACCEL_INPUT_BASE    ((volatile float    *)0x10009028)
#define ACCEL_DONE_REG      (*((volatile uint32_t *)0x10009210))
#define ACCEL_OUTPUT_BASE   ((volatile float    *)0x10009214)

#define INPUT_DIM       122
#define NUM_LAYERS      5
#define NUM_CLASSES     5
#define TOTAL_BYTES_TO_RECEIVE (INPUT_DIM * 4)   // 488

// Globals
volatile int count = 0;

typedef union {
    float   f;
    uint8_t bytes[4];
} float_bytes_t;

volatile float         input_array[INPUT_DIM] = {0};
volatile float_bytes_t rx_var;

uart uart0;

// Delay Function (64 NOPs)
void delay_64_nops() {
    for (volatile int n = 0; n < 64; n++) {
        __asm__ volatile ("nop");
    }
}

// Accelerator inference
//                      ↓ const volatile to safely accept both boot_input and input_array
int accel_infer(const volatile float *x)
{
    // Write layer topology
    ACCEL_LAYER_NUM_REG = NUM_LAYERS;
    uint32_t layer_configs[8] = {256, 128, 64, 32, NUM_CLASSES, 0, 0, 0};
    for (int i = 0; i < 8; i++)
        ACCEL_LAYER_BASE[i] = layer_configs[i];

    // Copy input vector into accelerator register file
    for (int i = 0; i < INPUT_DIM; i++)
        ACCEL_INPUT_BASE[i] = x[i];

    // Kick the accelerator
    ACCEL_START_REG = 1;

    // Loop until done
    while (ACCEL_DONE_REG == 0)
        ;

    // Clear start
    ACCEL_START_REG = 0;

    // Argmax over the 5 output scores
    int   best    = 0;
    float max_val = ACCEL_OUTPUT_BASE[0];
    for (int i = 1; i < NUM_CLASSES; i++) {
        float v = ACCEL_OUTPUT_BASE[i];
        if (v > max_val) { max_val = v; best = i; }
    }

    return best;
}

// -------------------------------------------------------------------------
// Main
// -------------------------------------------------------------------------
int main(void)
{
    SET_MTVEC_VECTOR_MODE();
    count = 0;

    uart_init(&uart0, (uint32_t *)0x10008010);

    // Boot-time hardcoded inference
    float boot_input[INPUT_DIM] = {
        0.000000f, 1.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f,
        0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f,
        0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f,
        0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f,
        0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f,
        0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f,
        0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f,
        0.000000f, 0.000000f, 0.000000f, 1.000000f, 0.000000f, 0.000000f, 0.000000f,
        0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f,
        0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f,
        0.000000f, 0.000000f, 0.000000f, 0.000000f, 1.000000f, 0.000000f, 0.000000f,
        0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f,
        -0.110249f, -0.007762f, -0.004919f, -0.014089f, -0.089486f, -0.007736f, -0.095076f,
        -0.027023f, -0.809262f, -0.011664f, -0.036652f, -0.024437f, -0.012385f, -0.026180f,
        -0.018610f, -0.041221f,  0.000000f, -0.002817f, -0.097531f,  1.265346f, -0.244204f,
        -0.637209f, -0.631929f,  2.746403f,  2.715365f, -1.412415f, -0.016930f, -0.374560f,
         0.734343f, -0.954389f, -1.071933f, -0.121485f, -0.480197f, -0.289103f, -0.639532f,
        -0.624871f,  2.874410f,  2.753914f
    };

    // ↓ Fixed: was accel_infer(boot_result) — uninitialized self-reference
    int boot_result = accel_infer(boot_input);
    uart_transmit_byte(&uart0, (uint8_t) boot_result);
    delay_64_nops();

    // Main loop: receive 488 bytes → infer → reply → repeat
    while (1)
    {
        // Reset counter and enable interrupts to start receiving
        count = 0;
        ENABLE_GLOBAL_IRQ();
        ENABLE_FAST_IRQ(0);

        // Wait until buffer is full (488 bytes)
        // The ISR will disable interrupts when done
        while (count < TOTAL_BYTES_TO_RECEIVE) {
            continue;
        }

        // --- Data Received ---
        // Run inference — no cast needed, signature now accepts const volatile float*
        int result = accel_infer(input_array);

        // Send result
        uart_transmit_byte(&uart0, (uint8_t) result);
        delay_64_nops();
    }

    return 0;
}

// -------------------------------------------------------------------------
// Interrupt handlers
// -------------------------------------------------------------------------
void mti_handler(void) {}
void exc_handler(void) {}
void mei_handler(void) {}
void msi_handler(void) {}

void fast_irq0_handler(void)
{
    char    *rx_ptr  = (char *)(uart0.base_addr) + UART_RX_ADDR_OFFSET;
    uint8_t  rx_byte = (uint8_t)(*rx_ptr);

    int c = count;
    rx_var.bytes[c % 4] = rx_byte;

    // Store float only when all 4 bytes of it have arrived
    if ((c % 4) == 3)
        input_array[c / 4] = rx_var.f;

    c++;

    if (c < TOTAL_BYTES_TO_RECEIVE) {
        count = c;
    } else {
        count = c;          // == TOTAL_BYTES_TO_RECEIVE, unblocks main loop
        DISABLE_GLOBAL_IRQ();
    }
}

void fast_irq1_handler(void) {}