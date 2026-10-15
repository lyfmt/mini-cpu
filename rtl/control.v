`timescale 1ns / 1ps
`include "defines.vh"

// 主控制器：ID 段一次生成这条指令在后面各段要用的全部控制信号。
// 不在 rv32i_qmul 范围内的指令（字节/半字访存、fence、ecall/ebreak、CSR、custom-0 里 qmul
// 以外的编码、funct7 不合法的 R 型、第 25 位非 0 的移位立即数……）输出全 0，即气泡的控制信号
// （不写寄存器、不读写存储器、不改 PC）。HAS_QMUL = 0 时 qmul 本身也按非法指令处理。
module control #(
    parameter HAS_QMUL = 1
) (
    input  wire [6:0] opcode,
    input  wire [2:0] funct3,
    input  wire [6:0] funct7,
    output reg  [2:0] ExtOp,
    output reg        ALUASrc,
    output reg  [1:0] ALUBSrc,
    output reg  [3:0] ALUctr,
    output reg        TargetSrc,   // 目标加法器的基地址：PC 或 rs1（jalr）
    output reg  [2:0] BrOp,        // 比较单元的条件，即条件分支的 funct3
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

    // R 型：funct7 只能是 0000000，add/sub 和 srl/sra 还可以是 0100000
    wire reg_ok = (funct7 == 7'b0000000) ||
                  (funct7 == 7'b0100000 && (funct3 == 3'b000 || funct3 == 3'b101));
    // 移位立即数：inst[31:25] 同样只能是 0000000，srai 是 0100000；
    // 其余立即数运算的 inst[31:25] 是立即数，不检查
    wire imm_ok = (funct3 == 3'b001) ? (funct7 == 7'b0000000) :
                  (funct3 == 3'b101) ? (funct7 == 7'b0000000 || funct7 == 7'b0100000) :
                                       1'b1;
    // 条件分支：funct3 的 010、011 没有定义
    wire br_ok  = (funct3 != 3'b010) && (funct3 != 3'b011);

    always @(*) begin
        // 默认：气泡。"无关"的字段也给固定值，避免仿真出现不定态。
        ExtOp     = `EXT_I;
        ALUASrc   = `ASRC_RS1;
        ALUBSrc   = `BSRC_RS2;
        ALUctr    = `ALU_ADD;
        TargetSrc = `TSRC_PC;
        BrOp      = `BR_EQ;
        Branch    = 1'b0;
        Jump      = 1'b0;
        MemRead   = 1'b0;
        MemWr     = 1'b0;
        MemtoReg  = 1'b0;
        RegWr     = 1'b0;
        UseRs1    = 1'b0;
        UseRs2    = 1'b0;

        case (opcode)
            `OP_REG: begin
                if (reg_ok) begin
                    // add sub sll slt sltu xor srl sra or and：ALU 编码就是 {inst[30], funct3}
                    ALUctr = {funct7[5], funct3};
                    RegWr  = 1'b1;
                    UseRs1 = 1'b1;
                    UseRs2 = 1'b1;
                end
            end
            `OP_IMM: begin
                if (imm_ok) begin
                    // addi slti sltiu xori ori andi：{0, funct3}；
                    // slli srli srai：和 R 型一样取 {inst[30], funct3}，移位量是立即数的低 5 位
                    ExtOp   = `EXT_I;
                    ALUBSrc = `BSRC_IMM;
                    ALUctr  = (funct3 == 3'b101) ? {funct7[5], funct3} : {1'b0, funct3};
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
            `OP_AUIPC: begin
                ExtOp   = `EXT_U;
                ALUASrc = `ASRC_PC;    // PC + (imm20 << 12)
                ALUBSrc = `BSRC_IMM;
                ALUctr  = `ALU_ADD;
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
                if (br_ok) begin
                    // 条件由 EX 段的比较单元按 funct3 给出，不占用 ALU；目标 = PC + imm
                    ExtOp  = `EXT_B;
                    BrOp   = funct3;
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
            `OP_JALR: begin
                if (funct3 == 3'b000) begin
                    // 返回地址同 jal；目标 = (rs1 + imm) 最低位清零，基地址取转发之后的 rs1
                    ExtOp     = `EXT_I;
                    ALUASrc   = `ASRC_PC;
                    ALUBSrc   = `BSRC_4;
                    ALUctr    = `ALU_ADD;
                    TargetSrc = `TSRC_RS1;
                    Jump      = 1'b1;
                    RegWr     = 1'b1;
                    UseRs1    = 1'b1;
                end
            end
            `OP_CUSTOM0: begin
                if (HAS_QMUL != 0 && funct3 == 3'b000 && funct7 == 7'b0000000) begin
                    // qmul：和 R 型运算一样读 rs1、rs2，结果由 EX 段的结果选择器取模乘单元的输出
                    ALUctr = `ALU_QMUL;
                    RegWr  = 1'b1;
                    UseRs1 = 1'b1;
                    UseRs2 = 1'b1;
                end
            end
            default: ;
        endcase
    end

endmodule
