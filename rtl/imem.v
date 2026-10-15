`timescale 1ns / 1ps

// 指令存储器：1024 字，分布式 RAM 写法（组合逻辑读出），IF 段当拍取出指令。
// 没有写端口：数据通路里没有写指令存储器的路径。
// INIT_FILE 供综合指定初始镜像；仿真时留空，由测试平台按 plusargs 用 $readmemh 载入。
module imem #(
    parameter INIT_FILE = ""
) (
    input  wire [9:0]  addr,   // 字地址
    output wire [31:0] rdata
);

    reg [31:0] mem [0:1023];

    initial begin
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, mem);
    end

    assign rdata = mem[addr];

endmodule
