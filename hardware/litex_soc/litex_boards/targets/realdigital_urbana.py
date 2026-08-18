from migen import ClockDomain, Signal

from litex.gen import LiteXModule
from litex.soc.cores.clock import S7IDELAYCTRL, S7PLL
from litex.soc.integration.builder import Builder
from litex.soc.integration.soc import SoCCore

from litedram.modules import MT41K64M16
from litedram.phy import s7ddrphy

from litex_boards.platforms import realdigital_urbana

Platform = realdigital_urbana.Platform


class _CRG(LiteXModule):
    def __init__(self, platform, sys_clk_freq):
        self.rst = Signal()
        self.cd_sys = ClockDomain()
        self.cd_sys2x = ClockDomain()
        self.cd_sys4x = ClockDomain()
        self.cd_sys4x_dqs = ClockDomain()
        self.cd_idelay = ClockDomain()

        self.pll = pll = S7PLL(speedgrade=-1)
        self.comb += pll.reset.eq(~platform.request("cpu_reset_n") | self.rst)
        pll.register_clkin(platform.request("clk100"), 100e6)
        pll.create_clkout(self.cd_sys, sys_clk_freq)
        pll.create_clkout(self.cd_sys2x, 2 * sys_clk_freq)
        pll.create_clkout(self.cd_sys4x, 4 * sys_clk_freq)
        pll.create_clkout(self.cd_sys4x_dqs, 4 * sys_clk_freq, phase=90)
        pll.create_clkout(self.cd_idelay, 200e6)
        platform.add_false_path_constraints(self.cd_sys.clk, pll.clkin)

        self.idelayctrl = S7IDELAYCTRL(self.cd_idelay)


class BaseSoC(SoCCore):
    def __init__(self, toolchain="vivado", sys_clk_freq=100e6,
        with_spi_flash=False, with_spi_sdcard=False, with_sdcard=False,
        **kwargs):
        if with_spi_sdcard and with_sdcard:
            raise ValueError("Urbana SD socket must use either SPI or native mode")

        platform = realdigital_urbana.Platform(toolchain=toolchain)
        self.crg = _CRG(platform, sys_clk_freq)

        SoCCore.__init__(
            self,
            platform,
            sys_clk_freq,
            ident="LiteX SoC on RealDigital Urbana",
            **kwargs,
        )

        if not self.integrated_main_ram_size:
            self.ddrphy = s7ddrphy.A7DDRPHY(
                platform.request("ddram"),
                memtype="DDR3",
                nphases=4,
                sys_clk_freq=sys_clk_freq,
            )
            self.add_sdram(
                "sdram",
                phy=self.ddrphy,
                # IS43TR16640CL-125JBL is a 1Gbit x16 DDR3 device. The
                # pinned LiteDRAM API has no exact ISSI model; MT41K64M16
                # supplies the same 8-bank, 8K-row, 1K-column geometry and
                # compatible DDR3-1600 timing model.
                module=MT41K64M16(sys_clk_freq, "1:4"),
                l2_cache_size=kwargs.get("l2_size", 8192),
            )

        if with_spi_flash:
            from litespi.modules import S25FL128S
            from litespi.opcodes import SpiNorFlashOpCodes as Codes

            self.add_spi_flash(
                mode="4x",
                module=S25FL128S(Codes.READ_1_1_4),
                with_master=True,
            )

        if with_spi_sdcard:
            self.add_spi_sdcard()

        if with_sdcard:
            self.add_sdcard()


def main():
    from litex.build.parser import LiteXArgumentParser

    parser = LiteXArgumentParser(
        platform=realdigital_urbana.Platform,
        description="LiteX SoC on RealDigital Urbana.",
    )
    parser.add_target_argument(
        "--sys-clk-freq", default=100e6, type=float,
        help="System clock frequency.",
    )
    parser.add_target_argument(
        "--with-spi-flash", action="store_true",
        help="Enable memory-mapped SPI flash.",
    )
    sdopts = parser.target_group.add_mutually_exclusive_group()
    sdopts.add_argument(
        "--with-spi-sdcard", action="store_true",
        help="Enable SPI-mode SDCard support.",
    )
    sdopts.add_argument(
        "--with-sdcard", action="store_true",
        help="Enable native SDCard support.",
    )
    args = parser.parse_args()

    soc = BaseSoC(
        toolchain=args.toolchain,
        sys_clk_freq=args.sys_clk_freq,
        with_spi_flash=args.with_spi_flash,
        with_spi_sdcard=args.with_spi_sdcard,
        with_sdcard=args.with_sdcard,
        **parser.soc_argdict,
    )
    builder = Builder(soc, **parser.builder_argdict)

    if args.build:
        builder.build(**parser.toolchain_argdict)

    if args.load:
        programmer = soc.platform.create_programmer()
        programmer.load_bitstream(builder.get_bitstream_filename(mode="sram"))


if __name__ == "__main__":
    main()
