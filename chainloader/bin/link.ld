ENTRY(start)

/*
 * FORMAT/ARCH: It's hard to find the right names for this. Keyword: "bfdname".
 * Also see GNU ld's source.
 */
OUTPUT_FORMAT("elf64-x86-64")
OUTPUT_ARCH("i386:x86-64")

/* Program headers. Also called segments. */
PHDRS
{
    /*
     * FLAGS:
     * - 0b111 - +read +write +execute
     * - Strictly speaking irrelevant for our dispatch in 32-bit protected mode,
     *   but technically the right permissions for those segments.
     */
    boot   PT_LOAD FLAGS(7) FILEHDR PHDRS;
    rx     PT_LOAD FLAGS(5);
    ro     PT_LOAD FLAGS(4);
    rw     PT_LOAD FLAGS(6);
}


/*
 * LINK=LOAD addr of boot code enables to fetch the relocation offset in
 + physical memory during runtime by adding the offset to the known link address
 * of the boot code's symbols.
 */
LINK_ADDR_BOOT = 0x200000;
LOAD_ADDR_BOOT = LINK_ADDR_BOOT;

/*
 * Base address for high-level code linkage. The compiled high-level code
 * following the boot code in physical memory has an offset from that address
 * that matches the size of the boot code. This way, virtual and physical
 * offsets are equal for all symbols in the binary regarding their
 * corresponding base address.
 */
LINK_ADDR_HIGH_BASE = 0xffffffff88200000;

LINK_ADDR_RX = ALIGN(LINK_ADDR_HIGH_BASE + SIZEOF(.boot), 4K);
LOAD_ADDR_RX = ALIGN(LOAD_ADDR_BOOT + SIZEOF(.boot), 4K);

LINK_ADDR_RO = ALIGN(LINK_ADDR_RX + SIZEOF(.text), 4K);
LOAD_ADDR_RO = ALIGN(LOAD_ADDR_RX + SIZEOF(.text), 4K);

LINK_ADDR_RW = ALIGN(LINK_ADDR_RO + SIZEOF(.rodata), 4K);
LOAD_ADDR_RW = ALIGN(LOAD_ADDR_RO + SIZEOF(.rodata), 4K);

/* Used by assembly code to perform the right amount of mappings. */
COUNT_PAGES_RX = (SIZEOF(.text) + 4K - 1) / 4K;
COUNT_PAGES_RO = (SIZEOF(.rodata) + 4K - 1) / 4K;
COUNT_PAGES_RW = ((SIZEOF(.bss) + SIZEOF(.data)) + 4K - 1) / 4K;

SECTIONS {

    /*
     * All symbols from the assembly code.
     */
    .boot LINK_ADDR_BOOT : AT(LOAD_ADDR_BOOT) ALIGN(2M) {
        *(.boot.text)
        KEEP(*(.mb2_hdr));
        *(.boot.data)

        /* . = ALIGN(., 4K); */
    } : boot

    /*
     * All symbols from the high-level Rust code.
     */

    .text LINK_ADDR_RX : AT(LOAD_ADDR_RX)
    {
        *(.text .text.*)

        /* . = ALIGN(., 4K); */
    } : rx

    .rodata LINK_ADDR_RO : AT(LOAD_ADDR_RO)
    {
        *(.rodata .rodata.*)

        /* . = ALIGN(., 4K); */
    } : ro

    .bss LINK_ADDR_RW : AT(LOAD_ADDR_RW)
    {
        *(COMMON)
        *(.bss .bss.*)

        /* . = ALIGN(., 4K); */
    } : rw

    .data : /* Link + Load Addr auto increment */
    {
        *(.data .data.*)

        /* . = ALIGN(., 4K); */
    } : rw

    BIN_SIZE = . - LINK_ADDR_HIGH_BASE;


    /* General Assertions */
    /*
     * Make sure the loader fits into 2 MiB. This ensures us that we only need
     * one L1 page table with 512 entries respectively one L2 page table with
     * one huge page mapping.
     */
    ASSERT(BIN_SIZE <= 2M, "The binary must be <= 2 MiB in size in memory")
    ASSERT(ALIGN(LINK_ADDR_BOOT, 2M) == LINK_ADDR_BOOT, "LINK_ADDR_BOOT must be 2 MiB aligned")
    ASSERT(ALIGN(LINK_ADDR_HIGH_BASE, 2M) == LINK_ADDR_HIGH_BASE, "LINK_ADDR_HIGH_BASE must be 2 MiB aligned")

    /DISCARD/ :
    {
        *(.comment .comment.*)
        *(.dynamic)
        *(.eh_frame*)
        *(.got .got.*)
        *(.note.*)
        *(.plt .plt.*)
        *(.rela .rela.*)
    }

}
