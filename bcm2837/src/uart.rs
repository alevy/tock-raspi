use core::fmt::Write;
use core::str;

use kernel::utilities::StaticRef;
use tock_registers::interfaces::ReadWriteable;
use tock_registers::interfaces::Readable;
use tock_registers::interfaces::Writeable;
use tock_registers::register_bitfields;
use tock_registers::registers::Aliased;
use tock_registers::registers::ReadOnly;
use tock_registers::registers::ReadWrite;

register_bitfields![u32,
    Mux [
    UART OFFSET(0) NUMBITS(1),
    SPI1 OFFSET(1) NUMBITS(1),
    SPI2 OFFSET(2) NUMBITS(1),
    ],
];

register_bitfields![u32,
    RBR [
        Data OFFSET(0) NUMBITS(8) [],
    ],
    THR [
        Data OFFSET(0) NUMBITS(8) [],
    ],
    IER [
        ModemStatusRegisterChange OFFSET(3) NUMBITS(1) [],
        ReceiverLineStatusRegisterChange OFFSET(2) NUMBITS(1) [],
        TransmitterHoldingRegisterEmpty OFFSET(1) NUMBITS(1) [],
        ReceivedDataAvailable OFFSET(0) NUMBITS(1) [],
    ],
    IIR [
        FIFO OFFSET(6) NUMBITS(2) [
            NoFIFO = 0,
            UnusableFIFO = 2,
            FIFOEnabled = 3,
        ],
        Identification OFFSET(1) NUMBITS(2) [
            None = 0,
            TransmitterHoldingRegisterEmpty = 1,
            ReceiveDataAvailable = 2,
        ],
        Pending OFFSET(0) NUMBITS(1) [
            Pending = 0,
            NotPending = 1,
        ],
    ],
    FCR [
        ClearTransmitFIFO OFFSET(2) NUMBITS(1) [],
        ClearReceiveFIFO OFFSET(1) NUMBITS(1) [],
    ],
    LCR [
        BreakSignal OFFSET(6) NUMBITS(1) [],
        ParityMode OFFSET(4) NUMBITS(2) [
            Odd = 0,
            Even = 1,
            High = 2,
            Low = 3,
        ],
        Parity OFFSET(3) NUMBITS(1) [],
        StopBits OFFSET(2) NUMBITS(1) [
            One = 0,
            OneHalfTwo = 1,
        ],
        DataWordLength OFFSET(0) NUMBITS(2) [
            Bits7 = 0,
            Bits8 = 3,
        ],
    ],
    MCR [
        RequestToSend OFFSET(1) NUMBITS(1) [],
    ],
    LSR [
        ErronousDataInFIFO OFFSET(7) NUMBITS(1) [],
        THREmptyLineIdle OFFSET(6) NUMBITS(1) [],
        THREmpty OFFSET(5) NUMBITS(1) [],
        BreakSignalReceived OFFSET(4) NUMBITS(1) [],
        FramingError OFFSET(3) NUMBITS(1) [],
        ParityError OFFSET(2) NUMBITS(1) [],
        OverrunError OFFSET(1) NUMBITS(1) [],
        DataAvailable OFFSET(0) NUMBITS(1) [],
    ],
    MSR [
        CarrierDetect OFFSET(7) NUMBITS(1) [],
        RingIndicator OFFSET(6) NUMBITS(1) [],
        DataSetReady OFFSET(5) NUMBITS(1) [],
        ClearToSend OFFSET(4) NUMBITS(1) [],
        ChangeInCarrierDetect OFFSET(3) NUMBITS(1) [],
        TrailingEdgeRingIndicator OFFSET(2) NUMBITS(1) [],
        ChangeInDataSetReady OFFSET(1) NUMBITS(1) [],
        ChangeInClearToSend OFFSET(0) NUMBITS(1) [],
    ],
    CNTL [
    ReceiverEnable OFFSET(0) NUMBITS (1) [],
    TransmitterEnable OFFSET(1) NUMBITS (1) [],
    RTSEnable OFFSET(2) NUMBITS (1) [],
    CTSEnable OFFSET(3) NUMBITS (1) [],
    RTSAutoFlowLevel OFFSET(4) NUMBITS (2) [],
    RTSAssertLevel OFFSET(6) NUMBITS (1) [],
    CTSAssertLevel OFFSET(6) NUMBITS (1) [],
    ],
];
register_bitfields![u16,
    DLR [
        Divisor OFFSET(0) NUMBITS(16) [],
    ],
    BAUD [
    Baudrate OFFSET(0) NUMBITS (16) [],
    ],
];

