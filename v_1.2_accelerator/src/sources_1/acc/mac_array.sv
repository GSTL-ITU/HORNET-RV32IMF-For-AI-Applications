`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/11/2026 06:23:05 PM
// Design Name: 
// Module Name: mac_array
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


`timescale 1ns / 1ps
module mac_array (
    input  logic          clk_i,
    input  logic          rst_ni,
    input  logic          last_i,          // Pulse HIGH on the last chunk of a neuron
    input  logic [1023:0] weights_data_i,
    input  logic [1023:0] inputs_data_i,
    output logic [1023:0] outputs_data_o  
);

    // =========================================================
    // Array Declarations
    // =========================================================
    logic [31:0] weights [32];
    logic [31:0] inputs  [32];
    logic [31:0] mac_out [32];
    logic [31:0] c_in    [32];

    // last_i delayed by one cycle.
    logic last_i_q;
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) last_i_q <= 1'b0;
        else         last_i_q <= last_i;
    end

    // =========================================================
    // Unpack / Pack Buses + C MUX
    // =========================================================
    always_comb begin
        for (int i = 0; i < 32; i++) begin
            weights[i] = weights_data_i[i*32 +: 32];
            inputs[i]  = inputs_data_i [i*32 +: 32];

            // Use the DELAYED last signal to clear C.
            // Cycle N   (last chunk):     c_in = mac_out  ← accumulate normally
            // Cycle N+1 (first new chunk): c_in = 0       ← fresh start
            c_in[i] = last_i_q ? 32'h00000000 : mac_out[i];

            outputs_data_o[i*32 +: 32] = mac_out[i];
        end
    end

    // =========================================================
    // MAC Array Instantiation
    // =========================================================
    genvar i;
    generate
        for (i = 0; i < 32; i++) begin : gen_mac
            fp_mac mac_inst (
                .aclk                 (clk_i),
                .aresetn              (rst_ni),
                
                .s_axis_a_tvalid      (1'b1),
                .s_axis_a_tready      (),
                .s_axis_a_tdata       (weights[i]),
                .s_axis_a_tlast       (last_i),     // Pass through for IP bookkeeping
                
                .s_axis_b_tvalid      (1'b1),
                .s_axis_b_tready      (),
                .s_axis_b_tdata       (inputs[i]),
                
                .s_axis_c_tvalid      (1'b1),
                .s_axis_c_tready      (),
                .s_axis_c_tdata       (c_in[i]),    // Zero on first chunk of new neuron
                
                .m_axis_result_tvalid (),
                .m_axis_result_tready (1'b1),
                .m_axis_result_tdata  (mac_out[i]),
                .m_axis_result_tlast  ()
            );
        end
    endgenerate

endmodule