`timescale 1ns / 1ps

module adder_tree #(
    parameter INPUTS_NUM = 32,
    parameter IDATA_WIDTH = 32
)(
    input  logic            clk_i,
    input  logic            rst_ni,
    input  logic [1023:0]   data_i, // 1024-bit flat input bus
    output logic [31:0]     data_o  // 32-bit floating point output
);

    // ========================================================================
    // PIPELINE STAGE ARRAYS
    // ========================================================================
    // We create arrays to hold the floating-point values between each stage.
    logic [31:0] stage0 [32]; // Inputs
    logic [31:0] stage1 [16]; // After 1st stage of adders
    logic [31:0] stage2 [8];  // After 2nd stage
    logic [31:0] stage3 [4];  // After 3rd stage
    logic [31:0] stage4 [2];  // After 4th stage
    
    // Unpack the 1024-bit flat input bus into our 32-element array
    always_comb begin
        for (int i = 0; i < 32; i++) begin
            stage0[i] = data_i[i*32 +: 32];
        end
    end

    // ========================================================================
    // ADDER TREE GENERATION
    // ========================================================================
    genvar i;
    generate
        // STAGE 1: 32 inputs -> 16 outputs
        for (i = 0; i < 16; i++) begin : gen_stage1
            fp_adder add_s1 (
                .aclk                 (clk_i),
                .aresetn              (rst_ni),
                .s_axis_a_tvalid      (1'b1),
                .s_axis_a_tready      (), // Left unconnected
                .s_axis_a_tdata       (stage0[2*i]),
                .s_axis_b_tvalid      (1'b1),
                .s_axis_b_tready      (), // Left unconnected
                .s_axis_b_tdata       (stage0[2*i+1]),
                .m_axis_result_tvalid (), // Left unconnected
                .m_axis_result_tready (1'b1), 
                .m_axis_result_tdata  (stage1[i])
            );
        end

        // STAGE 2: 16 inputs -> 8 outputs
        for (i = 0; i < 8; i++) begin : gen_stage2
            fp_adder add_s2 (
                .aclk                 (clk_i),
                .aresetn              (rst_ni),
                .s_axis_a_tvalid      (1'b1),
                .s_axis_a_tready      (), 
                .s_axis_a_tdata       (stage1[2*i]),
                .s_axis_b_tvalid      (1'b1),
                .s_axis_b_tready      (), 
                .s_axis_b_tdata       (stage1[2*i+1]),
                .m_axis_result_tvalid (), 
                .m_axis_result_tready (1'b1), 
                .m_axis_result_tdata  (stage2[i])
            );
        end

        // STAGE 3: 8 inputs -> 4 outputs
        for (i = 0; i < 4; i++) begin : gen_stage3
            fp_adder add_s3 (
                .aclk                 (clk_i),
                .aresetn              (rst_ni),
                .s_axis_a_tvalid      (1'b1),
                .s_axis_a_tready      (), 
                .s_axis_a_tdata       (stage2[2*i]),
                .s_axis_b_tvalid      (1'b1),
                .s_axis_b_tready      (), 
                .s_axis_b_tdata       (stage2[2*i+1]),
                .m_axis_result_tvalid (), 
                .m_axis_result_tready (1'b1), 
                .m_axis_result_tdata  (stage3[i])
            );
        end

        // STAGE 4: 4 inputs -> 2 outputs
        for (i = 0; i < 2; i++) begin : gen_stage4
            fp_adder add_s4 (
                .aclk                 (clk_i),
                .aresetn              (rst_ni),
                .s_axis_a_tvalid      (1'b1),
                .s_axis_a_tready      (), 
                .s_axis_a_tdata       (stage3[2*i]),
                .s_axis_b_tvalid      (1'b1),
                .s_axis_b_tready      (), 
                .s_axis_b_tdata       (stage3[2*i+1]),
                .m_axis_result_tvalid (), 
                .m_axis_result_tready (1'b1), 
                .m_axis_result_tdata  (stage4[i])
            );
        end

        // STAGE 5: 2 inputs -> 1 final output
        fp_adder add_s5 (
            .aclk                 (clk_i),
            .aresetn              (rst_ni),
            .s_axis_a_tvalid      (1'b1),
            .s_axis_a_tready      (), 
            .s_axis_a_tdata       (stage4[0]),
            .s_axis_b_tvalid      (1'b1),
            .s_axis_b_tready      (), 
            .s_axis_b_tdata       (stage4[1]),
            .m_axis_result_tvalid (), 
            .m_axis_result_tready (1'b1), 
            .m_axis_result_tdata  (data_o)
        );
    endgenerate

endmodule