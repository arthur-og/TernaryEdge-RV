from litex.build.generic_platform import IOStandard, Misc, Pins, Subsignal
from litex.build.openocd import OpenOCD
from litex.build.xilinx import Xilinx7SeriesPlatform


_io = [
    ("clk100", 0, Pins("N15"), IOStandard("LVCMOS33")),
    # SW0 is the board reset input (official constraint: sys_rst = G1).
    ("cpu_reset_n", 0, Pins("G1"), IOStandard("LVCMOS25")),
    ("serial", 0,
        Subsignal("tx", Pins("B16")),
        Subsignal("rx", Pins("A16")),
        IOStandard("LVCMOS33")),
    ("spiflash", 0,
        Subsignal("cs_n", Pins("M13")),
        Subsignal("mosi", Pins("K17")),
        Subsignal("miso", Pins("K18")),
        Subsignal("wp", Pins("L14")),
        Subsignal("hold", Pins("M15")),
        IOStandard("LVCMOS33")),
    ("spiflash4x", 0,
        Subsignal("cs_n", Pins("M13")),
        Subsignal("dq", Pins("K17 K18 L14 M15")),
        IOStandard("LVCMOS33")),
    ("spisdcard", 0,
        Subsignal("clk", Pins("P18")),
        Subsignal("mosi", Pins("P17")),
        Subsignal("miso", Pins("M16")),
        Subsignal("cs_n", Pins("N18")),
        IOStandard("LVCMOS33")),
    ("sdcard", 0,
        Subsignal("data", Pins("M16 M17 M18 N18")),
        Subsignal("cmd", Pins("P17")),
        Subsignal("clk", Pins("P18")),
        Subsignal("cd", Pins("R18")),
        IOStandard("LVCMOS33")),
    ("ddram", 0,
        Subsignal("a", Pins("V3 R4 P6 T3 T6 T1 V5 U7 R7 U6 U3 P5 V6 V7 R6"),
            IOStandard("SSTL135")),
        Subsignal("ba", Pins("V2 V4 R3"), IOStandard("SSTL135")),
        Subsignal("ras_n", Pins("U2"), IOStandard("SSTL135")),
        Subsignal("cas_n", Pins("U1"), IOStandard("SSTL135")),
        Subsignal("we_n", Pins("T2"), IOStandard("SSTL135")),
        Subsignal("dm", Pins("K4 M3"), IOStandard("SSTL135")),
        Subsignal("dq", Pins("K2 M4 K3 L5 L6 M6 L4 K6 N5 M1 P1 N1 R2 N4 P2 M2"),
            IOStandard("SSTL135"), Misc("IN_TERM=UNTUNED_SPLIT_50")),
        Subsignal("dqs_p", Pins("K1 N3"),
            IOStandard("DIFF_SSTL135"), Misc("IN_TERM=UNTUNED_SPLIT_50")),
        Subsignal("dqs_n", Pins("L1 N2"),
            IOStandard("DIFF_SSTL135"), Misc("IN_TERM=UNTUNED_SPLIT_50")),
        Subsignal("clk_p", Pins("R5"), IOStandard("DIFF_SSTL135")),
        Subsignal("clk_n", Pins("T4"), IOStandard("DIFF_SSTL135")),
        Subsignal("reset_n", Pins("M5"), IOStandard("SSTL135")),
        Subsignal("cke", Pins("T5"), IOStandard("SSTL135")),
        Subsignal("odt", Pins("P7"), IOStandard("SSTL135")),
        Misc("SLEW=FAST")),
]


class Platform(Xilinx7SeriesPlatform):
    default_clk_name = "clk100"
    default_clk_period = 1e9 / 100e6

    def __init__(self, toolchain="vivado"):
        Xilinx7SeriesPlatform.__init__(
            self,
            "xc7s50csga324-1",
            _io,
            toolchain=toolchain,
        )
        self.add_platform_command(
            "set_property INTERNAL_VREF 0.675 [get_iobanks 34]"
        )
        if toolchain == "openxc7":
            # nextpnr-xilinx does not pack the VexRiscv cache's RAM256X1S,
            # and cannot legalise MUXF7/MUXF8 wide-mux chains on Spartan-7.
            self.toolchain._synth_opts += "-nolutram -nowidelut "

    def create_programmer(self):
        return OpenOCD("openocd_xc7_ft2232.cfg", "bscan_spi_xc7s50.bit")

    def do_finalize(self, fragment):
        Xilinx7SeriesPlatform.do_finalize(self, fragment)
        self.add_period_constraint(
            self.lookup_request("clk100", loose=True),
            self.default_clk_period,
        )
