#![no_std]

pub static _START: unsafe extern "C" fn() -> ! = cortex_a::_start;

pub mod uart;
