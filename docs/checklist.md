# 📌 CHECKLIST OFICIAL DO PROJETO: TERNARY EDGE-RV
**Última atualização operacional:** 20/08/2026. O registro histórico de 17/08/2026 informa placa Urbana conectada via micro-USB (FTDI FT2232H detectado, JTAG IDCODE 0x362f093, `/dev/ttyUSB0` e `/dev/ttyUSB1` criados), simulação RTL 4/4 e flags openXC7 `-nolutram -nowidelut`. O registro 4/4 não representa uma execução disponível no shell atual.
**Prazo final de submissão (SBCCI/LASCAS):** 31/08/2026

---

## Regras de Ouro
- **⚠️ [BLOQUEIO]:** Se você precisa de algo de outro membro para continuar.
- **🛠️ [BLOQUEIO]:** Se uma ferramenta ou validação estiver indisponível, registre o bloqueio e continue apenas com tarefas que não dependam dela. Nunca fabrique resultados.
- **📄 Paper 1:** Todos os 4 autores mantidos (Arthur Oliveira Gomes, Gildo Alves de Lima Junior, Gustavo Alexandre dos Santos, Gilvan Alves Pastor Junior). O template está em `paper/paper1_template.tex`.

As listas das Fases 1 a 3 abaixo são registros históricos do desenvolvimento.
A evidência corrente é: C++ v1 8/8, C++ v2 21/21, Python 5/5 e ABI IOCTL
aprovada. O testbench Verilog está indisponível no shell atual. Não há
inferência FPGA end-to-end nem benchmark CPU versus NPU comprovado.

---

# 🟢 FASE 1: FUNDAMENTAÇÃO E EMULAÇÃO (Semanas 1-3)
**Objetivo:** Cada um trabalhando sozinho, validando ferramentas. **Tudo OK.**

### Arthur (Hardware)
- [X] Instalar dependências do LiteX/Python
- [X] SoC VexRiscv RV32IMA gerado
- [X] Mapa de memória esboçado (0x40000000, IRQ=10)
- [X] Endianness definido (Little-Endian)
- [X] `docs/arquitetura/mapa_de_memoria.md` criado
- [X] Conectar FPGA Urbana e detectar FTDI FT2232H (JTAG IDCODE 0x362f093, `/dev/ttyUSB0` e `/dev/ttyUSB1`)

### Gildo (OS + HAL)
- [X] Buildroot configurado (`software/os_buildroot/`)
- [X] `ternaryedge_rv_defconfig` criado (RV32IMA)
- [X] Boot funcional no QEMU (OpenSBI + U-Boot + Kernel + RootFS)
- [X] Toolchain disponível via `make sdk` (cada um compila a sua)

### Gustavo (Driver)
- [X] Ambiente LKM configurado
- [X] Driver "Hello World" testado no QEMU (insmod/lsmod/rmmod)
- [X] Platform Driver com DT match, DMA Coherent, IRQ, mmap, wait_queue

### Gilvan (IA Histórica, registro histórico)
- [X] Ambiente Python + Larq configurado
- [X] TNN treinada (>95% accuracy, pesos ternários)
- [X] Sparsity L1 implementada
- [X] Fake quantization INT8 entre camadas

---

# 🟡 FASE 2: CONFIGURAÇÃO E EXPORTAÇÃO (Semanas 4-7)
**Objetivo:** Pontes de comunicação criadas. **Quase tudo OK.**

### Arthur (Hardware)
- [X] `ternary_mac.v`: MAC multiplierless (apenas somadores/subtratores)
- [X] `npu_ternaria_top.v`: Wishbone Slave + FSM + IRQ
- [X] Pino `irq_out` implementado
- [X] **NPU v2: alvo de 64 MACs + Wishbone Master + Layer Sequencer**; síntese e desempenho pendentes

### Gildo (OS + HAL)
- [X] Toolchain 32 bits configurada
- [X] HIGH_RES_TIMERS ativado no kernel

### Gustavo (Driver)
- [X] `/dev/npu_ternaria` via `register_chrdev`
- [X] `struct file_operations` completa (.mmap, .unlocked_ioctl, .open, .release)
- [X] `dma_alloc_coherent()` + `dma_mmap_coherent()`
- [X] `ioremap()` via `devm_ioremap_resource()`
- [X] `devm_request_irq()` + `wait_event_interruptible()`

