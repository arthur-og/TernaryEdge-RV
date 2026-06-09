# Plano de Trabalho — Gilvan Alves Pastor Junior
**Papel no Projeto:** AI Pipeline & User Space (QAT, C Application, Benchmarking, Golden Model)
**Última atualização:** 10/06/2026

---

## Marcos do Projeto

| Marco | Previsão | Status |
|:------|:---------|:-------|
| M1 — TNN treinada (>95% accuracy, pesos ternários) + weights.h exportado | Concluído | ✅ |
| M2 — Golden Model C++ v2 (64 MACs + DMA + Layer Sequencer) | Concluído | ✅ |
| M3 — user_app.c real (forward pass completo + timing segregado) | Concluído | ✅ |
| M4 — Inferência funcional na FPGA rodando | Após FPGA + 1 sem | ⏳ |
| M5 — Seção "AI Pipeline" do Paper 1 + gráficos CPU vs NPU | Antes prazo final | ⏳ |

---

## Fase 1 (Concluída): Treinamento e Quantização

- ✅ Larq framework para TNN (Dense ternária)
- ✅ Precisão >95% no MNIST com pesos restritos a {-1, 0, 1}
- ✅ Sparsity L1 implementada (regularização forcing zeros)
- ✅ Fake quantization INT8 entre camadas

## Fase 2 (Concluída): Exportação de Pesos

- ✅ `pack_weights.py` — empacota 16 pesos de 2 bits por uint32_t (Little-Endian)
- ✅ `generate_weights_h.py` → `weights.h` com 3 camadas
- ✅ Total: 91.136 words = 364 KB compactados

## Fase 3 (Concluída — 4/5 tarefas): Aplicação C e Golden Model

### ✅ 3.1 — Golden Model C++ v2 (npu_sim_v2.cpp)

**Arquivos:** `npu_sim_v2.h` (169 linhas) + `npu_sim_v2.cpp` (477 linhas) + `demo_npu_v2.cpp` (257 linhas)

**O que foi feito:**
- ✅ **STATUS register corrigido:** `zero_counter` em bits `[15:8]` — alinhado com RTL
- ✅ **64 MACs paralelos:** `process_compute_batch()` processa 64 entradas × 64 pesos por ciclo, acumulando em `acc[0]`
- ✅ **DMA simulation:** `run_dma_cycle()` modela Wishbone Master lendo de buffer RAM virtual
- ✅ **Layer Sequencer:** FSM de 10 estados itera 3 layers (784→1024→512→256)
- ✅ **21/21 testes passando:**
  1. Register access (7 registradores)
  2. STATUS bit layout (zero_counter em [15:8])
  3. 64 MACs — acúmulo correto em acc[0]
  4. Zero-skipping (sparsity counting)
  5. IRQ sync (clear_irq via CONTROL)
  6. Layer sequencer (~92K ciclos)

### ✅ 3.2 — user_app.c (Implementação Real)

**Arquivo:** `user_app.c` (236 linhas)

Implementa:
1. Abertura de `/dev/npu_ternaria`
2. `mmap()` do buffer DMA (zero-copy via driver)
3. Carga de pesos sintéticos + 784 ativações no buffer
4. `ioctl(START_INFERENCE)` com struct `npu_ioctl_args`:
   - `dma_size`, `weight_cfg`, `act_cfg`, `mac_cfg`, `layer_cfg`
5. Timing segregado via `gettimeofday()`:
   - `t_setup_us`: preparação dos dados
   - `t_inference_us`: tempo de espera da IRQ (NPU computando)
   - `t_readback_us`: leitura do resultado
6. Baseline CPU com flag `--cpu`:
   - `forward_ternary_layer()` — forward pass ternário em C puro
   - Comparação de speedup (NPU vs CPU)

**Print do benchmark:**
```
========== BENCHMARK ==========
  DMA setup:     XXX us
  NPU inference: XXX us  (CPU was ASLEEP)
  Readback:      XXX us
  Total:         XXX us
================================
```

### ⚠️ 3.3 — Output Layer (Única Pendência)

**Gap conhecido:** Camada de saída `Dense(10, softmax)` usa FP32.

**Opções:**
1. **A)** Forçar saída ternária no treinamento (re-treinar com 2 bits na última layer)
2. **B)** Última layer na CPU (software fallback) — já implementada em `forward_ternary_layer()`

**Decisão pendente:** Gilvan deve testar Opção A. Se acurácia cair abaixo de 90%, adotar Opção B.

### ✅ 3.4 — Revisão do pack_weights.py

Encoding consistente com o RTL:
- `+1 = 0b01`
- `0 = 0b00`
- `-1 = 0b11`
- Little-Endian: peso[0] no LSB

✅ `.gitignore` atualizado para excluir `weights.h` (regenerar via Makefile).

## Fase 4 (Futura): Deploy Físico e Paper

- 【 】 Executar inferência completa de imagens de teste na FPGA
- 【 】 Salvar milissegundos em .csv comprovando speedup NPU > CPU
- 【 】 Gerar gráficos de tempo para o Paper 1
- 【 】 Escrever seção **"AI Pipeline"** do Paper 1: QAT, empacotamento, golden model, resultados de benchmark
