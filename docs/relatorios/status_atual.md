# Status Atual do Projeto — Ternary Edge-RV
**Data:** 04/08/2026
**Autor:** Arthur Oliveira Gomes (Hardware)

---

## Resumo Executivo

O projeto completou **toda a Fase 3** e está em **Fase 4 — Deploy Físico e Paper 1**. NPU v2, HAL, Driver, Buildroot packages, golden model e pipeline QAT estão 100% code-complete e validados em simulação (29/29 testes no golden model C++).

**Novidade crítica (Agosto 2026):** A **RealDigital Urbana** (AMD Spartan-7 XC7S50-CSGA324, 128 MB DDR3, MicroSD) **foi recebida**. O bloqueio histórico da Fase 4 desapareceu. Agora o caminho crítico é puramente físico — síntese, boot Linux na FPGA, `insmod` e benchmarks reais.

**Status do software:** Gildo entregou a NPU HAL completa (`npu_hal.c`/`npu_classifier.c`/`npu_weights.c`) e os Buildroot packages. Gilvan entregou `weights.h` real (91.169 linhas) e golden model v2 (21/21). Gustavo entregou driver v3.0 (offsets NPU v2 + IOCTL struct). Arthur entregou RTL v2 (64 MACs, Layer Sequencer, Wishbone Master) e `base_soc.py` pronto para Urbana.

**Mudança organizacional importante:** O `user_app.c` foi transferido de Gilvan para Gildo. Gildo agora assume a **NPU HAL + Classifier + Buildroot Packages** — uma expansão significativa de escopo que reflete a filosofia: *quanto menos complexa a NPU (puramente ternária), mais complexo o software que a completa.*

---

## 1. 👨‍💻 Arthur (Hardware — RTL/SoC)

### Fase Real: 3.5/4 (Fase 1 ✅, Fase 2 ✅, Fase 3 ✅, Fase 4 iniciando)

| Tarefa | Status | Arquivo |
|--------|--------|---------|
| Mapa de Memória Oficial v2 | ✅ `docs/arquitetura/mapa_de_memoria.md` | 10 registradores, `0x40000000`, IRQ 10 |
| Requisitos FPGA | ✅ `hardware/litex_soc/requisitos_fpga.md` | Mínimo 32MB RAM, 15k LUTs, SD Card |
| SoC Base VexRiscv | ✅ `hardware/litex_soc/base_soc.py` | RV32IMA Linux, Wishbone, região NPU reservada |
| MAC Multiplierless (ternário×INT8) | ✅ `hardware/npu_rtl/ternary_mac.v` | 0 DSPs — Mux + Somador |
| NPU v1 (1 MAC, PIO, Wishbone Slave) | ✅ `npu_ternaria_top.v`, `tb_npu_ternaria_top.v` | Legado funcional |
| **64 MACs paralelos + Adder Tree** | ✅ `ternary_mac_array.v` + `adder_tree_64.v` | 63 adders, 6 estágios pipeline |
| **Wishbone Master DMA (burst reads)** | ✅ `wishbone_master.v` | B4 Standard, burst incrementante |
| **NPU v2 Top-Level integrado** | ✅ `npu_ternaria_top_v2.v` | FSM 10 estados, Layer Sequencer |
| **Layer Sequencer (3 layers)** | ✅ (embutido no top v2) | 784→1024→512→256 automático, ~92K ciclos |
| **Testbench Verilog v2** | ✅ `tb_npu_v2.v` | RAM simulada, testes registrador/IRQ/STATUS |
| **Golden Model C++ v2** | ✅ `npu_sim_v2.cpp` + `demo_npu_v2.cpp` | 21/21 testes passando |
| **Pacote de definições compartilhadas** | ✅ `npu_v2_pkg.v` | Register map, FSM states, constantes |
| **SoC base atualizado (IRQ=10, NPU v2)** | ✅ `base_soc.py` | Wishbone Slave + Master, IRQ 10 no PLIC. Importa `realdigital_urbana` |
| **Device Tree FPGA real** | ✅ `urrbana.dts` | DDR3 128MB @ `0x80000000`, NPU, LiteX peripherals |
| **FPGA Física** | ✅ Recebida (Urbana, ago/2026) | Spartan-7 XC7S50-CSGA324. Síntese pendente. |

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
| Offsets v2 (10 registradores) | ✅ | `npu_driver.c` v3.0 — alinhado com RTL v2 |
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
| Timing closure na FPGA não fechar | SoC não atinge 100 MHz | Baixa | Spartan-7 é farto em LUTs (52k) e NPU é multiplierless;Critical path provavelmente no controlador DDR3 |
| Bug de DMA crossbar (master NPU → RAM 0x80000000) | NPU lê lixo da RAM | Média | Verificar `base_soc.py` linha 173 (`self.bus.add_master`) — confirmar que crossbar LiteX mapeia master Wishbone para região DDR3 |
| Bug de alinhamento no HAL | Inference dá resultado errado | Média | Revisar `npu_hal.c:76` (cast 8 vs 32 bits) e `npu_hal.c:51` (offset 0x5C000) contra `npu_v2_pkg.v` antes da integração final |
| Paper 1 ainda em 30% | Submissão atrasada | Alta | Toda seção de HW/OS/Driver/AI está esqueletada; depende só de métricas reais da FPGA. Caminho crítico: síntese → boot → insmod → benchmark → tabelas |
| Toolchain não compilada por todos | Membros não testam .ko/.HAL localmente | Média | Cada um roda `make sdk` em `software/os_buildroot/`. Documentado no README do OS |
| Notebook do Arthur (i5-5200U, 8 GB RAM) | Síntese Vivado lenta/Swap | Média | Opção B: openXC7 (Yosys + nextpnr + openFPGALoader) — ~600 MB total vs 70 GB Vivado. Mais leve, adequado para 8GB RAM |
