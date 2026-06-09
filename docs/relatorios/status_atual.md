# Status Atual do Projeto — Ternary Edge-RV
**Data:** 10/06/2026
**Autor:** Arthur Oliveira Gomes (Hardware)

---

## Resumo Executivo

O projeto completou **a Fase 3 inteira** — NPU v2 com 64 MACs paralelos, Wishbone Master DMA e Layer Sequencer está implementada e validada. O golden model C++ passa **29/29 testes** (8 v1 + 21 v2). Toda a documentação foi atualizada para refletir a arquitetura v2. O Paper 1 tem template LaTeX pronto. O gargalo atual é a **FPGA física** para síntese e deploy real.

---

## 1. 👨‍💻 Arthur (Hardware — RTL/SoC)

### Fase Real: 3.5/4 (Fase 1 ✅, Fase 2 ✅, Fase 3 ✅, Fase 4 iniciando)

| Tarefa | Status | Arquivo |
|--------|--------|---------|
| Mapa de Memória Oficial v2 | ✅ `docs/arquitetura/mapa_de_memoria.md` | 10 registradores, `0x40000000`, IRQ 10 |
| Requisitos FPGA | ✅ `hardware/litex_soc/requisitos_fpga.md` | Mínimo 32MB RAM, 15k LUTs, SD Card |
| SoC Base VexRiscv | ✅ `hardware/litex_soc/base_soc.py` | RV32IMA Linux, Wishbone, região NPU reservada |
| MAC Multiplierless (ternário×INT8) | ✅ `hardware/npu_rtl/ternary_mac.v` | 0 DSPs — Mux + Somador |
| **NPU v1 (1 MAC, PIO, Wishbone Slave)** | ✅ `npu_ternaria_top.v`, `tb_npu_ternaria_top.v` | Legado funcional |
| **64 MACs paralelos + Adder Tree** | ✅ `ternary_mac_array.v` + `adder_tree_64.v` | 63 adders, 6 estágios pipeline |
| **Wishbone Master DMA (burst reads)** | ✅ `wishbone_master.v` | B4 Standard, burst incrementante |
| **NPU v2 Top-Level integrado** | ✅ `npu_ternaria_top_v2.v` | FSM 10 estados, Layer Sequencer |
| **Layer Sequencer (3 layers)** | ✅ (embutido no top v2) | 784→1024→512→256 automático, ~92K ciclos |
| **Testbench Verilog v2** | ✅ `tb_npu_v2.v` | RAM simulada, testes registrador/IRQ/STATUS |
| **Golden Model C++ v2** | ✅ `npu_sim_v2.cpp` + `demo_npu_v2.cpp` | 21/21 testes passando |
| **Pacote de definições compartilhadas** | ✅ `npu_v2_pkg.v` | Register map, FSM states, constantes |
| **FPGA Física** | ❌ Bloqueado | Aguardando professor |

### Detalhamento dos Testes (Golden Model v2):
- Teste 1: Wishbone Slave Register Access ✅
- Teste 2: STATUS bit layout [15:8]=zero_counter ✅
- Teste 3: 64 MACs — acúmulo correto em acc[0] ✅
- Teste 4: Zero-skipping (sparsity counting) ✅
- Teste 5: IRQ sync (clear_irq via CONTROL) ✅
- Teste 6: Layer Sequencer (3 layers, ~91.967 ciclos) ✅

### Bloqueios:
- Sem FPGA física para sintetizar/testar

---

## 2. 🖥️ Gildo (Sistema Operacional — Buildroot)

### Fase Real: 2.5/4 (Fase 1 ✅, Fase 2 ✅, Fase 3 iniciando)

| Tarefa | Status | Arquivo |
|--------|--------|---------|
| Buildroot External Tree | ✅ `software/os_buildroot/` | Estrutura completa |
| Defconfig RV32IMA | ✅ `configs/ternaryedge_rv_defconfig` | BR2_RISCV_32, kernel 6.18, OpenSBI, QEMU |
| Toolchain via SDK | ✅ `software/os_buildroot/README.md` | Cada um compila a sua |
| HIGH_RES_TIMERS | ✅ Ativado | CONFIG_HIGH_RES_TIMERS habilitado |
| **Device Tree (.dts) oficial com NPU v2** | ❌ Pendente | Aguardando definição do node com IRQ=10 |
| **RootFS com LKM + user_app** | ❌ Pendente | Verificar Config.in, external.mk |
| **FAT32/ext4 no RootFS** | ❌ Pendente (Fase 4) | Para SD Card |

