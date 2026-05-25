# Requisitos da Placa FPGA (Projeto Ternary Edge-RV)

Para que o professor possa selecionar e disponibilizar a placa FPGA correta para o projeto, a placa DEVE atender aos seguintes requisitos mínimos para suportar um SoC RISC-V capaz de rodar o Sistema Operacional Linux (Buildroot) juntamente com um acelerador customizado (NPU).

## 1. Memória RAM Externa (Crítico)
* **Requisito:** Mínimo de **32 MB** de memória RAM (DDR2, DDR3, DDR4 ou SDRAM).
* **Justificativa:** O núcleo RISC-V puro roda em FPGAs minúsculas, mas **o Linux exige memória externa para fazer o boot e alocar espaço de usuário**. FPGAs que possuem apenas BRAM (SRAM Interna) na ordem de Kilobytes **NÃO SERVEM** para bootar o kernel Linux + Driver + App de IA.

## 2. Elementos Lógicos (LUTs / FFs)
* **Requisito:** Mínimo de **15.000 a 20.000 Logic Cells (LUTs)**.
* **Justificativa:** O núcleo `VexRiscv` (variante Linux com MMU) ocupa entre 3k a 5k LUTs. O controlador de memória DDR ocupa espaço considerável. O restante será reservado para instanciar a nossa NPU Ternária no barramento.

## 3. Armazenamento (Non-Volatile)
* **Requisito:** Slot de **Cartão MicroSD** ou memória Flash SPI grande (mínimo 16MB, porém SD Card é altamente recomendado).
* **Justificativa:** O *RootFS* (Sistema de Arquivos do Linux gerado pelo Gildo), o Kernel, o Driver (`.ko`) e as imagens de teste MNIST precisam ser lidas de algum lugar durante o boot.

## 4. Interfaces de Comunicação
* **Requisito:** 1x Porta UART (Geralmente via USB-Serial / Micro-USB).
* **Justificativa:** Obrigatório para acessar o terminal (console) do Linux.

---
### 🏆 Sugestões de Placas (Exemplos que funcionam perfeitamente no LiteX):
Se o professor tiver alguma destas, o projeto está garantido:
1. **Digilent Arty A7 (35T ou 100T):** (A mais famosa e fácil de usar com LiteX + Linux).
2. **Terasic DE10-Nano (Cyclone V):** (Excelente, possui muita RAM).
3. **Radiona ULX3S:** (Opção Open-Source excelente, com ECP5 e SDRAM).
4. **OrangeCrab / LFE5U:** (Pequena, mas possui memória DDR3 e slot SD).
