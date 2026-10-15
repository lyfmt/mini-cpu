// 非法指令单元测试（sim/run_unit.sh 现场构建）。
//
// 同一份源码构建三个镜像：
//   CPU 镜像：      ILL(w) 是非法指令字 w，QMUL 是真正的 qmul；
//   参考 1（-DREF）：ILL(w) 换成 nop，qmul 保留      -> 参考模型 --isa rv32i_qmul，对照 HAS_QMUL=1；
//   参考 0（-DREF -DNO_QMUL）：qmul 也换成 nop        -> 参考模型 --isa rv32i，对照 HAS_QMUL=0。
// 非法指令在 CPU 里是气泡，效果和 nop 一样，所以轨迹必须与参考一致。
//
// 每个非法字的 rd、rs1 都选成"若被当成合法指令执行就会产生事件"的寄存器：rd = x5（会出现
// 多余的 R 事件），访存基址 x7 指向数据区（会出现多余的 M 事件），跳转类的会改变 PC。
// 每组后面把 x5 存一次，确认它没被改写。
//
// 停顿：程序里只有末尾一处 load-use，即 lw x6 后紧跟 qmul x5, x6, x6。HAS_QMUL=1 时停 1 拍；
// HAS_QMUL=0 时 qmul 是非法指令，不读寄存器，不停顿。另有两处"lw 后紧跟一个非法字、
// 其 rs1/rs2 字段等于 lw 的 rd"，两种配置下都不能停顿。run_unit.sh 检查 STALLS 分别为 1 和 0。
#include "test.h"
#include "qmul.h"

#ifdef REF
#define ILL(w) addi x0, x0, 0
#else
#define ILL(w) .word w
#endif

#if defined(REF) && defined(NO_QMUL)
#define QMUL(rd, a, b) addi x0, x0, 0
#else
#define QMUL(rd, a, b) qmul rd, a, b
#endif

// R 型编码：rd = x5，rs1 = rs2 = x6
#define RENC(f7, f3, op) (((f7) << 25) | (6 << 20) | (6 << 15) | ((f3) << 12) | (5 << 7) | (op))

    .option norelax
TEST_BEGIN
    LA      x7, buf
    addi    x5, x0, 0x55
    addi    x6, x0, 0x66

    // 字节、半字访存：lb lh lbu lhu x5,0(x7)；sb sh x6,0(x7)
    ILL(0x00038283)
    ILL(0x00039283)
    ILL(0x0003c283)
    ILL(0x0003d283)
    ILL(0x00638023)
    ILL(0x00639023)
    // 不存在的 load/store funct3：ld x5,0(x7)、sd x6,0(x7)、funct3 = 111
    ILL(0x0003b283)
    ILL(0x0063b023)
    ILL(0x0003f283)
    ILL(0x0063f023)
    sw      x5, 0(x7)

    // fence、fence.i、ecall、ebreak
    ILL(0x0ff0000f)
    ILL(0x0000100f)
    ILL(0x00000073)
    ILL(0x00100073)
    // CSR：csrrw x5,mscratch,x6；csrrs x5,cycle,x0；csrrc；csrrwi；csrrsi；csrrci
    ILL(0x340312f3)
    ILL(0xc00022f3)
    ILL(0x340332f3)
    ILL(0x340fd2f3)
    ILL(0x340fe2f3)
    ILL(0x340ff2f3)
    sw      x5, 4(x7)

    // R 型 funct7 不合法：mul（0000001）；0100000 配 funct3 ≠ 000/101；0000010；0010000
    ILL(RENC(0x01, 0, 0x33))
    ILL(RENC(0x20, 1, 0x33))
    ILL(RENC(0x20, 2, 0x33))
    ILL(RENC(0x20, 3, 0x33))
    ILL(RENC(0x20, 4, 0x33))
    ILL(RENC(0x20, 6, 0x33))
    ILL(RENC(0x20, 7, 0x33))
    ILL(RENC(0x02, 0, 0x33))
    ILL(RENC(0x10, 5, 0x33))
    sw      x5, 8(x7)

    // 移位立即数：第 25 位非 0（shamt = 33），slli 带 0100000，funct7 的其它位
    ILL(0x02131293)
    ILL(0x02135293)
    ILL(0x42135293)
    ILL(0x40131293)
    ILL(0x80135293)
    ILL(0x04131293)
    sw      x5, 12(x7)

    // 分支 funct3 010、011（rs1 = rs2 = x0，若被当成分支一定"成立"）；jalr funct3 ≠ 000
    ILL(0x00002463)
    ILL(0x00003463)
    ILL(0x008312e7)
    ILL(0x008372e7)
    // 全 0、全 1、低两位不是 11 的字
    ILL(0x00000000)
    ILL(0xffffffff)
    ILL(0x00a30290)
    sw      x5, 16(x7)

    // custom-0 里 qmul 以外的编码：funct3 = 1..7；funct7 = 0000001、0100000、1111111
    ILL(RENC(0x00, 1, 0x0b))
    ILL(RENC(0x00, 2, 0x0b))
    ILL(RENC(0x00, 3, 0x0b))
    ILL(RENC(0x00, 4, 0x0b))
    ILL(RENC(0x00, 5, 0x0b))
    ILL(RENC(0x00, 6, 0x0b))
    ILL(RENC(0x00, 7, 0x0b))
    ILL(RENC(0x01, 0, 0x0b))
    ILL(RENC(0x20, 0, 0x0b))
    ILL(RENC(0x7f, 0, 0x0b))
    // custom-1、custom-2、custom-3
    ILL(RENC(0x00, 0, 0x2b))
    ILL(RENC(0x00, 0, 0x5b))
    ILL(RENC(0x00, 0, 0x7b))
    sw      x5, 20(x7)

    // 真正的 qmul：HAS_QMUL = 0 时是非法指令，x5 保持不变
    addi    x6, x0, 1234
    QMUL(x5, x6, x6)
    sw      x5, 24(x7)

    // load 后紧跟一个非法字，它的 rs1/rs2 字段等于 lw 的 rd（x6）：不读寄存器，不能停顿
    lw      x6, 0(x7)
    ILL(0x00030283)                               // lb x5, 0(x6)
    lw      x6, 4(x7)
    ILL(RENC(0x01, 0, 0x33))                      // mul x5, x6, x6
    add     x5, x5, x6
    sw      x5, 28(x7)

    // 唯一一处 load-use：HAS_QMUL = 1 时停 1 拍，HAS_QMUL = 0 时 qmul 是非法指令，不停
    lw      x6, 8(x7)
    QMUL(x5, x6, x6)
    sw      x5, 32(x7)
TEST_END

    .data
buf: .space 64
