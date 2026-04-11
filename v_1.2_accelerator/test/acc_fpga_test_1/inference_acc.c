// ---- config: choose how your Dense weights are laid out ----
#ifndef USE_KERAS_LAYOUT
#define USE_KERAS_LAYOUT 1
#endif

#include "../../drivers/uart.h"
#include "../../drivers/irq.h"
#include <stdint.h>

// -------------------------------------------------------------------------
// Hardware Memory Map — Accelerator Registers
// -------------------------------------------------------------------------
#define ACCEL_START_REG     (*((volatile uint32_t *)0x10009000))
#define ACCEL_LAYER_NUM_REG (*((volatile uint32_t *)0x10009004))
#define ACCEL_LAYER_BASE    ((volatile uint32_t *)0x10009008)   // [0..7]
#define ACCEL_INPUT_BASE    ((volatile float    *)0x10009028)   // [0..121]
#define ACCEL_DONE_REG      (*((volatile uint32_t *)0x10009210))
#define ACCEL_OUTPUT_BASE   ((volatile float    *)0x10009214)   // [0..4]

// -------------------------------------------------------------------------
// Dimensions
// -------------------------------------------------------------------------
#define INPUT_DIM       122
#define NUM_LAYERS      5
#define NUM_CLASSES     5
#define TOTAL_BYTES     (INPUT_DIM * 4)   // 488

// -------------------------------------------------------------------------
// Globals
// -------------------------------------------------------------------------
uart uart0;

typedef union {
    float    f;
    uint8_t  bytes[4];
} float_bytes_t;

volatile float         input_array[INPUT_DIM] = {0};
volatile float_bytes_t rx_var;
volatile int           count = 0;   // counts bytes received (0 .. TOTAL_BYTES)

// -------------------------------------------------------------------------
// Accelerator inference — replaces model_infer()
// -------------------------------------------------------------------------
static int accel_infer(const volatile float *x)
{
    // 1. Write layer topology (same every call, but harmless to repeat)
    ACCEL_LAYER_NUM_REG = NUM_LAYERS;
    uint32_t layer_configs[8] = {256, 128, 64, 32, NUM_CLASSES, 0, 0, 0};
    for (int i = 0; i < 8; i++)
        ACCEL_LAYER_BASE[i] = layer_configs[i];

    // 2. Copy input vector into accelerator register file
    for (int i = 0; i < INPUT_DIM; i++)
        ACCEL_INPUT_BASE[i] = x[i];

    // 3. Kick the accelerator
    ACCEL_START_REG = 1;

    // 4. Spin until done
    while (ACCEL_DONE_REG == 0)
        ;

    // 5. Argmax over the 5 output probabilities
    uint8_t best = 0;
    float   max_val = ACCEL_OUTPUT_BASE[0];
    for (int i = 1; i < NUM_CLASSES; i++) {
        float v = ACCEL_OUTPUT_BASE[i];
        if (v > max_val) { max_val = v; best = i; }
    }

    return (int)best;
}

// -------------------------------------------------------------------------
// MAIN
// -------------------------------------------------------------------------
int main(void)
{
    // 1. Interrupt initialisation
    SET_MTVEC_VECTOR_MODE();

    // 2. Hardcoded boot-time test vector (same as your original firmware)
    float boot_input[INPUT_DIM] = {
        0.000000f, 1.000000f, 0.000000f, 0.000000f,
        0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f,
        0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f,
        0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f,
        0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f,
        0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f,
        0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f,
        0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f,
        0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f,
        1.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f,
        0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f,
        0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f,
        0.000000f, 0.000000f, 0.000000f, 0.000000f, 1.000000f, 0.000000f,
        0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f,
        0.000000f, 0.000000f,-0.110249f,-0.007762f,-0.004919f,-0.014089f,
       -0.089486f,-0.007736f,-0.095076f,-0.027023f,-0.809262f,-0.011664f,
       -0.036652f,-0.024437f,-0.012385f,-0.026180f,-0.018610f,-0.041221f,
        0.000000f,-0.002817f,-0.097531f, 1.265346f,-0.244204f,-0.637209f,
       -0.631929f, 2.746403f, 2.715365f,-1.412415f,-0.016930f,-0.374560f,
        0.734343f,-0.954389f,-1.071933f,-0.121485f,-0.480197f,-0.289103f,
       -0.639532f,-0.624871f, 2.874410f, 2.753914f
    };

    // 3. Initialise UART
    uart_init(&uart0, (uint32_t *)0x10008010);

    // 4. Run one boot-time inference and send result
    volatile int result = accel_infer(boot_input);
    uart_transmit_byte(&uart0, (uint8_t)result);

    // 5. Main loop — receive 488 bytes, infer, reply, repeat
    while (1)
    {
        count = 0;                  // reset byte counter for this sample

        ENABLE_GLOBAL_IRQ();
        ENABLE_FAST_IRQ(0);         // re-arm UART RX interrupt

        // Block until ISR signals completion
        while (count != TOTAL_BYTES)
            ;

        // ISR has disabled global IRQ and count == TOTAL_BYTES
        result = accel_infer(input_array);
        uart_transmit_byte(&uart0, (uint8_t)result);
    }

    return 0;
}

// -------------------------------------------------------------------------
// Interrupt handlers (unused vectors kept to satisfy the vector table)
// -------------------------------------------------------------------------
void mti_handler(void) {}
void exc_handler(void) {}
void mei_handler(void) {}
void msi_handler(void) {}

// -------------------------------------------------------------------------
// UART RX ISR
// Reconstructs one IEEE-754 float per 4 bytes, stores into input_array.
// When all INPUT_DIM floats have been received it disables interrupts
// so the main loop can proceed.
//
// Fix vs. original: count is incremented BEFORE the boundary check so
// that the very last byte (byte 487, count going 487→488) is committed
// to input_array[121] before the loop exit condition (count==488) is met.
// -------------------------------------------------------------------------
void fast_irq0_handler(void)
{
    // Read the incoming byte
    char *rx_ptr = (char *)(uart0.base_addr) + UART_RX_ADDR_OFFSET;
    uint8_t rx_byte = (uint8_t)(*rx_ptr);

    int c = count;                      // local copy for clarity

    // Accumulate into the union (little-endian byte order)
    rx_var.bytes[c % 4] = rx_byte;

    // On every 4th byte (index 3), the float is complete — store it
    if ((c % 4) == 3)
        input_array[c / 4] = rx_var.f;

    c++;                                // advance byte counter

    if (c < TOTAL_BYTES) {
        count = c;                      // more bytes expected, stay armed
    } else {
        count = c;                      // == TOTAL_BYTES, signals main loop
        DISABLE_GLOBAL_IRQ();           // stop accepting bytes
    }
}

void fast_irq1_handler(void) {}