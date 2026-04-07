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
        ST_MAC        = 4'b1000,  
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
    
    // PPRAM & MAC Helpers
    logic [31:0] current_layer_q, current_layer_d;
    
    // How many neurons remain in this layer (counts DOWN)
    // Loaded fresh when neuron_idx_q == 0, decremented in ST_CHECK
    logic [31:0] neuron_cnt_q, neuron_cnt_d;
    
    // Which neuron we are computing within the layer (counts UP)
    // Drives weight ROM offset calculation
    logic [7:0]  neuron_idx_q, neuron_idx_d;
    
    // Weight ROM base address for neuron 0 of the current layer
    // Accumulated across completed layers in ST_CHECK
    logic [W_ROM_ADDR_WIDTH-1:0] w_rom_layer_base_q, w_rom_layer_base_d;
    
    // MAC chunk counter: which 32-weight chunk are we on (0 to macs_per_neuron-1)
    // Reset here in LAYER_INIT, incremented in ST_MAC
    logic [2:0] mac_chunk_cnt_q, mac_chunk_cnt_d;  // 3 bits covers up to 8 chunks (max 256 neurons per layer)
    
    // Input length feeding the current layer.
    // Layer 0 reads the original input (INPUT_SIZE = 122).
    // Layer N>0 reads the output of layer N-1 = layer_params_q[N-1].
    logic [31:0] current_input_len;
    assign current_input_len = (current_layer_q == '0)
                               ? 32'(INPUT_SIZE)
                               : layer_params_q[current_layer_q - 1];
    
    // How many 32-wide MAC chunks one neuron of this layer needs.
    // ceil(input_len / 32) = (input_len + 31) >> 5
    // Layer 0: (122 + 31) >> 5 = 153 >> 5 = 4  ✓
    logic [31:0] macs_per_neuron;
    assign macs_per_neuron = (current_input_len + 31) >> 5;
        
    
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
            current_layer_q     <= current_layer_d;
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
                        
                        // Initialize layer tracking before entering the compute loop
                        current_layer_d    = '0;
                        neuron_idx_d       = '0;
                        neuron_cnt_d       = '0;    // Loaded properly on first ST_LAYER_INIT entry
                        w_rom_layer_base_d = '0;    // Layer 0 weights begin at ROM address 0
                        mac_chunk_cnt_d    = '0;
                    end else begin
                        config_cnt_d = config_cnt_q + 1'b1;
                    end
                end
            end

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
                // Set ping-pong for the entire duration of this layer.
                // Combinational - driven every cycle we are in this state.
                ppram_ping_pong_sel_o = current_layer_q[0];
            
                // Load neuron count only on the first neuron of a layer.
                // After that, ST_CHECK has already decremented it - we trust it.
                if (neuron_idx_q == '0) begin
                    neuron_cnt_d = layer_params_q[current_layer_q];
                end
            
                // PPRAM read always restarts from row 0 for every neuron.
                // This lands in ppram_rd_addr_q on the first ST_MAC cycle.
                ppram_rd_addr_d = '0;
            
                // MAC chunk counter always restarts from 0.
                mac_chunk_cnt_d = '0;
            
                // Compute the weight ROM start address for this neuron.
                // Result lands in w_rom_rd_addr_q on the first ST_MAC cycle.
                // ST_MAC cycle 1 presents this to the ROM → data arrives cycle 2.
                w_rom_rd_addr_d = w_rom_layer_base_q
                                + W_ROM_ADDR_WIDTH'(neuron_idx_q) * W_ROM_ADDR_WIDTH'(macs_per_neuron);
            
                // Unconditional one-cycle transition.
                state_d = ST_MAC;
            end
            
            ST_MAC: begin
            
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