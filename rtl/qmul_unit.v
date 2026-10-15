`timescale 1ns / 1ps

// 模乘单元（设计文档第七节）：y = (rs1[11:0] × rs2[11:0]) mod 3329，操作数按无符号数。
// EX 段单周期组合逻辑，和 ALU 并排；输出由 EX 段的结果选择器按 ALUctr 选入运算结果通路。
//
// 算法与 scripts/check_barrett.py 的 qmul_model() 逐位一致（那里对全部 4096 × 4096 种输入穷举过）：
//   1. p    = a × b                12 × 12 位，p < 2^24
//   2. qhat = (p × 5039) >> 24      24 × 13 位，5039 = floor(2^24 / 3329)，qhat ≤ 5036 < 2^13
//   3. r    = p − qhat × 3329       13 × 12 位，r 落在 [0, 2q) 内，只需 13 位
//   4. y    = r ≥ q ? r − q : r
// 三个乘法都在 DSP48E1 的 25 × 18 之内。
module qmul_unit (
    /* verilator lint_off UNUSEDSIGNAL */  // 只取低 12 位
    input  wire [31:0] rs1,
    input  wire [31:0] rs2,
    /* verilator lint_on UNUSEDSIGNAL */
    output wire [31:0] y
);

    localparam [11:0] Q = 12'd3329;
    localparam [12:0] M = 13'd5039;

    wire [11:0] a = rs1[11:0];
    wire [11:0] b = rs2[11:0];

    // 各中间量按完整位宽计算，再取用得到的位；高位里恒为 0 或用不到的部分不报 lint
    /* verilator lint_off UNUSEDSIGNAL */
    wire [23:0] p    = a * b;                 // 乘法 1：12 × 12
    wire [36:0] pm   = p * M;                 // 乘法 2：24 × 13。必须用 37 位接住整个乘积：
                                              // 直接写 (p * M) >> 24 会按 24 位计算，高位被截掉
    wire [12:0] qhat = pm[36:24];
    wire [23:0] qq   = qhat * Q;              // 乘法 3：13 × 12，qq ≤ p
    wire [23:0] diff = p - qq;                // 在 [0, 2q) 内，高 11 位恒为 0
    wire [12:0] r    = diff[12:0];
    wire [12:0] r_q  = r - {1'b0, Q};         // r ≥ q 时在 [0, q) 内，第 12 位为 0
    /* verilator lint_on UNUSEDSIGNAL */

    // 最后一次条件减
    wire [11:0] res = (r >= {1'b0, Q}) ? r_q[11:0] : r[11:0];

    assign y = {20'b0, res};

endmodule