### Gilvan (IA Histórica, registro histórico)
- [X] `pack_weights.py`: empacota 16 pesos/word Little-Endian
- [X] `generate_weights_h.py` -> registro histórico de `weights.h` (3 layers, 91.136 words)
- [X] Encoding: +1=0b01, 0=0b00, -1=0b11

---

# 🟠 FASE 3: LÓGICA E INTEGRAÇÃO: NPU v2 (Semanas 8-13)
**Objetivo:** Os mundos conversarem via DMA.

## Arthur (Hardware RTL, LiteX SoC, Verilog Regression, Synthesis & Bitstream)
- [X] Definir o alvo de **64 MACs** em paralelo + adder tree (`ternary_mac_array.v`, `adder_tree_64.v`); integração e síntese continuam pendentes
- [X] Implementar **Wishbone Master (DMA)**: ler RAM em burst (`wishbone_master.v`)
- [X] BRAM interna de **12K words** (384 Kb) para pesos (`npu_v2_pkg.v: WEIGHT_BRAM_DEPTH=12288`)
- [X] **Layer Sequencer**: FSM de 10 estados que itera 3 layers automaticamente
- [ ] Executar o testbench Verilator/Verilog (`tb_npu_v2.v`): indisponível no shell atual; o registro histórico de 4/4 permanece datado e não é evidência corrente
- [X] Corrigir STATUS register: `zero_counter` em `[15:8]` (alinhar com C++)
- [X] Atualizar `npu_ternaria_top_v2.v`: top-level documentado; a integração física ainda depende de validação
- [X] Atualizar flags openXC7 para `-nolutram -nowidelut` na plataforma para eliminar RAM256X1S e MUXF7/MUXF8

## Gildo (OS Infrastructure, Buildroot, Device Tree, NPU HAL, Classifier, MicroSD, Physical Boot)

### Device Tree e kernel config (concluído ✅)
- [X] **Device Tree (.dts):** node da NPU v2 com IRQ=10 (`setup_qemu/ternaryedge.dts`)
- [X] **Device Tree para FPGA real:** `hardware/litex_soc/urrbana.dts`
- [X] **kernel config fragment:** `configs/kernel-npu.cfg` (FAT/EXT4, HIGH_RES_TIMERS)
- [X] **Config.in, external.mk, external.desc:** estrutura da external tree preenchida

### NPU HAL (CONCLUÍDO ✅)
- [X] `software/npu_hal/npu_hal.h`: API pública (init, load_weights, predict, deinit, print_result)
- [X] `software/npu_hal/npu_hal.c`: Implementação (open, mmap, ioctl, output layer CPU)
- [X] `software/npu_hal/npu_hal_internal.h`: Estruturas internas do contexto

### NPU Classifier (CONCLUÍDO ✅)
- [X] `software/npu_hal/npu_classifier.h`: API classifier_run, argmax, softmax
- [X] `software/npu_hal/npu_classifier.c`: Output layer 256->10 FP32 CPU

### NPU Weights (CONCLUÍDO ✅)
- [X] `software/npu_hal/npu_weights.h`: API para carregar pesos no DMA
- [X] `software/npu_hal/npu_weights.c`: Loader de pesos do QAT pipeline
- [X] `software/npu_hal/weights.h`: símbolos FP32 presentes; valores de fallback `0.01`/`0.1`, não validados como parâmetros treinados

### Buildroot Packages (CONCLUÍDO ✅)
- [X] `package/npu-ternaria/`: Kernel module package
- [X] `package/npu-hal/`: Biblioteca estática libnpu_hal.a
- [X] `package/user-app/`: Binário user_app
- [X] Atualizar `Config.in`, `external.mk`, `defconfig`

### User App (CONCLUÍDO ✅)
- [X] Refatorar `user_app.c` para usar HAL (init -> load_weights -> predict -> print_result)
- [X] Manter flag `--cpu` para baseline CPU
- [X] Adicionar `--file` para imagens reais, `--batch` para benchmark

## Gustavo (AI Pipeline, weights.h, Golden Model, Driver, Cross-Compilation, Validation & Benchmarks)
- [X] **Adaptar driver para mapa v2:** offsets atualizados no `npu_driver.c` v3.0
- [X] Adicionar `iowrite32()` para `WEIGHT_CFG` e `ACT_CFG` no ioctl
- [X] Pipeline `START_INFERENCE` completo: SRC + DST + SIZE + WEIGHT + ACT + MAC + LAYER -> CONTROL
- [X] **IOCTL Header:** `software/include/npu_ioctl.h` com struct npu_ioctl_args
- [X] Manutenção corrente do pipeline de IA, contrato `weights.h` e exportação de pesos
- [X] Manutenção e regressão dos Golden Models: C++ v1 8/8 e C++ v2 21/21 checks
- [X] Diagnóstico Python do pipeline: 5/5 checks; diagnóstico da ABI IOCTL aprovado

