#include <stdint.h>

// -------------------------------------------------------------------------
// Hardware Memory Map
// -------------------------------------------------------------------------
#define DEBUG_IF_ADDR       0x10008010 

// Write Address Space (Host -> Accelerator)
#define ACCEL_START_REG     0x10009000 // rfile_1[0]
#define ACCEL_LAYER_NUM_REG 0x10009004 // rfile_1[1]
#define ACCEL_LAYER_BASE    0x10009008 // rfile_1[2] to rfile_1[9]
#define ACCEL_INPUT_BASE    0x10009028 // rfile_1[10] to rfile_1[131]

// Read Address Space (Accelerator -> Host) -- For future driver use
#define ACCEL_DONE_REG      0x10009210 // rfile_2[0]
#define ACCEL_OUTPUT_BASE   0x10009214 // rfile_2[1] to rfile_2[5]

// These are hardwired and heavily optimized for IDS, do not changed
#define INPUT_DIM 122
#define OUTPUT_DIM 5

// This can be changed 0-8
#define NUM_HIDDEN_LAYERS 4

int main() {
    // -------------------------------------------------------------------------
    // Data Initialization
    // -------------------------------------------------------------------------
    // Input for class 0 (normal attack type) 
    volatile float input[INPUT_DIM] = { 
        0.000000f, 1.000000f, 0.000000f, 0.000000f, 0.000000f, 
        0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 
        0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 
        0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 
        0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 
        0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 
        0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 1.000000f, 
        0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 
        0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 
        0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 1.000000f, 0.000000f, 0.000000f, 
        0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, 0.000000f, -0.110249f, 
        -0.007762f, -0.004919f, -0.014089f, -0.089486f, -0.007736f, -0.095076f, -0.027023f, -0.809262f, 
        -0.011664f, -0.036652f, -0.024437f, -0.012385f, -0.026180f, -0.018610f, -0.041221f, 0.000000f, 
        -0.002817f, -0.097531f, 1.265346f, -0.244204f, -0.637209f, -0.631929f, 2.746403f, 2.715365f, 
        -1.412415f, -0.016930f, -0.374560f, 0.734343f, -0.954389f, -1.071933f, -0.121485f, -0.480197f, 
        -0.289103f, -0.639532f, -0.624871f, 2.874410f, 2.753914f 
    };

    // Dummy layer configurations
    uint32_t layer_configs[8] = {256, 128, 64, 32, 0, 0, 0, 0}; 

    // -------------------------------------------------------------------------
    // Write Parameters
    // -------------------------------------------------------------------------
    volatile uint32_t *layer_num_ptr = (volatile uint32_t *)ACCEL_LAYER_NUM_REG;
    volatile uint32_t *layer_ptr     = (volatile uint32_t *)ACCEL_LAYER_BASE;

    *layer_num_ptr = NUM_HIDDEN_LAYERS; // Writes to 0x1000_9004 -> rfile_1[1]

    for (int i = 0; i < 8; i++) {
        layer_ptr[i] = layer_configs[i]; // Writes 0x1000_9008 to 0x1000_9024 -> rfile_1[2:9]
    }

    // -------------------------------------------------------------------------
    // Write Inputs 
    // -------------------------------------------------------------------------
    volatile float *acc_input_ptr = (volatile float *)ACCEL_INPUT_BASE;
    
    for (int i = 0; i < INPUT_DIM; i++) {
        // Writes 0x1000_9028 to 0x1000_920C -> rfile_1[10:131]
        acc_input_ptr[i] = input[i]; 
    }

    // -------------------------------------------------------------------------
    // Start the Accelerator
    // -------------------------------------------------------------------------
    volatile uint32_t *start_ptr = (volatile uint32_t *)ACCEL_START_REG;
    *start_ptr = 1; // Writes to 0x1000_9000 -> rfile_1[0]

    // -------------------------------------------------------------------------
    // Finish Testbench via Debug IF
    // -------------------------------------------------------------------------
    volatile char *debug_ptr = (volatile char *)DEBUG_IF_ADDR;
    
    // Write 1 to signify the test completed successfully.
    // Ensure the testbench traps this write to call $finish.
    *debug_ptr = 1; 

    return 0;
}