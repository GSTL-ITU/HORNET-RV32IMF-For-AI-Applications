`timescale 1ns / 1ps
module pp_ram #(
    parameter WORD_WIDTH  = 32,
    parameter NUM_WORDS   = 32,
    parameter DATA_WIDTH  = WORD_WIDTH * NUM_WORDS,
    parameter MAX_NEURONS = 256,
    parameter ROW_DEPTH   = MAX_NEURONS / NUM_WORDS,
    parameter ROW_ADDR_W  = $clog2(ROW_DEPTH),
    parameter COL_ADDR_W  = $clog2(NUM_WORDS)
)(
    input  logic                  clk_i,
    input  logic                  manual_rst_ni,
    input  logic                  ping_pong_sel,

    // Write port
    input  logic                  wr_en_i,
    input  logic [ROW_ADDR_W-1:0] wr_row_addr_i,
    input  logic [COL_ADDR_W-1:0] wr_col_addr_i,
    input  logic [WORD_WIDTH-1:0] wr_data_i,

    // Read port
    input  logic [ROW_ADDR_W-1:0] rd_addr_i,
    output logic [DATA_WIDTH-1:0] rd_data_o
);
    logic [WORD_WIDTH-1:0] bank_a [0:ROW_DEPTH-1][0:NUM_WORDS-1];
    logic [WORD_WIDTH-1:0] bank_b [0:ROW_DEPTH-1][0:NUM_WORDS-1];

    // =====================================================================
    // ========================= WRITE LOGIC ===============================
    // =====================================================================
    always_ff @(posedge clk_i) begin
        if (!manual_rst_ni) begin
            for (int r = 0; r < ROW_DEPTH; r++) begin
                for (int c = 0; c < NUM_WORDS; c++) begin
                    bank_a[r][c] <= '0;
                    bank_b[r][c] <= '0;
                end
            end
        end else begin
            if (wr_en_i) begin
                if (ping_pong_sel == 1'b0) begin
                    bank_b[wr_row_addr_i][wr_col_addr_i] <= wr_data_i;
                end else begin
                    bank_a[wr_row_addr_i][wr_col_addr_i] <= wr_data_i;
                end
            end
        end
    end

    // =====================================================================
    // ========================= READ LOGIC ================================
    // =====================================================================
    always_ff @(posedge clk_i) begin
        if (!manual_rst_ni) begin
            rd_data_o <= '0;
        end else begin
            for (int i = 0; i < NUM_WORDS; i++) begin
                if (ping_pong_sel == 1'b0) begin
                    rd_data_o[i*WORD_WIDTH +: WORD_WIDTH] <= bank_a[rd_addr_i][i];
                end else begin
                    rd_data_o[i*WORD_WIDTH +: WORD_WIDTH] <= bank_b[rd_addr_i][i];
                end
            end
        end
    end

endmodule