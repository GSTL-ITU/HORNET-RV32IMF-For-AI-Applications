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
    
    parameter INPUT_SIZE        = 122
)(
    input  logic                        clk_i,
    input  logic                        rst_ni,
    
    output logic                        acc_we_o,       
    output logic [31:0]                 acc_dat_o,
    output logic [31:0]                 acc_adr_o,
    input  logic [31:0]                 acc_dat_i,
    
    output logic [W_ROM_ADDR_WIDTH-1:0] w_rom_rd_addr_o,
    
    output logic                        ppram_man_rst_ni_o,
    output logic                        ppram_ping_pong_sel_o,
    output logic                        ppram_wr_en_o,
    output logic [PPR_ROW_ADDR_W-1:0]   ppram_wr_row_addr_o,
    output logic [PPR_COL_ADDR_W-1:0]   ppram_wr_col_addr_o,
    output logic [PPR_ROW_ADDR_W-1:0]   ppram_rd_addr_o,
        
    output logic                        macarr_man_rst_ni,
    output logic                        macarr_en_i,
    
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
        ST_BIAS       = 4'b0100,
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
    logic [7:0]  input_cnt_q, input_cnt_d;

    // Latched configuration registers
    logic [31:0] layer_num_q, layer_num_d;
    logic [31:0] layer_params_q [8], layer_params_d [8];
    
    // PPRAM & MAC Helpers
    logic [31:0] current_layer_q, current_layer_d;
    
    // Loaded fresh when neuron_idx_q == 0, decremented in ST_CHECK
    logic [31:0] neuron_cnt_q, neuron_cnt_d;
    
    // Drives weight ROM offset calculation
    logic [7:0]  neuron_idx_q, neuron_idx_d;
    
    // Weight ROM base address regs
    logic [W_ROM_ADDR_WIDTH-1:0] w_rom_layer_base_q, w_rom_layer_base_d;
    
    // MAC chunk counter
    logic [3:0] mac_chunk_cnt_q, mac_chunk_cnt_d; 
    
    logic mac_reset;
    assign macarr_man_rst_ni = mac_reset && rst_ni;
    
    // Input length feeding the current layer
    logic [31:0] current_input_len;
    assign current_input_len = (current_layer_q == '0)
                               ? 32'(INPUT_SIZE)
                               : layer_params_q[current_layer_q - 1];
    
    // How many 32-wide MAC chunks one neuron of this layer needs.
    // ceil(input_len / 32) = (input_len + 31) >> 5
    // Layer 0: (122 + 31) >> 5 = 153 >> 5 = 4 
    logic [31:0] macs_per_neuron;
    assign macs_per_neuron = (current_input_len + 31) >> 5;
    
    // To keep MACs reset 
    logic macarr_en_i_q, macarr_en_i_d;
    assign macarr_en_i = macarr_en_i_q;
        
    // Adder Tree Helper
    logic [2:0] adder_tree_cnt_q, adder_tree_cnt_d; 
    
    // PPRAM write address pointers
    logic [PPR_ROW_ADDR_W-1:0] ppram_wr_row_addr_q, ppram_wr_row_addr_d;
    logic [PPR_COL_ADDR_W-1:0] ppram_wr_col_addr_q, ppram_wr_col_addr_d;

    // Read address
    logic [PPR_ROW_ADDR_W-1:0] ppram_rd_addr_q,     ppram_rd_addr_d;

    // ROM address pointers
    logic [W_ROM_ADDR_WIDTH-1:0] w_rom_rd_addr_q,   w_rom_rd_addr_d;
    logic [B_ROM_ADDR_WIDTH-1:0] b_rom_rd_addr_q,   b_rom_rd_addr_d;
    
    // BROM stage registers
    logic [B_ROM_ADDR_WIDTH-1:0] b_rom_layer_base_q, b_rom_layer_base_d;
    
    // FSM counters
    logic bias_cnt_q, bias_cnt_d;  
    logic wb_cnt_q, wb_cnt_d;

    // =========================================================
    // Wire registered addresses to outputs
    // =========================================================
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
            current_layer_q     <= '0;
            w_rom_layer_base_q  <= '0;
            neuron_idx_q        <= '0;
            mac_chunk_cnt_q     <= '0;
            adder_tree_cnt_q    <= '0;
            b_rom_layer_base_q  <= '0;
            bias_cnt_q          <= '0;
            neuron_cnt_q        <= '0;
            macarr_en_i_q       <= '0;
            wb_cnt_q            <= '0;
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
            w_rom_layer_base_q  <= w_rom_layer_base_d;
            neuron_idx_q        <= neuron_idx_d;
            mac_chunk_cnt_q     <= mac_chunk_cnt_d;
            adder_tree_cnt_q    <= adder_tree_cnt_d;
            b_rom_layer_base_q  <= b_rom_layer_base_d;
            bias_cnt_q          <= bias_cnt_d;
            neuron_cnt_q        <= neuron_cnt_d;
            macarr_en_i_q       <= macarr_en_i_d;
            wb_cnt_q            <= wb_cnt_d;
        end
    end

    // =========================================================
    // Combinational Block 
    // =========================================================
    always_comb begin
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
        current_layer_d     = current_layer_q;
        w_rom_layer_base_d  = w_rom_layer_base_q;
        neuron_idx_d        = neuron_idx_q;
        mac_chunk_cnt_d     = mac_chunk_cnt_q;
        adder_tree_cnt_d    = adder_tree_cnt_q;
        b_rom_layer_base_d  = b_rom_layer_base_q;
        bias_cnt_d          = bias_cnt_q;
        neuron_cnt_d        = neuron_cnt_q;
        macarr_en_i_d       = macarr_en_i_q;
        wb_cnt_d            = wb_cnt_q;
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
        macarr_man_rst_ni     = 1'b1;
        mac_reset             = 1'b1;
        ppram_man_rst_ni_o    = 1'b1;
        

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
                    ppram_man_rst_ni_o = 1'b0;
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
                // Combinational
                ppram_ping_pong_sel_o = current_layer_q[0];
            
                if (neuron_idx_q == '0) begin
                    neuron_cnt_d = layer_params_q[current_layer_q];
                end
            
                // PPRAM read always restarts from row 0 for every neuron
                ppram_rd_addr_d = '0;
            
                // MAC chunk counter always restarts from 0
                mac_chunk_cnt_d = '0;
                
                // Addr calculator for each loop
                w_rom_rd_addr_d = w_rom_layer_base_q
                                + W_ROM_ADDR_WIDTH'(neuron_idx_q) * W_ROM_ADDR_WIDTH'(macs_per_neuron);
            
                
                state_d = ST_MAC;
            end
            
            ST_MAC: begin
                ppram_ping_pong_sel_o = current_layer_q[0];
                macarr_en_i_d = 1;
                
                if (mac_chunk_cnt_q == W_ROM_ADDR_WIDTH'(macs_per_neuron)) begin
                        mac_chunk_cnt_d = mac_chunk_cnt_q  + 1'b1;
                        macarr_en_i_d = 0;
                        state_d       = ST_ADD_TREE;
                    end else begin
                        // More chunks to go - advance addresses and counter
                        w_rom_rd_addr_d = w_rom_rd_addr_q + 1'b1;
                        ppram_rd_addr_d = ppram_rd_addr_q  + 1'b1;
                        mac_chunk_cnt_d = mac_chunk_cnt_q  + 1'b1;
                    end
            end
            
            ST_ADD_TREE: begin
                ppram_ping_pong_sel_o = current_layer_q[0];
            
                if (adder_tree_cnt_q == 3'd4) begin
                    // Cycle 5 - data_o is valid at end of this cycle.
                    // Transition so ST_BIAS_RELU sees it stable on cycle 1.
                    adder_tree_cnt_d = '0;                                  // Reset for next neuron
                    b_rom_rd_addr_d  = b_rom_layer_base_q 
                         + B_ROM_ADDR_WIDTH'(neuron_idx_q);
                    state_d          = ST_BIAS;
                    mac_reset        = 1'b0;
                end else begin
                    adder_tree_cnt_d = adder_tree_cnt_q + 1'b1;
                end
            end

            ST_BIAS: begin
                ppram_ping_pong_sel_o = current_layer_q[0];
            
                if (bias_cnt_q == 1'b0) begin
                    // Cycle 1: bias ROM is reading
                    bias_cnt_d = 1'b1;
            
                end else begin
                    // Cycle 2: fp_adder result is valid at end of this
                    bias_cnt_d = 1'b0;
                    
                    ppram_wr_row_addr_d = {2'b00, neuron_idx_q[7:5]};
                    ppram_wr_col_addr_d = {       neuron_idx_q[4:0]};
        
                    state_d    = ST_WB;
                end
            end

            ST_WB: begin
                if(wb_cnt_q == 1'b0) wb_cnt_d = 1'b1;
                else begin    
                    wb_cnt_d = 1'b0;
                    
                    if (current_layer_q == layer_num_q - 1) begin
                        demux_wb_out_sel  = 1'b0;                           // ReLU to regfile path
                        mux_cu_or_wbdemux = 1'b1;                           // Select wb_out into regfile
                        acc_we_o          = 1'b1;                           // Enable regfile write
                        acc_adr_o         = 32'd1 + {24'd0, neuron_idx_q};  // regf_2 index 1..N
                        // mux_wb_in doesn't matter: not writing to PPRAM
            
                    end else begin
                        demux_wb_out_sel  = 1'b1;                           // ReLU to PPRAM path
                        mux_wb_in_sel     = 1'b1;                           // Select wb_out (not regfile) into PPRAM
                        ppram_ping_pong_sel_o = current_layer_q[0];         // Same sel, write goes to opposite bank
                        ppram_wr_en_o     = 1'b1;                           // Enable PPRAM write
                        
                    end
            
                    // Always go to CHECK after one cycle
                    state_d = ST_CHECK;
                end    
            end

            ST_CHECK: begin
                if (neuron_cnt_q == 32'd1) begin
                    w_rom_layer_base_d = w_rom_layer_base_q
                                       + W_ROM_ADDR_WIDTH'(
                                           layer_params_q[current_layer_q] * macs_per_neuron
                                         );
                    b_rom_layer_base_d = b_rom_layer_base_q
                                       + B_ROM_ADDR_WIDTH'(
                                           layer_params_q[current_layer_q]
                                         );
            
                    // Reset neuron tracking for next layer
                    neuron_idx_d = '0;
                    neuron_cnt_d = '0;  // LAYER_INIT reloads this
            
                    if (current_layer_q == layer_num_q - 1) begin
                        // All layers complete
                        state_d = ST_DONE;
                    end else begin
                        current_layer_d = current_layer_q + 1'b1;
                        state_d         = ST_LAYER_INIT;
                    end
            
                end else begin
                    neuron_cnt_d = neuron_cnt_q - 1'b1;
                    neuron_idx_d = neuron_idx_q + 1'b1;
                    state_d      = ST_LAYER_INIT;
                end
            end

            ST_DONE: begin
                acc_we_o          = 1'b1;
                acc_adr_o         = 32'd0;      // regf_2[0] = done register
                acc_dat_o         = 32'd1;      // done = 1
                mux_cu_or_wbdemux = 1'b0;       // CU drives regfile write port directly
                                                // holds ST_DONE until reset
                
                mac_reset = 1'b0;                                
            end

            default: state_d = ST_IDLE;
        endcase
    end

endmodule