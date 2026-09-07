# Status Atual do Projeto — Ternary Edge-RV
**Data:** 24/08/2026
**Autor:** Arthur Oliveira Gomes (Hardware)

---

## Resumo Executivo

O projeto está em **Fase 4, deploy físico e Paper 1**. O RTL atual de Arthur integra 64 PEs ternárias, árvore registrada 64->1, acumulador escalar INT32, ativações bancadas, pós-processamento de três estágios, DMA Wishbone Classic single-beat com `CTI=000`, `BTE=00`, `ERR` downstream e timeout de 256 ciclos, ABI canônico de 17 offsets `0x00..0x40` e até 8 descritores software-programáveis.

**Evidência canônica atual:** os testes Icarus focados e a matriz de top com 16, 32 e 64 PEs passam, incluindo a regressão de produção `784->1024->512->256` com pesos não uniformes na última linha: outputs 0..254 iguais a `65024` e output 255 igual a `-65024`. A matriz de lint Verilator, a síntese genérica Yosys e `synth_matrix` também passam. Os testes de contrato da apresentação passam em 11/11 e os testes unitários do report-gate passam em 12/12. Os resultados físicos Vivado continuam pendentes.

**Mapa congelado:** DDR em `0x40000000`, janela NPU de 64 KiB em `0x80000000`, IRQ 10. Somente os 17 offsets `0x00..0x40` são válidos; os demais retornam `ERR`. As PEs ternárias evitam multiplicadores no caminho ternário, mas a requantização inclui intencionalmente um multiplicador geral com sinal. A utilização física de DSPs aguarda os relatórios Vivado atuais.

**Status de integração:** a forma de shell para uma validação Vivado executada pelo usuário é `nix develop path:.#vivado`, pois `nix/vivado.nix` está atualmente não rastreado. Isso documenta um procedimento de aceitação, não comprova síntese, recursos, timing, bitstream ou comportamento físico.

Todos os recursos físicos, timing, bitstream, placa, boot Linux, IRQ, DMA, inferência, benchmark, potência e energia permanecem pendentes.

O corpo histórico abaixo é preservado para crédito e contexto. Ele não deve ser
lido como evidência corrente quando contradiz o resumo operacional acima.

**Mudança organizacional importante:** O `user_app.c` foi transferido de Gilvan para Gildo. Gildo agora assume a **NPU HAL + Classifier + Buildroot Packages** — uma expansão significativa de escopo que reflete a filosofia: *quanto menos complexa a NPU (puramente ternária), mais complexo o software que a completa.*

---

## 1. 👨‍💻 Arthur (Hardware — RTL/SoC)

### Fase Real: 3.5/4 (Fase 1 ✅, Fase 2 ✅, Fase 3 ✅, Fase 4 iniciando)

| Tarefa | Status | Arquivo |
|--------|--------|---------|
| Mapa de Memória Oficial v2 | ✅ `docs/arquitetura/mapa_de_memoria.md` | DDR `0x40000000`, NPU `0x80000000`, IRQ 10 |
| Requisitos FPGA | ✅ `hardware/litex_soc/requisitos_fpga.md` | Mínimo 32MB RAM, 15k LUTs, SD Card |
| SoC Base VexRiscv | ✅ `hardware/litex_soc/base_soc.py` | RV32IMA Linux, Wishbone, região NPU reservada |
| PE ternária, caminho sem multiplicador | ✅ `hardware/npu_rtl/ternary_mac.v` | DSP físico pendente de relatório Vivado |
| NPU v1 (1 MAC, PIO, Wishbone Slave) | ✅ `npu_ternaria_top.v`, `tb_npu_ternaria_top.v` | Legado funcional |
| **64 PEs integradas + árvore** | ✅ `ternary_mac_array.v` + `adder_tree_64.v` | Array integrado, sem afirmar recurso físico |
| **Acumulador e ativações** | ✅ RTL atual | Acumulador escalar e bancos de ativações |
| **Pós-processamento** | ✅ `postprocess_unit.v` | Três estágios; requantização usa multiplicador geral com sinal |
| **Wishbone Master DMA** | ✅ `wishbone_master.v` | Transferência single-beat, `ERR` e timeout |
| **NPU v2 Top-Level integrado** | ✅ `npu_ternaria_top_v2.v` | ABI de descritores, controlador sequencial e estados internos de pós-processamento e erro |
| **Testes RTL atuais** | ✅ `hardware/npu_rtl/Makefile` | Icarus focado, top 16/32/64 e lint Verilator |
| **LiteX ERR propagation** | ✅ `hardware/litex_soc/base_soc.py` | ERR propagado no caminho Wishbone |
| **Golden Model C++ v2** | ✅ `npu_sim_v2.cpp` + `demo_npu_v2.cpp` | Registro histórico, 21/21 checks |
| **Pacote de definições compartilhadas** | ✅ `npu_v2_pkg.v` | 17 offsets `0x00..0x40`, até 8 descritores, STATUS com camada em `[15:8]`, estados internos `0..19` incluindo `ST_POSTPROCESS_WAIT` |
| **SoC base atualizado (IRQ 10, NPU v2)** | ✅ `base_soc.py` | Wishbone e IRQ 10 no PLIC. Importa `realdigital_urbana` |
| **Device Tree FPGA real** | ✅ `urrbana.dts` | DDR em `0x40000000`, NPU em `0x80000000` |
| **Wrapper Vivado e proveniência Urbana** | ✅ `nix/vivado.nix`, check local | Shell puro Nix, dispositivo `xc7s50csga324-1` |
| **FPGA Física** | ✅ Recebida (Urbana, ago/2026) | Spartan-7 XC7S50-CSGA324. Síntese pendente. |

