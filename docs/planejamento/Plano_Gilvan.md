# Plano de Trabalho — Gilvan Alves Pastor Junior
**Papel no Projeto:** AI Pipeline & Golden Model (QAT, C++ Simulation, Benchmark Data)
**Última atualização:** 04/08/2026

> **Snapshot histórico:** este documento preserva o registro das contribuições de Gilvan. Gilvan não tem ownership operacional atual. Gustavo conduz agora a manutenção do pipeline de IA, exportação e contrato `weights.h`, regressão e manutenção dos Golden Models, compilação cruzada RV32, coordenação de validação física, benchmarks CPU versus NPU e resultados e discussão do Paper 1. Gilvan permanece creditado por QAT, empacotamento ternário, C++ Golden Model v2 e como quarto autor.

---

## Mudança de Escopo

O `user_app.c` (aplicação de usuário) foi **transferido para o Gildo**, que o refatorou com sucesso para usar a NPU HAL (entregue em agosto/2026).

O registro histórico atribui a Gilvan o **pipeline de IA** (treinamento, quantização, geração de pesos) e o **golden model C++** (validação bit-accurate). A manutenção corrente dessas frentes, os gráficos de benchmark e os dados comparativos CPU × NPU foram transferidos para Gustavo, usando a HAL do Gildo como interface para a FPGA real.

---

## Marcos do Projeto

| Marco | Previsão | Status |
|:------|:---------|:-------|
| M1 — TNN treinada (>95% accuracy, pesos ternários) + weights.h exportado | Concluído | ✅ |
| M2 — Golden Model C++ v2 (64 MACs + DMA + Layer Sequencer) | Concluído | ✅ |
| M3 — Output layer validada (Opção A: ternária ou Opção B: CPU fallback) | Concluído | ✅ |
| M4 — Inferência funcional na FPGA Urrbana rodando | Registro histórico, pendente | ⏳ |
| M5 — Seção "AI Pipeline" do Paper 1 + gráficos CPU vs NPU | Transferido para Gustavo | ⏳ |

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

## Fase 3 (Concluída no registro histórico): Golden Model e Validação

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

O registro histórico de `weights.h` descreve o formato esperado pela HAL do Gildo:

```c
// 3 layers ternárias (usadas pela HAL → DMA → NPU)
static const uint32_t quant_dense_weights[50176];     // Layer 0: 784→1024
static const uint32_t quant_dense_1_weights[32768];   // Layer 1: 1024→512
static const uint32_t quant_dense_2_weights[8192];    // Layer 2: 512→256

// Output layer FP32 (usada pelo Classifier na CPU)
static const float output_weights[2560];               // 256 × 10
static const float output_bias[10];                    // current symbol name for bias
```

## Fase 4 (Registro histórico): Deploy Físico e Paper

Este snapshot registrava a chegada da RealDigital Urrbana em agosto/2026 e atribuía a Gilvan a coleta de métricas e a seção de resultados. Essas tarefas são atualmente de Gustavo, com Arthur e Gildo nas frentes de hardware e OS. Não há inferência FPGA end-to-end ou benchmark CPU versus NPU comprovado.

### Evidência corrente preservada

- C++ Golden Model v1: 8/8 checks.
- C++ Golden Model v2: 21/21 checks.
- Python AI pipeline: 5/5 checks.
- IOCTL ABI: check aprovado.
- Verilog testbench: indisponível no shell atual; o registro histórico 4/4 permanece apenas como histórico.
- `weights.h`: símbolos FP32 presentes, com valores de fallback `0.01`/`0.1` não validados como parâmetros treinados.

A lista de tarefas abaixo é preservada como registro do plano antigo de Gilvan.
A execução operacional corrente pertence a Gustavo, com apoio de Arthur e
Gildo nas frentes de hardware e OS.

- 【 】 Preparar 10-100 imagens MNIST de teste em formato `.raw` (784 bytes cada, uint8_t) para serem enviadas à FPGA
- 【 】 Empacotar as imagens junto com a RootFS (ou via scp na UART) para `/root/mnist/`
- 【 】 Executar inferência na FPGA Urrbana com `user_app --file /root/mnist/sample_X.raw` para cada amostra
- 【 】 Salvar saída em `.csv` — usar o timing segregado da HAL (`time_copy_us`, `time_npu_us`, `time_output_us`, `time_total_us`)
- 【 】 Rodar baseline CPU no mesmo set: `user_app --cpu --file /root/mnist/sample_X.raw`
- 【 】 Gerar gráficos (Python + matplotlib), tarefa transferida para Gustavo após a validação física:
  - Bar chart: latência CPU vs NPU por layer
  - Box plot: distribuição de speedup sobre N amostras
  - Scatter: accuracy (golden model) vs accuracy (real FPGA)
  - Exportar para `paper/figures/`
- 【 】 **Escrever §IV "Experimental Results"**, tarefa transferida para Gustavo, do `paper1_template.tex`:
  - Tabela de síntese (Arthur preenche após síntese: LUTs, FFs, DSPs, BRAM, Fmax)
  - Tabela de benchmark (Gustavo após validação): 784→1024, 1024→512, 512→256, CPU versus NPU (ms)
  - Speedup total somente com número observado; o placeholder histórico de 9.3× não é resultado
  - Gráficos de benchmark
- 【 】 **Escrever §II-B "Existing FPGA Accelerators"** com análise comparativa contra FINN, Larq Compute Engine (esqueleto existe no template)
- 【 】 Contribuir com §V "Conclusion" reforçada com números reais
