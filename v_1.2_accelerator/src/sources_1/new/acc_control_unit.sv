`timescale 1ns / 1ps

module acc_control_unit #(
    parameter W_ROM_DEPTH       = 2373,
    parameter W_ROM_ADDR_WIDTH  = $clog2(W_ROM_DEPTH),  
    
    parameter PPR_WORD_WIDTH    = 32,
    parameter PPR_NUM_WORDS     = 32,
    parameter PPR_DATA_WIDTH    = PPR_WORD_WIDTH * PPR_NUM_WORDS,
    parameter PPR_MAX_NEURONS   = 256,
    parameter PPR_ROW_DEPTH     = PPR_MAX_NEURONS / PPR_NUM_WORDS,
    parameter PPR_ROW_ADDR_W    = $clog2(PPR_ROW_DEPTH),
    parameter PPR_COL_ADDR_W    = $clog2(PPR_NUM_WORDS),
    
    parameter B_ROM_DATA_WIDTH  = 32,
    parameter B_ROM_DEPTH       = 1200,
    parameter B_ROM_ADDR_WIDTH  = $clog2(B_ROM_DEPTH),

    // Input vector size (max 122 values → indices 10..131)
    parameter INPUT_SIZE        = 122
)(
    input  logic                        clk_i,
    input  logic                        rst_ni,
    
    output logic                        acc_we_o,       
    output logic [31:0]                 acc_dat_o,
    output logic [31:0]                 acc_adr_o,
    input  logic [31:0]                 acc_dat_i,
    
    output logic [W_ROM_ADDR_WIDTH-1:0] w_rom_rd_addr_o,
    
    output logic                        ppram_ping_pong_sel_o,
    output logic                        ppram_wr_en_o,
    output logic [PPR_ROW_ADDR_W-1:0]   ppram_wr_row_addr_o,
    output logic [PPR_COL_ADDR_W-1:0]   ppram_wr_col_addr_o,
    output logic [PPR_ROW_ADDR_W-1:0]   ppram_rd_addr_o,
        
    output logic                        macarr_last_o,
    
    output logic [B_ROM_ADDR_WIDTH-1:0] b_rom_rd_addr_o,
    
    output logic                        mux_wb_in_sel,
    output logic                        demux_wb_out_sel,
    
    output logic                        demux_cu_or_ppram,
    output logic                        mux_cu_or_wbdemux
);
    
    // =========================================================
    // State Encoding
    // =========================================================
    typedef enum logic [3:0] {
        ST_IDLE       = 4'b0000,
        ST_CONFIG     = 4'b0001,
        ST_LOAD_INPUT = 4'b0011,
        ST_LAYER_INIT = 4'b0010,
        ST_ADD_TREE   = 4'b0110,
        ST_BIAS_RELU  = 4'b0100,
        ST_WB         = 4'b0101,
        ST_CHECK      = 4'b0111,
        ST_DONE       = 4'b1111
    } state_t; 

    // =========================================================
    // Registered State (_q) and Next State (_d) Declarations
    // =========================================================
    state_t state_q, state_d;

    // CONFIG state: tracks which register we are reading (0..8)
    logic [3:0]  config_cnt_q, config_cnt_d;

    // LOAD_INPUT state: tracks which of the 122 inputs we've written (0..121)
    logic [6:0]  input_cnt_q, input_cnt_d;

    // Latched configuration registers
    logic [31:0] layer_num_q, layer_num_d;
    logic [31:0] layer_params_q [8], layer_params_d [8];

    // PPRAM write address pointers
    logic [PPR_ROW_ADDR_W-1:0] ppram_wr_row_addr_q, ppram_wr_row_addr_d;
    logic [PPR_COL_ADDR_W-1:0] ppram_wr_col_addr_q, ppram_wr_col_addr_d;

    // Read address (used in MAC states later)
    logic [PPR_ROW_ADDR_W-1:0] ppram_rd_addr_q,     ppram_rd_addr_d;

    // ROM address pointers
    logic [W_ROM_ADDR_WIDTH-1:0] w_rom_rd_addr_q,   w_rom_rd_addr_d;
    logic [B_ROM_ADDR_WIDTH-1:0] b_rom_rd_addr_q,   b_rom_rd_addr_d;

    // =========================================================
    // Wire registered addresses to outputs
    // =========================================================
    // These are registered outputs - driven from _q, not combinationally.
    // This is a deliberate choice: address lines to memories are registered
    // to reduce glitching and ease timing closure. The one-cycle latency
    // cost is absorbed into the protocol for each memory.
    assign w_rom_rd_addr_o   = w_rom_rd_addr_q;
    assign ppram_wr_row_addr_o = ppram_wr_row_addr_q;
    assign ppram_wr_col_addr_o = ppram_wr_col_addr_q;
    assign ppram_rd_addr_o   = ppram_rd_addr_q;
    assign b_rom_rd_addr_o   = b_rom_rd_addr_q;

    // =========================================================
    // Sequential Block 
    // =========================================================
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_q             <= ST_IDLE;
            config_cnt_q        <= '0;
            input_cnt_q         <= '0;
            layer_num_q         <= '0;
            for (int i = 0; i < 8; i++) layer_params_q[i] <= '0;
            ppram_wr_row_addr_q <= '0;
            ppram_wr_col_addr_q <= '0;
            ppram_rd_addr_q     <= '0;
            w_rom_rd_addr_q     <= '0;
            b_rom_rd_addr_q     <= '0;
        end else begin
            state_q             <= state_d;
            config_cnt_q        <= config_cnt_d;
            input_cnt_q         <= input_cnt_d;
            layer_num_q         <= layer_num_d;
            for (int i = 0; i < 8; i++) layer_params_q[i] <= layer_params_d[i];
            ppram_wr_row_addr_q <= ppram_wr_row_addr_d;
            ppram_wr_col_addr_q <= ppram_wr_col_addr_d;
            ppram_rd_addr_q     <= ppram_rd_addr_d;
            w_rom_rd_addr_q     <= w_rom_rd_addr_d;
            b_rom_rd_addr_q     <= b_rom_rd_addr_d;
        end
    end

    // =========================================================
    // Combinational Block 
    // =========================================================
    always_comb begin

        // ---------------------------------------------------------
        // Default: all _d signals hold their current _q value.
        // without defaults, any signal not
        // assigned in a branch infers a latch in synthesis.
        // ---------------------------------------------------------
        state_d             = state_q;
        config_cnt_d        = config_cnt_q;
        input_cnt_d         = input_cnt_q;
        layer_num_d         = layer_num_q;
        for (int i = 0; i < 8; i++) layer_params_d[i] = layer_params_q[i];
        ppram_wr_row_addr_d = ppram_wr_row_addr_q;
        ppram_wr_col_addr_d = ppram_wr_col_addr_q;
        ppram_rd_addr_d     = ppram_rd_addr_q;
        w_rom_rd_addr_d     = w_rom_rd_addr_q;
        b_rom_rd_addr_d     = b_rom_rd_addr_q;

        // ---------------------------------------------------------
        // Default: all pure combinational outputs are de-asserted.
        // ---------------------------------------------------------
        acc_we_o              = 1'b0;
        acc_dat_o             = '0;
        acc_adr_o             = '0;
        demux_cu_or_ppram     = 1'b0;
        mux_cu_or_wbdemux     = 1'b0;
        mux_wb_in_sel         = 1'b0;
        demux_wb_out_sel      = 1'b0;
        ppram_ping_pong_sel_o = 1'b0;
        ppram_wr_en_o         = 1'b0;
        macarr_last_o         = 1'b0;

        // ---------------------------------------------------------
        // FSM
        // ---------------------------------------------------------
        unique case (state_q)

            // =====================================================
            // ST_IDLE
            // Wait for software to write 1 into the Start register
            // (regfile index 0). We poll it every cycle.
            //
            // Timing note: acc_adr_o = 0 is driven combinationally
            // here. The register file sees address 0 and presents
            // regf_1[0] on acc_dat_i ONE cycle later (synchronous
            // read). So we read acc_dat_i while still in IDLE -
            // it carries last cycle's read of address 0, which is
            // exactly the Start register. Correct.
            // =====================================================
            ST_IDLE: begin
                // Reset all configuration we may have stored previously
                layer_num_d = '0;
                for (int i = 0; i < 8; i++) layer_params_d[i] = '0;
                ppram_wr_row_addr_d = '0;
                ppram_wr_col_addr_d = '0;
                ppram_rd_addr_d     = '0;
                w_rom_rd_addr_d     = '0;
                b_rom_rd_addr_d     = '0;

                // Poll Start register (regfile index 0)
                acc_adr_o = 32'd0;

                if (acc_dat_i == 32'd1) begin
                    // Start detected. 
                    state_d      = ST_CONFIG;
                    config_cnt_d = 4'd0;
                    acc_adr_o    = 32'd1;   // Pre-fetch layer_num
                end
            end

            // =====================================================
            // ST_CONFIG
            // Read layer_num (index 1), then layer_params[0..7]
            // (indices 2..9) from the register file.
            //
            // Because the register file has 1-cycle read latency:
            //   - Cycle N:   we drive acc_adr_o = X  
            //   - Cycle N+1: acc_dat_i carries regf_1[X]
            //
            // So config_cnt_q represents "the data arriving NOW
            // belongs to which parameter?":
            //
            //   config_cnt_q = 0 → acc_dat_i = layer_num  (addr 1 was pre-fetched in IDLE)
            //   config_cnt_q = 1 → acc_dat_i = layer[0]   (addr 2 was driven when cnt=0)
            //   ...
            //   config_cnt_q = 8 → acc_dat_i = layer[7]   (addr 9 was driven when cnt=7)
            //
            // On the last valid capture (cnt==8), we also:
            //   - Start routing the data bus through the PPRAM path
            //   - Pre-fetch input[0] address (index 10)
            //   - Transition to ST_LOAD_INPUT
            // =====================================================
            ST_CONFIG: begin
                // Drive the NEXT address to pre-fetch while we capture current data
                // When cnt=0 we just captured layer_num, so drive addr for layer[0]
                // When cnt=7 we just captured layer[6], so drive addr for layer[7]
                // When cnt=8 we just captured layer[7], so drive addr for input[0]
                if (config_cnt_q < 4'd8) begin
                    // Address for the parameter AFTER the one arriving now
                    acc_adr_o = 32'd2 + {28'd0, config_cnt_q};      // addr 2,3,...,9
                end else begin
                    acc_adr_o = 32'd10;                             // First input element
                end

                // Capture the data that arrived this cycle
                if (config_cnt_q == 4'd0) begin
                    layer_num_d  = acc_dat_i;                       // Latch layer_num
                    config_cnt_d = config_cnt_q + 1'b1;
                end else if (config_cnt_q <= 4'd8) begin
                    layer_params_d[config_cnt_q - 1] = acc_dat_i;   // Latch layer[0..7]

                    if (config_cnt_q == 4'd8) begin
                        // All params captured. Set up for LOAD_INPUT.
                        config_cnt_d        = '0;
                        input_cnt_d         = '0;
                        ppram_wr_row_addr_d = '0;
                        ppram_wr_col_addr_d = '0;
                        
                        // Route register file output into PPRAM write data path
                        demux_cu_or_ppram     = 1'b1;
                        ppram_ping_pong_sel_o = 1'b1;               // Write to bank A (sel=1 -> write A)
                        state_d               = ST_LOAD_INPUT;
                    end else begin
                        config_cnt_d = config_cnt_q + 1'b1;
                    end
                end
            end

            // =====================================================
            // ST_LOAD_INPUT
            // Write all INPUT_SIZE (122) input values into PPRAM
            // bank B, row 0..3 (since 122 values / 32 words = 4
            // rows with partial fill on the last row).
            //
            // Timing:
            //   - acc_adr_o drives regfile address → data arrives
            //     on acc_dat_i next cycle (1-cycle latency)
            //   - ppram_wr_en_o is asserted the cycle AFTER the
            //     address is presented, when valid data is on the
            //     bus - which is exactly when we're in this state
            //     after the first prefetch done at end of CONFIG.
            //
            // Address plan (regfile indices 10..131):
            //   input_cnt_q = 0: addr=10 was pre-fetched → write input[0]
            //   input_cnt_q = 1: addr=11 → write input[1]
            //   ...
            //   input_cnt_q = 121: addr=131 → write input[121]
            //
            // PPRAM address plan:
            //   col advances 0→31, then wraps to 0 and row advances.
            //   Row 0: inputs  0..31
            //   Row 1: inputs 32..63
            //   Row 2: inputs 64..95
            //   Row 3: inputs 96..121 (cols 0..25, cols 26..31 are zero-padded in weights)
            // =====================================================
            ST_LOAD_INPUT: begin
                // Keep data path routed: regfile → PPRAM write port
                demux_cu_or_ppram     = 1'b1;
                ppram_ping_pong_sel_o = 1'b1; // Write to bank A

                if (input_cnt_q < INPUT_SIZE[6:0]) begin
                    // Drive next regfile address to pre-fetch (arrives next cycle)
                    acc_adr_o = 32'd10 + {25'd0, input_cnt_q} + 32'd1;

                    // Write the value that arrived this cycle into PPRAM
                    ppram_wr_en_o = 1'b1;
                    // ppram_wr_row/col_addr_o are driven from _q via assign - already set

                    // Advance column, wrap and bump row after each write
                    if (ppram_wr_col_addr_q == PPR_COL_ADDR_W'(PPR_NUM_WORDS - 1)) begin
                        ppram_wr_col_addr_d = '0;
                        ppram_wr_row_addr_d = ppram_wr_row_addr_q + 1'b1;
                    end else begin
                        ppram_wr_col_addr_d = ppram_wr_col_addr_q + 1'b1;
                    end

                    input_cnt_d = input_cnt_q + 1'b1;

                end else begin
                    // All inputs written. Do not assert wr_en on this last cycle.
                    // Reset write pointers for future writeback use.
                    ppram_wr_en_o       = 1'b0;
                    ppram_wr_row_addr_d = '0;
                    ppram_wr_col_addr_d = '0;
                    input_cnt_d         = '0;
                    state_d             = ST_LAYER_INIT;
                end
            end

            ST_LAYER_INIT: begin
                // To be implemented next
            end

            ST_ADD_TREE: begin
                // To be implemented next
            end

            ST_BIAS_RELU: begin
                // To be implemented next
            end

            ST_WB: begin
                // To be implemented next
            end

            ST_CHECK: begin
                // To be implemented next
            end

            ST_DONE: begin
                // To be implemented next
            end

            default: state_d = ST_IDLE;
        endcase
    end

endmodule