#include <stdint.h>

// -------------------------------------------------------------------------
// Hardware Memory Map
// -------------------------------------------------------------------------
#define DEBUG_IF_ADDR       0x10008010

// Write Address Space (Host -> Accelerator)
#define ACCEL_START_REG     0x10009000  // rfile_1[0]
#define ACCEL_LAYER_NUM_REG 0x10009004  // rfile_1[1]
#define ACCEL_LAYER_BASE    0x10009008  // rfile_1[2] to rfile_1[9]
#define ACCEL_INPUT_BASE    0x10009028  // rfile_1[10] to rfile_1[131]

// Read Address Space (Accelerator -> Host)
#define ACCEL_DONE_REG      0x10009210  // rfile_2[0]
#define ACCEL_OUTPUT_BASE   0x10009214  // rfile_2[1] to rfile_2[5]

#define INPUT_DIM    122
#define NUM_LAYERS   5
#define NUM_CLASSES  5

// -------------------------------------------------------------------------
// Helpers
// -------------------------------------------------------------------------

// Pointer aliases — defined once, used everywhere
static volatile uint32_t * const start_ptr     = (volatile uint32_t *)ACCEL_START_REG;
static volatile uint32_t * const done_ptr      = (volatile uint32_t *)ACCEL_DONE_REG;
static volatile uint32_t * const layer_num_ptr = (volatile uint32_t *)ACCEL_LAYER_NUM_REG;
static volatile uint32_t * const layer_ptr     = (volatile uint32_t *)ACCEL_LAYER_BASE;
static volatile float    * const acc_input_ptr = (volatile float    *)ACCEL_INPUT_BASE;
static volatile float    * const output_ptr    = (volatile float    *)ACCEL_OUTPUT_BASE;
static volatile char     * const debug_ptr     = (volatile char     *)DEBUG_IF_ADDR;

// Small busy-wait: burns exactly 'n' iterations so the CPU stalls
// long enough for the accelerator FSM to settle into IDLE.
// At 20 MHz one iteration ~ 50 ns; 16 iterations ~ 800 ns >> 2 clock cycles.
static void delay_cycles(volatile uint32_t n)
{
    while (n--) { __asm__ volatile ("nop"); }
}

// Write layer topology (same for every inference)
static void write_config(void)
{
    uint32_t layer_configs[8] = {256, 128, 64, 32, NUM_CLASSES, 0, 0, 0};

    *layer_num_ptr = NUM_LAYERS;
    for (int i = 0; i < 8; i++)
        layer_ptr[i] = layer_configs[i];
}

// Copy one input vector into the accelerator register file
static void write_input(const float *src)
{
    for (int i = 0; i < INPUT_DIM; i++)
        acc_input_ptr[i] = src[i];
}

// Kick the accelerator, immediately clear start so IDLE re-entry
// does not auto-re-trigger, then spin until done.
static void run_inference(void)
{
    *start_ptr = 1;

    // Clear start within the same C sequence.
    // The accelerator latches the rising edge during ST_IDLE polling;
    // once it has transitioned to ST_CONFIG the start value no longer
    // matters, but clearing it now guarantees IDLE will not loop.
    *start_ptr = 0;

    // Spin until the accelerator writes done=1
    while (*done_ptr == 0) { /* wait */ }

    // The accelerator holds done=1 for exactly 1 cycle then writes
    // done=0 and transitions to IDLE (2 cycles in ST_DONE total).
    // We wait a few extra NOPs so the FSM has fully settled in IDLE
    // before the next write_config / write_input sequence begins.
    delay_cycles(16);
}

// Argmax over the 5 output floats
static uint8_t read_result(void)
{
    uint8_t best = 0;
    float   max_val = output_ptr[0];
    for (int i = 1; i < NUM_CLASSES; i++) {
        float v = output_ptr[i];
        if (v > max_val) { max_val = v; best = (uint8_t)i; }
    }
    return best;
}

// -------------------------------------------------------------------------
// Test Vectors
// -------------------------------------------------------------------------

