# 📌 CHECKLIST OFICIAL DO PROJETO — TERNARY EDGE-RV
**Última atualização:** 10/06/2026 — Fase 3 completa (NPU v2 implementada, 29/29 testes)
**Próximo marco:** Paper 1 (SBCCI/LASCAS)

---

## Regras de Ouro
- **⚠️ [BLOQUEIO]:** Se você precisa de algo de outro membro para continuar.
- **🛠️ [MOCK]:** Se alguém te bloqueou, invente um dado falso, avise no grupo e **continue programando**. Não espere!
- **📄 Paper 1:** Todo mundo escreve sua seção. O template está em `paper/paper1_template.tex`.

---

# 🟢 FASE 1: FUNDAMENTAÇÃO E EMULAÇÃO (Semanas 1–3)
**Objetivo:** Cada um trabalhando sozinho, validando ferramentas. **Tudo OK.**

### Arthur (Hardware)
- [X] Instalar dependências do LiteX/Python
- [X] SoC VexRiscv RV32IMA gerado
- [X] Mapa de memória esboçado (0x40000000, IRQ=10)
- [X] Endianness definido (Little-Endian)
- [X] `docs/arquitetura/mapa_de_memoria.md` criado
- [ ] Sintetizar SoC na FPGA (aguardando placa)

### Gildo (OS)
- [X] Buildroot configurado (`software/os_buildroot/`)
- [X] `ternaryedge_rv_defconfig` criado (RV32IMA)
- [X] Boot funcional no QEMU (OpenSBI + U-Boot + Kernel + RootFS)
- [X] Toolchain disponível via `make sdk` (cada um compila a sua)

### Gustavo (Driver)
- [X] Ambiente LKM configurado
- [X] Driver "Hello World" testado no QEMU (insmod/lsmod/rmmod)
- [X] Platform Driver com DT match, DMA Coherent, IRQ, mmap, wait_queue

### Gilvan (IA)
- [X] Ambiente Python + Larq configurado
- [X] TNN treinada (>95% accuracy, pesos ternários)
- [X] Sparsity L1 implementada
- [X] Fake quantization INT8 entre camadas

---

# 🟡 FASE 2: CONFIGURAÇÃO E EXPORTAÇÃO (Semanas 4–7)
**Objetivo:** Pontes de comunicação criadas. **Quase tudo OK.**

### Arthur (Hardware)
- [X] `ternary_mac.v` — MAC multiplierless (apenas somadores/subtratores)
- [X] `npu_ternaria_top.v` — Wishbone Slave + FSM + IRQ
- [X] Pino `irq_out` implementado
- [ ] **NPU v2 iniciada: 64 MACs + Wishbone Master + Layer Sequencer** ← **AGORA**

### Gildo (OS)
- [X] Toolchain 32 bits configurada
- [X] HIGH_RES_TIMERS ativado no kernel

### Gustavo (Driver)
- [X] `/dev/npu_ternaria` via `register_chrdev`
- [X] `struct file_operations` completa (.mmap, .unlocked_ioctl, .open, .release)
- [X] `dma_alloc_coherent()` + `dma_mmap_coherent()`
- [X] `ioremap()` via `devm_ioremap_resource()`
- [X] `devm_request_irq()` + `wait_event_interruptible()`

### Gilvan (IA)
- [X] `pack_weights.py` — empacota 16 pesos/word Little-Endian
- [X] `generate_weights_h.py` → `weights.h` (3 layers, 91.136 words)
- [X] Encoding: +1=0b01, 0=0b00, -1=0b11

---

# 🟠 FASE 3: LÓGICA E INTEGRAÇÃO — NPU v2 (Semanas 8–13)
**Objetivo:** Os 4 mundos conversarem via DMA. ⏳ **Fase atual.**

