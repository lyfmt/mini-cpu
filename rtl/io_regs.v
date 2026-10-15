`timescale 1ns / 1ps
`include "defines.vh"

// I/O 寄存器（基址 0x8000_0000，由 cpu_top 按地址第 31 位选中）。
// 计数器在复位时清零，读出的是当拍的值。读未定义偏移返回 0，写只读寄存器被忽略。
module io_regs (
    input  wire        clk,
    input  wire        rst,
    input  wire [30:2] addr,        // 偏移的字地址
    input  wire        re,
    input  wire        we,
    output reg  [31:0] rdata,
    // 计数事件，来自流水线
    input  wire        retire,      // WB 段有效
    input  wire        stall,
    input  wire        flush,
    // 写 FINISH / MARK 的当拍脉冲（写入的值就是 store 数据），测试平台据此结束仿真或打点
    output wire        finish_we,
    output wire        mark_we
);

    reg [31:0] cycle_cnt;
    reg [31:0] instret_cnt;
    reg [31:0] stall_cnt;
    reg [31:0] flush_cnt;

    always @(posedge clk) begin
        if (rst) begin
            cycle_cnt   <= 32'b0;
            instret_cnt <= 32'b0;
            stall_cnt   <= 32'b0;
            flush_cnt   <= 32'b0;
        end else begin
            cycle_cnt <= cycle_cnt + 32'd1;
            if (retire) instret_cnt <= instret_cnt + 32'd1;
            if (stall)  stall_cnt   <= stall_cnt + 32'd1;
            if (flush)  flush_cnt   <= flush_cnt + 32'd1;
        end
    end

    always @(*) begin
        rdata = 32'b0;
        if (re) begin
            case (addr)
                `IO_CYCLE:   rdata = cycle_cnt;
                `IO_INSTRET: rdata = instret_cnt;
                `IO_STALLS:  rdata = stall_cnt;
                `IO_FLUSHES: rdata = flush_cnt;
                default:     rdata = 32'b0;
            endcase
        end
    end

    assign finish_we = we && (addr == `IO_FINISH);
    assign mark_we   = we && (addr == `IO_MARK);

endmodule
