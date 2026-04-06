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

module mac_array(
    input  logic                 clk_i,
    input  logic                 rst_ni,
    input  logic                 last_i, // MUX control: 1 = clear accumulator, 0 = accumulate
    input  logic [1023:0]        weights_data_i,
    input  logic [1023:0]        inputs_data_i,
    output logic [1023:0]        outputs_data_o  
);

    // ========================================================================
    // ARRAY DECLARATIONS
    // ========================================================================
    logic [31:0] weights [32];
    logic [31:0] inputs  [32];
    logic [31:0] mac_out [32];
    logic [31:0] c_in    [32]; // The MUX output going into the C port

    // Unpack 1024-bit flat buses into 32-bit arrays
    always_comb begin
        for (int i = 0; i < 32; i++) begin
            weights[i] = weights_data_i[i*32 +: 32];
            inputs[i]  = inputs_data_i[i*32 +: 32];
            
            // Pack the output array back into the flat bus
            outputs_data_o[i*32 +: 32] = mac_out[i];
        end
    end

    // ========================================================================
    // MAC GENERATION & MUX LOGIC
    // ========================================================================
    genvar i;
    generate
        for (i = 0; i < 32; i++) begin : gen_mac
            
            // The 2-to-1 MUX you requested: 
            // If 'last_i' is high, feed 0 into C to start a fresh accumulation.
            // Otherwise, loop the MAC output back into C.
            assign c_in[i] = last_i ? 32'h00000000 : mac_out[i];

            fp_mac mac_inst (
                .aclk                 (clk_i),
                .aresetn              (rst_ni),
                
                // Input A (Weights)
                .s_axis_a_tvalid      (1'b1),
                .s_axis_a_tready      (), 
                .s_axis_a_tdata       (weights[i]),
                .s_axis_a_tlast       (last_i),
                
                // Input B (Inputs)
                .s_axis_b_tvalid      (1'b1),
                .s_axis_b_tready      (),
                .s_axis_b_tdata       (inputs[i]),
                
                // Input C (Feedback Accumulator via MUX)
                .s_axis_c_tvalid      (1'b1),
                .s_axis_c_tready      (),
                .s_axis_c_tdata       (c_in[i]),
                
                // Output Result
                .m_axis_result_tvalid (), 
                .m_axis_result_tready (1'b1),
                .m_axis_result_tdata  (mac_out[i]),
                .m_axis_result_tlast  () 
            );
        end
    endgenerate

endmodule