# Plano de Trabalho — Gilvan Alves Pastor Junior
**Papel no Projeto:** AI Pipeline & Golden Model (QAT, C++ Simulation, Benchmark Data)
**Última atualização:** 04/08/2026

---

## Mudança de Escopo

O `user_app.c` (aplicação de usuário) foi **transferido para o Gildo**, que o refatorou com sucesso para usar a NPU HAL (entregue em agosto/2026).

Gilvan mantém o foco no **pipeline de IA** (treinamento, quantização, geração de pesos) e no **golden model C++** (validação bit-accurate). Os gráficos de benchmark e dados comparativos CPU × NPU continuam com você, usando a HAL do Gildo como interface para a FPGA real.

---

## Marcos do Projeto

| Marco | Previsão | Status |
|:------|:---------|:-------|
| M1 — TNN treinada (>95% accuracy, pesos ternários) + weights.h exportado | Concluído | ✅ |
| M2 — Golden Model C++ v2 (64 MACs + DMA + Layer Sequencer) | Concluído | ✅ |
| M3 — Output layer validada (Opção A: ternária ou Opção B: CPU fallback) | Concluído | ✅ |
| M4 — Inferência funcional na FPGA Urrbana rodando | Ago/2026 — em andamento | ⏳ |
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
- ✅ `.gitignore` atualizado (weights.h excluído do Git)

## Fase 3 (Concluída): Golden Model e Validação

### ✅ 3.1 — Golden Model C++ v2 (npu_sim_v2.cpp)

**Arquivos:** `npu_sim_v2.h` (169 linhas) + `npu_sim_v2.cpp` (477 linhas) + `demo_npu_v2.cpp` (257 linhas)

- ✅ **STATUS register corrigido:** `zero_counter` em bits `[15:8]` — alinhado com RTL
- ✅ **64 MACs paralelos:** `process_compute_batch()` processa 64 entradas × 64 pesos por ciclo
- ✅ **DMA simulation:** `run_dma_cycle()` modela Wishbone Master lendo de buffer RAM virtual
- ✅ **Layer Sequencer:** FSM de 10 estados itera 3 layers (784→1024→512→256)
- ✅ **21/21 testes passando** (6 categorias de verificação)

### ✅ 3.2 — Validação da Output Layer

**Decisão:** Opção B **(CPU fallback)** adotada como padrão.

A última camada `Dense(10, softmax)` usa FP32 porque a NPU é puramente ternária. O hardware acelera 3 layers (784→1024→512→256) e a CPU executa a classificação final (256→10).

A Opção A (forçar saída ternária) foi testada e descartada por queda de acurácia abaixo de 90%.

### ✅ 3.3 — weights.h para a HAL

O `weights.h` gerado pelo pipeline agora segue o formato esperado pela HAL do Gildo:

```c
// 3 layers ternárias (usadas pela HAL → DMA → NPU)
static const uint32_t quant_dense_weights[50176];     // Layer 0: 784→1024
static const uint32_t quant_dense_1_weights[32768];   // Layer 1: 1024→512
static const uint32_t quant_dense_2_weights[8192];    // Layer 2: 512→256

// Output layer FP32 (usada pelo Classifier na CPU)
static const float output_weights[2560];               // 256 × 10
static const float output_biases[10];                  // bias
```

## Fase 4 (Em Andamento): Deploy Físico e Paper

A RealDigital Urrbana chegou em agosto/2026. Síntese do hardware (Arthur) e boot Linux (Gildo + Gustavo) destravaram o caminho crítico. Sua contribuição na Fase 4 é coletar métricas reais e finalizar §IV "Experimental Results" do paper.

- 【 】 Preparar 10-100 imagens MNIST de teste em formato `.raw` (784 bytes cada, uint8_t) para serem enviadas à FPGA
- 【 】 Empacotar as imagens junto com a RootFS (ou via scp na UART) para `/root/mnist/`
- 【 】 Executar inferência na FPGA Urrbana com `user_app --file /root/mnist/sample_X.raw` para cada amostra
- 【 】 Salvar saída em `.csv` — usar o timing segregado da HAL (`time_copy_us`, `time_npu_us`, `time_output_us`, `time_total_us`)
- 【 】 Rodar baseline CPU no mesmo set: `user_app --cpu --file /root/mnist/sample_X.raw`
- 【 】 Gerar gráficos (Python + matplotlib):
  - Bar chart: latência CPU vs NPU por layer
  - Box plot: distribuição de speedup sobre N amostras
  - Scatter: accuracy (golden model) vs accuracy (real FPGA)
  - Exportar para `paper/figures/`
- 【 】 **Escrever §IV "Experimental Results"** do `paper1_template.tex`:
  - Tabela de síntese (Arthur preenche: LUTs, FFs, DSPs=0, BRAM, Fmax)
  - Tabela de benchmark (sua, do Gilvan): 784→1024, 1024→512, 512→256 — CPU vs NPU (ms)
  - Speedup total (placeholder atual de 9.3× será substituído pelo número real)
  - Gráficos de benchmark
- 【 】 **Escrever §II-B "Existing FPGA Accelerators"** com análise comparativa contra FINN, Larq Compute Engine (esqueleto existe no template)
- 【 】 Contribuir com §V "Conclusion" reforçada com números reais