## Gilvan (IA Histórica + Golden Model, registro histórico)
- [X] **Corrigir `npu_sim_v2.cpp`:** STATUS `zero_counter` -> bits `[15:8]`
- [X] **Expandir `npu_sim_v2.cpp`:** modelar 64 MACs + DMA simulation (21/21 testes)
- [X] **Validar output layer:** Opção A (ternária na última camada) testada
- [X] **Manter Opção B** (CPU fallback na output layer) como padrão aceito
- [X] Retido e creditado como autor histórico

---

# 🔴 FASE 4: DEPLOY FÍSICO E PAPER 1 (Prazo histórico: 31/08/2026)
**Objetivo:** Rodar no silício real, extrair métricas, submeter paper para SBCCI/LASCAS.
**Registro histórico em 17/08/2026:** FPGA RealDigital Urbana conectada via micro-USB, FTDI FT2232H detectado (JTAG IDCODE 0x362f093, `/dev/ttyUSB0` e `/dev/ttyUSB1` ativos). O registro RTL Verilog 4/4 e as flags openXC7 `-nolutram -nowidelut` ficam preservados como histórico. No shell atual, o testbench Verilog está indisponível.

### Arthur (Hardware RTL, LiteX SoC, Verilog Regression, Synthesis & Bitstream)
- [X] Detectar placa Urbana via micro-USB (FTDI FT2232H, JTAG IDCODE 0x362f093)
- [ ] Executar regressão Verilog `make verilog_v2` quando o simulador estiver disponível; registro histórico 4/4 mantido, sem nova evidência corrente
- [X] Atualizar flags openXC7 com `-nolutram -nowidelut`
- [ ] Sintetizar SoC final e NPU v2 para a FPGA Urbana via `base_soc.py --build`
- [ ] Gerar bitstream e carregar na FPGA Urbana
- [ ] Extrair relatório de recursos, incluindo a verificação do objetivo de 0 DSPs, LUTs, FFs e BRAM
- [ ] **Escrever seção do Paper 1:** Arquitetura Multiplierless, alvo de 64 MACs e DMA, sem apresentar intenção como resultado

### Gildo (OS Infrastructure, Buildroot, Device Tree, NPU HAL, MicroSD & Physical Boot)
- [ ] Gerar imagem final Buildroot (kernel 6.18.7 + OpenSBI 1.6 + RootFS com `npu-ternaria`, `npu-hal`, `user-app`)
- [ ] Particionar cartão MicroSD (FAT32 boot + ext4 rootfs) e gravar imagem
- [ ] Bootar Linux físico na Urbana via SD e validar `dmesg`
- [ ] **Escrever seção do Paper 1:** OS Infrastructure e NPU HAL (`libnpu_hal.a`)

### Gustavo (AI Pipeline, Weights, Golden Model, Driver, Cross-Compilation, Physical Validation & Results)
- [ ] Manter o pipeline de IA e validar a exportação de `weights.h`; os símbolos FP32 atuais usam valores de fallback `0.01`/`0.1`, não parâmetros treinados validados
- [ ] Manter regressão dos Golden Models C++ v1 (8/8) e v2 (21/21), além do diagnóstico Python (5/5)
- [ ] Cross-compilar driver (`npu_driver.ko`) para RV32IMA
- [ ] `insmod` do driver na FPGA Urbana física e verificar `/dev/npu_ternaria`
- [ ] Coordenar a validação física com Arthur e Gildo; não há inferência FPGA end-to-end comprovada
- [ ] Executar benchmark físico (CPU vs NPU) com dataset MNIST
- [ ] **Escrever seção do Paper 1:** Kernel Driver e Resultados & Discussão (tabela comparativa CPU x NPU)

### Gilvan (Contribuição Histórica de IA, sem tarefas operacionais atuais)
- [X] Pipeline QAT, empacotamento de pesos e Golden Model v2 integrados e documentados
- [X] Autoria preservada no Paper 1

### Equipe
- [ ] Revisão final do artigo `paper/paper1_template.tex` com dados medidos
- [ ] Submissão para SBCCI/LASCAS até 31/08/2026
