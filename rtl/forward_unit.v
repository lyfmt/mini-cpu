`timescale 1ns / 1ps
`include "defines.vh"

// 转发单元（EX 段的 BusAFw/BusBFw，M 段的 DiSrc）。
// 阶段 1 不做转发：选择信号固定为 00 / 0，接口按阶段 2 的需要先定好。
module forward_unit (
    /* verilator lint_off UNUSEDSIGNAL */  // 阶段 1 桩，输入暂未使用
    // EX 段指令的源寄存器
    input  wire [4:0] ex_rs1,
    input  wire [4:0] ex_rs2,
    // M 段指令（EX/M）
    input  wire [4:0] m_rd,
    input  wire       m_RegWr,
    input  wire       m_MemRead,  // M 段的 load 不参与 EX/M 转发
    input  wire [4:0] m_rs2,      // store 数据寄存器，DiSrc 用
    input  wire       m_MemWr,
    // WB 段指令（M/WB）
    input  wire [4:0] wb_rd,
    input  wire       wb_RegWr,
    /* verilator lint_on UNUSEDSIGNAL */
    output wire [1:0] BusAFw,
    output wire [1:0] BusBFw,
    output wire       DiSrc
);

    assign BusAFw = `FW_ID;
    assign BusBFw = `FW_ID;
    assign DiSrc  = 1'b0;

endmodule
