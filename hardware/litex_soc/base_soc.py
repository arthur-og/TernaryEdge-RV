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
#   - NPU Ternária v2 (64 MACs, Wishbone Master DMA) em 0x40000000
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
from litex.soc.integration.builder import *
from litex.soc.interconnect import wishbone
from litex_boards.targets import realdigital_urbana

# -----------------------------------------------------------------------------
# Constantes
# -----------------------------------------------------------------------------
NPU_BASE = 0x40000000
NPU_SIZE = 0x10000   # 64 KB (espaço generoso para CSR + DMA scratch)
NPU_IRQ  = 10        # Linha de interrupção no PLIC

NPU_RTL_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "npu_rtl")

NPU_SOURCES = [
    "npu_v2_pkg.v",
    "ternary_mac.v",
    "ternary_mac_array.v",
    "adder_tree_64.v",
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

            # ------------------------------------------------------------------
            # Wishbone Master Interface (NPU faz DMA na RAM)
            # ------------------------------------------------------------------
            o_wb_m_adr_o = wb_master.adr,
            o_wb_m_dat_o = wb_master.dat_w,
            o_wb_m_sel_o = wb_master.sel,
            o_wb_m_we_o  = wb_master.we,
            o_wb_m_cyc_o = wb_master.cyc,
            o_wb_m_stb_o = wb_master.stb,
            o_wb_m_cti_o = wb_master.cti,   # Burst type
            o_wb_m_bte_o = wb_master.bte,   # Burst type extension
            i_wb_m_dat_i = wb_master.dat_r,
            i_wb_m_ack_i = wb_master.ack,
            i_wb_m_err_i = 0,

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

        # Inicializa o SoC base da Urbana (CRG, DDR3, UART, PLL, SD card)
        realdigital_urbana.BaseSoC.__init__(self,
            sys_clk_freq    = 100e6,        # 100 MHz system clock
            with_spi_sdcard = True,         # SD em SPI (bootloader)
            with_sdcard     = True,         # SD nativo 4-bit (RootFS)
            **kwargs)

        # Remove reserved region added by BaseSoC — we'll replace it
        # Remove existing npu region if present
        if "npu" in self.bus.slaves:
            del self.bus.slaves["npu"]

        # ------------------------------------------------------------------
        # Integração da NPU v2 no barramento Wishbone
        # ------------------------------------------------------------------

        # Cria interface Wishbone para o slave (CPU acessa registradores NPU)
        npu_slave_if = wishbone.Interface()

        # Cria interface Wishbone para o master (NPU faz DMA na RAM)
        npu_master_if = wishbone.Interface()

        # Instancia o wrapper Verilog da NPU v2
        self.submodules.npu_ternaria = NPUTernariaV2(
            platform   = self.platform,
            wb_slave   = npu_slave_if,
            wb_master  = npu_master_if)

        # Conecta o Wishbone Slave da NPU como escravo no barramento principal
        # (CPU lê/escreve registradores MMIO da NPU)
        self.add_wb_slave(name="npu_ternaria",
                          slave=npu_slave_if,
                          address=NPU_BASE)

        # Registra a região de memória para o gerador de headers
        self.add_memory_region("npu_ternaria", NPU_BASE, NPU_SIZE, type="io")

        # Conecta o Wishbone Master da NPU como mestre no crossbar
        # (NPU faz burst reads/writes na RAM do sistema via DMA)
        self.bus.add_master(master=npu_master_if)

        # Conecta a interrupção IRQ 10
        self.irq.add("npu_ternaria", NPU_IRQ)
        self.comb += self.irq.request.eq(self.npu_ternaria.irq)

        print(f"[TernaryEdgeSoC] NPU v2 integrada em 0x{NPU_BASE:08X}, IRQ={NPU_IRQ}")
        print(f"[TernaryEdgeSoC] Fontes: {NPU_RTL_DIR}")
        print(f"[TernaryEdgeSoC] 0 DSPs usados — multiplierless!")


# -----------------------------------------------------------------------------
# Build / Load / Flash
# -----------------------------------------------------------------------------
def main():
    from litex.build.parser import LiteXArgumentParser

    parser = LiteXArgumentParser(
        platform    = realdigital_urbana.Platform,
        description = "Ternary Edge-RV: VexRiscv + NPU v2 Multiplierless para Urbana Board")

    args = parser.parse_args()

    soc_kwargs = parser.soc_argdict

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
