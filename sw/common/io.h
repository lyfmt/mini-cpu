/*
 * mini-cpu 地址空间与 I/O 寄存器（实现约定第 3 节）
 */
#ifndef MINICPU_IO_H
#define MINICPU_IO_H

#define IMEM_BASE    0x00000000
#define DMEM_BASE    0x00010000
#define MEM_SIZE     0x1000          /* 两块存储器各 4 KB */
#define STACK_TOP    0x00011000      /* 数据存储器末尾 */

#define IO_BASE      0x80000000
#define IO_BASE_HI   0x80000         /* lui rd, IO_BASE_HI 得到 IO_BASE */

/* 相对 IO_BASE 的偏移 */
#define IO_FINISH    0x00            /* 写：结果码，0 = 通过 */
#define IO_CYCLE     0x04            /* 读：周期数 */
#define IO_INSTRET   0x08            /* 读：退休指令数 */
#define IO_STALLS    0x0C            /* 读：load-use 停顿周期数 */
#define IO_FLUSHES   0x10            /* 读：冲刷次数 */
#define IO_MARK      0x14            /* 写：打点 */

#endif
