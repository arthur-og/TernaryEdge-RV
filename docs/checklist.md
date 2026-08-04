# 📌 CHECKLIST OFICIAL DO PROJETO — TERNARY EDGE-RV
**Última atualização:** 04/08/2026 — FPGA Urrbana recebida, Fase 3 100% completa, Fase 4 em andamento
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
- [ ] Sintetizar SoC na FPGA Urrbana (placa recebida ago/2026, síntese pendente)

### Gildo (OS + HAL)
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
- [X] **NPU v2: 64 MACs + Wishbone Master + Layer Sequencer**

### Gildo (OS + HAL)
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

## Gildo (OS + NPU HAL + Classifier + Buildroot Packages)

### Device Tree e kernel config (concluído ✅)
- [X] **Device Tree (.dts):** node da NPU v2 com IRQ=10 (`setup_qemu/ternaryedge.dts`)
- [X] **Device Tree para FPGA real:** `hardware/litex_soc/urrbana.dts`
- [X] **kernel config fragment:** `configs/kernel-npu.cfg` (FAT/EXT4, HIGH_RES_TIMERS)
- [X] **Config.in, external.mk, external.desc:** estrutura da external tree preenchida

### NPU HAL (CONCLUÍDO ✅)
- [X] `software/npu_hal/npu_hal.h` — API pública (init, load_weights, predict, deinit, print_result)
- [X] `software/npu_hal/npu_hal.c` — Implementação (open, mmap, ioctl, output layer CPU)
- [X] `software/npu_hal/npu_hal_internal.h` — Estruturas internas do contexto

### NPU Classifier (CONCLUÍDO ✅)
- [X] `software/npu_hal/npu_classifier.h` — API classifier_run, argmax, softmax
- [X] `software/npu_hal/npu_classifier.c` — Output layer 256→10 FP32

### NPU Weights (CONCLUÍDO ✅)
- [X] `software/npu_hal/npu_weights.h` — API para carregar pesos no DMA
- [X] `software/npu_hal/npu_weights.c` — Loader de pesos do QAT pipeline
- [X] `software/npu_hal/weights.h` — Stub (pesos zerados) para compilação

### Buildroot Packages (CONCLUÍDO ✅)
- [X] `package/npu-ternaria/` — Kernel module package
- [X] `package/npu-hal/` — Biblioteca estática libnpu_hal.a
- [X] `package/user-app/` — Binário user_app
- [X] Atualizar `Config.in`, `external.mk`, `defconfig`

### User App (CONCLUÍDO ✅)
- [X] Refatorar `user_app.c` para usar HAL (init → load_weights → predict → print_result)
- [X] Manter flag `--cpu` para baseline CPU
- [X] Adicionar `--file` para imagens reais, `--batch` para benchmark

## Gustavo (Driver) — ✅ COMPLETO
- [X] **Adaptar driver para mapa v2:** offsets atualizados no `npu_driver.c` v3.0
- [X] Adicionar `iowrite32()` para `WEIGHT_CFG` e `ACT_CFG` no ioctl
- [X] Pipeline `START_INFERENCE` completo: SRC + DST + SIZE + WEIGHT + ACT + MAC + LAYER → CONTROL
- [X] **IOCTL Header:** `software/include/npu_ioctl.h` com struct npu_ioctl_args

## Gilvan (IA + Golden Model) — ✅ COMPLETO (Fase 3)
- [X] **Corrigir `npu_sim_v2.cpp`:** STATUS `zero_counter` → bits `[15:8]`
- [X] **Expandir `npu_sim_v2.cpp`:** modelar 64 MACs + DMA simulation (21/21 testes)
- [X] **Validar output layer:** Opção A (ternária na última camada) testada
- [X] **Manter Opção B** (CPU fallback na output layer) como padrão aceito
- [X] Adicionar `weights.h` ao `.gitignore` (regenerar no build)

> **Nota:** O `user_app.c` foi transferido para Gildo, que o refatorará para usar a HAL.
> Gilvan mantém: pipeline QAT, pesos, golden model, benchmark data.

---

# 🔴 FASE 4: DEPLOY FÍSICO E PAPER 1 (Semanas 14–16)
**Objetivo:** Rodar no silício real, extrair métricas, escrever paper.
**Status:** FPGA RealDigital Urrbana (Spartan-7 XC7S50-CSGA324) recebida em agosto/2026. Caminho crítico desbloqueado.

### Arthur
- [ ] Sintetizar SoC final + NPU v2 na FPGA Urrbana via `base_soc.py --build` (timing closure)
- [ ] Opção A: Vivado WebPACK (Spartan-7 suportado) ou Opção B: openXC7 (yosys+nextpnr, mais leve)
- [ ] Extrair relatório: 0 DSPs, LUTs, FFs, BRAM (comprovação central da tese do Paper 1)
- [ ] Validar testbench pós-síntese (gate-level sim) antes do flash
- [ ] **Escrever seção do Paper 1:** Arquitetura Multiplierless + 64 MACs + DMA
- [ ] **Escrever §III-B** do paper: tabela de registradores MMIO (já está 90% pronta no template)

### Gildo
- [ ] Suporte a FAT32/ext4 no RootFS (já configurado em `configs/kernel-npu.cfg`)
- [ ] Gerar imagem final Buildroot (kernel 6.18.7 + OpenSBI 1.6 + RootFS com `npu-ternaria`, `npu-hal`, `user-app`)
- [ ] Particionar SD card (FAT32 boot + ext4 rootfs) e gravar imagem
- [ ] Bootar Linux na Urrbana via SD e validar `dmesg` (sem kernel panic, periféricos OK)
- [ ] **Escrever seção do Paper 1:** OS Infrastructure + NPU HAL:
  - Buildroot, Device Tree, integração Linux+NPU
  - Arquitetura da HAL (init, load, predict, batch)
  - Classifier (output layer CPU, softmax, argmax)
  - Comparação CPU vs NPU via flag `--cpu`

### Gustavo
- [ ] Cross-compilar driver (`.ko`) para RV32IMA usando toolchain Buildroot
- [ ] `insmod` do driver na FPGA Urrbana física
- [ ] Verificar `dmesg` — sem kernel panic, IRQ registrado, `/dev/npu_ternaria` criado
- [ ] Validar IOCTL, IRQ e DMA no hardware real (transação completa com a NPU)
- [ ] **Escrever seção do Paper 1:** Kernel Driver Design (MMIO, DMA, sincronização IRQ, overhead)

### Gilvan
- [ ] Preparar imagens MNIST de teste (raw 784 bytes cada) para SD card
- [ ] Executar inferência na FPGA com `user_app --file`
- [ ] Salvar .csv com tempos (CPU vs NPU) — usa timing segregado da HAL
- [ ] Gerar gráficos de benchmark (bar chart ou box plot)
- [ ] **Escrever seção do Paper 1:** AI Pipeline (QAT, empacotamento, golden model, resultados)
- [ ] **Escrever seção do Paper 1:** Resultados e Discussão (tabela comparativa CPU × NPU)

### Equipe
- [ ] Abstract, Introdução, Trabalhos Relacionados, Conclusão (esqueletos já existem no template)
- [ ] Revisão final e submissão SBCCI/LASCAS
- [ ] Preencher dados institucionais no `paper1_template.tex` (departamento, universidade, contatos)
