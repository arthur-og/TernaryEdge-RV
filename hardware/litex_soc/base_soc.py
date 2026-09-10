#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-2-Clause
#
# base_soc.py — Ternary Edge-RV SoC VexRiscv + NPU v2 for RealDigital Urbana Board
# Autor: Arthur Oliveira Gomes (Hardware)
#
# Gera o SoC completo para a AMD Urbana Board (Spartan-7 XC7S50-CSGA324):
#   - VexRiscv RV32IMA (variante linux com MMU, 100 MHz)
#   - 128 MB DDR3 (800 MT/s, 64Mx16)
#   - UART via FTDI (micro USB — console Linux)
#   - SD Card (SPI mode para boot + SDIO 4-bit para RootFS)
#   - NPU Ternária v2 (64 MACs, Wishbone Master DMA) em 0x80000000
#   - IRQ 10 conectado ao PLIC do VexRiscv
#
# Requer: LiteX + Vivado instalados
# Uso:    python3 base_soc.py --build
#         python3 base_soc.py --load
#         python3 base_soc.py --flash
#
# Depende da NPU v2 RTL em hardware/npu_rtl/

import os
import sys

from migen import *
from litex.soc.integration.soc_core import *
from litex.soc.integration.soc import SoCRegion
from litex.soc.integration.builder import *
from litex.soc.interconnect import wishbone
from litex_boards.targets import realdigital_urbana

# -----------------------------------------------------------------------------
# Constantes
# -----------------------------------------------------------------------------
NPU_BASE = 0x80000000
NPU_SIZE = 0x10000   # 64 KiB reserved MMIO aperture; only the 17 ABI offsets ACK
NPU_IRQ  = 10        # Linha de interrupção no PLIC

NPU_RTL_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "npu_rtl")

NPU_SOURCES = [
    "npu_v2_pkg.v",
    "ternary_mac.v",
    "ternary_mac_array.v",
    "adder_tree_64.v",
    "postprocess_unit.v",
    "wishbone_master.v",
    "npu_ternaria_top_v2.v",
]

# -----------------------------------------------------------------------------
# NPU v2 Wrapper (Module LiteX para instanciar o Verilog da NPU)
# -----------------------------------------------------------------------------
class NPUTernariaV2(Module):
    """Wrapper LiteX para o módulo Verilog npu_ternaria_top_v2.v

    Conecta o Wishbone Slave (CPU → NPU) e o Wishbone Master (NPU → RAM DMA)
    da NPU v2 no barramento do SoC. Expõe o pino irq_out para o controlador
    de interrupções do VexRiscv.
    """
    def __init__(self, platform, wb_slave, wb_master):
        # Adiciona os fontes Verilog ao build
        for src in NPU_SOURCES:
            path = os.path.join(NPU_RTL_DIR, src)
            if os.path.exists(path):
                platform.add_source(path)
            else:
                raise FileNotFoundError(f"NPU RTL não encontrado: {path}")

        # Sinais internos
        self.irq = Signal()

        # Instancia o Verilog top-level da NPU v2
        self.specials += Instance("npu_ternaria_top_v2",

            # ------------------------------------------------------------------
            # Clock / Reset
            # ------------------------------------------------------------------
            i_clk   = ClockSignal(),
            i_rst_n = ~ResetSignal(),

            # ------------------------------------------------------------------
            # Wishbone Slave Interface (CPU configura registradores da NPU)
            # ------------------------------------------------------------------
            i_wb_s_adr_i = wb_slave.adr,
            i_wb_s_dat_i = wb_slave.dat_w,
            i_wb_s_sel_i = wb_slave.sel,
            i_wb_s_we_i  = wb_slave.we,
            i_wb_s_cyc_i = wb_slave.cyc,
            i_wb_s_stb_i = wb_slave.stb,
            o_wb_s_dat_o = wb_slave.dat_r,
            o_wb_s_ack_o = wb_slave.ack,
            o_wb_s_err_o = wb_slave.err,

            # ------------------------------------------------------------------
            # Wishbone Master Interface (NPU faz DMA na RAM)
            # ------------------------------------------------------------------
            o_wb_m_adr_o = wb_master.adr,
            o_wb_m_dat_o = wb_master.dat_w,
            o_wb_m_sel_o = wb_master.sel,
            o_wb_m_we_o  = wb_master.we,
            o_wb_m_cyc_o = wb_master.cyc,
            o_wb_m_stb_o = wb_master.stb,
            o_wb_m_cti_o = wb_master.cti,   # Wishbone cycle type
            o_wb_m_bte_o = wb_master.bte,   # Wishbone cycle extension
            i_wb_m_dat_i = wb_master.dat_r,
            i_wb_m_ack_i = wb_master.ack,
            i_wb_m_err_i = wb_master.err,

            # ------------------------------------------------------------------
            # Interrupção
            # ------------------------------------------------------------------
            o_irq_out = self.irq,
        )

        # NPU wishbone master interface config
        wb_master.we.reset = 0
        wb_master.sel.reset = 0xF


