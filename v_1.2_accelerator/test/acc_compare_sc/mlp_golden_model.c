/*
 * mlp_golden_model.c  —  FPGA Accelerator Verification Golden Model
 * ==================================================================
 * Reads weight_init.mem and bias_init.mem, runs inference in pure
 * single-precision float (matching hardware exactly), and dumps
 * intermediate ping-pong RAM contents in 1024-bit row format for
 * direct comparison against Vivado simulation memory dumps.
 *
 * Compile:  gcc -o mlp_golden_model mlp_golden_model.c -lm
 * Run:      ./mlp_golden_model
 *
 * Weight .mem layout (matches generate_weights_mem()):
 *   - Each line = 1024-bit = 32 x IEEE-754 floats, stored REVERSED
 *     i.e. on disk: [w31][w30]...[w1][w0]  (each 8 hex chars)
 *   - Outer loop: neuron o=0..out_dim-1
 *   - Inner loop: block  b=0..n_blocks-1   (n_blocks = ceil(in_dim/32))
 *   - in_dim padded to next multiple of 32 with zeros
 *
 * Bias .mem layout:
 *   - One 32-bit hex value per line, all layers concatenated
 *
 * MAC (mirrors hardware, neuron-by-neuron):
 *   y[o] = b[o] + sum( x[i] * w[o][i],  i = 0..in_dim-1 )
 *   then ReLU on every layer except the last (output logits)
 *
 * Output ping-pong RAM row format (same as weight .mem):
 *   Row r:  hex(n[r*32+31]) hex(n[r*32+30]) ... hex(n[r*32+0])
 *
 * Network: 122 -> 256 -> 128 -> 64 -> 32 -> 5
 *
 * Expected weight_init.mem line counts per layer:
 *   Layer 0: 256 neurons x 4 blocks =  1024 lines  (in=122 -> pad=128)
 *   Layer 1: 128 neurons x 8 blocks =  1024 lines  (in=256 -> pad=256)
 *   Layer 2:  64 neurons x 4 blocks =   256 lines  (in=128 -> pad=128)
 *   Layer 3:  32 neurons x 2 blocks =    64 lines  (in= 64 -> pad= 64)
 *   Layer 4:   5 neurons x 1 block  =     5 lines  (in= 32 -> pad= 32)
 *   TOTAL                            =  2373 lines
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

/* ============================================================
 * ARCHITECTURE  — edit here if your network changes
 * ============================================================ */
#define N_LAYERS   5
#define INPUT_DIM  122

static const int OUT_DIMS[N_LAYERS]  = { 256, 128, 64, 32, 5 };
static const int IN_DIMS[N_LAYERS]   = { 122, 256, 128, 64, 32 };

/* Maximum neurons in any layer — used for stack buffers */
#define MAX_NEURONS 256

#define WEIGHT_FILE "weight_init.mem"
#define BIAS_FILE   "bias_init.mem"

/* ============================================================
 * IEEE-754 HELPER
 * ============================================================ */

/* Reinterpret a uint32 bit pattern as a float (no arithmetic). */
static float bits_to_float(uint32_t bits)
{
    float f;
    memcpy(&f, &bits, 4);
    return f;
}

/* Reinterpret a float as its uint32 bit pattern. */
static uint32_t float_to_bits(float f)
{
    uint32_t bits;
    memcpy(&bits, &f, 4);
    return bits;
}

/* Parse an 8-character hex string into a float via its bit pattern. */
static float hex8_to_float(const char *h)
{
    uint32_t bits = (uint32_t)strtoul(h, NULL, 16);
    return bits_to_float(bits);
}

/* ============================================================
 * WEIGHT LOADER
 * ============================================================
 * weights[layer][neuron_o][input_i]
 * Caller must free: free(weights[l][o]) for all l,o then free(weights[l]) then free(weights)
 */