// The Mini UART is 16550-like, but not identical.
#[repr(C)]
struct Registers {
    irq: ReadWrite<u32, Mux::Register>,
    enables: ReadWrite<u32, Mux::Register>,
    _reserved0: [u8; 0x40 - 0x08],

    /// 0x40:
    /// - DLAB = 0
    ///   - Read: receiver buffer (RBR)
    ///   - Write: transmitter holding (THR)
    /// - DLAB = 1: divisor latch LSB (DLL)
    rbr_thr: Aliased<u32, RBR::Register, THR::Register>,

    /// 0x44:
    /// - DLAB = 0: interrupt enable (IER)
    /// - DLAB = 1: divisor latch MSB (DLM)
    ier: ReadWrite<u32, IER::Register>,

    /// 0x48:
    /// - Read: interrupt identification (IIR)
    /// - Write: FIFO control (FCR)
    iir_fcr: Aliased<u32, IIR::Register, FCR::Register>,

    /// 0x4C: line control (LCR)
    lcr: ReadWrite<u32, LCR::Register>,

    /// 0x50: modem control (MCR)
    mcr: ReadWrite<u32, MCR::Register>,

    /// 0x54: line status (LSR)
    lsr: ReadOnly<u32, LSR::Register>,

    /// 0x58: modem status (MSR)
    msr: ReadOnly<u32, MSR::Register>,

    /// 0x5C: scratch
    scratch: ReadOnly<u32, ()>,

    /// 0x60: extra constrol (CNTL)
    control: ReadWrite<u32, CNTL::Register>,

    /// 0x64: extra status (STAT)
    status: ReadOnly<u32, ()>,

    /// 0x68: baudrate (BAUD)
    baud: ReadWrite<u32, BAUD::Register>,
}

pub struct UART(StaticRef<Registers>);

impl UART {
    pub unsafe fn uart1() -> UART {
        UART(StaticRef::new(0x3F215000 as *const Registers))
    }

    pub fn init(&mut self) {
        self.0.enables.modify(Mux::UART::SET);
        self.0.control.modify(CNTL::ReceiverEnable::SET);
        self.0.lcr.modify(LCR::DataWordLength::Bits8);
        self.0.mcr.modify(MCR::RequestToSend::CLEAR);
        self.0.ier.set(0);
        self.0
            .iir_fcr
            .write(FCR::ClearReceiveFIFO::CLEAR + FCR::ClearTransmitFIFO::CLEAR);
        self.0.baud.set(25000000 / 8 / 115200);
        self.0
            .control
            .modify(CNTL::ReceiverEnable::SET + CNTL::TransmitterEnable::SET);
    }

    pub fn write_byte(&mut self, byte: u8) {
        while self.0.lsr.read(LSR::THREmpty) == 0 {}
        self.0.rbr_thr.set(byte as u32);
    }

    pub fn write_bytes(&mut self, s: &[u8]) {
        for byte in s.iter() {
            self.write_byte(*byte);
        }
    }

    pub fn read_byte(&mut self) -> u8 {
        while self.0.lsr.read(LSR::DataAvailable) == 0 {}
        self.0.rbr_thr.read(RBR::Data) as u8
    }
}

impl Write for UART {
    fn write_str(&mut self, s: &str) -> core::fmt::Result {
        self.write_bytes(s.as_bytes());
        Ok(())
    }
}
