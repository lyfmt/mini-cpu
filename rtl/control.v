`timescale 1ns / 1ps
`include "defines.vh"

// 主控制器：ID 段一次生成这条指令在后面各段要用的全部控制信号。
// 不认识的指令输出全 0，即气泡的控制信号（不写寄存器、不读写存储器、不改 PC）。
module control (
    input  wire [6:0] opcode,
    input  wire [2:0] funct3,
    input  wire [6:0] funct7,
    output reg  [2:0] ExtOp,
    output reg        ALUASrc,
    output reg  [1:0] ALUBSrc,
    output reg  [3:0] ALUctr,
    output reg        Branch,
    output reg        Jump,
    output reg        MemRead,
    output reg        MemWr,
    output reg        MemtoReg,
    output reg        RegWr,
    // 是否读 rs1 / rs2，供 load-use 检测只检查真正用到的源寄存器
    output reg        UseRs1,
    output reg        UseRs2
);

    always @(*) begin
        // 默认：气泡。"无关"的字段也给固定值，避免仿真出现不定态。
        ExtOp    = `EXT_I;
        ALUASrc  = `ASRC_RS1;
        ALUBSrc  = `BSRC_RS2;
        ALUctr   = `ALU_ADD;
        Branch   = 1'b0;
        Jump     = 1'b0;
        MemRead  = 1'b0;
        MemWr    = 1'b0;
        MemtoReg = 1'b0;
        RegWr    = 1'b0;
        UseRs1   = 1'b0;
        UseRs2   = 1'b0;

        case (opcode)
            `OP_REG: begin
                if (funct7 == 7'b0000000 &&
                    (funct3 == 3'b000 || funct3 == 3'b010 || funct3 == 3'b011)) begin
                    // add / slt / sltu
                    ALUctr = {funct7[5], funct3};
                    RegWr  = 1'b1;
                    UseRs1 = 1'b1;
                    UseRs2 = 1'b1;
                end
            end
            `OP_IMM: begin
                if (funct3 == 3'b110) begin  // ori
                    ExtOp   = `EXT_I;
                    ALUBSrc = `BSRC_IMM;
                    ALUctr  = `ALU_OR;
                    RegWr   = 1'b1;
                    UseRs1  = 1'b1;
                end
            end
            `OP_LUI: begin
                ExtOp   = `EXT_U;
                ALUBSrc = `BSRC_IMM;
                ALUctr  = `ALU_PASSB;  // 结果就是立即数，ALU 直通 B
                RegWr   = 1'b1;
            end
            `OP_LOAD: begin
                if (funct3 == 3'b010) begin  // lw
                    ExtOp    = `EXT_I;
                    ALUBSrc  = `BSRC_IMM;
                    ALUctr   = `ALU_ADD;
                    MemRead  = 1'b1;
                    MemtoReg = 1'b1;
                    RegWr    = 1'b1;
                    UseRs1   = 1'b1;
                end
            end
            `OP_STORE: begin
                if (funct3 == 3'b010) begin  // sw
                    ExtOp   = `EXT_S;
                    ALUBSrc = `BSRC_IMM;
                    ALUctr  = `ALU_ADD;
                    MemWr   = 1'b1;
                    UseRs1  = 1'b1;
                    UseRs2  = 1'b1;
                end
            end
            `OP_BRANCH: begin
                if (funct3 == 3'b000) begin  // beq：ALU 做减法，条件成立 = Zero
                    ExtOp  = `EXT_B;
                    ALUctr = `ALU_SUB;
                    Branch = 1'b1;
                    UseRs1 = 1'b1;
                    UseRs2 = 1'b1;
                end
            end
            `OP_JAL: begin
                // 返回地址 PC+4 由 ALU 算（A=PC, B=4），目标 PC+imm 由目标加法器算
                ExtOp   = `EXT_J;
                ALUASrc = `ASRC_PC;
                ALUBSrc = `BSRC_4;
                ALUctr  = `ALU_ADD;
                Jump    = 1'b1;
                RegWr   = 1'b1;
            end
            default: ;
        endcase
    end

endmodule
