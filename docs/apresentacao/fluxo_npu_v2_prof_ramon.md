# NPU Ternária v2 — Fluxo Completo de Dados para Professor Ramon

**Autor:** Arthur Oliveira Gomes
**Data:** 30/06/2026
**Projeto:** Ternary Edge-RV — Fase 3

---

## Sumário

1. [Visão Geral da Arquitetura](#1-visão-geral-da-arquitetura)
2. [Layout da RAM (Endereços Reais)](#2-layout-da-ram-endereços-reais)
3. [Codificação dos Pesos Ternários](#3-codificação-dos-pesos-ternários)
4. [Operação MAC Multiplierless](#4-operação-mac-multiplierless)
5. [FSM — Estado a Estado com o RTL](#5-fsm--estado-a-estado-com-o-rtl)
6. [Problema Atual: cur_layer Reseta a Cada Start](#6-problema-atual-cur_layer-reseta-a-cada-start)
7. [Correção Necessária: Layer Override no RTL](#7-correção-necessária-layer-override-no-rtl)
8. [Inter-Layer Gap — BatchNorm + ReLU + Quantização](#8-inter-layer-gap--batchnorm--relu--quantização)
9. [Fluxo Correto Após a Correção — Passo a Passo com C](#9-fluxo-correto-após-a-correção--passo-a-passo-com-c)
10. [IRQ — Quem Interrompe Quem e Quando](#10-irq--quem-interrompe-quem-e-quando)
11. [Inconsistências Encontradas no Projeto](#11-inconsistências-encontradas-no-projeto)
12. [Próximos Passos](#12-próximos-passos)

---

## 1. Visão Geral da Arquitetura

```
┌────────────────────────────────────────────────────────────────────┐
│                      SoC (LiteX + VexRiscv RV32IMA)               │
│                                                                    │
│  ┌──────────┐   Wishbone Slave     ┌─────────────────────────┐    │
│  │   CPU    │◄────────────────────►│                         │    │
│  │ RV32IMA  │  (config registers)  │  NPU v2                 │    │
│  │ 50 MHz   │                      │                         │    │
│  └────┬─────┘                      │  ┌───────────────────┐  │    │
│       │                            │  │ Wishbone Master   │  │    │
│       │  Wishbone Master           │  │ (DMA Autônomo)    │  │    │
│       ├───────────────────────────►│  └────────┬──────────┘  │    │
│       │  (NPU → RAM:              │           │              │    │
│       │   reads weights/acts,     │  ┌────────▼──────────┐  │    │
│       │   writes results)         │  │ Layer Sequencer   │  │    │
│       │                            │  │ (FSM Principal)   │  │    │
│       ▼                            │  └────────┬──────────┘  │    │
│  ┌──────────┐                      │           │              │    │
│  │   RAM    │◄─────────────────────┘  ┌────────▼──────────┐  │    │
│  │  (DDR3)  │  (shared CPU+NPU)      │ 64 MACs (para-    │  │    │
│  │ 128 MB   │                        │ lelos, sem DSP)   │  │    │
│  └──────────┘                        └───────────────────┘  │    │
│                                       ┌───────────────────┐  │    │
│                                       │ act_mem[1024]×8b  │  │    │
│                                       │ wt_buf[4]×32b     │  │    │
│                                       │ acc_reg[64]×32b   │  │    │
│                                       └───────────────────┘  │    │
│                                       IRQ ─────► PLIC        │    │
└────────────────────────────────────────────────────────────────────┘
```

### Barramentos

| Barramento | Quem inicia | O que trafega |
|------------|-------------|---------------|
| **Wishbone Slave** | CPU → NPU | Escrita: `SRC_ADDR`, `DST_ADDR`, `CONTROL.start` / Leitura: `STATUS` |
| **Wishbone Master** | NPU → RAM | Leitura burst: ativações e pesos / Escrita: 32-bit results |

### O que cada um faz

| Componente | Responsabilidade |
|------------|------------------|
| **NPU (hardware)** | `acc[j] = Σ(act[i] × weight[i][j])` para cada neurônio j, escreve 32-bit na RAM, asserta IRQ ao fim |
| **CPU (software/HAL)** | BatchNorm + ReLU + quant [0,127] entre camadas, output layer FP32 (256→10) + softmax |

---

## 2. Layout da RAM (Endereços Reais)

A NPU acessa a RAM via Wishbone Master (burst reads/writes). O CPU acessa a mesma RAM via barramento do VexRiscv. **Ambos enxergam o mesmo espaço de endereçamento.**

### Buffer DMA no sistema real

```
Endereço físico DDR3:  0x80000000
Tamanho do buffer:     4 MB (mmapado pelo driver)

Offset relativo  │ Tamanho  │ Conteúdo
(do início       │          │
do buffer)       │          │
─────────────────┼──────────┼─────────────────────────────────
0x0000 - 0x03FF  │ 1024 B   │ Ativações da camada ATUAL
                 │          │ (CPU escreve antes de cada start)
                 │          │ Layer 0: imagem MNIST (784 B)
                 │          │ Layer 1: ativações processadas (1024 B)
                 │          │ Layer 2: ativações processadas (512 B)
─────────────────┼──────────┼─────────────────────────────────
0x1000 - 0x31FFF │ 200704 B │ Pesos Layer 0 (50176 words)
0x32000- 0x51FFF │ 131072 B │ Pesos Layer 1 (32768 words)
0x52000- 0x5BFFF │  32768 B │ Pesos Layer 2 (8192 words)
─────────────────┼──────────┼─────────────────────────────────
0x5C000- 0x5CFFF │  4096 B  │ Resultados Layer 0 (1024×int32)
0x5D000- 0x5D7FF │  2048 B  │ Resultados Layer 1 (512×int32)
0x5D800- 0x5DBFF │  1024 B  │ Resultados Layer 2 (256×int32)
─────────────────┼──────────┼─────────────────────────────────
0x5DC00- 0x5FFFF │   ~1 KB  │ (livre para a HAL)
```

### Endereços Físicos

| O quê | Endereço |
|-------|----------|
| NPU Wishbone Slave (config) | **`0x40000000`** |
| Buffer DMA compartilhado | **`0x80000000`** (início da DDR3) |
| IRQ | **linha 10** do PLIC |

### Como a NPU calcula endereços (linhas relevantes do RTL)

```verilog
// Leitura de ativações — ST_CFG_ACT (linha 267):
dma_addr <= cfg_src_addr + (cur_layer * 1024);
dma_bytes <= layer_in[cur_layer];
// cur_layer=0 → cfg_src_addr + 0, lê 784 bytes
// cur_layer=1 → cfg_src_addr + 1024, lê 1024 bytes
// cur_layer=2 → cfg_src_addr + 2048, lê 512 bytes

// Base dos pesos na RAM (linha 199-206):
layer_weight_offset = (cur_layer==0) ? 0 :
                     (cur_layer==1) ? layer_wcnt[0]*4 :
                                      (layer_wcnt[0]+layer_wcnt[1])*4;
wt_ram_base = cfg_src_addr + 4096 + layer_weight_offset;

// Leitura de pesos — COMPUTE_STEP_LOAD_WEIGHTS (linha 297-299):
dma_addr <= wt_ram_base
         + (cur_output * words_per_output * 4)   // offset do neurônio
         + (cur_in_batch * 16);                    // offset do batch

// Escrita de resultados — ST_WRITE_RESULT (linha 350):
dma_addr <= cfg_dst_addr + (cur_output * 4);      // 1 word por neurônio
dma_wdata <= acc_reg[0];                           // 32-bit signed
```

### Tabela de dependências (CRÍTICO)

Tudo depende de `cur_layer`:

| Expressão | Layer 0 | Layer 1 | Layer 2 |
|-----------|:-------:|:-------:|:-------:|
| `layer_in[cur_layer]` (nº ativações) | 784 | 1024 | 512 |
| `layer_out[cur_layer]` (nº neurônios) | 1024 | 512 | 256 |
| `layer_wcnt[cur_layer]` (nº weight words) | 50176 | 32768 | 8192 |
| `words_per_output = layer_in/16` | 49 | 64 | 32 |
| `layer_weight_offset` (pesos na RAM) | 0 | 200704 | 331776 |

---

## 3. Codificação dos Pesos Ternários

Cada peso ternário ocupa **2 bits**:

| Peso real | Código 2-bit | Operação MAC |
|-----------|:------------:|--------------|
| `+1`      | `0b01`       | `acc += act` (soma) |
| `0`       | `0b00`       | skip (sparsity — economia) |
| `-1`      | `0b11`       | `acc -= act` (subtração) |

16 pesos por word `uint32_t`, Little-Endian:

```
Bit: 31 30  29 28  ...  3 2  1 0
     ├──┴──┤ ├──┴──┤     ├──┴──┤ ├──┴──┤
     p15   p14    ...     p1   p0
```

**Exemplo:** `0x55555555` = 16 pesos +1 | `0xFFFFFFFF` = 16 pesos -1

### Matriz de pesos na RAM

Para layer 0 (784→1024): `words_per_output = 49`
```
RAM: [neurônio0: 49 words] [neurônio1: 49 words] ... [neurônio1023: 49 words]
       ^^^^^^^^^^^^^^^^^^^^
       batch0(acts0-63): words 0-3 (4 words = 64 pesos)
       batch1(acts64-127): words 4-7
       ...
       batch12(acts768-783): word 48 (só 16 ativações)
```

---

## 4. Operação MAC Multiplierless

### Lógica do MAC individual (ternary_mac.v)

```verilog
// Zero DSPs. Substitui multiplicador por Mux.
if (weight == 2'b01)      pseudo_prod =  act;      // +1: passa direto
else if (weight == 2'b11) pseudo_prod = -act;      // -1: complemento de 2
else                      pseudo_prod =  0;        //  0: pula
```

### 64 MACs paralelos no RTL (linha 311-331)

```verilog
for (m = 0; m < 64; m++) begin
    act_idx = cur_in_batch * 64 + m;
    w_idx   = m / 16;                  // qual word de peso
    b_idx   = (m % 16) * 2;            // qual peso de 2 bits
    w_val   = wt_buf[w_idx][b_idx +: 2];

    if (act_idx < layer_in[cur_layer]) begin
        if (w_val == 2'b01)
            acc_reg[0] <= acc_reg[0] + $signed(act_mem[act_idx]);
        else if (w_val == 2'b11)
            acc_reg[0] <= acc_reg[0] - $signed(act_mem[act_idx]);
        else if (w_val == 2'b00)
            zero_counter <= zero_counter + 1;  // sparsity stats
    end
end
```

### Número de operações por layer

| Layer | Ativações | Neurônios | Batches/neurônio | Total batches | Total MACs | Ciclos (~) |
|-------|:---------:|:---------:|:----------------:|:-------------:|:----------:|:----------:|
| 0     | 784       | 1024      | 13              | 13.312       | 851.968    | ~60K       |
| 1     | 1024      | 512       | 16              | 8.192        | 524.288    | ~40K       |
| 2     | 512       | 256       | 8               | 2.048        | 131.072    | ~10K       |

Tudo isso é feito pela NPU **sem intervenção do CPU**.

---

## 5. FSM — Estado a Estado com o RTL

### Estados para UMA camada

```
IDLE → CFG_ACT → DMA_ACT → COMPUTE_BATCH (loop batches) → WRITE_RESULT → NEXT_OUTPUT
                                                                               │
                                                                        (repete p/
                                                                       cada neurônio)
                                                                               │
                                                                         quando todos:
                                                                               ▼
                                                                         LAYER_DONE
                                                                               │
                                                                     se LAYER_CFG=1:
                                                                               ▼
                                                                          ST_DONE → IRQ!
```

### Passo a passo (código real)

```
┌────────────────────────────────────────────────────────────────────────────────┐
│ IDLE (linha 245-258):                                                           │
│   Aguarda cmd_start. Quando recebe:                                             │
│     cur_layer <= 0  ←─── PROBLEMA: sempre zera!                                │
│     cur_output <= 0, cur_in_batch <= 0                                          │
│     acc_reg[0..63] <= 0, wt_buf_idx <= 0                                        │
│   next_state = ST_CFG_ACT                                                       │
├────────────────────────────────────────────────────────────────────────────────┤
│ ST_CFG_ACT (linha 262-270):                                                     │
│   DMA lê ativações da RAM:                                                      │
│     dma_addr  <= cfg_src_addr + (cur_layer * 1024)                              │
│     dma_bytes <= layer_in[cur_layer]                                            │
│   next_state = ST_DMA_ACT                                                       │
├────────────────────────────────────────────────────────────────────────────────┤
│ ST_DMA_ACT (linha 272-280):                                                     │
│   Cada palavra recebida:                                                         │
│     act_mem[act_waddr+0] <= dma_word_data[7:0]   (byte 0)                       │
│     act_mem[act_waddr+1] <= dma_word_data[15:8]  (byte 1)                       │
│     act_mem[act_waddr+2] <= dma_word_data[23:16] (byte 2)                       │
│     act_mem[act_waddr+3] <= dma_word_data[31:24] (byte 3)                       │
│   next_state = ST_COMPUTE_BATCH (quando act_waddr >= layer_in)                  │
├────────────────────────────────────────────────────────────────────────────────┤
│ ST_COMPUTE_BATCH (linha 285-344):                                               │
│   Sub-estado LOAD_WEIGHTS:                                                      │
│     DMA lê 4 words (64 pesos) da RAM:                                           │
│       dma_addr <= wt_ram_base                                                   │
│                + cur_output * words_per_output * 4                              │
│                + cur_in_batch * 16                                              │
│     Quando wt_buf[0..3] cheios → ACCUMULATE                                     │
│                                                                                 │
│   Sub-estado ACCUMULATE:                                                        │
│     64 MACs: acc_reg[0] += Σ(act_i × weight_i)                                 │
│     Se último batch → next_state = ST_WRITE_RESULT                              │
│     Senão → cur_in_batch++, volta pra LOAD_WEIGHTS                              │
├────────────────────────────────────────────────────────────────────────────────┤
│ ST_WRITE_RESULT (linha 348-354):                                                │
│   DMA escreve resultado 32-bit na RAM:                                          │
│     dma_addr  <= cfg_dst_addr + (cur_output * 4)                                │
│     dma_bytes <= 4                                                              │
│     dma_read  <= 0    (WRITE)                                                   │
│     dma_wdata <= acc_reg[0]                                                     │
├────────────────────────────────────────────────────────────────────────────────┤
│ ST_NEXT_OUTPUT (linha 357-363):                                                 │
│   acc_reg[0]  <= 0       (zera p/ próximo neurônio)                             │
│   cur_output  <= cur_output + 1                                                 │
│   cur_in_batch <= 0                                                             │
│   next_state = ST_COMPUTE_BATCH                                                 │
├────────────────────────────────────────────────────────────────────────────────┤
│ ST_LAYER_DONE (linha 366-371):                                                  │
│   cur_output <= 0, cur_in_batch <= 0                                            │
│   SE cur_layer+1 >= cfg_layer_cfg → ST_DONE (IRQ!)                              │
│   SENÃO → ST_NEXT_LAYER                                                         │
├────────────────────────────────────────────────────────────────────────────────┤
│ ST_DONE (linha 384-388):                                                        │
│   irq_out <= 1!                                                                 │
│   Aguarda cmd_clear para voltar a IDLE                                          │
└────────────────────────────────────────────────────────────────────────────────┘
```

---

## 6. Problema Atual: cur_layer Reseta a Cada Start

### O bug (linha 248-249)

```verilog
`ST_IDLE: begin
    if (cmd_start) begin
        cur_layer <= 32'd0;   // ←─── RESETA PRA ZERO!
```

**Toda vez que o CPU escreve CONTROL.start=1, `cur_layer` volta para 0.**

### Consequência: LAYER_CFG=1 SÓ funciona para Layer 0

Com `LAYER_CFG=1`, a NPU processa **1 camada** e vai para ST_DONE. Mas:

```
Invocação 1 (Layer 0):  cur_layer=0 → ✅ funciona
  - Lê ativações de cfg_src_addr + 0 (imagem)
  - Lê pesos de cfg_src_addr + 4096 + 0 (layer 0)
  - words_per_output = 784/16 = 49 (layer 0)
  - layer_out = 1024 neurônios
  - Escreve resultados em cfg_dst_addr
  - IRQ!

Invocação 2 (Layer 1):  cur_layer=0 → ❌ PROBLEMA!
  - Lê ativações de cfg_src_addr + 0 (ok, CPU copiou p/ lá)
  - Lê pesos de cfg_src_addr + 4096 + 0 = LAYER 0! ❌
  - words_per_output = 784/16 = 49 (deveria ser 64) ❌
  - layer_out = 1024 neurônios (deveria ser 512) ❌
```

### Consequência: LAYER_CFG=3 também NÃO funciona

Com `LAYER_CFG=3`, a FSM vai para `ST_NEXT_LAYER` e incrementa `cur_layer`:

```verilog
`ST_NEXT_LAYER: cur_layer <= cur_layer + 1;  // 0 → 1 → 2
```

Mas aí:

```
Layer 0:  ✅ processa corretamente
Layer 1:
  - ST_CFG_ACT: lê de cfg_src_addr + 1024
    └── Mas resultados da layer 0 foram p/ cfg_dst_addr (outro lugar!)
    └── Lê lixo da memória! ❌
  - Pesos: corrige (cur_layer=1)
  - Dimensões: corrige
  - Resultado matemático: LIXO (ativações erradas)
```

### Resumo dos problemas

| Modo | O que acontece | Funciona? |
|------|---------------|:---------:|
| LAYER_CFG=1 (layer 0) | cur_layer=0, tudo certo | ✅ |
| LAYER_CFG=1 (layer 1) | cur_layer=0, pesos/dimensões erradas | ❌ |
| LAYER_CFG=1 (layer 2) | cur_layer=0, pesos/dimensões erradas | ❌ |
| LAYER_CFG=3 | cur_layer incrementa, mas ativações vêm do lugar errado | ❌ |
| LAYER_CFG=3 com cfg_dst=cfg_src+offset | Ativações lêem 32-bit como 8-bit | ❌ |

---

## 7. Correção Necessária: Layer Override no RTL

### Mínima modificação no RTL para suportar as 3 camadas

**O que adicionar:** Um seletor de camada manual no registrador `LAYER_CTRL` (offset `0x2C`).

Atualmente:
```verilog
reg [31:0] cfg_layer_ctrl;  // [0]=irq_per_layer, [5:0]=result_window_idx
```

Vamos adicionar:

```
LAYER_CTRL (offset 0x2C):
  bit  [0]     = irq_per_layer       (já existe)
  bits [5:0]   = result_window_idx   (já existe — atenção: bit [0] overlap!)
  bits [7:6]   = layer_override      (NOVO: 0=layer0, 1=layer1, 2=layer2)
  bit  [8]     = layer_override_en   (NOVO: 1=override ativo)
```

### Mudança no RTL (linha 248-249)

```verilog
// ANTES (bug):
if (cmd_start) begin
    cur_layer <= 32'd0;

// DEPOIS (corrigido):
if (cmd_start) begin
    if (cfg_layer_ctrl[8])              // override enable?
        cur_layer <= cfg_layer_ctrl[7:6];  // usa valor do registrador
    else
        cur_layer <= 32'd0;                // comportamento original
```

### Fluxo de Invocação com o Fix

```
                        (bit 8)(7:6) (5:0)(bit 0)
                          │     │      │     │
Layer 0: LAYER_CTRL = 0b 0    00   000000  0  → 0x000
                    override=off, layer=0, irq_per_layer=0

Layer 1: LAYER_CTRL = 0b 1    01   000000  0  → 0x140
                    override=on,  layer=1

Layer 2: LAYER_CTRL = 0b 1    10   000000  0  → 0x180
                    override=on,  layer=2
```

Com `cur_layer=1`:
- `layer_in[1]` = 1024 → lê 1024 bytes de ativação
- `layer_out[1]` = 512 → processa 512 neurônios
- `words_per_output = 1024/16 = 64` → 64 words por neurônio ✅
- `layer_weight_offset = layer_wcnt[0]*4 = 200704` → pesos em `cfg_src_addr + 4096 + 200704` ✅
- Resultados escritos em `cfg_dst_addr + cur_output*4` ✅

---

## 8. Inter-Layer Gap — BatchNorm + ReLU + Quantização

### Arquitetura real da rede (Keras — train_qat_mnist.py)

```python
model = tf.keras.Sequential([
    QuantDense(784→1024, ternary, use_bias=False),
    BatchNormalization(),             # γ, β, μ, σ² por neurônio
    Activation("relu"),               # max(0, x)
    Lambda(fake_quant[0, 127, 8b]),   # clamp(round(x), 0, 127) → INT8

    QuantDense(1024→512, ternary, use_bias=False),
    BatchNormalization(),
    Activation("relu"),
    Lambda(fake_quant[0, 127, 8b]),

    QuantDense(512→256, ternary, use_bias=False),
    BatchNormalization(),
    Activation("relu"),
    Lambda(fake_quant[0, 127, 8b]),

    Dense(256→10, FP32, softmax),     # ← output layer na CPU
])
```

**A rede FOI treinada com BatchNorm + ReLU + FakeQuant entre as camadas ternárias.**

### Por que a NPU não pode fazer isso

| Operação | Requer | NPU tem? |
|----------|--------|:--------:|
| MAC ternário | Mux + somador int8 | ✅ 64 em paralelo |
| BatchNorm: γ·(x-μ)/√(σ²+ε)+β | Multiplicador FP32 | ❌ zero DSPs |
| ReLU: max(0, x) | Comparador | ❌ |
| FakeQuant: clamp(round(x),0,127) | FP32→int8 | ❌ |
| Output layer: Dense + softmax | FP32 mul + exp() | ❌ |

**A NPU é intencionalmente simples** — zero DSPs, puramente add/sub. O software faz o resto.

### Parâmetros que precisam ser exportados do Keras

```c
// BatchNorm Layer 0 (1024 neurônios):
float bn_gamma_0[1024], bn_beta_0[1024];
float bn_mean_0[1024],  bn_var_0[1024];

// BatchNorm Layer 1 (512 neurônios):
float bn_gamma_1[512],  bn_beta_1[512];
float bn_mean_1[512],   bn_var_1[512];

// BatchNorm Layer 2 (256 neurônios):
float bn_gamma_2[256],  bn_beta_2[256];
float bn_mean_2[256],   bn_var_2[256];

// Output layer FP32:
float output_weights[2560];   // 10 classes × 256 entradas
float output_biases[10];
```

Atualmente o `weights.h` só exporta os pesos ternários (`QuantDense`).

### BatchNorm durante inferência

BatchNorm na inferência é determinístico (parâmetros fixos do treino):

```c
// Para cada neurônio j:
float y = bn_gamma[j] * (x - bn_mean[j])
        / sqrtf(bn_var[j] + 1e-5f) + bn_beta[j];

// Isso é uma transformação LINEAR:  y = A·x + B
// Onde A = γ/√(σ²+ε) e B = β - γ·μ/√(σ²+ε)
// Mas A e B são DIFERENTES para cada neurônio!
```

---

## 9. Fluxo Correto Após a Correção — Passo a Passo com C

### Setup inicial

```c
// Mapeia buffer DMA (4 MB compartilhado CPU+NPU)
uint32_t *dma = mmap(NULL, 4*1024*1024, PROT_READ|PROT_WRITE,
                     MAP_SHARED, fd, 0);

// 1. Copia imagem MNIST (784 bytes) → offset 0x0000
//    Normaliza de [0,255] para [0,127]
for (int i = 0; i < 784; i++)
    ((uint8_t*)dma)[i] = (uint8_t)(imagem[i] / 2);

// 2. Copia pesos ternários → offsets 0x1000, 0x32000, 0x52000
memcpy((uint32_t*)((uint8_t*)dma + 0x1000),
       quant_dense_weights, 50176 * 4);
memcpy((uint32_t*)((uint8_t*)dma + 0x32000),
       quant_dense_1_weights, 32768 * 4);
memcpy((uint32_t*)((uint8_t*)dma + 0x52000),
       quant_dense_2_weights, 8192 * 4);

uint32_t dma_phys = 0x80000000;  // Endereço físico da DDR3
```

### Layer 0

```c
// Configura NPU
npu_write(NPU_BASE + 0x08, dma_phys + 0x0000);    // SRC_ADDR: ativações
npu_write(NPU_BASE + 0x0C, dma_phys + 0x5C000);   // DST_ADDR: resultados 0
npu_write(NPU_BASE + 0x24, 1);                      // LAYER_CFG = 1
npu_write(NPU_BASE + 0x2C, 0x000);                   // LAYER_CTRL: sem override
npu_write(NPU_BASE + 0x04, 1);                      // CONTROL.start = 1
//                                                    └── cur_layer = 0
//                                                        layer_in=784, layer_out=1024
//                                                        pesos em dma+0x1000

// NPU processa autonomamente:
//   Lê 784 bytes de dma+0x0000 → act_mem
//   Para j=0..1023:
//     Para batch b=0..12:
//       Lê 4 words de dma+0x1000 + j*49*4 + b*16
//       64 MACs → acc_reg[0]
//     Escreve acc_reg[0] em dma+0x5C000 + j*4
//   IRQ!

wait_irq();

// CPU lê resultados:
int32_t *layer0_out = (int32_t*)((uint8_t*)dma + 0x5C000);

// CPU aplica BatchNorm + ReLU + quant:
for (int j = 0; j < 1024; j++) {
    float y = bn_gamma_0[j] * (layer0_out[j] - bn_mean_0[j])
            / sqrtf(bn_var_0[j] + 1e-5f) + bn_beta_0[j];
    y = fmaxf(0.0f, y);   // ReLU
    ((uint8_t*)dma)[j] = (uint8_t)fminf(fmaxf(y, 0.0f), 127.0f);
    // Ativações Layer 1 agora estão em dma+0x0000
}
```

### Layer 1

```c
// SRC_ADDR continua dma_phys+0 (ativações já estão lá)
npu_write(NPU_BASE + 0x0C, dma_phys + 0x5D000);   // DST_ADDR: resultados 1
npu_write(NPU_BASE + 0x24, 1);
npu_write(NPU_BASE + 0x2C, 0x140);                   // LAYER_CTRL: override=1
npu_write(NPU_BASE + 0x04, 1);
//                                                    └── cur_layer = 1
//                                                        layer_in=1024, layer_out=512
//                                                        pesos em dma+0x32000

// NPU processa:
//   Lê 1024 bytes de dma+0x0000 (ativações que a CPU escreveu!)
//   Para j=0..511:
//     Para batch b=0..15:
//       Lê 4 words de dma+0x32000 + j*64*4 + b*16
//       64 MACs → acc_reg[0]
//     Escreve acc_reg[0] em dma+0x5D000 + j*4
//   IRQ!

wait_irq();
int32_t *layer1_out = (int32_t*)((uint8_t*)dma + 0x5D000);

for (int j = 0; j < 512; j++) {
    float y = bn_gamma_1[j] * (layer1_out[j] - bn_mean_1[j])
            / sqrtf(bn_var_1[j] + 1e-5f) + bn_beta_1[j];
    y = fmaxf(0.0f, y);
    ((uint8_t*)dma)[j] = (uint8_t)fminf(fmaxf(y, 0.0f), 127.0f);
}
```

### Layer 2

```c
npu_write(NPU_BASE + 0x0C, dma_phys + 0x5D800);   // DST_ADDR: resultados 2
npu_write(NPU_BASE + 0x24, 1);
npu_write(NPU_BASE + 0x2C, 0x180);                   // LAYER_CTRL: override=2
npu_write(NPU_BASE + 0x04, 1);
//                                                    └── cur_layer = 2
//                                                        layer_in=512, layer_out=256
//                                                        pesos em dma+0x52000

wait_irq();
int32_t *layer2_out = (int32_t*)((uint8_t*)dma + 0x5D800);
```

### Output layer (CPU, FP32)

```c
// Output layer: Dense(256→10) com pesos FP32 + softmax
float scores[10];
for (int c = 0; c < 10; c++) {
    scores[c] = output_biases[c];
    for (int i = 0; i < 256; i++)
        scores[c] += layer2_out[i] * output_weights[c][i];
}

// Argmax
int classe = 0;
for (int c = 1; c < 10; c++)
    if (scores[c] > scores[classe]) classe = c;

printf("Classe: %d\n", classe);
```

### Diagrama temporal

```
Tempo ──────────────────────────────────────────────────────────────►

CPU: [prepara RAM] [config L0] [  dorme  ] [BN+ReLU] [config L1] [  dorme  ] [BN+ReLU] ...
                      │          │           │          │          │
                      ▼          ▼           ▼          ▼          ▼
NPU:               [IDLE]──►[LAYER 0 PROCESSANDO]──►IRQ![IDLE]──►[LAYER 1 PROCESSANDO]──►...
                             784→1024                   1024→512
               ▲____________________________________▲
               │          sleep via IRQ             │
               │   (CPU bloqueado no wait_event)    │
               └────────────────────────────────────┘
```

---

## 10. IRQ — Quem Interrompe Quem e Quando

### Mecanismo

```
NPU ──irq_out──► PLIC (VexRiscv) ──IRQ#10──► CPU

1. NPU termina camada → ST_DONE → irq_out = 1
2. PLIC interrompe CPU
3. Driver acorda (wait_event_interruptible)
4. CPU lê resultados (da RAM compartilhada) e processa
5. CPU escreve CONTROL.bit1=1 → clear_irq (NPU volta a IDLE)
6. CPU reconfigura e escreve CONTROL.bit0=1 → próximo start
```

### Com layer_override (após correção)

```
Layer 0: NPU processa → IRQ → CPU faz BN+ReLU+quant → CPU reconfigura → START
Layer 1: NPU processa → IRQ → CPU faz BN+ReLU+quant → CPU reconfigura → START
Layer 2: NPU processa → IRQ → CPU faz output layer → resultado final
```

3 IRQs no total, uma por camada. CPU dorme entre IRQs (consumo mínimo).

### Comportamento atual do RTL

```verilog
// ST_DONE (linha 384-388):
irq_out <= 1'b1;

// Só sai de ST_DONE quando cmd_clear:
// ST_DONE (linhas 437-439):
`ST_DONE: begin
    if (cmd_clear) next_state = `ST_IDLE;
end
```

---

## 11. Inconsistências Encontradas no Projeto

### 🔴 Inconsistência #1: `weights.h` não exporta BatchNorm nem output layer

O script `generate_weights_h.py` (linha 48-51) só exporta `QuantDense`:

```python
quant_layers = [l for l in model.layers
                if isinstance(l, lq.layers.QuantDense)]  # SÓ ternárias!
```

**Faltam:** BatchNorm (γ, β, μ, σ²), output layer (pesos FP32 + bias).

### 🔴 Inconsistência #2: CPU baseline (`user_app.c --cpu`) interpreta int32[] como uint8[]

```c
// user_app.c linha 211:
forward_ternary_layer(...,
    (uint8_t*)layer_out,   // ← layer_out é int32[1024]!
    ...);
```

Isso casta o ponteiro `int32_t*` para `uint8_t*`. Cada byte do resultado 32-bit vira uma "ativação" separada. Em Little-Endian, o byte 0 (LSB) vira `activation[0]`, geralmente um valor pequeno ou negativo.

**Efeito:** modo `--cpu` produz resultados INCORRETOS. Não serve como baseline.

### 🔴 Inconsistência #3: Simulador C++ (`npu_sim_v2.cpp`) só salva o último grupo

```cpp
m_cur_output += 64;  // Processa 64 neurônios por vez!
if (m_cur_output >= LAYER_OUTPUTS[m_cur_layer])
    m_state = ST_LAYER_DONE;  // Só salva acc do último grupo
```

O RTL faz `cur_output++` (1 por vez) e escreve cada resultado na RAM. O C++ sim processa 64 e descarta os intermediários. **Não reflete o RTL.**

---

## 12. Próximos Passos

### Correções no RTL

| O quê | Arquivo | Linha | Mudança |
|-------|---------|:-----:|---------|
| layer_override no LAYER_CTRL | `npu_v2_pkg.v` | — | Definir bits [8], [7:6] do REG_LAYER_CTRL |
| Usar override no start | `npu_ternaria_top_v2.v` | 249 | `cur_layer <= override ? cfg_layer_ctrl[7:6] : 0` |

### Correções no software

| O quê | Quem | Prioridade |
|-------|------|:----------:|
| Exportar BN params + output layer do Keras | Gilvan | Alta |
| Implementar HAL (BN+ReLU+quant em C) | Gildo | Alta |
| Implementar classifier (output layer FP32) | Gildo | Alta |
| Corrigir `user_app.c --cpu` | Gildo/Gustavo | Média |
| Corrigir `npu_sim_v2.cpp` (1 neurônio/vez) | Arthur | Média |

### Opções de arquitetura para discutir com o professor

**Opção A — Software entre camadas (recomendada):**
- layer_override no RTL + HAL em C
- CPU faz BN+ReLU+quant entre invocações da NPU
- ✅ Flexível, suporta BatchNorm completo
- ✅ NPU continua simples (zero DSPs)
- ⚠ CPU precisa processar 3× entre camadas (leve, ~1M floats)

**Opção B — Hardware autônomo:**
- Modificar RTL para escrever int8 truncado diretamente na área da próxima camada
- Retreinar rede SEM BatchNorm (ou foldar BN nos pesos via QAT)
- ✅ NPU processa 3 layers sem intervenção do CPU
- ⚠ Precisão pode cair sem BatchNorm
- ⚠ Mais complexo de validar

---

## Apêndice A: RAM Layout com Endereços (Resumo)

```
Buffer DMA (4 MB, físico 0x80000000):

  0x0000  [    1024 B    ]  Ativações da camada atual (CPU escreve)
  0x0400  [    3 KB      ]  (reservado)
  0x1000  [  200704 B    ]  Pesos Layer 0 (50176 words × 4B)
  0x32000 [  131072 B    ]  Pesos Layer 1 (32768 words × 4B)
  0x52000 [   32768 B    ]  Pesos Layer 2 (8192 words × 4B)
  0x5C000 [   4096 B     ]  Resultados Layer 0 (1024 × int32)
  0x5D000 [   2048 B     ]  Resultados Layer 1 (512 × int32)
  0x5D800 [   1024 B     ]  Resultados Layer 2 (256 × int32)
  0x5DC00 [   ~135 KB    ]  (livre)
```

Fórmulas de endereçamento após correção (com layer_override):

```
Ativações lidas de:   cfg_src_addr + (cur_layer * 1024)
Pesos lidos de:       cfg_src_addr + 4096
                      + layer_weight_offset[cur_layer]
                      + cur_output * (layer_in[cur_layer]/16) * 4
                      + cur_in_batch * 16
Resultados escritos:  cfg_dst_addr + cur_output * 4
```

## Apêndice B: Código da FSM (Referência Rápida)

| Estado | Linha | Faz |
|--------|:-----:|-----|
| IDLE | 245 | Espera `cmd_start`. Zera `cur_layer` (bug!) |
| CFG_ACT | 262 | Dispara DMA p/ ler ativações da RAM |
| DMA_ACT | 272 | Armazena palavras recebidas em `act_mem[0..1023]` |
| COMPUTE_BATCH | 285 | LOAD_WEIGHTS: DMA lê 4 words de peso / ACCUMULATE: 64 MACs |
| WRITE_RESULT | 348 | DMA escreve `acc_reg[0]` (32-bit) na RAM |
| NEXT_OUTPUT | 357 | Zera `acc_reg[0]`, incrementa `cur_output` |
| LAYER_DONE | 366 | Verifica se há próxima camada |
| NEXT_LAYER | 374 | Incrementa `cur_layer` (só usado com LAYER_CFG>1) |
| DONE | 384 | `irq_out = 1`, espera clear |

---

*Documento gerado para apresentação ao Professor Ramon — 30/06/2026*
*Ternary Edge-RV Project — Fase 3 — Rev 2.0 (corrigido após verificação do RTL)*
