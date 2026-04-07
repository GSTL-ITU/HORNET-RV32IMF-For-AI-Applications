`timescale 1ns / 1ps

module pp_ram #(
    parameter WORD_WIDTH  = 32,
    parameter NUM_WORDS   = 32,
    parameter DATA_WIDTH  = WORD_WIDTH * NUM_WORDS,   // 1024 bits
    parameter MAX_NEURONS = 256,
    parameter ROW_DEPTH   = MAX_NEURONS / NUM_WORDS,  // 8 rows
    parameter ROW_ADDR_W  = $clog2(ROW_DEPTH),        // 3 bits
    parameter COL_ADDR_W  = $clog2(NUM_WORDS)         // 5 bits
)(
    input  logic                  clk_i,
    input  logic                  ping_pong_sel, 
    
    // Write port (Writes ONE 32-bit float at a time)
    input  logic                  wr_en_i,
    input  logic [ROW_ADDR_W-1:0] wr_row_addr_i, // Which 1024-bit chunk (0-7)
    input  logic [COL_ADDR_W-1:0] wr_col_addr_i, // Which 32-bit slice inside that chunk (0-31)
    input  logic [WORD_WIDTH-1:0] wr_data_i,     // The 32-bit ReLU output
    
    // Read port (Reads THIRTY-TWO floats at once)
    input  logic [ROW_ADDR_W-1:0] rd_addr_i,     // Which 1024-bit chunk to read (0-7)
    output logic [DATA_WIDTH-1:0] rd_data_o
);

    // Memory banks as 2D arrays: [8 rows] x [32 columns] of 32-bit words
    logic [WORD_WIDTH-1:0] bank_a [0:ROW_DEPTH-1][0:NUM_WORDS-1];
    logic [WORD_WIDTH-1:0] bank_b [0:ROW_DEPTH-1][0:NUM_WORDS-1];

    // =====================================================================
    // ========================= WRITE LOGIC ===============================
    // =====================================================================
    always_ff @(posedge clk_i) begin
        if (wr_en_i) begin
            if (ping_pong_sel == 1'b0) begin
                bank_b[wr_row_addr_i][wr_col_addr_i] <= wr_data_i; // Write to B
            end else begin
                bank_a[wr_row_addr_i][wr_col_addr_i] <= wr_data_i; // Write to A
            end
        end
    end

    // =====================================================================
    // ========================= READ LOGIC ================================
    // =====================================================================
    always_ff @(posedge clk_i) begin
        // Loop through the 32 columns and pack them into the flat output bus
        for (int i = 0; i < NUM_WORDS; i++) begin
            if (ping_pong_sel == 1'b0) begin
                rd_data_o[i*WORD_WIDTH +: WORD_WIDTH] <= bank_a[rd_addr_i][i]; // Read A
            end else begin
                rd_data_o[i*WORD_WIDTH +: WORD_WIDTH] <= bank_b[rd_addr_i][i]; // Read B
            end
        end
    end

endmodule