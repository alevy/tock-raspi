/* Licensed under the Apache License, Version 2.0 or the MIT License. */
/* SPDX-License-Identifier: Apache-2.0 OR MIT                         */
/* Copyright Tock Contributors 2023.                                  */

MEMORY
{
  rom (rx)  : ORIGIN = 0x80000, LENGTH = 0x100000
  prog (rx) : ORIGIN = 0x180000, LENGTH = 0x10
  ram (rwx) : ORIGIN = 0x00000, LENGTH = 0x80000
}

/*
 * `_etext`, `_srelocate`, `_erelocate`
 *    The `_etext` symbol marks the end of data stored in flash that should
 *    stay in flash. `_srelocate` and `_erelocate` mark the address range in
 *    SRAM that mutable program data is copied to.
 *
 *    Tock will copy `_erelocate` - `_srelocate` bytes of data from the
 *    `_etext` pointer to the `_srelocate` pointer.
 *
 * `_szero`, `_ezero`
 *
 *    The `_szero` and `_ezero` symbols define the range of the BSS, SRAM that
 *    Tock will zero on boot.
 *
 * `_sapps`, `_eapps`
 *
 *    The `_sapps` symbol marks the beginning of application memory in flash.
 *    The `_eapps` symbol marks the end of application memory in flash by
 *    pointing to next address after application flash.
 *
 * `_sappmem`, `_eappmem`
 *
 *    The `_sappmem` symbol marks the beginning of application memory in RAM.
 *    The `_eappmem` symbol marks the end of application memory in RAM by
 *    pointing to next address after application RAM.
 */

PAGE_SIZE = 4096;

