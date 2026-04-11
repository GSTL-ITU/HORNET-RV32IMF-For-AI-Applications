`timescale 1ns / 1ps

module mac_array (
    input  logic          clk_i,
    input  logic          rst_ni,          // System reset, active-low
    input  logic          manual_rst_ni,   // CU-driven flush, active-low pulse
    input  logic          en_i,            // Active-high enable. LOW freezes all MACs
    input  logic [1023:0] weights_data_i,
    input  logic [1023:0] inputs_data_i,
    output logic [1023:0] outputs_data_o,
    output logic          rst_busy_o       // HIGH while internal reset is being stretched
);

    
    logic rst_stretch_q [2];   // 2-stage shift register
    logic aresetn_int;         // Combined reset to fp_mac instances
    logic raw_rst;             // 1 = both inputs are de-asserted

    assign raw_rst     = rst_ni & manual_rst_ni;  // Both active-low: AND = "all released"
    assign aresetn_int = rst_stretch_q[0] & rst_stretch_q[1];
    assign rst_busy_o  = ~aresetn_int;           // Busy while either stage is still 0

    // =========================================================
    // Array Declarations
    // =========================================================
    logic [31:0] weights [32];
    logic [31:0] inputs  [32];
    logic [31:0] mac_out [32];
    
    always_ff @(posedge clk_i) begin
        rst_stretch_q[1] <= raw_rst;
        rst_stretch_q[0] <= rst_stretch_q[1];
        
        if(!aresetn_int) begin
            for(int i = 0; i<32; i++) mac_out[i] = '0;
        end
    end
    
    // =========================================================
    // Unpack / Pack - no c_in mux, no last_i, no feedback
    // =========================================================
    always_comb begin
        for (int i = 0; i < 32; i++) begin
            weights[i] = weights_data_i[i*32 +: 32];
            inputs[i]  = inputs_data_i [i*32 +: 32];
            outputs_data_o[i*32 +: 32] = mac_out[i];
        end
    end

    
    genvar i;
    generate
        for (i = 0; i < 32; i++) begin : gen_mac
            fp_mac mac_inst (
                .aclk                 (clk_i),
                .aresetn              (aresetn_int),
                .aclken               (en_i),

                .s_axis_a_tvalid      (1'b1),
                .s_axis_a_tdata       (weights[i]),

                .s_axis_b_tvalid      (1'b1),
                .s_axis_b_tdata       (inputs[i]),

                .s_axis_c_tvalid      (1'b1),
                .s_axis_c_tdata       (mac_out[i]),

                .m_axis_result_tvalid (),
                .m_axis_result_tdata  (mac_out[i])
            );
        end
    endgenerate

endmodule