static float ***load_weights(const char *filepath)
{
    FILE *fh = fopen(filepath, "r");
    if (!fh) { fprintf(stderr, "[ERROR] Cannot open '%s'\n", filepath); exit(1); }

    /* Count lines first so we can warn if the file doesn't match. */
    int total_lines = 0;
    {
        int c;
        int in_line = 0;
        while ((c = fgetc(fh)) != EOF) {
            if (c == '\n') { if (in_line) total_lines++; in_line = 0; }
            else { in_line = 1; }
        }
        if (in_line) total_lines++;   /* last line without newline */
    }
    rewind(fh);

    /* Allocate outer array */
    float ***all_layers = malloc(N_LAYERS * sizeof(float **));

    /* 1024-bit line = 256 hex chars + newline + safety */
    char line_buf[300];
    char chunk[9];
    chunk[8] = '\0';

    int lines_consumed = 0;

    for (int l = 0; l < N_LAYERS; l++) {
        int in_dim  = IN_DIMS[l];
        int out_dim = OUT_DIMS[l];
        int padded  = ((in_dim + 31) / 32) * 32;
        int n_blocks = padded / 32;

        all_layers[l] = malloc(out_dim * sizeof(float *));

        for (int o = 0; o < out_dim; o++) {
            all_layers[l][o] = malloc(in_dim * sizeof(float));

            for (int blk = 0; blk < n_blocks; blk++) {
                if (!fgets(line_buf, sizeof(line_buf), fh)) {
                    fprintf(stderr, "[ERROR] Unexpected end of '%s' at layer %d neuron %d block %d\n",
                            filepath, l, o, blk);
                    exit(1);
                }
                lines_consumed++;

                /* Line has 32 floats stored REVERSED:
                 * float k (k=0 = lowest input index in this block) is at
                 * string offset (31-k)*8                               */
                for (int k = 0; k < 32; k++) {
                    int offset = (31 - k) * 8;
                    memcpy(chunk, line_buf + offset, 8);
                    float val = hex8_to_float(chunk);

                    int input_idx = blk * 32 + k;
                    if (input_idx < in_dim) {
                        all_layers[l][o][input_idx] = val;
                    }
                    /* else: padding zero — discard */
                }
            }
        }

        printf("  Layer %d: %d neurons x %d weights | %d lines/neuron | %d lines total\n",
               l, out_dim, in_dim, n_blocks, out_dim * n_blocks);
    }

    fclose(fh);

    if (lines_consumed != total_lines) {
        printf("\n[WARNING] Consumed %d lines but file has %d lines.\n",
               lines_consumed, total_lines);
        printf("          Verify ARCHITECTURE matches your export script.\n");
    }

    return all_layers;
}

/* ============================================================
 * BIAS LOADER
 * ============================================================
 * biases[layer][neuron_o]
 */
static float **load_biases(const char *filepath)
{
    FILE *fh = fopen(filepath, "r");
    if (!fh) { fprintf(stderr, "[ERROR] Cannot open '%s'\n", filepath); exit(1); }

    float **all_biases = malloc(N_LAYERS * sizeof(float *));
    char line_buf[32];
    char chunk[9];
    chunk[8] = '\0';

    for (int l = 0; l < N_LAYERS; l++) {
        int out_dim = OUT_DIMS[l];
        all_biases[l] = malloc(out_dim * sizeof(float));

        for (int o = 0; o < out_dim; o++) {
            if (!fgets(line_buf, sizeof(line_buf), fh)) {
                fprintf(stderr, "[ERROR] Unexpected end of '%s' at layer %d neuron %d\n",
                        filepath, l, o);
                exit(1);
            }
            memcpy(chunk, line_buf, 8);
            all_biases[l][o] = hex8_to_float(chunk);
        }
    }

    fclose(fh);
    return all_biases;
}

/* ============================================================
 * INPUT PARSER  (mirrors clean_line() in your GCC sim)
 * ============================================================
 * Accepts C-array literal:  { 0.0f, 1.0f, ... }
 * or plain comma/space-separated floats.
 */
static void parse_input(const char *text, float *out, int expected)
{
    /* Work on a copy so we can mutate */
    int len = (int)strlen(text);
    char *buf = malloc(len + 1);
    memcpy(buf, text, len + 1);

    /* Replace { } , ; f  with spaces */
    for (int i = 0; i < len; i++) {
        char c = buf[i];
        if (c == '{' || c == '}' || c == ',' || c == ';' || c == 'f')
            buf[i] = ' ';
    }

    int count = 0;
    char *ptr = buf;
    char *end;
    while (count < expected) {
        /* Skip whitespace */
        while (*ptr == ' ' || *ptr == '\t' || *ptr == '\n' || *ptr == '\r')
            ptr++;
        if (*ptr == '\0') break;

        out[count++] = strtof(ptr, &end);
        if (end == ptr) { ptr++; continue; }  /* not a number, skip char */
        ptr = end;
    }

    free(buf);

    if (count != expected) {
        fprintf(stderr, "[ERROR] Parsed %d values, expected %d.\n", count, expected);
        exit(1);
    }
}

/* ============================================================
 * INFERENCE — one layer
 * ============================================================ */
static float relu_f(float x) { return x > 0.0f ? x : 0.0f; }

static void layer_forward(const float *x, int in_dim,
                           float **weights, float *biases, int out_dim,
                           float *y, int apply_relu)
{
    for (int o = 0; o < out_dim; o++) {
        float acc = biases[o];
        for (int i = 0; i < in_dim; i++) {
            acc += x[i] * weights[o][i];
        }
        y[o] = apply_relu ? relu_f(acc) : acc;
    }
}

/* ============================================================
 * PING-PONG RAM ROW PRINTER
 * ============================================================
 * Format: hex(n[r*32+31]) ... hex(n[r*32+0])   — same as weight .mem
 */