SECTIONS
{

   .stack (NOLOAD) :
    {
        /* Kernel stack.
         *
         * Tock places the kernel stack at the bottom of SRAM so that the
         * kernel will trigger memory fault if it exceeds its stack depth,
         * rather than silently overwriting valuable data.
         */
        . = ALIGN(PAGE_SIZE);
         _sstack = .;

         /* For GNU LD, we can just advance the location pointer (".") here to
          * reserve space for the stack. That, however, doesn't seem to work
          * for LLVM LLD. The resulting ELF has a stack section that shows the
          * correct size, but the next section (in our case .relocate) is not
          * moved down as well, instead it sits at the same address as .stack.
          * To work around this, we declare a dummy buffer and then insert it
          * here in the .stack section. This sets the stack size correctly and
          * places the .relocate section at the correct address. */
         KEEP(*(.stack_buffer))
         /*. = . + 0x1000;*/  /*This is the original method. */

         . = ALIGN(8);
         _estack = .;
    } > ram


    /* STATIC ELEMENTS FOR TOCK KERNEL */
    .text :
    {
        . = 0x80000; /* BMC loads binary to this address and jumps */
        KEEP(*(.start));

        /* .text and .rodata hold most program code and immutable constants */
        /* .gnu.linkonce hold C++ elements with vague linkage
                https://gcc.gnu.org/onlinedocs/gcc/Vague-Linkage.html */
        *(.text .text.* .gnu.linkonce.t.*)

        /* glue_7 and glue_7t hold helper functions emitted by the compiler to
           support interworking (linking between functions in ARM and THUMB
           mode). */
        *(.glue_7t) *(.glue_7)

        /* End constructor/destructor */
    } > rom


    /* ARM Exception support
     *
     * This contains compiler-generated support for unwinding the stack,
     * consisting of key-value pairs of function addresses and information on
     * how to unwind stack frames.
     * https://wiki.linaro.org/KenWerner/Sandbox/libunwind?action=AttachFile&do=get&target=libunwind-LDS.pdf
     *
     * .ARM.exidx is sorted, so has to go in its own output section.
     */
    PROVIDE_HIDDEN (__exidx_start = .);
    .ARM.exidx :
    {
      /* (C++) Index entries for section unwinding */
      *(.ARM.exidx* .gnu.linkonce.armexidx.*)
    } > rom
    PROVIDE_HIDDEN (__exidx_end = .);

    /* Region for on-chip kernel non-volatile storage.
     *
     * Align on PAGE_SIZE number of bytes. Volumes within this region are
     * allocated with the storage_volume! macro in utils.rs.
     */
    .storage :
    {
      . = ALIGN(PAGE_SIZE);
      _sstorage = .;
      *(.storage* storage*)
      _estorage = .;
      . = ALIGN(PAGE_SIZE);
    } > rom
    . = ALIGN(PAGE_SIZE);

    /* Mark the end of static elements */
    . = ALIGN(4);
    _erodata = .;
    _etext = .;


    /* Customer configuration is most often located at the end of the rom. It is
     * conditional, and won't be written if not specified in the board specific
     * linker file.
     */
    .ccfg : {
        KEEP(*(.ccfg))
    } > ccfg


    /* Section for application binaries in flash.
     *
     * This section is put into the "prog" memory, which is reserved for
     * applications. This section is not used for the kernel, but including it
     * in the .elf file allows for concatenating application binaries with the
     * kernel.
     */
    .apps :
    {
        /* _sapps symbol used by Tock to look for first application. */
        . = ALIGN(4);
        _sapps = .;

        /* Include placeholder bytes in this section so that the linker
         * includes a segment for it. Otherwise the section will be empty and
         * the linker will ignore it when defining the segments.
         * If less than 4 bytes, some linkers set this section to size 0
         * and openocd fails to write it.
         *
         * An issue has been submitted https://github.com/raspberrypi/openocd/issues/25
         */
        BYTE(0xFF)
        BYTE(0xFF)
        BYTE(0xFF)
        BYTE(0xFF)
    } > prog
    /* _eapps symbol used by tock to calculate the length of app flash */
    _eapps = _sapps + LENGTH(prog);

    /* Kernel data that must be relocated. This is program data that is
     * expected to live in SRAM, but is initialized with a value. This data is
     * physically placed into flash and is copied into SRAM by Tock. The
     * symbols here will be defined with addresses in SRAM.
     *
     * Tock assumes the relocation section follows all static elements and will
     * copy (_erelocate - _srelocate) bytes from _etext to _srelocate.
     */
    .relocate :
    {
        . = ALIGN(PAGE_SIZE);
        _srelocate = .;

        *(.ramfunc .ramfunc.*);
        *(.sdata .sdata.* .gnu.linkonce.r.*)
        *(.data .data.*);

        . = ALIGN(PAGE_SIZE);
        _erelocate = .;
    } > ram AT>rom

    .sram (NOLOAD) :
    {
        /* Kernel BSS section. Memory that is expected to be initialized to
         * zero.
         *
         * Elements in this section do not contribute to the binary size. Tock
         * initialization will write zeros to the memory between _szero and
         * _ezero.
         *
         * Elements placed in the .bss and .COMMON sections are simply used to
         * measure amount of memory to zero out.
         */
        . = ALIGN(PAGE_SIZE);
        _szero = .;

        /* In addition to the traditional .bss section, RISC-V splits out a "small data" section
         * see: https://github.com/riscv/riscv-pk/blob/a3e4ac61d2b1ff37a22b9193b85d3b94273e80cb/pk/pk.lds#L84
         */
        *(.sbss .sbss.* .bss .bss.*);
        *(COMMON)

        . = ALIGN(PAGE_SIZE);
        _ezero = .;

        /* Application Memory.
         *
         * Tock uses the remainder of SRAM for application memory.
         *
         * Currently, Tock allocates a fixed array of application memory at
         * compile-time, and that array is simply placed here. A possible
         * future enhancement may allow the kernel to parcel this memory space
         * dynamically, requiring changes to this section.
         */
        _sappmem = .;
        *(.app_memory)
    } > ram
    _eappmem = ORIGIN(ram) + LENGTH(ram);
}

