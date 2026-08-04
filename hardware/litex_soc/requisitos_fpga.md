# Requisitos da Placa FPGA (Projeto Ternary Edge-RV)
**Última atualização:** 04/08/2026 — **FPGA recebida: RealDigital Urbana**

> ✅ **Placa adquirida:** RealDigital Urbana board (AMD Spartan-7 XC7S50-CSGA324). Cumpre todos os requisitos abaixo. Ver `base_soc.py` e `urrbana.dts` para a integração LiteX.

## 1. Memória RAM Externa (Crítico)
* **Requisito:** Mínimo de **32 MB** de memória RAM (DDR2, DDR3, DDR4 ou SDRAM).
* **Justificativa:** O núcleo RISC-V puro roda em FPGAs minúsculas, mas **o Linux exige memória externa para fazer o boot e alocar espaço de usuário**. FPGAs que possuem apenas BRAM (SRAM Interna) na ordem de Kilobytes **NÃO SERVEM** para bootar o kernel Linux + Driver + App de IA.
* **Urbana:** ✅ 128 MB DDR3 (`0x80000000–0x87FFFFFF`, 800 MT/s, 64Mx16).

## 2. Elementos Lógicos (LUTs / FFs)
* **Requisito:** Mínimo de **15.000 a 20.000 Logic Cells (LUTs)**.
* **Justificativa:** O núcleo `VexRiscv` (variante Linux com MMU) ocupa entre 3k a 5k LUTs. O controlador de memória DDR ocupa espaço considerável. O restante será reservado para instanciar a nossa NPU Ternária no barramento.
* **Urbana:** ✅ Spartan-7 XC7S50 fornece ~52.000 LUTs — 2,5× o requisito mínimo.

## 3. Armazenamento (Non-Volatile)
* **Requisito:** Slot de **Cartão MicroSD** ou memória Flash SPI grande (mínimo 16MB, porém SD Card é altamente recomendado).
* **Justificativa:** O *RootFS* (Sistema de Arquivos do Linux gerado pelo Gildo), o Kernel, o Driver (`.ko`) e as imagens de teste MNIST precisam ser lidas de algum lugar durante o boot.
* **Urbana:** ✅ Slot MicroSD dedicado. `base_soc.py` habilita `with_spi_sdcard=True` (bootloader) + `with_sdcard=True` (RootFS SDIO 4-bit).

## 4. Interfaces de Comunicação
* **Requisito:** 1x Porta UART (Geralmente via USB-Serial / Micro-USB).
* **Justificativa:** Obrigatório para acessar o terminal (console) do Linux.
* **Urbana:** ✅ UART via FTDI (micro USB — console Linux a 115200 baud).

## 5. Programador
* **Requisito:** Cabo USB capaz de programar a flash SPI.
* **Urbana:** ✅ FTDI FT2232H integrado — aceita Vivado Hardware Manager e `openFPGALoader`.

---

### 🏆 Comparativo com placas alternativas (apenas registro histórico)
A RealDigital Urbana foi selecionada por já estar disponível no laboratório. Para fins de referência, estas também funcionariam:
1. **Digilent Arty A7 (35T ou 100T):** (A mais famosa e fácil de usar com LiteX + Linux).
2. **Terasic DE10-Nano (Cyclone V):** (Excelente, possui muita RAM).
3. **Radiona ULX3S:** (Opção Open-Source excelente, com ECP5 e SDRAM).
4. **OrangeCrab / LFE5U:** (Pequena, mas possui memória DDR3 e slot SD).
