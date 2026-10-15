`timescale 1ns / 1ps

// 冒险检测单元：load-use 停顿（ID 段检测）和跳转冲刷（M 段决定）。
// 阶段 1 输出固定为"不停顿、不冲刷"，接口按阶段 2 的需要先定好。
//   stall = 1：PC、IF/ID 保持，ID/EX 进气泡
//   flush = 1：IF/ID、ID/EX、EX/M 进气泡（优先于 stall）
module hazard_unit (
    /* verilator lint_off UNUSEDSIGNAL */  // 阶段 1 桩，输入暂未使用
    // ID 段指令
    input  wire [4:0] id_rs1,
    input  wire [4:0] id_rs2,
    input  wire       id_UseRs1,
    input  wire       id_UseRs2,
    input  wire       id_MemWr,     // store 的 rs2 到 M 段才用，不触发停顿
    // EX 段指令
    input  wire [4:0] ex_rd,
    input  wire       ex_MemRead,
    // M 段跳转决定
    input  wire       m_redirect,
    /* verilator lint_on UNUSEDSIGNAL */
    output wire       stall,
    output wire       flush
);

    assign stall = 1'b0;
    assign flush = 1'b0;

endmodule
