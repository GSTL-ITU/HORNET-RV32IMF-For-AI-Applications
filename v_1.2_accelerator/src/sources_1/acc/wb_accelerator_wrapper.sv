`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/11/2026 06:23:05 PM
// Design Name: 
// Module Name: wb_accelerator_wrapper
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module wb_accelerator_wrapper #(
    parameter W_ROM_DEPTH   = 2373,
    parameter DATA_WIDTH    = 32,
    parameter B_ROM_DEPTH   = 485,
    parameter PPR_NUM_WORDS = 32,
    parameter MAX_NEURONS   = 256,
    parameter MAC_NUM       = 32,
    parameter W_MEM_INIT    = "weight_init.mem",
    parameter B_MEM_INIT    = "bias_init.mem"
)(
    input   logic           wb_rst_i,   // All the wishbone perpiharals receives an active-high reset
    input   logic           wb_clk_i,
    input   logic           wb_cyc_i,
    input   logic           wb_stb_i,
    input   logic           wb_we_i,
    input   logic   [31:0]  wb_adr_i,
    input   logic   [31:0]  wb_dat_i,
    input   logic   [3:0]   wb_sel_i,   // no use
    output  logic           wb_stall_o, // no use
    output  logic           wb_ack_o,
    output  logic   [31:0]  wb_dat_o,
    output                  wb_err_o    // no use 
    );
    
    // We need active-low reset besides the other peripherals
    logic wb_rst_ni;
    assign wb_rst_ni = ~wb_rst_i;   
    
// ---------------------------------------------------------
// Wishbone Parsing & Bus Interface Logic
// ---------------------------------------------------------
    logic       wb_hit_1;
    logic       wb_hit_2;
    logic [7:0] parsed_wr_idx;
    logic [2:0] parsed_rd_idx;
    logic       regf_we_enb;

    // Check Address Ranges
    assign wb_hit_1 = (wb_adr_i >= 32'h1000_9000) && (wb_adr_i <= 32'h1000_920C);
    assign wb_hit_2 = (wb_adr_i >= 32'h1000_9210) && (wb_adr_i <= 32'h1000_9224);

    // Translate to 0-indexed values
    assign parsed_wr_idx = (wb_adr_i - 32'h1000_9000) >> 2;
    assign parsed_rd_idx = (wb_adr_i - 32'h1000_9210) >> 2;

    // Generate Clean Write Enable
    assign regf_we_enb = wb_cyc_i && wb_stb_i && wb_we_i && wb_hit_1 && !wb_ack_o;

    // Generate Wishbone ACK -> No use for Hornet's wishbone
    always_ff @(posedge wb_clk_i or negedge wb_rst_ni) begin
        if (!wb_rst_ni) begin
            wb_ack_o <= 1'b0;
        end else begin
            wb_ack_o <= 1'b0; // Default: drop ACK
            if (wb_cyc_i && wb_stb_i && !wb_ack_o) begin
                if (wb_hit_1 || wb_hit_2) begin
                    wb_ack_o <= 1'b1; 
                end
            end
        end
    end
    
// ---------------------------------------------------------
// Wires & Signals
// ---------------------------------------------------------

    // RegFile Wires
    logic                               w_cu_rf_we;
    logic [31:0]                        w_cu_rf_addr;
    
    // Weights ROM Wires
    logic [$clog2(W_ROM_DEPTH)-1:0]     w_cu_wrom_addr;
    logic [(DATA_WIDTH*MAC_NUM)-1:0]    w_wrom_mac_data;
    
    // PPRAM Wires
    logic                                       w_cu_pp_man_rst_ni;
    logic                                       w_cu_pp_bank_sel;
    logic                                       w_cu_pp_we;
    logic [$clog2(MAX_NEURONS / MAC_NUM)-1:0]   w_cu_pp_wr_row_addr;
    logic [$clog2(MAC_NUM)-1:0]                 w_cu_pp_wr_col_addr;
    logic [$clog2(MAX_NEURONS / MAC_NUM)-1:0]   w_cu_pp_rd_addr;
    logic [(DATA_WIDTH * MAC_NUM)-1:0]          w_pp_mac_data;
    
    // MAC Array Wires
    logic [(DATA_WIDTH * MAC_NUM)-1:0]  w_mac_add_data;
    logic                               w_cu_mac_man_rst_ni;
    logic                               w_cu_mac_en;
    
    // Adder Tree Wires
    logic [DATA_WIDTH-1:0]              w_add_addbias_data;
    
    // Bias ROM Wires
    logic [$clog2(B_ROM_DEPTH)-1:0]     w_cu_brom_addr;
    logic [DATA_WIDTH-1:0]              w_brom_addbias_data;
    
    // Bias Adder Wires
    logic [DATA_WIDTH-1:0]              w_addbias_relu_data;
    
    // WriteBack OUT DEMUX
    logic                               w_cu_demux_wb_out_sel;
    logic [31:0]                        w_demuxWBOut_demuxWBIn_data;
    logic [31:0]                        w_demuxWBOut_muxRegf_in_data;
    logic [31:0]                        w_relu_demuxWBOut_data;
    
    assign w_demuxWBOut_demuxWBIn_data  = (w_cu_demux_wb_out_sel == 1'b1) ? w_relu_demuxWBOut_data : '0;
    assign w_demuxWBOut_muxRegf_in_data = (w_cu_demux_wb_out_sel == 1'b0) ? w_relu_demuxWBOut_data : '0;
    
    // WriteBack IN MUX
    logic                               w_cu_mux_wb_in_sel;
    logic [31:0]                        w_demuxRegf_muxWBIn_data;
    logic [31:0]                        w_muxWBIn_ppramIn_data;
    
    assign w_muxWBIn_ppramIn_data  = (w_cu_mux_wb_in_sel == 1'b0) ? w_demuxRegf_muxWBIn_data : w_demuxWBOut_demuxWBIn_data;
    
    // Regfile Read DEMUX
    logic                               w_demuxRegf_read_sel;
    logic [31:0]                        w_Regf_demuxRegf_data;
    logic [31:0]                        w_demuxRegf_cu_data;
    
    assign w_demuxRegf_cu_data      = (w_demuxRegf_read_sel == 1'b0) ? w_Regf_demuxRegf_data : '0;
    assign w_demuxRegf_muxWBIn_data = (w_demuxRegf_read_sel == 1'b1) ? w_Regf_demuxRegf_data : '0;
    
    // Regfile Write MUX
    logic                               w_muxRegf_write_sel;
    logic [31:0]                        w_cu_muxRegf_write_data;
    logic [31:0]                        w_muxRegf_write_Regf_data;
    
    assign w_muxRegf_write_Regf_data = (w_muxRegf_write_sel == 1'b0) ? w_cu_muxRegf_write_data : w_demuxWBOut_muxRegf_in_data;
    
// ---------------------------------------------------------
// Submodule Instantetions
// ---------------------------------------------------------
   
    acc_control_unit #(
    // Weights ROM Parameters
    .W_ROM_DEPTH        (W_ROM_DEPTH),
    .W_ROM_ADDR_WIDTH   ($clog2(W_ROM_DEPTH)),  
    
    // PP-RAM Parameters
    .PPR_WORD_WIDTH     (DATA_WIDTH),
    .PPR_NUM_WORDS      (PPR_NUM_WORDS),
    .PPR_DATA_WIDTH     (DATA_WIDTH * PPR_NUM_WORDS),
    .PPR_MAX_NEURONS    (MAX_NEURONS),
    .PPR_ROW_DEPTH      (MAX_NEURONS / PPR_NUM_WORDS),
    .PPR_ROW_ADDR_W     ($clog2(MAX_NEURONS / PPR_NUM_WORDS)),
    .PPR_COL_ADDR_W     ($clog2(PPR_NUM_WORDS)),
    
    // Bias ROM Parameters
    .B_ROM_DATA_WIDTH   (DATA_WIDTH),
    .B_ROM_DEPTH        (B_ROM_DEPTH),
    .B_ROM_ADDR_WIDTH   ($clog2(B_ROM_DEPTH))
    
) u_control_unit (
    // Global Signals
    .clk_i                 (wb_clk_i),
    .rst_ni                (wb_rst_ni),
    
    // Regfile Signals
    .acc_we_o              (w_cu_rf_we),
    .acc_dat_o             (w_cu_muxRegf_write_data),
    .acc_adr_o             (w_cu_rf_addr),
    .acc_dat_i             (w_demuxRegf_cu_data),
    
    // Weight ROM Signals
    .w_rom_rd_addr_o       (w_cu_wrom_addr),
    
    // PP-RAM Signals
    .ppram_man_rst_ni_o    (w_cu_pp_man_rst_ni),
    .ppram_ping_pong_sel_o (w_cu_pp_bank_sel),
    .ppram_wr_en_o         (w_cu_pp_we),
    .ppram_wr_row_addr_o   (w_cu_pp_wr_row_addr),
    .ppram_wr_col_addr_o   (w_cu_pp_wr_col_addr),
    .ppram_rd_addr_o       (w_cu_pp_rd_addr),
    
    // MAC Array Signals
    .macarr_man_rst_ni         (w_cu_mac_man_rst_ni),
    .macarr_en_i               (w_cu_mac_en),
    
    // Bias ROM Signals
    .b_rom_rd_addr_o       (w_cu_brom_addr),
    
    // WriteBack MUX/DEMUX Signals
    .mux_wb_in_sel         (w_cu_mux_wb_in_sel),
    .demux_wb_out_sel      (w_cu_demux_wb_out_sel),
    
    // RegFile MUX/DEMUX Signals
    .demux_cu_or_ppram     (w_demuxRegf_read_sel),
    .mux_cu_or_wbdemux     (w_muxRegf_write_sel)
);

// ---------------------------------------------------------
// Register File Instantiation
// ---------------------------------------------------------
    acc_register_file u_register_file (
        // Host Interface
        .clk_i         (wb_clk_i),
        .rst_ni        (wb_rst_ni),
        .host_wr_idx_i (parsed_wr_idx),
        .host_rd_idx_i (parsed_rd_idx),
        .host_dat_i    (wb_dat_i),
        .host_we_i     (regf_we_enb),      
        .host_dat_o    (wb_dat_o),
        
        // Accelerator Hardware Interface
        .acc_we_i      (w_cu_rf_we),
        .acc_dat_i     (w_muxRegf_write_Regf_data),
        .acc_adr_i     (w_cu_rf_addr),
        .acc_dat_o     (w_Regf_demuxRegf_data)
    );
        
// ---------------------------------------------------------
// Weight ROM Instantiation
// ---------------------------------------------------------
    weight_rom #(
        .DATA_WIDTH  (DATA_WIDTH),
        .MAC_NUM     (MAC_NUM),
        .MEM_DEPTH   (W_ROM_DEPTH),
        .ADDR_WIDTH  ($clog2(W_ROM_DEPTH)), 
        .MEMORY_INIT (W_MEM_INIT)
    ) u_weight_rom (
        .clk_i     (wb_clk_i),
        .rd_addr_i (w_cu_wrom_addr),
        .rd_data_o (w_wrom_mac_data)
    );

// ---------------------------------------------------------
// Ping-Pong RAM Instantiation
// ---------------------------------------------------------
    pp_ram #(
        .WORD_WIDTH  (DATA_WIDTH),
        .NUM_WORDS   (MAC_NUM),
        .DATA_WIDTH  (DATA_WIDTH * MAC_NUM),
        .MAX_NEURONS (MAX_NEURONS),
        .ROW_DEPTH   (MAX_NEURONS / MAC_NUM),
        .ROW_ADDR_W  ($clog2(MAX_NEURONS / MAC_NUM)),
        .COL_ADDR_W  ($clog2(MAC_NUM))
    ) u_pp_ram (
        .clk_i         (wb_clk_i),
        .manual_rst_ni (w_cu_pp_man_rst_ni),
        .ping_pong_sel (w_cu_pp_bank_sel),
        
        // Write port
        .wr_en_i       (w_cu_pp_we),
        .wr_row_addr_i (w_cu_pp_wr_row_addr),
        .wr_col_addr_i (w_cu_pp_wr_col_addr),
        .wr_data_i     (w_muxWBIn_ppramIn_data),
        
        // Read port
        .rd_addr_i     (w_cu_pp_rd_addr),
        .rd_data_o     (w_pp_mac_data)
    );
    
// ---------------------------------------------------------
// MAC Array Instantiation
// ---------------------------------------------------------
    mac_array u_mac_array (
        .clk_i          (wb_clk_i),
        .rst_ni         (wb_rst_ni),
        .manual_rst_ni  (w_cu_mac_man_rst_ni),
        .en_i           (w_cu_mac_en),
        .weights_data_i (w_wrom_mac_data),
        .inputs_data_i  (w_pp_mac_data),
        .outputs_data_o (w_mac_add_data),
        .rst_busy_o     ()
    );    

// ---------------------------------------------------------
// Adder Tree Instantiation
// ---------------------------------------------------------
    adder_tree #(
        .INPUTS_NUM  (MAC_NUM),
        .IDATA_WIDTH (DATA_WIDTH)
    ) u_adder_tree (
        .clk_i   (wb_clk_i),
        .rst_ni  (wb_rst_ni),
        .data_i  (w_mac_add_data),
        .data_o  (w_add_addbias_data)
    );

// ---------------------------------------------------------
// Bias ROM Instantiation
// ---------------------------------------------------------
    bias_rom #(
        .DATA_WIDTH  (DATA_WIDTH),
        .MEM_DEPTH   (B_ROM_DEPTH),
        .ADDR_WIDTH  ($clog2(B_ROM_DEPTH)),
        .MEMORY_INIT (B_MEM_INIT)
    ) u_bias_rom (
        .clk_i     (wb_clk_i),
        .rd_addr_i (w_cu_brom_addr),
        .rd_data_o (w_brom_addbias_data)
    );

// ---------------------------------------------------------
// Bias Adder Instantiation
// ---------------------------------------------------------
fp_adder add_bias (
                .aclk                 (wb_clk_i),
                .aresetn              (wb_rst_ni),
                .s_axis_a_tvalid      (1'b1),
                .s_axis_a_tready      (), // Left unconnected
                .s_axis_a_tdata       (w_add_addbias_data),
                .s_axis_b_tvalid      (1'b1),
                .s_axis_b_tready      (), // Left unconnected
                .s_axis_b_tdata       (w_brom_addbias_data),
                .m_axis_result_tvalid (), // Left unconnected
                .m_axis_result_tready (1'b1), 
                .m_axis_result_tdata  (w_addbias_relu_data)
            );

// ---------------------------------------------------------
// ReLU Activation Instantiation
// ---------------------------------------------------------
    relu_act u_relu_act (
        .clk_i  (wb_clk_i),
        .data_i (w_addbias_relu_data),
        .data_o (w_relu_demuxWBOut_data)
    );
endmodule
