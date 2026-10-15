/*
 * mini-cpu 链接脚本（实现约定第 3、5 节）
 *
 *   .text                    -> 指令存储器 0x0000_0000 起，4 KB
 *   .rodata / .data / .bss   -> 数据存储器 0x0001_0000 起，4 KB
 *
 * 栈顶 __stack_top = 0x0001_1000（数据存储器末尾）。
 * load 指令读不到指令存储器，所以常量表必须放在 .data 或 .rodata 里。
 */
OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
    IMEM (rx)  : ORIGIN = 0x00000000, LENGTH = 4K
    DMEM (rw)  : ORIGIN = 0x00010000, LENGTH = 4K
}

__stack_top = ORIGIN(DMEM) + LENGTH(DMEM);

SECTIONS
{
    .text : {
        *(.text.init)
        *(.text .text.*)
    } > IMEM

    .rodata : {
        *(.rodata .rodata.* .srodata .srodata.*)
    } > DMEM

    .data : {
        *(.data .data.* .sdata .sdata.*)
    } > DMEM

    .bss (NOLOAD) : {
        *(.bss .bss.* .sbss .sbss.* COMMON)
    } > DMEM

    /DISCARD/ : {
        *(.comment) *(.note .note.*)
    }
}