### Pendente para Gildo:
1. Preencher `Config.in` e `external.mk` (estão vazios — 0 bytes)
2. Criar `.dts` oficial com node NPU v2 (`compatible = "ternaryedge,npu-ternaria"`, IRQ=10)
3. Auxiliar Arthur em testbench Verilator quando ambiente estiver disponível

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
| Dummy App corrigido | ✅ | `mmap.h` → `mman.h` |
| User App revisado | ✅ | `user_app.c` com timing segregado + `--cpu` flag |

### Bloqueios:
- Aguardando toolchain do Gildo para compilar `.ko` para RISC-V
- Aguardando FPGA real para teste físico

---

## 4. 🧠 Gilvan (Inteligência Artificial)

### Fase Real: 3.0/4 (Fase 1 ✅, Fase 2 ✅, Fase 3 ✅, Fase 4 iniciando)

| Tarefa | Status | Detalhes |
|--------|--------|----------|
| Ambiente Python + Larq | ✅ | TensorFlow + Larq |
| Modelo QAT (3 layers ternárias) | ✅ | 784→1024→512→256 |
| Sparsity L1 | ✅ | Regularização forcing zeros |
| Fake Quant INT8 entre layers | ✅ | `fake_quant_with_min_max_args(min=0, max=127, num_bits=8)` |
| Acurácia >95% | ✅ | Validado |
| Pack de pesos (16/uint32_t) | ✅ | `pack_weights.py` |
| weights.h gerado | ✅ | 3 layers, 91.136 words (364 KB) |
| **Golden Model v2 (64 MACs + DMA)** | ✅ `npu_sim_v2.cpp` | Modelagem bit-accurate, 64 MACs paralelos, DMA simulado |
| **STATUS register bits [15:8]** | ✅ | Alinhado com RTL v2 |
| **User app real (forward pass + timing)** | ✅ `user_app.c` | IOCTL args, timing segregado, baseline CPU |
| **Camada de saída ternária?** | ⚠️ Gap | Atualmente FP32 softmax — precisa decidir Opção A ou B |

### Gap:
A camada de saída `Dense(10, activation="softmax")` usa FP32. Opções documentadas na `architecture_contract.md`.

### Arquitetura do Modelo:
```
Entrada: 784 pixels (INT8, 0-255 normalizado)
  │
Layer 1: QuantDense(1024) → BatchNorm → ReLU → FakeQuant(INT8)
  │   Pesos: 784×1024 = 802.816 ternários packed em 50.176 words
  │
Layer 2: QuantDense(512)  → BatchNorm → ReLU → FakeQuant(INT8)
  │   Pesos: 1024×512 = 524.288 ternários packed em 32.768 words
  │
Layer 3: QuantDense(256)  → BatchNorm → ReLU → FakeQuant(INT8)
  │   Pesos: 512×256 = 131.072 ternários packed em 8.192 words
  │
Output: Dense(10) → Softmax  ← ⚠️ FP32 (NÃO ternário!)
```

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
| Gildo Fase 3 | 3 tarefas | **0** (não iniciou) | ❌ Atrasado |
| Gustavo Fase 1 | 3 tarefas | 3 tarefas | ✅ Completo |
| Gustavo Fase 2 | 5 tarefas | 5+ (IOCTL, header) | ✅ Superou |
| Gustavo Fase 3 | 5 tarefas | **5** (todas feitas) | 🚀 Completo |
| Gilvan Fase 1 | 3 tarefas | 3+ (sparsity, fq) | ✅ Superou |
| Gilvan Fase 2 | 3 tarefas | 3 tarefas | ✅ Completo |
| Gilvan Fase 3 | 5 tarefas | **4** (output layer pendente) | ✅ Quase completo |

---

## 7. 🚨 Riscos Atuais

| Risco | Impacto | Probabilidade | Mitigação |
|-------|---------|---------------|-----------|
| Saída FP32 não ternária | Hardware não acelera última camada | Alta | Gilvan testar saída ternária OU CPU fallback |
| Sem FPGA física | Projeto só roda em QEMU | Média | Artigo pode focar em prototipagem virtual |
| Config.in / external.mk vazios (Gildo) | Buildroot external tree incompleta | Média | Preencher com conteúdo mínimo |
| Device Tree não criado | Driver não encontra NPU no boot | Média | Gildo precisa criar .dts oficial |
| Desbalanceamento de carga | Gildo ocioso, Arthur sobrecarregado | Média | Redistribuir tarefas: Gildo pegar testbench Verilator e DT |
