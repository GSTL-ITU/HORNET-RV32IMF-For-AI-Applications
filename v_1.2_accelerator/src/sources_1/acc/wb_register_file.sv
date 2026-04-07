`timescale 1ns / 1ps

// =====================================================================
// ================== Wishbone WR - Acc RD Ports =======================
// =====================================================================
// 1000_9000    Start       ->  rfile_1 000
// 1000_9004    Layer_num   ->  rfile_1 001
// 1000_9008    layer[0]    ->  rfile_1 002
// 1000_900C    layer[1]    ->  rfile_1 003
// 1000_9010    layer[2]    ->  rfile_1 004
// 1000_9014    layer[3]    ->  rfile_1 005
// 1000_9018    layer[4]    ->  rfile_1 006
// 1000_901C    layer[5]    ->  rfile_1 007
// 1000_9020    layer[6]    ->  rfile_1 008
// 1000_9024    layer[7]    ->  rfile_1 009
// 1000_9028    input[0]    ->  rfile_1 010
//                ...
// 1000_920C    input[121]  ->  rfile_1 131 

// =====================================================================
// ================== Wishbone RD - Acc WR Ports =======================
// =====================================================================

// 1000_9210    done        ->  rfile_2 000
// 1000_9214    output[0]   ->  rfile_2 001
// 1000_9218    output[1]   ->  rfile_2 002
// 1000_921C    output[2]   ->  rfile_2 003
// 1000_9220    output[3]   ->  rfile_2 004
// 1000_9224    output[4]   ->  rfile_2 005


module wb_register_file (
    // =====================================================================
    // ==================== WISHBONE SLAVE INTERFACE =======================
    // =====================================================================
    input  logic        clk_i,
    input  logic        rst_ni,
    input  logic [31:0] wb_adr_i, 
    input  logic [31:0] wb_dat_i, 
    input  logic        wb_we_i,  
    input  logic        wb_stb_i, 
    input  logic        wb_cyc_i, 
    output logic [31:0] wb_dat_o, 
    output logic        wb_ack_o, 
    
    // =====================================================================
    // ================ ACCELERATOR HARDWARE INTERFACE =====================
    // =====================================================================
    // Control & Params 
    input  logic        acc_we_i,       // we = 0 -> read; we = 1 -> write
    input  logic [31:0] acc_dat_i,
    input  logic [31:0] acc_adr_i,
    output logic [31:0] acc_dat_o
);
    
    // WB write, ACC read mem
    logic [31:0] regf_1 [132];          // 122 inputs, 1 layer num, 8 layer widths, 1 start
    
    // WB read, ACC write mem
    logic [31:0] regf_2 [6];            // 5 outputs, 1 done
    
    // =====================================================================
    // ======================== MEMORY-1 LOGIC =============================
    // =====================================================================
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if(!rst_ni) begin
            for (int i=0; i < 132; i++) regf_1[i] <= '0;
        end else begin
            if(wb_we_i) begin
                regf_1[wb_adr_i] <= wb_dat_i;
            end else begin
                wb_dat_o <= regf_2[wb_adr_i];
            end    
        end
    end
    
    // =====================================================================
    // ======================== MEMORY-2 LOGIC =============================
    // =====================================================================
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if(!rst_ni) begin
            for (int i=0; i < 6; i++) regf_2[i] <= '0;
        end else begin
            if(acc_we_i) begin
                regf_2[acc_adr_i] <= acc_dat_i;
            end else begin
                acc_dat_o <= regf_1[acc_adr_i];
            end    
        end
    end
    
endmodule