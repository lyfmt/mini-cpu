`timescale 1ns / 1ps
`include "defines.vh"

// 扩展器：五种立即数拼法各自接好线，由 ExtOp 选一种。符号位总是 inst[31]。
module extender (
    input  wire [31:7] inst,
    input  wire [2:0]  ExtOp,
    output reg  [31:0] imm
);

    always @(*) begin
        case (ExtOp)
            `EXT_I:  imm = {{21{inst[31]}}, inst[30:20]};
            `EXT_S:  imm = {{21{inst[31]}}, inst[30:25], inst[11:7]};
            `EXT_B:  imm = {{20{inst[31]}}, inst[7], inst[30:25], inst[11:8], 1'b0};
            `EXT_U:  imm = {inst[31:12], 12'b0};
            `EXT_J:  imm = {{12{inst[31]}}, inst[19:12], inst[20], inst[30:21], 1'b0};
            default: imm = 32'b0;
        endcase
    end

endmodule
