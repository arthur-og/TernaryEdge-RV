# Status Atual do Projeto — Ternary Edge-RV
**Data:** 09/06/2026
**Autor:** Arthur Oliveira Gomes (Hardware)

---

## Resumo Executivo

O projeto está em boa posição geral, com avanço significativo nas camadas de Software e IA. O gargalo principal está no Hardware (FPGA física) e na integração final entre os módulos. A toolchain RISC-V já foi exportada por Gildo via Google Drive (09/06/2026), desbloqueando Gustavo e Gilvan. Abaixo, o detalhamento por domínio.

---

## 1. 👨‍💻 Arthur (Hardware — RTL/SoC)

### Fase Real: 2.5/4 (Fase 1 ✅, Fase 2 ✅, Fase 3 iniciando)

| Tarefa | Status | Arquivo |
|--------|--------|---------|
| Mapa de Memória Oficial | ✅ `docs/arquitetura/mapa_de_memoria.md` | `0x40000000`, IRQ 10, Little-Endian |
| Requisitos FPGA | ✅ `hardware/litex_soc/requisitos_fpga.md` | Mínimo 32MB RAM, 15k LUTs, SD Card |
| SoC Base VexRiscv | ✅ `hardware/litex_soc/base_soc.py` | RV32IMA Linux, Wishbone, região 0x40000000 reservada |
| MAC Multiplierless (ternário×INT8) | ✅ `hardware/npu_rtl/ternary_mac.v` | 0 DSPs — apenas Mux + Somador |
| NPU Wishbone Slave c/ IRQ | ✅ `hardware/npu_rtl/npu_ternaria_top.v` | FSM + registradores + irq_out |
| **Controlador DMA (Wishbone Master)** | ❌ Pendente | NPU precisa ler RAM sozinha |
| **Layer Sequencer** | ❌ Pendente | Iterar Layer1→2→3→Output |
| **Testbench Verilator** | ❌ Pendente | Validar hardware antes da síntese |
| **FPGA Física** | ❌ Bloqueado | Aguardando professor |

### Bloqueios:
- Sem FPGA física para sintetizar/testar

---

## 2. 🖥️ Gildo (Sistema Operacional — Buildroot)

### Fase Real: 2.5/4 (Fase 1 ✅, Fase 2 ✅, Fase 3 iniciando)

| Tarefa | Status | Arquivo |
|--------|--------|---------|
| Buildroot External Tree | ✅ `software/os_buildroot/` | Estrutura completa |
| Defconfig RV32IMA | ✅ `configs/ternaryedge_rv_defconfig` | BR2_RISCV_32, kernel 6.18, OpenSBI, QEMU |
| **Exportar Toolchain riscv32** | ✅ Google Drive | Link em `software/os_buildroot/README.md` |
| **HIGH_RES_TIMERS** | ✅ Ativado | CONFIG_HIGH_RES_TIMERS habilitado |
| **Device Tree (.dts) oficial** | ❌ Pendente (Fase 3) | Aguardando mapa de memória oficial do Arthur |
| **FAT32/ext4 no RootFS** | ❌ Pendente (Fase 4) | Para deploy no SD Card |

### Observação:
Gildo concluiu a toolchain (Fase 2) e HIGH_RES_TIMERS. Próximo passo: .dts oficial na Fase 3.

---

## 3. ⚙️ Gustavo (Driver de Kernel)

### Fase Real: 3/4 (Fase 1 ✅, Fase 2 ✅, Fase 3 ✅ em simulação)

**Este é o membro mais adiantado do projeto.**

| Tarefa | Status | Detalhes |
|--------|--------|----------|
| LKM Hello World | ✅ | Fase 1 |
| Character Device | ✅ | `/dev/npu_ternaria` via `register_chrdev` |
| File Operations | ✅ | `.mmap`, `.unlocked_ioctl`, `.open`, `.release` |
| Platform Driver | ✅ | Device Tree match `compatible = "ternary,npu-dma"` |
| MMIO (ioremap) | ✅ | `devm_ioremap_resource()` no probe |
| DMA Coherent Memory | ✅ | `dma_alloc_coherent()` — 4MB buffer |
| Zero-Copy (mmap) | ✅ | `dma_mmap_coherent()` — usuário escreve direto |
| IRQ Handler | ✅ | `devm_request_irq()` + `wait_event_interruptible()` |
| IOCTL (start inference) | ✅ | `NPU_IOCTL_START_INFERENCE` |
| QEMU DT Injection | ✅ | NPU virtual em QEMU testada |
| IOCTL Header | ✅ | `software/include/npu_ioctl.h` |
| Dummy App (esqueleto) | ✅ | `software/user_app/dummy_app.c` |