static void print_ping_pong(const float *activations, int out_dim, const char *label)
{
    int n_rows = (out_dim + 31) / 32;
    printf("\n  %s  (%d x 1024-bit rows):\n", label, n_rows);
    printf("  Format per row: n[hi]...n[lo]  (MSB=high index, LSB=low index)\n\n");

    for (int r = 0; r < n_rows; r++) {
        int lo = r * 32;
        int hi = lo + 31;
        int actual_hi = hi < out_dim ? hi : out_dim - 1;

        printf("  Row %2d  [n%d..n%d]:\n    ", r, actual_hi, lo);

        /* Print hex line: n[31] first (MSB), n[0] last (LSB) */
        for (int k = 31; k >= 0; k--) {
            int idx = lo + k;
            float val = (idx < out_dim) ? activations[idx] : 0.0f;
            printf("%08x", float_to_bits(val));
        }
        printf("\n");

        /* Annotated per-neuron breakdown */
        printf("    ");
        for (int k = actual_hi - lo; k >= 0; k--) {
            int idx = lo + k;
            printf("[n%d:%08x] ", idx, float_to_bits(activations[idx]));
        }
        printf("\n\n");
    }
}

/* ============================================================
 * MAIN
 * ============================================================ */
int main(void)
{
    printf("========================================================================\n");
    printf("  MLP Golden Model  —  FPGA Ping-Pong RAM Verification\n");
    printf("  All arithmetic in single-precision float (matches hardware exactly)\n");
    printf("========================================================================\n");

    /* --- Load weights & biases --- */
    printf("\nLoading '%s' ...\n", WEIGHT_FILE);
    float ***all_weights = load_weights(WEIGHT_FILE);

    printf("\nLoading '%s' ...\n", BIAS_FILE);
    float **all_biases = load_biases(BIAS_FILE);
    printf("  OK\n");

    /* --- Read input from terminal --- */
    printf("\n========================================================================\n");
    printf("  Paste input vector (%d floats), C-array format.\n", INPUT_DIM);
    printf("  Example:  { 0.0f, 1.0f, 0.0f, ... }\n");
    printf("  Press Enter twice (blank line) when done.\n");
    printf("========================================================================\n\n");

    /* Collect lines until blank line */
    char *input_text = NULL;
    size_t input_len = 0;
    char line_buf[16384];

    while (fgets(line_buf, sizeof(line_buf), stdin)) {
        /* Blank line = done */
        int blank = 1;
        for (int i = 0; line_buf[i] && line_buf[i] != '\n'; i++)
            if (line_buf[i] != ' ' && line_buf[i] != '\r') { blank = 0; break; }
        if (blank && input_text) break;

        size_t chunk_len = strlen(line_buf);
        input_text = realloc(input_text, input_len + chunk_len + 1);
        memcpy(input_text + input_len, line_buf, chunk_len);
        input_len += chunk_len;
        input_text[input_len] = '\0';
    }

    float x[INPUT_DIM];
    parse_input(input_text, x, INPUT_DIM);
    free(input_text);
    printf("\n  Parsed %d input values OK.\n", INPUT_DIM);

    /* Show input as ping-pong rows */
    print_ping_pong(x, INPUT_DIM, "INPUT ping-pong RAM rows");

    /* --- Layer-by-layer forward pass --- */
    printf("\n========================================================================\n");
    printf("  LAYER-BY-LAYER FORWARD PASS\n");
    printf("========================================================================\n");

    /* Use two buffers, ping-pong style (just like your hardware) */
    float buf_a[MAX_NEURONS];
    float buf_b[MAX_NEURONS];
    const float *src = x;
    float       *dst = buf_a;

    for (int l = 0; l < N_LAYERS; l++) {
        int in_dim  = IN_DIMS[l];
        int out_dim = OUT_DIMS[l];
        int is_last = (l == N_LAYERS - 1);

        layer_forward(src, in_dim, all_weights[l], all_biases[l], out_dim, dst, !is_last);

        /* --- Print layer results --- */
        const char *label = is_last
            ? "OUTPUT LOGITS (no ReLU — argmax in SW)"
            : "POST-ReLU";

        printf("\n========================================================================\n");
        printf("  LAYER %d  |  %s  |  %d neurons\n", l, label, out_dim);
        printf("========================================================================\n");

        printf("\n  Neuron float values:\n");
        for (int o = 0; o < out_dim; o++) {
            printf("    n[%4d] = %+14.6f   hex: %08x\n",
                   o, dst[o], float_to_bits(dst[o]));
        }

        print_ping_pong(dst, out_dim, "Ping-pong RAM dump");

        /* Swap buffers */
        src = dst;
        dst = (dst == buf_a) ? buf_b : buf_a;
    }

    /* --- Final argmax (mirrors your RISC-V FPU code) --- */
    const float *logits = src;
    int predicted = 0;
    float max_val = logits[0];
    for (int i = 1; i < OUT_DIMS[N_LAYERS - 1]; i++) {
        if (logits[i] > max_val) { max_val = logits[i]; predicted = i; }
    }

    printf("\n========================================================================\n");
    printf("  FINAL PREDICTION: Class %d\n", predicted);
    printf("========================================================================\n\n");

    /* --- Cleanup --- */
    for (int l = 0; l < N_LAYERS; l++) {
        for (int o = 0; o < OUT_DIMS[l]; o++) free(all_weights[l][o]);
        free(all_weights[l]);
        free(all_biases[l]);
    }
    free(all_weights);
    free(all_biases);

    return 0;
}