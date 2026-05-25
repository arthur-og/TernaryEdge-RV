#!/usr/bin/env python3
import os
import argparse

from migen import *
from litex.soc.integration.soc_core import *
from litex.soc.integration.builder import *
from litex.soc.interconnect import wishbone

# -----------------------------------------------------------------------------
# SoC Base RISC-V Linux + NPU Ternary Mock (Phase 1)
# Autor: Arthur Oliveira Gomes (Hardware)
# -----------------------------------------------------------------------------
# Este script e o esqueleto de um SoC VexRiscv (RV32IMA) compativel com Linux.
# Como a placa fisica ainda nao foi definida pelo professor, este codigo usa 
# a classe base SoCCore de forma modular. Depois de pegar a placa, basta 
# importar este modulo e plugar os pinos de Clock/DDR dela.
# 
# Ponto Critico: Este codigo JA ALOCA os espacos de memoria exigidos 
# pela Equipe de Software (0x40000000) usando o barramento Wishbone.
# -----------------------------------------------------------------------------

class TernaryEdgeSoC(SoCCore):
    def __init__(self, sys_clk_freq=int(50e6), **kwargs):
        
        # 1. Configuracao OBRIGATORIA para o Buildroot/Linux (Gildo)
        # O kernel exige instrucoes M, A (Atomic) e F/D, porem como usamos 
        # a NPU Multiplierless, a variante 'linux' pura com MMU ja basta 
        # para inicializar o sistema (rv32ima-ilp32).
        kwargs["cpu_type"]    = "vexriscv"
        kwargs["cpu_variant"] = "linux"
        kwargs["bus_standard"]= "wishbone"

        # Initialize base SoC
        SoCCore.__init__(self, clk_freq=sys_clk_freq, **kwargs)

        # ---------------------------------------------------------------------
        # FASE 1: MOCK DE HARDWARE (Reservando endereco 0x40000000 para a NPU)
        # ---------------------------------------------------------------------
        # O Gustavo (Software) precisa que o mapeamento no QEMU exista no 
        # mundo fisico. Criamos uma memoria dummy (SRAM) para representar os 
        # registradores da NPU no Barramento Wishbone.
        #
        # Na Fase 3 (Integração), substituiremos o 'wishbone.SRAM' pelo modulo
        # Verilog real da NPU.
        
        npu_base_address = 0x40000000
        npu_size         = 0x1000 # 4KB de espaco de enderecamento
        
        self.submodules.npu_dummy = wishbone.SRAM(npu_size, bus=wishbone.Interface())
        
        # Adiciona a NPU como Slave no barramento principal
        self.add_wb_slave(name="npu_ternaria", 
                          slave=self.npu_dummy.bus, 
                          address=npu_base_address)
        
        # Informa ao LiteX e ao gerador de C-Headers que essa regiao e I/O
        self.add_memory_region("npu_ternaria", npu_base_address, npu_size, type="io")
        
        # Nota sobre Interrupcao (IRQ): 
        # Na Fase 3, vincularemos o pino 10 ao EventManager.
        # self.add_interrupt("npu_ternaria", 10)

def main():
    parser = argparse.ArgumentParser(description="LiteX SoC Base for TernaryEdge-RV")
    parser.add_argument("--build", action="store_true", help="Build bitstream")
    parser.add_argument("--doc",   action="store_true", help="Generate Documentation/C-Headers")
    args = parser.parse_args()

    # Como não temos os pinos fisicos ainda, nao instanciamos uma board 
    # especifica, mas deixamos o script pronto para importar.
    print("[Ternary Edge-RV] - Script SoC Base gerado com sucesso.")
    print("[Info] Arquitetura: VexRiscv-Linux (RV32IMA)")
    print("[Info] Barramento NPU (Dummy): 0x40000000 via Wishbone")
    print("\nAguardando placa FPGA do professor para gerar Bitstream fisico.")

if __name__ == "__main__":
    main()