### Bloqueios:
- Aguardando toolchain do Gildo para compilar `.ko` para RISC-V (atualmente testa em QEMU x86)
- Aguardando FPGA real para teste físico

---

## 4. 🧠 Gilvan (Inteligência Artificial)

### Fase Real: 2.5/4 (Fase 1 ✅, Fase 2 ✅, Fase 3 iniciando)

| Tarefa | Status | Detalhes |
|--------|--------|----------|
| Ambiente Python + Larq | ✅ | TensorFlow + Larq |
| Modelo QAT (3 layers ternárias) | ✅ | 784→1024→512→256 |
| Sparsity L1 (fator 1.0) | ✅ | Força zeros nos pesos |
| Fake Quant INT8 entre layers | ✅ | `fake_quant_with_min_max_args(min=0, max=127, num_bits=8)` |
| Acurácia >95% | ✅ | Validado |
| Pack de pesos (16/uint32_t) | ✅ | `pack_weights.py` |
| weights.h gerado | ✅ | 3 layers, 91.136 words (364 KB) |
| **Camada de saída ternária?** | ⚠️ Gap | Atualmente FP32 softmax — `ternary_mac.v` não suporta |
| **User app real (forward pass C)** | ❌ Pendente | Apenas esqueleto `dummy_app.c` existe |
| **Medição de tempo segregada** | ❌ Pendente | t_copy, t_inference, t_copy_back |

### Gap Crítico:
A camada de saída `Dense(10, activation="softmax")` usa pesos FP32. Isso significa que:
- O `ternary_mac.v` (que só faz ternário×INT8) **não consegue** computar a última camada
- Solução A: Gilvan testa tornar a saída ternária (`QuantDense` + softmax)
- Solução B: Arthur implementa MAC híbrido (suporta INT8×FP32 para última camada)

### Arquitetura do Modelo (do código):

```
Entrada: 784 pixels (INT8, 0-255 normalizado para 0.0-1.0)
  │
Layer 1: QuantDense(1024) → BatchNorm → ReLU → FakeQuant(INT8)
  │   Pesos: 784×1024 = 802.816 ternários {−1,0,+1}
  │   Packed: 50.176 words × uint32_t
  │
Layer 2: QuantDense(512)  → BatchNorm → ReLU → FakeQuant(INT8)
  │   Pesos: 1024×512 = 524.288 ternários
  │   Packed: 32.768 words × uint32_t
  │
Layer 3: QuantDense(256)  → BatchNorm → ReLU → FakeQuant(INT8)
  │   Pesos: 512×256 = 131.072 ternários
  │   Packed: 8.192 words × uint32_t
  │
Output: Dense(10) → Softmax  ← ⚠️ FP32 (NÃO ternário!)
    Pesos: 256×10 = 2.560 floats (10 KB)
```

---

## 5. Comparativo: Checklist Original vs Realidade

| Item | Checklist Original | Realidade | Diferença |
|------|-------------------|-----------|-----------|
| Arthur Fase 1 | 3 tarefas | 5 tarefas (criou docs extras) | ✅ Superou |
| Arthur Fase 2 | 2 tarefas | 2+ (criou RTL) | ✅ Completo |
| Gildo Fase 1 | 3 tarefas | 3 tarefas | ✅ Completo |
| Gildo Fase 2 | 3 tarefas | 3 tarefas (toolchain + HIGH_RES_TIMERS) | ✅ Completo |
| Gustavo Fase 1 | 3 tarefas | 3 tarefas | ✅ Completo |
| Gustavo Fase 2 | 2 tarefas | 4+ (muito além) | 🚀 Avançou para Fase 3 |
| Gilvan Fase 1 | 3 tarefas | 3+ (adicionou sparsity, fq) | ✅ Superou |
| Gilvan Fase 2 | 3 tarefas | 3 tarefas | ✅ Completo |

---

## 6. 🚨 Riscos Atuais

| Risco | Impacto | Probabilidade | Mitigação |
|-------|---------|---------------|-----------|
| Saída FP32 não ternária | Hardware não acelera última camada | Alta | Gilvan testar saída ternária OU Arthur fazer MAC híbrido |
| Sem FPGA física | Projeto só roda em QEMU | Média | Artigo pode focar em prototipagem virtual |
| Desbalanceamento de carga | Gildo ocioso, Arthur sobrecarregado | Média | Gildo já tem próximas tarefas (.dts → FAT32) |
