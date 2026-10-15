`timescale 1ns / 1ps

// 冒险检测单元。
//   stall = 1：load-use。PC、IF/ID 保持，ID/EX 进气泡（EX 段空转一拍）。
//   flush = 1：M 段跳转成立。PC 换成目标，IF/ID、ID/EX、EX/M 进气泡。
// 冲刷优先：被冲刷的 ID/EX 两条指令都在错误路径上，停顿它们没有意义，
// 而且停顿会让 PC 保持，此刻 PC 必须换成跳转目标。所以 stall 在冲刷时清 0，
// STALLS 计数器也就只统计实际生效的停顿。
module hazard_unit (
    // ID 段指令
    input  wire [4:0] id_rs1,
    input  wire [4:0] id_rs2,
    input  wire       id_UseRs1,
    input  wire       id_UseRs2,
    input  wire       id_MemWr,     // store 的 rs2 到 M 段才用（DiSrc 补上），不触发停顿
    // EX 段指令
    input  wire [4:0] ex_rd,
    input  wire       ex_MemRead,
    // M 段跳转决定
    input  wire       m_redirect,
    output wire       stall,
    output wire       flush
);

    // 只检查真正会被读、且在 EX 段就要用的源寄存器；写 x0 的 load 没有结果可等
    wire use1 = id_UseRs1 && (id_rs1 == ex_rd);
    wire use2 = id_UseRs2 && !id_MemWr && (id_rs2 == ex_rd);
    wire load_use = ex_MemRead && (ex_rd != 5'd0) && (use1 || use2);

    assign flush = m_redirect;
    assign stall = load_use && !flush;

endmodule
