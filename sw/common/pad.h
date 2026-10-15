/*
 * 空指令填充（实现约定第 8 节）
 *
 * 同一份测试源码构建出两个变体：
 *   pad    定义了 PAD，填充宏展开成空指令，用于没有冒险处理的阶段 1 CPU；
 *   nopad  没定义 PAD，填充宏展开为空，从阶段 2 起使用。
 *
 *   PAD_DATA  两条空指令。放在有数据依赖的两条指令之间，
 *             保证读寄存器的指令和写它的指令之间至少隔两条。
 *   PAD_JUMP  三条空指令。放在每条分支和跳转指令之后。
 *   SEP       三条空指令，两个变体里都保留。冒险测试用它把要演示的指令序列
 *             和前后的准备、检查代码隔开，使 nopad 变体里的冒险恰好只有
 *             场景本身那几条指令之间的。
 *
 * 空指令写成 add x0, x0, x0，因为 base9 里没有 addi（nop 伪指令用不了）。
 * 构建时参考模型以 --check-pad 运行 pad 变体，填充不够会直接报错。
 */
#ifndef MINICPU_PAD_H
#define MINICPU_PAD_H

#define NOP0 add x0, x0, x0

#ifdef PAD
#define PAD_DATA NOP0; NOP0
#define PAD_JUMP NOP0; NOP0; NOP0
#else
#define PAD_DATA
#define PAD_JUMP
#endif

#define SEP NOP0; NOP0; NOP0

#endif
