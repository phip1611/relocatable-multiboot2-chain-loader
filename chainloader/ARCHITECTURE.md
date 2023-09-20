# Architecture

This document describes the architecture of the binary and the Cargo project.

## Binary
The loader produces a static binary in x86_64 ELF format with four LOAD segments
and no relocation information. They are all continuous in physical memory and
all together less than two MiB in size. They must be loaded at a two MiB aligned
physical (and virtual) address. The loader is relocatable in physical address
space but not in virtual address space. All symbols in the loader have the same
offset regarding the previous 2 MiB boundary in physical and their corresponding
virtual address space.

### Load Segment Overview
- `boot`: Consists of code that was written in assembly. It holds the entry
  point into the binary. It is position-independent and patches its code live
  during runtime to cope with a relocation, if necessary.
- `rx`: Contains the compiled instruction stream from the compiled Rust code.
- `ro`: Contains read-only symbols from the compiled Rust code.
- `rw`: Contains writeable data symbols from the compiled Rust code.

### Two MiB Restriction
Having a two MiB alignment requirement allows to use two MiB huge-mappings for
the LOAD segments. Having an overall size-restriction of two MiB allows to map
the whole loader using one single L1 page table that covers the whole range.

Furthermore, the less virtual memory space the binary allocates, the more
freedom do kernel payloads of the loader have.

### Page Table Structure
Two facilitate the transition to 64-bit mode, we need an identity mapping of the
boot code and a regular mapping of the actual code. The binary is structured
in a way to ease the following mapping structure.

For reference: L4, L3, L2, and L1 correspond to the page-table levels of
64-bit 4-level paging.

```
L4 -> L3 (lo) -> L2 (lo) -> 2 MiB r+x idendity mapping of boot code
  \-> L3 (hi) -> L2 (hi) -> L1 (hi) -> x rx mappings of RX segment
                                   \-> x ro mappings of RO segment
                                   \-> x rw mappings of RW segment
```

## Cargo Project
The project tries to facilitate as much as possible of the Cargo-native
toolchain options to build this binary. However, for a convenient testing and
build environment - `no_std` binaries + Cargo come in fact with some caveats -
a small Makefile-based wrapper is used.

## High-level Rust Code
The high-level Rust code is compiled to 64-bit code and expects a bootstrapped
CPU. This means activated paging and all required CPU features that are
used during compilation, for example `SSE`. The boot code is responsible for
preparing this environment.
