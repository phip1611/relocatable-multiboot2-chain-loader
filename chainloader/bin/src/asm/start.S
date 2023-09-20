# The assembly file uses GNU Assembly (GAS) language with AT&T syntax.

# Entry of the bootloader. Look at "start" symbol for more information.
#
# Register Usage:
# - %edi holds the bootloader magic
# - %esi holds the bootloader info address.
# - %ebp will contain the load address offset during runtime
# - All other 32-bit registers can be used as general purpose registers

.extern rust_entry STACK_TOP

.code32
.section .boot.text, "ax", @progbits

# Entry into the loader. This "boot code" is fully position-independent. This
# way, the loader can cope with physical relocations when it is loaded by a
# Multiboot2 loader (such as GRUB) even though the ELF file is a static
# executable without any relocation information. Where necessary, instructions
# are patched during runtime to cope with relocations.
.global start
start:
    # #############################################################
    # Clear interrupts. They should never be activated at this point anyway.
    cli

    # #############################################################
    # Save Multiboot2 handoff parameters
    # (%eax and %ebx are working registers in the following)
    mov  %eax, %edi
    mov  %ebx, %esi

    # #############################################################
    # Enable FPU, SSE, and FXSAVE
    mov  %cr0,     %eax
    and  $0xfffb,  %ax     # clear coprocessor emulation CR0.EM
    M_SET_CR_BITS  %cr0 CR0_MP
    M_SET_CR_BITS  %cr4 (CR4_OSFXSR | CR4_OSXMMEXCPT)

    # #############################################################
    # Find relocation offset and store it in %ebp

    mov   (%ebx), %eax   # Save first 4 bytes of MBI.
    mov   %ebx,   %esp   # Use MBI (= valid RAM) as temporary stack.
    call  1f             # call-pop trick -> get instruction pointer
    1:
    pop  %ebp
    sub  $1b,     %ebp   # %ebp now contains load offset (i32, i.e., pos or neg)
                         # that can be added to known (link = load address)-
                         # addresses to get the actual address.
    mov  %eax,    (%ebx) # Restore first 4 bytes of MBI.

    # #############################################################
    # Prepare far jump (ljmp) into 64-bit mode.

    # Update ldgdt input data with relocation offset and load GDT.
    M_RESOLVE_RUNTIME_ADDR  gdt,             %eax
    M_RESOLVE_RUNTIME_ADDR  gdt_ptr,         %ebx
    mov                     %eax,            (%ebx)
    M_RESOLVE_RUNTIME_ADDR ldt_gdt_data,     %eax
    lgdt                                     (%eax)

    M_RESOLVE_RUNTIME_ADDR bit64_trampoline, %eax
    M_RESOLVE_RUNTIME_ADDR ljmp_dest,        %ebx
    mov                     %eax,            (%ebx)

    # #############################################################
    # Prepare page tables
    #
    # Flags:
    # -  0x1: present
    # -  0x3: present + writeable
    # - 0x83: present + writeable, huge page

    # Create identity mapping.
    M_MAP_SYMBOL32  4 LINK_ADDR_BOOT boot_mem_pt_l4 boot_mem_pt_l3_lo 0x1
    M_MAP_SYMBOL32  3 LINK_ADDR_BOOT boot_mem_pt_l3_lo boot_mem_pt_l2_lo 0x1
    M_MAP_SYMBOL32  2 LINK_ADDR_BOOT boot_mem_pt_l2_lo LINK_ADDR_BOOT 0x81


    # common mappings for all segments
    M_MAP_HIGH_ADDR  4 LINK_ADDR_RX_PTR boot_mem_pt_l4 boot_mem_pt_l3_hi 0x3
    M_MAP_HIGH_ADDR  3 LINK_ADDR_RO_PTR boot_mem_pt_l3_hi boot_mem_pt_l2_hi 0x3
    M_MAP_HIGH_ADDR  2 LINK_ADDR_RW_PTR boot_mem_pt_l2_hi boot_mem_pt_l1_hi 0x3

    M_MAP_HIGH_ADDR  1 LINK_ADDR_RX_PTR boot_mem_pt_l1_hi LINK_ADDR_BOOT 0x1
    M_MAP_HIGH_ADDR  1 LINK_ADDR_RO_PTR boot_mem_pt_l1_hi LINK_ADDR_BOOT (1 << 63 | 0x1)
    M_MAP_HIGH_ADDR  1 LINK_ADDR_RW_PTR boot_mem_pt_l1_hi LINK_ADDR_BOOT (1 << 63 | 0x3)


    # #############################################################
    # Enable paging
    #
    # We bring the BSP from 32-bit protected mode without paging into IA32e
    # compatibility mode (64-bit mode with 32-bit opcodes) with 4-level paging.
    # The page table structure must be prepared accordingly beforehand. If no
    # identity mapping of this code at runtime exists, the BSP will die with a
    # page fault after the update of %cr0.

    M_RESOLVE_RUNTIME_ADDR  boot_mem_pt_l4, %eax
    mov  %eax, %cr3 # set root page table

    M_SET_MSR_BITS  MSR_IA32_EFER_REG MSR_IA32_EFER_BITS

    # Set paging properties.
    # Unlike for 32-bit paging, the CR4.PSE bit is not required for huge pages.
    M_SET_CR_BITS %cr4, CR4_PAE

    # Finally activate paging.
    M_SET_CR_BITS %cr0, (CR0_PE | CR0_WP | CR0_PG)

    # Now, we are in 64-bit compatibility mode with 4-level paging. The code
    # running right now is identity mapped.

    # #############################################################
    # Far jump (ljmp) into 64-bit mode.

    # Equal to something like "ljmp $8:label" but constructed at runtime.
    # Required, as ljmp needs an absolute address.
    .byte X86_LJMP
    ljmp_dest: .long 0
    .word 8 # Offset of first GDT selector

    # #############################################################
    # 64-bit trampoline
    #
    # Prepare entry into Rust code: prepare function arguments
