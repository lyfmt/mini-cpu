`timescale 1ns / 1ps

// 寄存器堆：两读一写。x0 恒读 0，写 x0 被忽略。
// 同周期写和读同一个寄存器时，读端口直接输出即将写入的值（内部旁路），
// 这样所有寄存器都只用上升沿，不必靠下降沿写入来解决"距离 3"的依赖。
module regfile (
    input  wire        clk,
    input  wire [4:0]  ra1,
    input  wire [4:0]  ra2,
    output wire [31:0] rd1,
    output wire [31:0] rd2,
    input  wire        we,
    input  wire [4:0]  wa,
    input  wire [31:0] wd
);

    reg [31:0] regs [0:31];

    // 上电清零，与参考模型的初始状态一致（FPGA 上 initial 可综合）
    integer i;
    initial begin
        for (i = 0; i < 32; i = i + 1)
            regs[i] = 32'b0;
    end

    always @(posedge clk) begin
        if (we && wa != 5'd0)
            regs[wa] <= wd;
    end

    wire byp1 = we && (wa != 5'd0) && (wa == ra1);
    wire byp2 = we && (wa != 5'd0) && (wa == ra2);

    assign rd1 = (ra1 == 5'd0) ? 32'b0 : byp1 ? wd : regs[ra1];
    assign rd2 = (ra2 == 5'd0) ? 32'b0 : byp2 ? wd : regs[ra2];

endmodule
