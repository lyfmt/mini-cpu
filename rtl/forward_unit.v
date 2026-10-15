`timescale 1ns / 1ps
`include "defines.vh"

// 转发单元。
//   BusAFw/BusBFw（EX 段）：10 用 EX/M 的运算结果，01 用 WB 段最终写回值，00 用 ID 段读出值。
//   DiSrc（M 段）：WB 段指令写的正是 store 的 rs2 时，store 数据改用 WB 写回值。
//     只有"load 后紧跟 store"真正需要它：那时 load 的数据在 EX 段还没出来，
//     其余距离的依赖已经在 EX 段转发进 EX/M 的 store 数据里。
module forward_unit (
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
    output wire [1:0] BusAFw,
    output wire [1:0] BusBFw,
    output wire       DiSrc
);

    // 能作为转发来源的条件：真的写寄存器（store、分支的 rd 字段是立即数），且不是 x0。
    // M 段的 load 在 EX/M 里只有访存地址，不是它要写回的数据，所以排除。
    wire m_src  = m_RegWr && !m_MemRead && (m_rd != 5'd0);
    wire wb_src = wb_RegWr && (wb_rd != 5'd0);

    // M 段优先：M 段那条离 EX 更近，值更新
    assign BusAFw = (m_src  && m_rd  == ex_rs1) ? `FW_M  :
                    (wb_src && wb_rd == ex_rs1) ? `FW_WB : `FW_ID;
    assign BusBFw = (m_src  && m_rd  == ex_rs2) ? `FW_M  :
                    (wb_src && wb_rd == ex_rs2) ? `FW_WB : `FW_ID;

    assign DiSrc  = m_MemWr && wb_src && (wb_rd == m_rs2);

endmodule
