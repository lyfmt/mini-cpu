`timescale 1ns / 1ps
`include "defines.vh"

// 比较单元：和 ALU 并列放在 EX 段，输入是转发之后的 rs1、rs2，
// 按 BrOp（即条件分支的 funct3）给出六种条件分支的"条件成立"信号。不是条件分支时输出无关（Branch 为 0）。
module branch_cmp (
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire [2:0]  BrOp,
    output reg         cond
);

    wire eq  = (a == b);
    wire lt  = $signed(a) < $signed(b);
    wire ltu = a < b;

    always @(*) begin
        case (BrOp)
            `BR_EQ:  cond = eq;
            `BR_NE:  cond = !eq;
            `BR_LT:  cond = lt;
            `BR_GE:  cond = !lt;
            `BR_LTU: cond = ltu;
            `BR_GEU: cond = !ltu;
            default: cond = 1'b0;
        endcase
    end

endmodule