### Gate de síntese e bloqueios atuais

O build Vivado atual deve ser executado pelo usuário a partir da raiz, depois
de `ternaryedge-check-litex-board`, e aceito somente por
`python3 hardware/litex_soc/check_vivado_reports.py`. A forma de shell é
`nix develop path:.#vivado`, porque `nix/vivado.nix` está não rastreado.

Os relatórios Vivado históricos estão stale e rejeitados: o Tcl gerado omitia
`postprocess_unit.v`, os artefatos precedem o RTL atual, WNS era `-7.392 ns` e
TNS era `-35888.277 ns`. Eles não comprovam recursos, timing, bitstream ou
funcionamento físico atuais.

Bloqueios registrados: `openFPGALoader --detect` retorna `device not found`, o
compilador RV32 do Buildroot está ausente e não há evidência física end-to-end,
incluindo boot Linux, IRQ, DMA, benchmark ou medição de desempenho.

---

## 2. 🖥️ Gildo (OS + NPU HAL + Classifier + Buildroot Packages)

### Fase Real: 4.0/4 (Fase 1 ✅, Fase 2 ✅, Fase 3 ✅, Fase 4 iniciando)

**Expansão de escopo:** Gildo agora é responsável por toda a camada de software entre o driver e o usuário — a NPU HAL, o Classifier (output layer CPU), o Weights Loader e os Buildroot Packages. O `user_app.c` foi recebido de Gilvan e refatorado para usar a HAL.

| Tarefa | Status | Arquivo |
|--------|--------|---------|
| Buildroot External Tree | ✅ `software/os_buildroot/` | Estrutura completa |
| Defconfig RV32IMA | ✅ `configs/ternaryedge_rv_defconfig` | BR2_RISCV_32, kernel 6.18.7, OpenSBI 1.6, QEMU |
| Toolchain via SDK | ✅ `software/os_buildroot/README.md` | Cada um compila a sua |
| HIGH_RES_TIMERS | ✅ Ativado | CONFIG_HIGH_RES_TIMERS habilitado |
| Device Tree (.dts) QEMU + FPGA | ✅ `setup_qemu/ternaryedge.dts`, `urrbana.dts` | IRQ=10, `compatible = "ternaryedge,npu-ternaria"` |
| Kernel config fragment (FAT/EXT4) | ✅ `configs/kernel-npu.cfg` | Suporte a sistemas de arquivo |
| **NPU HAL — API pública** | ✅ `software/npu_hal/npu_hal.h` (20 linhas) | init, load_weights, predict, batch, deinit, print_result |
| **NPU HAL — Implementação** | ✅ `software/npu_hal/npu_hal.c` (115 linhas) | open, mmap, ioctl, output layer CPU, timing segregado |
| **NPU HAL — Estruturas internas** | ✅ `software/npu_hal/npu_hal_internal.h` (21 linhas) | `npu_ctx_t`, `npu_result_t` |
| **NPU Classifier** | ✅ `software/npu_hal/npu_classifier.c` (28 linhas) | Output layer 256→10 FP32 + argmax + softmax |
| **NPU Weights Loader** | ✅ `software/npu_hal/npu_weights.c` (32 linhas) | Carrega 3 layers ternários + FP32 output para DMA |
| **Buildroot package npu-ternaria** | ✅ `software/os_buildroot/package/npu-ternaria/` | Kernel module package |
| **Buildroot package npu-hal** | ✅ `software/os_buildroot/package/npu-hal/` | Biblioteca estática `libnpu_hal.a` |
| **Buildroot package user-app** | ✅ `software/os_buildroot/package/user-app/` | Binário usuário |
| **user_app.c refatorado para HAL** | ✅ `software/user_app/user_app.c` (133 linhas) | `--cpu` baseline, `--file` MNIST, `--batch` benchmark |
| **libnpu_hal.a validada** | ✅ Compilação nativa OK | Pendente cross-compile + validação FPGA |

