#![no_main]
#![no_std]

use bcm2837;
use core::arch::asm;
use core::fmt::Write;

/// Dummy buffer that causes the linker to reserve enough space for the stack.
#[no_mangle]
#[link_section = ".stack_buffer"]
pub static mut STACK_MEMORY: [u8; 0x2000] = [0; 0x2000];

#[no_mangle]
pub extern "C" fn kernel_main() {
    let mut uart = unsafe { bcm2837::uart::UART::uart1() };
    let _ = write!(&mut uart, "Hello world\n");
    loop {
        match uart.read_byte() {
            b'\r' => uart.write_byte(b'\n'),
            0x7F => {
                let _ = uart.write_str("\x1B[1D");
                let _ = uart.write_str("\x1B[K");
            }
            r => {
                uart.write_byte(r);
            }
        }
    }
}

use core::panic::PanicInfo;

#[panic_handler]
fn panic(_panic_info: &PanicInfo<'_>) -> ! {
    loop {
        unsafe {
            asm!("wfi");
        }
    }
}
