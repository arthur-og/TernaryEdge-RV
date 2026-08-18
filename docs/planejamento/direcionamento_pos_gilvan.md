# Direcionamento pós-Gilvan: organização operacional e fechamento do Paper 1

**Data de referência:** 17/08/2026
**Janela de fechamento:** até 31/08/2026 (submissão SBCCI/LASCAS)
**Status:** Organização operacional ativa e atualização de status em 17/08/2026

> Este documento é a fonte de verdade para a transição de responsabilidades e para o escopo de fechamento do Paper 1. As atas e planos anteriores continuam válidos como registros históricos.

## 1. Objetivo

Alinhar a divisão operacional após a transição do Gilvan, separar autoria acadêmica da responsabilidade operacional ativa, registrar a evolução de evidências em 17/08/2026 e direcionar o trabalho para a submissão do Paper 1 até 31/08/2026.

## 2. Status em um parágrafo (17/08/2026)

A placa RealDigital Urbana (AMD Spartan-7 XC7S50-CSGA324) está fisicamente conectada via micro-USB com chip FTDI FT2232H detectado, JTAG IDCODE 0x362f093 confirmado e portas `/dev/ttyUSB0` e `/dev/ttyUSB1` ativas. A simulação RTL em Verilog (`make verilog_v2`) atinge 100% de aprovação (4/4 testes de regressão passados). As flags de síntese do openXC7 na plataforma foram atualizadas para `-nolutram -nowidelut` para eliminar cadeias RAM256X1S e MUXF7/MUXF8. A autoria original de 4 membros permanece totalmente preservada para a submissão do Paper 1 até 31/08/2026.

## 3. Ownership operacional ativo

| Pessoa | Frente operacional | Escopo e entregas principais |
|:--|:--|:--|
| **Arthur Oliveira Gomes** | Hardware RTL, LiteX SoC, regressão Verilog, síntese openXC7/Vivado, Bitstream | Desenvolvimento RTL NPU v2, SoC LiteX VexRiscv, regressão Verilog (100% PASS), síntese openXC7 com `-nolutram -nowidelut`, geração de bitstream e relatório de recursos para a FPGA Urbana |
| **Gildo Alves de Lima Junior** | Infraestrutura de OS, Buildroot, Device Tree, NPU HAL, Classifier, MicroSD, boot físico Linux | Buildroot image, Device Tree (`urrbana.dts`), NPU HAL (`libnpu_hal.a`), Classifier FP32 CPU para camada de saída (256->10), preparação do cartão MicroSD e boot físico do Linux na Urbana |
| **Gustavo Alexandre dos Santos** | Kernel Driver, contrato weights.h, manutenção de exportação de IA, compilação cruzada, benchmarks físicos e seção de resultados | Kernel driver (`npu_driver.ko`), manutenção do contrato `weights.h` e exportação do pipeline de IA, compilação cruzada para RV32IMA, execução dos benchmarks físicos (CPU vs NPU), escrita da seção de resultados e discussão |
| **Gilvan Alves Pastor Junior** | Contribuição histórica de IA e Golden Model (Retido e creditado) | Pipeline histórico de QAT (Larq/STE), empacotamento de pesos ternários e Golden Model C++ v2 mantidos e creditados no projeto |

## 4. Autoria do paper e preservação de créditos

### Lista original de autores (preservada no Paper 1)

1. Arthur Oliveira Gomes
2. Gildo Alves de Lima Junior
3. Gustavo Alexandre dos Santos
4. Gilvan Alves Pastor Junior

Gilvan permanece como quarto autor do Paper 1. A transição de atividades operacionais não remove autoria e não reescreve contribuições históricas acumuladas. A lista acima deve constar no template LaTeX, no README e nas citações.

### Regra de separação

Autoria registra contribuição acadêmica acumulada. Ownership operacional registra quem conduz a execução ativa das próximas entregas.

## 5. Matriz de evidências (Status em 17/08/2026)

| Evidência validada e confirmada | Em andamento para o prazo de 31/08/2026 |
|:--|:--|
| Placa Urbana conectada via micro-USB, FTDI FT2232H detectado, JTAG IDCODE 0x362f093, `/dev/ttyUSB0` e `/dev/ttyUSB1` criados | Bitstream gerado e carregado na FPGA Urbana real |
| Regressão Verilog RTL (`make verilog_v2`) 100% PASS (4/4 testes passados) | Boot físico do Linux a partir do cartão MicroSD na Urbana |
| openXC7 flags atualizadas para `-nolutram -nowidelut` na plataforma | Carregamento do driver (`insmod npu_driver.ko`) no hardware real |
| Golden Model C++ v2 com 21/21 testes host-side passando | Medição física de tempo de inferência (CPU vs NPU) via `user_app` |
| Contrato de interfaces formalizado (MMIO, DMA, Device Tree `urrbana.dts`, HAL `libnpu_hal.a`) | Tabela final de síntese de recursos (LUTs, FFs, BRAM, 0 DSPs) |

## 6. Gates de trabalho ate 31/08/2026

1. **G1, Regressão e Validação Hardware:** Arthur valida regressão RTL (100% PASS) e aplica `-nolutram -nowidelut` na síntese openXC7.
2. **G2, Síntese e Bitstream:** Arthur executa a síntese do SoC NPU v2 para Spartan-7 XC7S50 e gera o bitstream.
3. **G3, Imagem de OS e SD Card:** Gildo gera a imagem Buildroot (kernel 6.18.7 + OpenSBI 1.6 + RootFS), prepara o MicroSD e realiza o boot na Urbana.
4. **G4, Driver e HAL Físicos:** Gustavo e Gildo validam a carga do `npu_driver.ko` e a execução da `libnpu_hal.a` na Urbana.
5. **G5, Benchmarks Físicos:** Gustavo executa os testes comparativos (CPU vs NPU) e coleta arquivos CSV de tempo.
6. **G6, Redação e Submissão:** Equipe consolida o texto em `paper/paper1_template.tex` para submissão até 31/08/2026.

## 7. Deliverables por membro da equipe

### Arthur Oliveira Gomes
- RTL da NPU v2 e SoC LiteX VexRiscv integrados.
- Log de regressão Verilog 100% PASS.
- Fluxo de síntese openXC7 ajustado (`-nolutram -nowidelut`) e bitstream gerado.
- Seção de Arquitetura de Hardware e Síntese no Paper 1.

### Gildo Alves de Lima Junior
- Imagem Buildroot e Device Tree `urrbana.dts` para a FPGA Urbana.
- Biblioteca HAL (`libnpu_hal.a`) e Classifier FP32 CPU para a camada de saída.
- Gravação do MicroSD e validação do boot físico do Linux.
- Seção de Infraestrutura de OS e HAL no Paper 1.

### Gustavo Alexandre dos Santos
- Driver de kernel (`npu_driver.ko`) cross-compilado para RV32IMA.
- Manutenção do contrato de pesos `weights.h` e exportação do pipeline de IA.
- Execução de testes de benchmark físicos e geração dos gráficos/tabelas CSV.
- Seção de Kernel Driver e Resultados e Discussão no Paper 1.

### Gilvan Alves Pastor Junior
- Pipeline QAT, empacotamento de pesos ternários e Golden Model v2 mantidos no histórico.
- Crédito de autoria mantido no Paper 1.