### Pendente para Gildo (Fase 4):
1. Gerar imagem final Buildroot (kernel 6.18.7 + OpenSBI 1.6 + RootFS com packages habilitados)
2. Particionar SD card (FAT32 boot + ext4 rootfs) e gravar
3. Bootar Linux na Urbana e validar `dmesg` (sem kernel panic, peripherals OK)
4. Validação end-to-end: HAL + driver + NPU real operando jun

### Notas de风险的 identificadas (para revisão pós-síntese):
- `npu_hal.c` linha 76: `npu_output[i] = (int32_t)ctx->dma_buffer[i]` lê 1 byte; se RTL escreve 32 bits/neurônio, deveria ser `((int32_t*)ctx->dma_buffer)[i]`. Revisar com o RTL do `npu_ternaria_top_v2.v`.
- `npu_hal.c` linha 51: `act_base + 0x5C000` hardcoded — confirmar que bate com `WEIGHT_CFG`/`ACT_CFG` e offsets esperados pelo `wishbone_master.v`.

---

## 3. ⚙️ Gustavo (Driver de Kernel)

### Fase Real: 3.5/4 (Fase 1 ✅, Fase 2 ✅, Fase 3 ✅, Fase 4 iniciando)

| Tarefa | Status | Detalhes |
|--------|--------|----------|
| LKM Hello World | ✅ | Fase 1 |
| Character Device | ✅ | `/dev/npu_ternaria` via `register_chrdev` |
| File Operations | ✅ | `.mmap`, `.unlocked_ioctl`, `.open`, `.release` |
| Platform Driver | ✅ | Device Tree match `compatible = "ternaryedge,npu-ternaria"` |
| MMIO (ioremap) | ✅ | `devm_ioremap_resource()` no probe |
| DMA Coherent Memory | ✅ | `dma_alloc_coherent()` — 4MB buffer |
| Zero-Copy (mmap) | ✅ | `dma_mmap_coherent()` — usuário escreve direto |
| IRQ Handler | ✅ | `devm_request_irq()` + `wait_event_interruptible()` |
| IOCTL (start inference) | ✅ | `NPU_IOCTL_START_INFERENCE` com struct `npu_ioctl_args` |
| Offsets v2 e mapa MMIO atual | ✅ | `npu_driver.c` v3.0, alinhado com RTL v2 |
| WEIGHT_CFG + ACT_CFG no ioctl | ✅ | `iowrite32()` para todos os 5 campos |
| IOCTL Header | ✅ | `software/include/npu_ioctl.h` |

### Bloqueios:
- Aguardando toolchain do Gildo para compilar `.ko` para RISC-V
- Aguardando FPGA real para teste físico

---

## 4. 🧠 Gilvan (Inteligência Artificial + Golden Model)

### Fase Real: 3.0/4 (Fase 1 ✅, Fase 2 ✅, Fase 3 ✅, Fase 4 iniciando)

| Tarefa | Status | Detalhes |
|--------|--------|----------|
| Ambiente Python + Larq | ✅ | TensorFlow + Larq |
| Modelo QAT (3 layers ternárias) | ✅ | 784→1024→512→256 |
| Sparsity L1 | ✅ | Regularização forcing zeros |
| Fake Quant INT8 entre layers | ✅ | `fake_quant_with_min_max_args(min=0, max=127, num_bits=8)` |
| Acurácia >95% | ✅ | Validado |
| Pack de pesos (16/uint32_t) | ✅ | `pack_weights.py` |
| weights.h gerado (3 layers + output FP32) | ✅ | Formato compatível com HAL |
| Golden Model v2 (64 MACs + DMA) | ✅ | 21/21 testes, bit-accurate |
| Output layer validada (Opção B adotada) | ✅ | CPU fallback na classificação final |
| user_app.c | 🔄 Transferido | Agora é responsabilidade do Gildo (via HAL) |

> **Nota:** O `user_app.c` foi transferido para Gildo. Gilvan agora fornece os pesos no formato correto (`quant_dense_weights[]`, `output_weights[]`, `output_biases[]`) e o golden model C++ para validação cruzada.

---

## 5. Estado da Verificação (Testes)

| Simulação | Testes | Passam | Status |
|:----------|-------:|-------:|:-------|
| NPU v1 (C++ golden model) | 8 | 8 | ✅ |
| NPU v2 (C++ golden model) | 21 | 21 | ✅ |
| **Total** | **29** | **29** | **✅ 100%** |

