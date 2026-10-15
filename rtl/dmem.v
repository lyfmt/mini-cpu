`timescale 1ns / 1ps

// 数据存储器：1024 字，分布式 RAM 写法（组合逻辑读出、上升沿写入），M 段当拍读出。
// 只做整字访问。INIT_FILE 用法同 imem。
module dmem #(
    parameter INIT_FILE = ""
) (
    input  wire        clk,
    input  wire [9:0]  addr,   // 字地址
    input  wire        we,
    input  wire [31:0] wdata,
    output wire [31:0] rdata
);

    reg [31:0] mem [0:1023];

    initial begin
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, mem);
    end

    always @(posedge clk) begin
        if (we)
            mem[addr] <= wdata;
    end

    assign rdata = mem[addr];

endmodule