# -----------------------------------------------------------------------------
# TernaryEdgeSoC — SoC principal
# -----------------------------------------------------------------------------
class TernaryEdgeSoC(realdigital_urbana.BaseSoC):
    def __init__(self, **kwargs):
        # ------------------------------------------------------------------
        # Configurações obrigatórias do processador para Linux
        # ------------------------------------------------------------------
        kwargs["cpu_type"]    = "vexriscv"
        kwargs["cpu_variant"] = "linux"     # RV32IMA + MMU (essencial para Linux)
        kwargs["bus_standard"] = "wishbone"

        # A Urbana tem 128 MB DDR3 externa — não precisamos de SRAM interna
        kwargs["integrated_rom_size"]       = 0
        kwargs["integrated_main_ram_size"]  = 0
        kwargs["cpu_reset_address"]        = 0x40000000

        # Inicializa o SoC base da Urbana (CRG, DDR3, UART, PLL, SD card)
        with_sdcard = kwargs.pop("with_sdcard", True)
        with_spi_sdcard = kwargs.pop("with_spi_sdcard", False)
        with_spi_flash = kwargs.pop("with_spi_flash", False)

        realdigital_urbana.BaseSoC.__init__(self,
            sys_clk_freq    = kwargs.pop("sys_clk_freq", 100e6),
            with_sdcard     = with_sdcard,   # SD nativo 4-bit (RootFS)
            with_spi_sdcard = with_spi_sdcard,
            with_spi_flash  = with_spi_flash,
            **kwargs)

        # ------------------------------------------------------------------
        # Integração da NPU v2 no barramento Wishbone
        # ------------------------------------------------------------------

        # Cria interface Wishbone para o slave (CPU acessa registradores NPU)
        npu_slave_if = wishbone.Interface(addressing="byte", address_width=32)

        # Cria interface Wishbone para o master (NPU faz DMA na RAM)
        npu_master_if = wishbone.Interface(addressing="byte", address_width=32)

        # Instancia o wrapper Verilog da NPU v2
        self.submodules.npu_ternaria = NPUTernariaV2(
            platform   = self.platform,
            wb_slave   = npu_slave_if,
            wb_master  = npu_master_if)

        # Conecta o Wishbone Slave da NPU como escravo no barramento principal
        # (CPU lê/escreve registradores MMIO da NPU)
        self.bus.add_slave(
            name="npu_ternaria",
            slave=npu_slave_if,
            region=SoCRegion(
                origin=NPU_BASE,
                size=NPU_SIZE,
                mode="rw",
                cached=False,
            ),
            strip_origin=True,
        )

        # Conecta o Wishbone Master da NPU como mestre no crossbar
        # (NPU acessa a RAM do sistema via Wishbone)
        self.bus.add_master(name="npu_dma", master=npu_master_if)

        # Conecta a interrupção IRQ 10
        self.irq.add("npu_ternaria", NPU_IRQ)

        print(f"[TernaryEdgeSoC] NPU v2 integrada em 0x{NPU_BASE:08X}, IRQ={NPU_IRQ}")
        print(f"[TernaryEdgeSoC] Fontes: {NPU_RTL_DIR}")


# -----------------------------------------------------------------------------
# Build / Load / Flash
# -----------------------------------------------------------------------------
def main():
    from litex.build.parser import LiteXArgumentParser

    parser = LiteXArgumentParser(
        platform    = realdigital_urbana.Platform,
        description = "Ternary Edge-RV: VexRiscv + NPU v2 para Urbana Board")
    parser.add_target_argument("--flash", action="store_true", help="Flash bitstream.")
    parser.add_target_argument("--sys-clk-freq", default=100e6, type=float,
        help="System clock frequency in Hz (default: 100e6).")

    args = parser.parse_args()

    soc_kwargs = parser.soc_argdict
    soc_kwargs["toolchain"] = args.toolchain
    soc_kwargs["sys_clk_freq"] = args.sys_clk_freq

    # Garante que a toolchain RV32 está disponível
    soc_kwargs["cpu_variant"] = "linux"

    soc = TernaryEdgeSoC(**soc_kwargs)

    builder = Builder(soc, **parser.builder_argdict)

    if args.build:
        builder.build(**parser.toolchain_argdict)

    if args.load:
        prog = soc.platform.create_programmer()
        prog.load_bitstream(builder.get_bitstream_filename(mode="sram"))

    if args.flash:
        prog = soc.platform.create_programmer()
        prog.flash(0, builder.get_bitstream_filename(mode="flash"))


if __name__ == "__main__":
    main()
