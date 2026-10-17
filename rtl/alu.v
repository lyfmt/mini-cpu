`timescale 1ns / 1ps
`include "defines.vh"

// ALU。分支条件由并列的比较单元（branch_cmp）给出，ALU 只管运算结果。
// 移位量只取 B 端的低 5 位。
module alu (
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire [3:0]  ALUctr,
    output reg  [31:0] y
);

    wire [4:0] shamt = b[4:0];

    always @(*) begin
        case (ALUctr)
            `ALU_ADD:   y = a + b;
            `ALU_SUB:   y = a - b;
            `ALU_SLL:   y = a << shamt;
            `ALU_SLT:   y = {31'b0, $signed(a) < $signed(b)};
            `ALU_SLTU:  y = {31'b0, a < b};
            `ALU_XOR:   y = a ^ b;
            `ALU_SRL:   y = a >> shamt;
            `ALU_SRA:   y = $signed(a) >>> shamt;
            `ALU_OR:    y = a | b;
            `ALU_AND:   y = a & b;
            `ALU_PASSB: y = b;  // lui：结果直接取 B 端的立即数，A 端无需提供常数 0
            default:    y = 32'b0;
        endcase
    end

endmodule