.code64
bit64_trampoline:
    # #############################################################
    # SystemV ABI x86_64 calling convention
    # 1st in %rdi, 2nd in %rsi, 3nd in %rdx

    # Boot Magic and Boot Info Ptr are already in %rdi and %rsi
    movsx  %ebp, %rdx  # 3rd param: Load offset: sign extend if negative

    # Set stack
    mov  (STACK_TOP_PTR), %rsp  # set the aligned stack top ptr as stack

    movabs  $rust_entry, %rax
    jmp  *%rax  # Absolute jump to link address of high-level code.
    ud2


.section .boot.data, "a", @progbits

.balign 4
# Input data for the ldgdt instruction which takes a 6-byte sequence:
# the size (2 byte) and the location (4 byte) of the GDT.
ldt_gdt_data:
            .word gdt_end - gdt - 1
gdt_ptr:    .quad 0     # this location will be updated during runtime to reflect relocations


# Provide mapping metadata info for the boot code.
# This way, the assembly code can access these symbols that come from the linker
# and operate with 64-bit values even in 32-bit mode.

.balign 8
LINK_ADDR_RX_PTR:   .quad LINK_ADDR_RX
                    .long COUNT_PAGES_RX
LINK_ADDR_RO_PTR:   .quad LINK_ADDR_RO
                    .long COUNT_PAGES_RO
LINK_ADDR_RW_PTR:   .quad LINK_ADDR_RW
                    .long COUNT_PAGES_RW

# Global Descriptor Table (GDT)
.balign 8
gdt:
    # null selector
    .long 0
    .long 0

    # 64-bit code segment ring 0 selector
    .long 0
    .long 0xa09b00
gdt_end:

# Page tables backing memory

.balign 4096
.global boot_mem_pt_l4
boot_mem_pt_l4:
    .zero 4096

.balign 4096
.global boot_mem_pt_l3_lo
boot_mem_pt_l3_lo:
    .zero 4096

.balign 4096
.global boot_mem_pt_l3_hi
boot_mem_pt_l3_hi:
    .zero 4096

.balign 4096
.global boot_mem_pt_l2_lo
boot_mem_pt_l2_lo:
    .zero 4096

.balign 4096
.global boot_mem_pt_l2_hi
boot_mem_pt_l2_hi:
    .zero 4096

.balign 4096
.global boot_mem_pt_l1_hi
boot_mem_pt_l1_hi:
    .zero 4096
