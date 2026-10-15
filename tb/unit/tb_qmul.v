`timescale 1ns / 1ps

// qmul_unit 穷举单元测试：
//   1. 低 12 位的全部 4096 × 4096 种组合（高位为 0），与 (a·b) mod 3329 比较；
//   2. 抽查 NRAND 组高位随机的 32 位输入，确认只取了低 12 位、输出高 20 位为 0。
// 用 sim/run_unit.sh 运行（verilator --binary --timing；没有 verilator 时用 iverilog，慢一些）。
module tb_qmul;
    parameter NRAND = 1000000;

    reg  [31:0] rs1, rs2;
    wire [31:0] y;

    qmul_unit dut (.rs1(rs1), .rs2(rs2), .y(y));

    integer a, b, k, errs, seed;
    reg [31:0] expect_y;

    task check;
        begin
            #1;
            expect_y = ((rs1 & 32'hfff) * (rs2 & 32'hfff)) % 32'd3329;
            if (y !== expect_y) begin
                if (errs < 10)
                    $display("ERR rs1=%h rs2=%h y=%h expected=%h", rs1, rs2, y, expect_y);
                errs = errs + 1;
            end
        end
    endtask

    initial begin
        errs = 0;
        for (a = 0; a < 4096; a = a + 1)
            for (b = 0; b < 4096; b = b + 1) begin
                rs1 = a;
                rs2 = b;
                check;
            end
        $display("qmul exhaustive: 16777216 inputs, %0d errors", errs);

        seed = 1;
        for (k = 0; k < NRAND; k = k + 1) begin
            rs1 = $random(seed);
            rs2 = $random(seed);
            if (k % 4 == 1) rs1 = rs1 | 32'hfffff000;   // 一部分高位全 1
            if (k % 4 == 2) rs2 = rs2 | 32'hfffff000;
            check;
        end
        $display("qmul high bits: %0d random 32-bit inputs checked", NRAND);
        if (errs == 0) $display("UNIT PASS tb_qmul");
        else           $display("UNIT FAIL tb_qmul (%0d errors)", errs);
        $finish;
    end
endmodule