## Arthur (Hardware) — NPU v2
- [X] Implementar **64 MACs** em paralelo + adder tree (`ternary_mac_array.v`, `adder_tree_64.v`)
- [X] Implementar **Wishbone Master (DMA)** — ler RAM em burst (`wishbone_master.v`)
- [X] BRAM interna de **12K words** (384 Kb) para pesos (`npu_v2_pkg.v: WEIGHT_BRAM_DEPTH=12288`)
- [X] **Layer Sequencer** — FSM de 10 estados que itera 3 layers automaticamente
- [X] Testbench **Verilator** com RAM simulada para DMA (`tb_npu_v2.v`)
- [X] Corrigir STATUS register: `zero_counter` em `[15:8]` (alinhar com C++)
- [X] Atualizar `npu_ternaria_top_v2.v` — top-level integrado (547 linhas)

## Gildo (OS + Testbench)
- [ ] **Device Tree (.dts):** node da NPU v2 com IRQ=10 e `reg = <0x40000000 0x1000>`
- [ ] **Preencher Config.in e external.mk** (atualmente vazios — 0 bytes)
- [ ] **Auxiliar Arthur** no testbench Verilator
- [ ] Verificar RootFS: LKM habilitado, `user_app` incluído

## Gustavo (Driver)
- [X] **Adaptar driver para mapa v2:** offsets atualizados no `npu_driver.c` v3.0
- [X] Adicionar `iowrite32()` para `WEIGHT_CFG` e `ACT_CFG` no ioctl
- [X] Pipeline `START_INFERENCE` completo: SRC + DST + SIZE + WEIGHT + ACT + MAC + LAYER → CONTROL
- [X] **Revisar user_app.c** em parceria com Gilvan
- [X] **Corrigir `#include <sys/mmap.h>` → `<sys/mman.h>`** no `dummy_app.c`

## Gilvan (IA + User Space)
- [X] **Corrigir `npu_sim_v2.cpp`:** STATUS `zero_counter` → bits `[15:8]`
- [X] **Expandir `npu_sim_v2.cpp`:** modelar 64 MACs + DMA simulation (21/21 testes)
- [X] **Implementar `user_app.c` real:**
  - [X] Abrir `/dev/npu_ternaria`, `mmap` buffer DMA
  - [X] Copiar pesos/ativações para buffer
  - [X] `ioctl(START_INFERENCE)` com timing segregado (DMA setup, inference, readback)
  - [X] Ler resultado e printar benchmark
  - [X] Baseline CPU com flag `--cpu` (forward_ternary_layer)
- [ ] **Testar camada de saída ternária** (Opção A). Se falhar >90%, adotar CPU fallback (Opção B)
- [X] Adicionar `weights.h` ao `.gitignore` (regenerar no build)

---

# 🔴 FASE 4: DEPLOY FÍSICO E PAPER 1 (Semanas 14–16)
**Objetivo:** Rodar no silício real, extrair métricas, escrever paper.

### Arthur
- [ ] Sintetizar SoC final + NPU v2 na FPGA (timing closure)
- [ ] Extrair relatório: 0 DSPs, LUTs, FFs, BRAM
- [ ] **Escrever seção do Paper 1:** Arquitetura Multiplierless + 64 MACs + DMA

### Gildo
- [ ] Suporte a FAT32/ext4 no RootFS
- [ ] Gravar imagem final no SD card e bootar na FPGA
- [ ] **Escrever seção do Paper 1:** OS Infrastructure (boot, Device Tree, integração Linux+NPU)

### Gustavo
- [ ] `insmod` do driver na FPGA física
- [ ] Verificar `dmesg` — sem kernel panic
- [ ] **Escrever seção do Paper 1:** Kernel Driver Design (MMIO, DMA, sincronização IRQ, overhead)

### Gilvan
- [ ] Executar inferência de imagens de teste na FPGA
- [ ] Salvar .csv com tempos (CPU vs NPU)
- [ ] Gerar gráficos de benchmark
- [ ] **Escrever seção do Paper 1:** AI Pipeline (QAT, empacotamento, golden model, resultados)
- [ ] **Escrever seção do Paper 1:** Resultados e Discussão (tabela comparativa CPU × NPU)

### Equipe
- [ ] Abstract, Introdução, Trabalhos Relacionados, Conclusão
- [ ] Revisão final e submissão