---

## 6. Comparativo: Checklist Original vs Realidade

| Item | Checklist Original | Realidade | Diferença |
|------|-------------------|-----------|-----------|
| Arthur Fase 1 | 5 tarefas | 5 tarefas | ✅ Completo |
| Arthur Fase 2 | 4 tarefas | 4+ (criou RTL) | ✅ Completo |
| Arthur Fase 3 | 6 tarefas | **7** (criou tb_v2, pkg) | 🚀 Superou |
| Gildo Fase 1 | 3 tarefas | 4 tarefas | ✅ Completo |
| Gildo Fase 2 | 2 tarefas | 2 tarefas | ✅ Completo |
| Gildo Fase 3 (antigo) | 3 tarefas (DT + Config.in + testbench) | **4** (DT, DTS, kernel cfg, external tree) | ✅ Reatribuído |
| Gildo Fase 3 (novo) | — | **12 tarefas** (HAL, Classifier, Weights, 3 packages, user_app) | 🆕 Escopo expandido |
| Gustavo Fase 1 | 3 tarefas | 3 tarefas | ✅ Completo |
| Gustavo Fase 2 | 5 tarefas | 5+ (IOCTL, header) | ✅ Superou |
| Gustavo Fase 3 | 5 tarefas | **5** (todas feitas) | 🚀 Completo |
| Gilvan Fase 1 | 3 tarefas | 3+ (sparsity, fq) | ✅ Superou |
| Gilvan Fase 2 | 3 tarefas | 3 tarefas | ✅ Completo |
| Gilvan Fase 3 | 5 tarefas | **5** (output layer validada, user_app transferido) | ✅ Completo |

---

## 7. 🚨 Riscos Atuais

| Risco | Impacto | Probabilidade | Mitigação |
|-------|---------|---------------|-----------|
| Timing e recursos da FPGA ainda desconhecidos | SoC pode não atingir 100 MHz ou usar recursos inesperados | Em avaliação | Executar o build Vivado atual e aceitar somente o relatório validado pelo gate |
| Bug de DMA crossbar (master NPU → DDR 0x40000000) | NPU lê lixo da RAM | Média | Verificar `base_soc.py` e o crossbar LiteX contra o mapa congelado |
| Bug de alinhamento no HAL | Inference dá resultado errado | Média | Revisar `npu_hal.c:76` (cast 8 vs 32 bits) e `npu_hal.c:51` (offset 0x5C000) contra `npu_v2_pkg.v` antes da integração final |
| Paper 1 ainda em 30% | Submissão atrasada | Alta | Toda seção de HW/OS/Driver/AI está esqueletada; depende só de métricas reais da FPGA. Caminho crítico: síntese → boot → insmod → benchmark → tabelas |
| Toolchain não compilada por todos | Membros não testam .ko/.HAL localmente | Média | Cada um roda `make sdk` em `software/os_buildroot/`. Documentado no README do OS |
| Notebook do Arthur (i5-5200U, 8 GB RAM) | Síntese Vivado lenta/Swap | Média | Usar o wrapper Vivado puro em Nix como etapa pesada do usuário, sem apresentar execução ainda pendente como resultado |

---

## Adendo operacional de transição (24/08/2026)

**Nota arquivística:** o corpo original deste registro é um **snapshot histórico** e permanece preservado. Este adendo aponta a fonte de verdade operacional vigente, sem reescrever as afirmações datadas acima.

- **Gilvan:** permanecem preservadas sua contribuição histórica no QAT, no empacotamento ternário e no Golden Model C++ v2, bem como sua condição de quarto autor do Paper 1.
- **Gustavo:** assume a manutenção ativa do pipeline de IA, da exportação e de `weights.h`, da regressão do Golden Model, do driver, da cross-compilação, da coordenação da validação física, dos benchmarks CPU versus NPU e dos resultados e discussão do Paper 1.
- **Evidência atual, registrada conservadoramente:** Icarus focado, matriz de top com 16, 32 e 64 PEs e matriz de lint Verilator passam. A regressão de produção `784->1024->512->256` passa em 16, 32 e 64 PEs, com outputs 0..254 iguais a `65024` e a última linha não uniforme produzindo `-65024` no output 255. A síntese genérica Yosys e `synth_matrix` passam, assim como os testes de contrato da apresentação (11/11) e os testes unitários do report-gate (12/12). Os resultados Vivado físicos permanecem pendentes e não há benchmark FPGA end-to-end comprovado.
- A menção histórica a `output_biases[]` no corpo deste snapshot usa nomenclatura antiga; o símbolo atual verificado no header é `output_bias[]`.
