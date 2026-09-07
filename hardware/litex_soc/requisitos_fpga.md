# Requisitos da Placa FPGA (Projeto Ternary Edge-RV)
**Última atualização:** 24/08/2026. **FPGA alvo:** RealDigital Urbana

Este documento registra os requisitos da placa e o procedimento de handoff.
Os comandos pesados abaixo são procedimentos documentados, não execuções
declaradas. Recursos físicos, timing, bitstream, IRQ, DMA e desempenho ainda
estão pendentes.

## 1. Memória RAM Externa (Crítico)
* **Requisito:** Mínimo de **32 MB** de memória RAM (DDR2, DDR3, DDR4 ou SDRAM).
* **Justificativa:** O núcleo RISC-V puro roda em FPGAs pequenas, mas o Linux
  exige memória externa para boot e espaço de usuário. FPGAs com apenas BRAM
  não atendem ao boot do kernel, driver e aplicação de IA.
* **Urbana:** 128 MB DDR3, com base de integração DDR em `0x40000000` e faixa
  de 128 MB até `0x47FFFFFF` no mapa LiteX fixado. Capacidade e funcionamento
  físico ainda precisam de validação.

## 2. Elementos Lógicos (LUTs / FFs)
* **Requisito:** Mínimo de **15.000 a 20.000 Logic Cells (LUTs)**.
* **Justificativa:** O `VexRiscv` Linux com MMU e o controlador DDR ocupam
  parte relevante da FPGA. O restante hospeda a NPU ternária integrada.
* **Urbana:** Spartan-7 XC7S50. A disponibilidade real de LUTs, FFs, BRAM e
  DSP depende da síntese e do relatório físico, ainda pendentes.

## 3. Contrato de Integração NPU

| Parâmetro | Valor |
|:----------|:------|
| NPU MMIO | `0x80000000` |
| DDR | `0x40000000` |
| IRQ | `10` |
| Endianness | Little endian |
| Barramento | Wishbone B4, 32 bits |

A NPU integrada tem 64 PEs ternários físicos, uma árvore registrada 64 para 1,
um acumulador escalar INT32 e armazenamento de ativações em bancos. O
pós-processador tem três estágios registrados para bias, multiplicação inteira
com sinal, arredondamento, deslocamento e saturação. O caminho PE é
multiplierless, mas a requantização usa intencionalmente um multiplicador
inteiro com sinal.

A DMA usa Wishbone Classic em um beat por requisição, com `CTI=000`, `BTE=00`,
propagação de `ERR` downstream e timeout de 256 ciclos. Não é uma interface de
burst.

## 4. Armazenamento (Non-Volatile)
* **Requisito:** Slot de cartão MicroSD ou memória Flash SPI grande, com pelo
  menos 16 MB. SD Card é recomendado.
* **Justificativa:** RootFS, kernel, driver e imagens MNIST precisam ser lidos
  durante o boot.
* **Urbana:** Slot MicroSD dedicado. `base_soc.py` habilita SDIO nativo de
  4 bits; SPI é uma alternativa separada.

## 5. Interfaces de Comunicação
* **Requisito:** Uma porta UART, geralmente USB-Serial ou Micro-USB.
* **Justificativa:** Acesso ao console Linux.
* **Urbana:** UART via FTDI, com console Linux a 115200 baud.

## 6. Programador
* **Requisito:** Cabo USB capaz de programar a flash SPI.
* **Urbana:** FTDI FT2232H integrado, compatível com Vivado Hardware Manager e
  `openFPGALoader`.

## 7. Toolchain de Síntese: Vivado e openXC7

Vivado é o fluxo final de produção. openXC7 é opcional e serve apenas para
corroboração host-side. Nenhum dos dois tem recursos físicos, timing ou
bitstream atuais declarados neste documento.

### Vivado (fluxo final)
* **Instalação:** AMD Vivado Design Suite 2026.1. No NixOS, o wrapper procura
  `settings64.sh` nestes candidatos, nesta ordem:
  ```text
  /opt/Xilinx/2026.1/Vivado
  /opt/amd/2026.1/Vivado
  /opt/Xilinx/Vivado/2026.1
  /opt/amd/Vivado/2026.1
  /opt/Xilinx/Vivado/2024.2
  /opt/amd/Vivado/2024.2
  /opt/Xilinx/Vivado/2024.1
  /opt/amd/Vivado/2024.1
  /opt/Xilinx/Vivado/2023.2
  /opt/amd/Vivado/2023.2
  ```
* **Runtime:** Se `VIVADO_HOME` estiver definido, ele tem precedência e é
  usado diretamente. Caso contrário, o primeiro candidato que contenha
  `settings64.sh` é usado. Se nenhum existir, o wrapper mantém
  `/opt/Xilinx/2026.1/Vivado` para produzir o erro de runtime. O wrapper então
  carrega `settings64.sh` dentro do ambiente FHS.
* **Licença:** Vivado Basic é uma licença anual gratuita. O arquivo `.lic` deve
  ser instalado em `~/.Xilinx` antes do build.
* **Handoff:**
  ```bash
  cd /home/arthur/Documents/Projects/TernaryEdge-RV
  nix develop .#vivado
  cd hardware/litex_soc
  python3 base_soc.py --build --toolchain vivado
  ```
  O gerador usa 100 MHz como frequência padrão, mas não há alegação de
  fechamento automático de timing a 100 MHz.

### openXC7 (corroboração opcional)
* **Limitações:** Fluxo open-source com limitações de LUTRAM/MUXF e timing.
  Qualquer frequência alternativa deve ser passada explicitamente com
  `--sys-clk-freq`.
* **Handoff:**
  ```bash
  nix develop .#hardware
  ternaryedge-setup-openxc7
  cd hardware/litex_soc
  python3 base_soc.py --build --toolchain openxc7
  ```

## 8. Report Gate Vivado

Depois que o fluxo Vivado terminar, a verificação deve ser executada a partir
da raiz do repositório:

```bash
python3 hardware/litex_soc/check_vivado_reports.py
```

Artefatos históricos do Vivado são evidência rejeitada: omitiram
`postprocess_unit.v` e registraram WNS `-7.392 ns` e TNS `-35888.277 ns`.
O gate rejeita esses artefatos e exige fontes RTL canônicas atuais, parte exata
`xc7s50csga324-1`, relatório roteado e timing sem violações.

## 9. Comparativo com placas alternativas (registro histórico)

A RealDigital Urbana foi selecionada por já estar disponível no laboratório.
Para referência, também foram consideradas Digilent Arty A7, Terasic DE10-Nano,
Radiona ULX3S e OrangeCrab/LFE5U.