// Class 0
static const float input_class0[INPUT_DIM] = {
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

// Class 1
static const float input_class1[INPUT_DIM] = {
    1.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f,
    0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f,
    0.000000f, 0.000000f, 0.000000f, 1.000000f, 0.000000f, 0.000000f, 0.000000f,
    0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f,
    0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f,
    0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f,
    0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f,
    0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f,
    0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f,
    0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f,
    0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f,
    0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 1.000000f, 0.000000f,
   -0.110249f, -0.007759f, -0.004919f, -0.014089f, -0.089486f, -0.007736f, -0.095076f,
   -0.027023f, -0.809262f, -0.011664f, -0.036652f, -0.024437f, -0.012385f, -0.026180f,
   -0.018610f, -0.041221f,  0.000000f, -0.002817f, -0.097531f, -0.725778f,  0.513001f,
   -0.637209f, -0.631929f, -0.374362f, -0.374432f,  0.771283f, -0.349683f,  3.474118f,
   -1.805831f, -0.529826f,  1.066401f, -0.439078f,  2.756092f,  2.198385f, -0.639532f,
   -0.624871f, -0.387635f, -0.376387f
};

// Class 3
static const float input_class3[INPUT_DIM] = {
    0.000000f, 1.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f,
    0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f,
    0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f,
    0.000000f, 1.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f,
    0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f,
    0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f,
    0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f,
    0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f,
    0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f,
    0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f,
    0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f,
    0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 1.000000f, 0.000000f,
   -0.107178f, -0.007725f, -0.004748f, -0.014089f, -0.089486f, -0.007736f,  1.765424f,
   -0.027023f,  1.235694f, -0.011664f, -0.036652f, -0.024437f, -0.012385f,  8.239424f,
   -0.018610f, -0.041221f,  0.000000f, -0.002817f, -0.097531f, -0.725778f, -0.368110f,
   -0.637209f, -0.631929f, -0.374362f, -0.374432f,  0.771283f, -0.349683f, -0.374560f,
   -1.301828f, -0.800824f, -0.025040f, -0.015621f, -0.415471f, -0.289103f, -0.639532f,
   -0.624871f, -0.387635f, -0.376387f
};

// Class 4
static const float input_class4[INPUT_DIM] = {
    0.000000f, 1.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f,
    0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f,
    0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f,
    0.000000f, 0.000000f, 1.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f,
    0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f,
    0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f,
    0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f,
    0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f,
    0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f,
    0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f,
    0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f,
    0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 1.000000f, 0.000000f,
   -0.109481f, -0.005551f, -0.004919f, -0.014089f, -0.089486f, -0.007736f, -0.095076f,
   -0.027023f, -0.809262f, -0.011664f, -0.036652f, -0.024437f, -0.012385f, -0.026180f,
   -0.018610f, -0.041221f,  0.000000f, -0.002817f, -0.097531f, -0.725778f, -0.368110f,
   -0.637209f, -0.631929f, -0.374362f, -0.374432f,  0.771283f, -0.349683f, -0.374560f,
   -0.485344f, -0.267863f,  0.197703f, -0.227350f,  1.493939f, -0.111426f, -0.639532f,
   -0.624871f, -0.387635f, -0.376387f
};

// -------------------------------------------------------------------------
// Test table — add more entries here to extend the test
// -------------------------------------------------------------------------
typedef struct {
    const float *vec;
    uint8_t      expected_class;
} test_case_t;

static const test_case_t tests[] = {
    { input_class0, 0 },
    { input_class1, 1 },
    { input_class3, 3 },
    { input_class4, 4 },
};

#define NUM_TESTS (sizeof(tests) / sizeof(tests[0]))

// -------------------------------------------------------------------------
// Main
// -------------------------------------------------------------------------
int main(void)
{
    // Write layer topology once — it does not change between inferences
    write_config();

    for (int t = 0; t < (int)NUM_TESTS; t++) {

        // 1. Load input vector into accelerator register file
        write_input(tests[t].vec);

        // 2. Start inference and wait for completion
        //    (start is cleared inside run_inference before done polling)
        run_inference();

        // 3. Read argmax result and write to debug interface
        //    The debug module prints whatever byte it receives to the
        //    TCL terminal, so class 0-4 appear directly.
        uint8_t result = read_result();
        *debug_ptr = (char)result;

        // 4. Small gap between test cases so the debug module has time
        //    to flush and the accelerator is firmly in IDLE
        delay_cycles(32);
    }

    // All tests done — sentinel value signals end of run to the
    // TCL monitor (11 is safely outside the 0-4 class range)
    *debug_ptr = 11;

    return 0;
}