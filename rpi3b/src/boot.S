.globl _start
.extern LD_STACK_PTR

.section ".text.boot"
_start:

	// read cpu id, stop slave cores
	mrs     x1, mpidr_el1
	and     x1, x1, #3
	cbz     x1, 2f
	// cpu id > 0, stop
1: wfi
	b       1b
2:  // cpu id == 0

	/* Enable NEON/SIMD instructions */
	mov x30, #(0x3 << 20)
	msr cpacr_el1, x30
	isb
	/* -- */

  ldr     x30, =LD_STACK_PTR0
	mov     sp, x30
  bl      kernel_main
halt:
	wfe
	b halt
