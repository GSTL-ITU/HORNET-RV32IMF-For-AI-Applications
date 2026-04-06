`timescale 1ns / 1ps
module weight_rom #(
    parameter   DATA_WIDTH  = 32,
    parameter   MAC_NUM     = 32,
    parameter   MEM_DEPTH   = 2373,
    parameter   ADDR_WIDTH  = $clog2(MEM_DEPTH),
    parameter   MEMORY_INIT = "weight_init.mem"
)(
    input   logic                               clk_i,
    input   logic   [ADDR_WIDTH-1:0]            rd_addr_i,
    output  logic   [(DATA_WIDTH*MAC_NUM)-1:0]  rd_data_o
    );
    
    // memory array so 1 address = 32 weights (1024 bits)
    logic [(DATA_WIDTH*MAC_NUM)-1:0] mem [0:MEM_DEPTH-1];
    
    initial begin
        $readmemh(MEMORY_INIT, mem);
    end
    
    // single-cycle synchronous read
    always_ff @(posedge clk_i) begin
        rd_data_o <= mem[rd_addr_i];
    end
    
endmodule
