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


module acc_register_file (
    // =====================================================================
    // ========================= HOST INTERFACE ============================
    // =====================================================================
    input  logic        clk_i,
    input  logic        rst_ni,
    input  logic [7:0]  host_wr_idx_i,  // Parsed index: 0 to 131
    input  logic [2:0]  host_rd_idx_i,  // Parsed index: 0 to 5
    input  logic [31:0] host_dat_i,
    input  logic        host_we_i,      // write enable only
    output logic [31:0] host_dat_o,
    
    // =====================================================================
    // ================ ACCELERATOR HARDWARE INTERFACE =====================
    // =====================================================================
    input  logic        acc_we_i,       
    input  logic [31:0] acc_dat_i,
    input  logic [31:0] acc_adr_i,
    output logic [31:0] acc_dat_o
);
    
    logic [31:0] regf_1 [132]; // Host write, ACC read
    logic [31:0] regf_2 [6];   // Host read, ACC write
    
    // =====================================================================
    // ======================== MEMORY-1 LOGIC =============================
    // =====================================================================
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if(!rst_ni) begin
            for (int i=0; i < 132; i++) regf_1[i] <= '0;
        end else if (host_we_i) begin
            regf_1[host_wr_idx_i] <= host_dat_i;
        end
    end
    
    // =====================================================================
    // ======================== MEMORY-2 LOGIC =============================
    // =====================================================================
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if(!rst_ni) begin
            for (int i=0; i < 6; i++) regf_2[i] <= '0;
            host_dat_o <= '0;
        end else begin
            // Acc Write
            if(acc_we_i) begin
                regf_2[acc_adr_i] <= acc_dat_i;
            end
            
            // Host Read (Updates output whenever not writing)
            if(!host_we_i) begin
                host_dat_o <= regf_2[host_rd_idx_i];
            end 
        end
    end

    // =====================================================================
    // ====================== ACCELERATOR READ =============================
    // =====================================================================
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if(!rst_ni) begin
            acc_dat_o <= '0;
        end else if (!acc_we_i) begin
            acc_dat_o <= regf_1[acc_adr_i];
        end
    end
    
endmodule