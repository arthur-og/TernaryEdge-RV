# Direcionamento pós-Gilvan: organização operacional e fechamento do Paper 1

**Data de referência:** 20/08/2026
**Janela de fechamento:** até 31/08/2026 (submissão SBCCI/LASCAS)
**Status:** Organização operacional ativa em 20/08/2026. Os registros de 17/08/2026 e anteriores são históricos e não substituem a evidência corrente.

> Este documento é a fonte de verdade para a transição de responsabilidades e para o escopo de fechamento do Paper 1. As atas e planos anteriores continuam válidos como registros históricos.

## 1. Objetivo

Alinhar a divisão operacional após a transição do Gilvan, separar autoria acadêmica da responsabilidade operacional ativa, registrar a evolução de evidências em 17/08/2026 e direcionar o trabalho para a submissão do Paper 1 até 31/08/2026.

## 2. Status em um parágrafo (17/08/2026)

A placa RealDigital Urbana (AMD Spartan-7 XC7S50-CSGA324) tem registro de conexão via micro-USB com chip FTDI FT2232H detectado, JTAG IDCODE 0x362f093 confirmado e portas `/dev/ttyUSB0` e `/dev/ttyUSB1` ativas. O registro histórico de Verilog informa 4/4, mas o testbench está indisponível no shell atual e não há nova aprovação corrente. A evidência corrente é C++ Golden Model v1 com 8/8 checks, C++ Golden Model v2 com 21/21 checks, Python com 5/5 checks e ABI IOCTL aprovada. Não há inferência end-to-end nem benchmark CPU versus NPU comprovado na FPGA. A autoria original de 4 membros permanece preservada.

## 3. Ownership operacional ativo

| Pessoa | Frente operacional | Escopo e entregas principais |
|:--|:--|:--|
| **Arthur Oliveira Gomes** | Hardware RTL, LiteX SoC, regressão Verilog, síntese openXC7/Vivado, Bitstream | Desenvolvimento RTL NPU v2, SoC LiteX VexRiscv, regressão Verilog quando o simulador estiver disponível, síntese openXC7 com `-nolutram -nowidelut`, geração de bitstream e relatório de recursos para a FPGA Urbana |
| **Gildo Alves de Lima Junior** | Infraestrutura de OS, Buildroot, Device Tree, NPU HAL, Classifier, MicroSD, boot físico Linux | Buildroot image, Device Tree (`urrbana.dts`), NPU HAL (`libnpu_hal.a`), Classifier FP32 CPU para camada de saída (256->10), preparação do cartão MicroSD e boot físico do Linux na Urbana |
| **Gustavo Alexandre dos Santos** | Pipeline de IA, exportação de pesos, contrato `weights.h`, Golden Model, Kernel Driver, compilação cruzada RV32, coordenação de validação física, benchmarks e Paper 1 | Manutenção corrente do pipeline de IA e do contrato `weights.h`, regressão e manutenção dos Golden Models, driver (`npu_driver.ko`), compilação cruzada RV32IMA, coordenação da validação física com Arthur e Gildo, benchmarks CPU versus NPU e resultados e discussão do Paper 1 |
| **Gilvan Alves Pastor Junior** | Contribuição histórica, sem ownership operacional atual | QAT histórico, empacotamento ternário e C++ Golden Model v2 preservados e creditados; permanece como quarto autor |

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
| Placa Urbana conectada via micro-USB, FTDI FT2232H detectado, JTAG IDCODE 0x362f093, `/dev/ttyUSB0` e `/dev/ttyUSB1` criados | Gerar e carregar o bitstream na FPGA Urbana real |
| C++ v1 8/8, C++ v2 21/21, Python 5/5 e ABI IOCTL aprovada | Boot físico do Linux a partir do cartão MicroSD na Urbana |
| Testbench Verilog indisponível no shell atual; o registro histórico 4/4 permanece datado | Inferência end-to-end e benchmark CPU versus NPU na FPGA |
| openXC7 flags atualizadas para `-nolutram -nowidelut` na plataforma | Carregamento do driver (`insmod npu_driver.ko`) no hardware real |
| Contrato de interfaces documentado (MMIO, DMA, Device Tree `urrbana.dts`, HAL `libnpu_hal.a`) | Medição física de tempo de inferência (CPU vs NPU) via `user_app` |
| Números de 64 MACs, 0 DSPs, throughput e speedup permanecem como intenção de projeto ou aguardam síntese e medição | Tabela final de síntese de recursos (LUTs, FFs, BRAM, DSPs) |

## 6. Gates de trabalho ate 31/08/2026

1. **G1, Regressão e Validação Hardware:** Arthur conduz a regressão RTL quando o simulador estiver disponível e aplica `-nolutram -nowidelut` na síntese openXC7. O registro histórico 4/4 não é evidência corrente.
2. **G2, Síntese e Bitstream:** Arthur executa a síntese do SoC NPU v2 para Spartan-7 XC7S50 e gera o bitstream.
3. **G3, Imagem de OS e SD Card:** Gildo gera a imagem Buildroot (kernel 6.18.7 + OpenSBI 1.6 + RootFS), prepara o MicroSD e realiza o boot na Urbana.
4. **G4, Driver e HAL Físicos:** Gustavo coordena a validação do `npu_driver.ko`, da compilação cruzada RV32 e da execução da `libnpu_hal.a` com Gildo na Urbana.
5. **G5, Benchmarks Físicos:** Gustavo coordena a validação física com Arthur e Gildo, executa os testes comparativos CPU versus NPU e coleta arquivos CSV de tempo.
6. **G6, Redação e Submissão:** Equipe consolida o texto em `paper/paper1_template.tex` para submissão até 31/08/2026.

## 7. Deliverables por membro da equipe

### Arthur Oliveira Gomes
- RTL da NPU v2 e SoC LiteX VexRiscv integrados.
- Log histórico de regressão Verilog 4/4; nova execução está indisponível no shell atual.
- Fluxo openXC7 ajustado (`-nolutram -nowidelut`) como corroboração opcional; bitstream atual permanece pendente do fluxo Vivado executado pelo usuário.
- Seção de Arquitetura de Hardware e Síntese no Paper 1.

### Gildo Alves de Lima Junior
- Imagem Buildroot e Device Tree `urrbana.dts` para a FPGA Urbana.
- Biblioteca HAL (`libnpu_hal.a`) e Classifier FP32 CPU para a camada de saída.
- Gravação do MicroSD e validação do boot físico do Linux.
- Seção de Infraestrutura de OS e HAL no Paper 1.

### Gustavo Alexandre dos Santos
- Manutenção do pipeline de IA, exportação de pesos e contrato `weights.h`.
- Regressão e manutenção dos Golden Models C++ v1 e v2.
- Driver de kernel (`npu_driver.ko`) cross-compilado para RV32IMA.
- Coordenação da validação física e da compilação cruzada com Arthur e Gildo.
- Execução de testes de benchmark CPU versus NPU e geração dos gráficos e tabelas CSV.
- Seção de Kernel Driver e Resultados e Discussão no Paper 1.

### Gilvan Alves Pastor Junior
- Pipeline QAT histórico, empacotamento de pesos ternários e Golden Model v2 mantidos no histórico.
- Crédito de autoria mantido no Paper 1.
