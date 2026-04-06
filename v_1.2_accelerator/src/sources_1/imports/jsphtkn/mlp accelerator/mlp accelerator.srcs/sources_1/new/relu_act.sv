`timescale 1ns / 1ps

module relu_act(
    input   logic   [31:0]  data_i,
    output  logic   [31:0]  data_o
    );
    
    // If the sign bit [31] is 1 (negative), output 0.0
    // Otherwise, pass the positive float straight through.
    assign data_o = data_i[31] ? '0 : data_i;
    
endmodule
