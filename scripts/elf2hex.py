#!/usr/bin/env python3
"""把链接好的 ELF 拆成指令存储器和数据存储器两个镜像（实现约定第 5 节）。

    python3 scripts/elf2hex.py prog.elf imem.hex dmem.hex

镜像是 $readmemh 格式：每行一个 32 位小端字，8 位小写十六进制，不带 0x，
恰好 1024 行，不足的补 00000000。第 i 行是"基址 + 4i"处的字。

所有带 SHF_ALLOC 标志的节都按地址放进对应的存储器：
[0x0000_0000, 0x0000_1000) 进 imem，[0x0001_0000, 0x0001_1000) 进 dmem，
落在别处就报错。.bss 这类 NOBITS 节填 0。入口地址必须是 0。
"""

import struct
import sys
from collections import namedtuple

IMEM_BASE = 0x00000000
DMEM_BASE = 0x00010000
MEM_WORDS = 1024
MEM_BYTES = MEM_WORDS * 4

SHT_NOBITS = 8
SHF_ALLOC = 0x2
SHF_EXECINSTR = 0x4
EM_RISCV = 243

Section = namedtuple('Section', 'name type flags addr size data')


class ElfError(Exception):
    pass


def read_sections(path):
    """返回 (入口地址, [Section])。只支持 32 位小端 RISC-V ELF。"""
    with open(path, 'rb') as f:
        blob = f.read()
    if blob[:4] != b'\x7fELF':
        raise ElfError('%s: not an ELF file' % path)
    if blob[4] != 1 or blob[5] != 1:
        raise ElfError('%s: not a 32-bit little-endian ELF' % path)
    (e_type, e_machine, e_version, e_entry, e_phoff, e_shoff, e_flags, e_ehsize,
     e_phentsize, e_phnum, e_shentsize, e_shnum, e_shstrndx) = \
        struct.unpack_from('<HHIIIIIHHHHHH', blob, 16)
    if e_machine != EM_RISCV:
        raise ElfError('%s: not a RISC-V ELF (e_machine=%d)' % (path, e_machine))

    headers = [struct.unpack_from('<IIIIIIIIII', blob, e_shoff + i * e_shentsize)
               for i in range(e_shnum)]
    strtab = headers[e_shstrndx]
    strtab_data = blob[strtab[4]:strtab[4] + strtab[5]]

    sections = []
    for sh_name, sh_type, sh_flags, sh_addr, sh_offset, sh_size, _, _, _, _ in headers:
        name = strtab_data[sh_name:strtab_data.index(b'\0', sh_name)].decode()
        if sh_type == SHT_NOBITS:
            data = bytes(sh_size)
        else:
            data = blob[sh_offset:sh_offset + sh_size]
        sections.append(Section(name, sh_type, sh_flags, sh_addr, sh_size, data))
    return e_entry, sections


def elf_to_images(path):
    """返回 (imem 字列表, dmem 字列表, 已分配的节列表)，两个列表各 1024 个字。"""
    entry, sections = read_sections(path)
    if entry != IMEM_BASE:
        raise ElfError('%s: entry point is %08x, must be %08x' % (path, entry, IMEM_BASE))
    imem = bytearray(MEM_BYTES)
    dmem = bytearray(MEM_BYTES)
    allocated = []
    for s in sections:
        if not s.flags & SHF_ALLOC or s.size == 0:
            continue
        allocated.append(s)
        end = s.addr + s.size
        if IMEM_BASE <= s.addr and end <= IMEM_BASE + MEM_BYTES:
            imem[s.addr - IMEM_BASE:end - IMEM_BASE] = s.data
        elif DMEM_BASE <= s.addr and end <= DMEM_BASE + MEM_BYTES:
            dmem[s.addr - DMEM_BASE:end - DMEM_BASE] = s.data
        else:
            raise ElfError('%s: section %s [%08x, %08x) is outside both memories'
                           % (path, s.name, s.addr, end))
    return to_words(imem), to_words(dmem), allocated


def to_words(data):
    return list(struct.unpack('<%dI' % (len(data) // 4), data))


def write_hex(path, words):
    assert len(words) == MEM_WORDS
    with open(path, 'w', newline='\n') as f:
        for w in words:
            f.write('%08x\n' % w)


def main(argv):
    if len(argv) != 4:
        print(__doc__.strip().splitlines()[2].strip(), file=sys.stderr)
        return 2
    try:
        imem, dmem, _ = elf_to_images(argv[1])
    except (OSError, ElfError) as e:
        print('elf2hex: %s' % e, file=sys.stderr)
        return 1
    write_hex(argv[2], imem)
    write_hex(argv[3], dmem)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
