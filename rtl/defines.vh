// mini-cpu 公共编码定义。所有 RTL 文件通过 `include "defines.vh" 引入。
`ifndef MINI_CPU_DEFINES_VH
`define MINI_CPU_DEFINES_VH

// ---------------- opcode ----------------
`define OP_LUI     7'b0110111
`define OP_AUIPC   7'b0010111
`define OP_JAL     7'b1101111
`define OP_JALR    7'b1100111
`define OP_BRANCH  7'b1100011
`define OP_LOAD    7'b0000011
`define OP_STORE   7'b0100011
`define OP_IMM     7'b0010011
`define OP_REG     7'b0110011

// ---------------- ExtOp：立即数格式 ----------------
`define EXT_I      3'd0
`define EXT_S      3'd1
`define EXT_B      3'd2
`define EXT_U      3'd3
`define EXT_J      3'd4

// ---------------- ALUASrc：A 端 ----------------
`define ASRC_RS1   1'b0
`define ASRC_PC    1'b1

// ---------------- ALUBSrc：B 端 ----------------
`define BSRC_RS2   2'b00
`define BSRC_IMM   2'b01
`define BSRC_4     2'b10

// ---------------- TargetSrc：目标加法器的基地址 ----------------
`define TSRC_PC    1'b0    // beq 等分支、jal：PC + imm
`define TSRC_RS1   1'b1    // jalr：转发之后的 rs1 + imm

// ---------------- ALUctr ----------------
// 编码取 {inst[30], funct3}：R 型运算和移位立即数直接用它，其余立即数运算取 {0, funct3}
// （它们的 inst[30] 是立即数的一位）。合法指令用不到的组合留给 ALU 自己的运算（直通 B）。
`define ALU_ADD    4'b0000
`define ALU_SLL    4'b0001
`define ALU_SLT    4'b0010
`define ALU_SLTU   4'b0011
`define ALU_XOR    4'b0100
`define ALU_SRL    4'b0101
`define ALU_OR     4'b0110
`define ALU_AND    4'b0111
`define ALU_SUB    4'b1000
`define ALU_SRA    4'b1101
`define ALU_PASSB  4'b1111

// ---------------- 分支条件：funct3 ----------------
`define BR_EQ      3'b000
`define BR_NE      3'b001
`define BR_LT      3'b100
`define BR_GE      3'b101
`define BR_LTU     3'b110
`define BR_GEU     3'b111

// ---------------- 转发选择 BusAFw / BusBFw ----------------
`define FW_ID      2'b00   // ID 段读出的值
`define FW_WB      2'b01   // WB 段最终写回值
`define FW_M       2'b10   // EX/M 中的运算结果

// ---------------- I/O 寄存器字地址（偏移 >> 2，基址 0x8000_0000） ----------------
`define IO_FINISH  29'h0   // 0x00 写
`define IO_CYCLE   29'h1   // 0x04 读
`define IO_INSTRET 29'h2   // 0x08 读
`define IO_STALLS  29'h3   // 0x0C 读
`define IO_FLUSHES 29'h4   // 0x10 读
`define IO_MARK    29'h5   // 0x14 写

`endif
