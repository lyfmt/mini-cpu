`timescale 1ns / 1ps
`include "defines.vh"

// ALU。zero 用作 beq 的"条件成立"。
module alu (
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire [3:0]  ALUctr,
    output reg  [31:0] y,
    output wire        zero
);

    always @(*) begin
        case (ALUctr)
            `ALU_ADD:   y = a + b;
            `ALU_SUB:   y = a - b;
            `ALU_SLT:   y = {31'b0, $signed(a) < $signed(b)};
            `ALU_SLTU:  y = {31'b0, a < b};
            `ALU_OR:    y = a | b;
            `ALU_PASSB: y = b;  // lui：结果就是 B 端的立即数，A 端选择器因此保持两路
            default:    y = 32'b0;
        endcase
    end

    assign zero = (y == 32'b0);

endmodule
