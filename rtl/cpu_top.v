`timescale 1ns / 1ps

// CPU 顶层：流水线 + 指令存储器 + 数据存储器 + I/O 寄存器。
// 地址第 31 位为 0 访问数据存储器（按 addr[11:2] 索引，越界回绕），为 1 访问 I/O。
// 测试平台通过层次化路径观察内部信号，对外只引出 FINISH / MARK 写入，使综合时整条数据通路都有负载。
module cpu_top #(
    parameter IMEM_INIT = "",
    parameter DMEM_INIT = "",
    parameter HAS_QMUL  = 1    // 1：带模乘单元（rv32i_qmul）；0：去掉模乘单元，qmul 按非法指令处理
) (
    input  wire        clk,
    input  wire        rst,        // 同步复位，高有效
    output wire        finish,     // 当拍写 FINISH
    output wire        mark,       // 当拍写 MARK
    output wire [31:0] io_wdata    // 写入 FINISH / MARK 的值
);

    /* verilator lint_off UNUSEDSIGNAL */  // 只做整字访问，地址低两位以及存储器容量以外的位不用
    wire [31:0] imem_addr;
    wire [31:0] dbus_addr;
    /* verilator lint_on UNUSEDSIGNAL */
    wire [31:0] imem_rdata;
    wire        dbus_re, dbus_we;
    wire [31:0] dbus_wdata, dbus_rdata;
    wire        retire, stall_evt, flush_evt;

    cpu_core #(
        .HAS_QMUL (HAS_QMUL)
    ) u_core (
        .clk        (clk),
        .rst        (rst),
        .imem_addr  (imem_addr),
        .imem_rdata (imem_rdata),
        .dbus_addr  (dbus_addr),
        .dbus_re    (dbus_re),
        .dbus_we    (dbus_we),
        .dbus_wdata (dbus_wdata),
        .dbus_rdata (dbus_rdata),
        .retire     (retire),
        .stall_evt  (stall_evt),
        .flush_evt  (flush_evt)
    );

    imem #(
        .INIT_FILE (IMEM_INIT)
    ) u_imem (
        .addr  (imem_addr[11:2]),
        .rdata (imem_rdata)
    );

    // 地址译码
    wire        sel_io = dbus_addr[31];
    wire [31:0] dmem_rdata, io_rdata;

    dmem #(
        .INIT_FILE (DMEM_INIT)
    ) u_dmem (
        .clk   (clk),
        .addr  (dbus_addr[11:2]),
        .we    (dbus_we & ~sel_io),
        .wdata (dbus_wdata),
        .rdata (dmem_rdata)
    );

    io_regs u_io (
        .clk       (clk),
        .rst       (rst),
        .addr      (dbus_addr[30:2]),
        .re        (dbus_re & sel_io),
        .we        (dbus_we & sel_io),
        .rdata     (io_rdata),
        .retire    (retire),
        .stall     (stall_evt),
        .flush     (flush_evt),
        .finish_we (finish),
        .mark_we   (mark)
    );

    assign dbus_rdata  = sel_io ? io_rdata : dmem_rdata;
    assign io_wdata    = dbus_wdata;

endmodule
