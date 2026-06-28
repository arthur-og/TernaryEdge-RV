# Plano de Trabalho — Gildo Alves de Lima Junior
**Papel no Projeto:** OS Infrastructure + NPU Complement Software (HAL, Classifier, Buildroot Packages)
**Última atualização:** 28/06/2026

---

## Filosofia Central

**Quanto menos complexa a NPU (puramente ternária, sem FP32), mais complexo o software que a completa.**

A NPU v2 executa apenas 3 camadas de MACs ternários {+1,0,-1} em hardware. Toda a lógica de **classificação final** (256→10 com pesos FP32, softmax, argmax), **gerenciamento de pesos** e **abstração da HAL** é responsabilidade do software — e este é o seu domínio.

Você constrói a ponte entre o hardware especializado e o usuário final.

---

## Marcos do Projeto

| Marco | Previsão | Status |
|:------|:---------|:-------|
| M1 — Buildroot + QEMU boot funcional (RV32IMA) | Concluído | ✅ |
| M2 — Toolchain exportada via SDK (cada um compila a sua) | Concluído | ✅ |
| M3 — Device Tree (.dts) com node da NPU v2 finalizada | 28/06 | ✅ |
| M4 — HAL + Classifier implementados e integrados | 2 semanas | ⏳ |
| M5 — Buildroot packages (npu-ternaria, npu-hal, user-app) configurados | Após M4 | ⏳ |
| M6 — user_app refatorado para usar HAL + teste CPU vs NPU | Após M5 | ⏳ |
| M7 — Suporte a FAT32/ext4 + deploy físico no SD card | Fase 4 | ⏳ |
| M8 — Seção "OS Infrastructure + NPU HAL" do Paper 1 escrita | Antes do prazo final | ⏳ |

---

## Fase 1 (Concluída): Configuração do Ambiente e Boot em Emulação

- ✅ Buildroot configurado (external tree em `software/os_buildroot/`)
- ✅ defconfig ternária (RV32IMA, linux) criada
- ✅ Boot funcional no QEMU (OpenSBI + U-Boot + Kernel + RootFS)
- ✅ HIGH_RES_TIMERS habilitado no kernel

## Fase 2 (Concluída): Geração da Toolchain

- ✅ `make sdk` funcional — cada membro compila sua toolchain localmente
- ✅ README.md em `software/os_buildroot/` com instruções
- ✅ Nenhuma dependência de Google Drive para distribuir toolchain

## Fase 3 (Em Andamento): Device Tree, HAL + Classifier, Buildroot Packages

### 3.1 — Device Tree (.dts) para NPU v2 ✅

Entregue em `setup_qemu/ternaryedge.dts` e `hardware/litex_soc/urrbana.dts`:
- Node NPU em `0x40000000` com IRQ=10
- Compatível com driver existente (`ternaryedge,npu-ternaria`)

### 3.2 — NPU HAL (Hardware Abstraction Layer)

Criar `software/npu_hal/npu_hal.h` + `npu_hal.c`:

```c
// API pública (projetar você mesmo — é sua interface)
npu_ctx_t *npu_init(void);                          // Abre device + mmap DMA
int        npu_load_weights(npu_ctx_t *ctx);         // Copia pesos → DMA
npu_result_t npu_predict(npu_ctx_t *ctx, const uint8_t *image);  // Inferência
void       npu_predict_batch(npu_ctx_t *ctx, const uint8_t *images, int n, npu_result_t *results);
void       npu_deinit(npu_ctx_t *ctx);
void       npu_print_result(const npu_result_t *result, int label);
```

**O que a HAL faz internamente:**
1. `npu_init`: `open("/dev/npu_ternaria")` → `mmap(DMA buffer, 4 MB)` → zera buffer
2. `npu_load_weights`: copia os 3 arrays de pesos ternários do `weights.h` para o DMA no offset correto
3. `npu_predict`:
   - Copia 784 bytes da imagem para o buffer de ativações (normalizando INT8)
   - Configura ioctl e chama `NPU_IOCTL_START_INFERENCE`
   - Lê 256 int32 do resultado DMA
   - Chama `classifier_run()` para output layer na CPU
   - Retorna classe predita + confiança + tempos

### 3.3 — NPU Classifier (Output Layer CPU)

Criar `software/npu_hal/npu_classifier.c` + `.h`:

A NPU entrega 256 int32 brutos (acumuladores ternários). O classifier transforma em 10 scores:

```c
void classifier_run(const float weights[10][256], const float bias[10],
                    const int32_t npu_output[256],
                    float scores[10], float *confidence, int *predicted);
```

**Matemática:**
```
score[c] = bias[c] + Σ(i=0..255) npu_output[i] × weights[c][i]
predicted = argmax(score)
confidence = softmax(score) = exp(score - max) / Σexp(...)
```

### 3.4 — NPU Weights Loader

Criar `software/npu_hal/npu_weights.c` + `.h`:
- Carregar os 3 arrays do `weights.h` (formato pipeline QAT) no buffer DMA
- Layout: `quant_dense_weights[50176]` + `quant_dense_1_weights[32768]` + `quant_dense_2_weights[8192]`
- Validar dimensões
- Fornecer os pesos FP32 da output layer para o classifier

### 3.5 — Buildroot Packages

Criar em `software/os_buildroot/package/`:

| Package | Tipo | Source |
|---------|------|--------|
| `npu-ternaria` | Kernel module (`kernel-module`) | `software/npu_driver/` |
| `npu-hal` | Biblioteca estática (`generic-package`) | `software/npu_hal/` |
| `user-app` | Binário usuário (`generic-package`) | `software/user_app/` |

Atualizar:
- `software/os_buildroot/Config.in` — source dos packages
- `software/os_buildroot/external.mk` — include dos .mk
- `software/os_buildroot/configs/ternaryedge_rv_defconfig` — habilitar packages

### 3.6 — Refatorar user_app.c

O `user_app.c` (atualmente com ioctl bruto) deve ser refatorado para usar a HAL:

```
user_app [--cpu] [--file <mnist.raw>] [--batch <N>]
```

- Modo padrão: `npu_init()` → `npu_load_weights()` → `npu_predict()` → `npu_print_result()`
- `--cpu`: baseline CPU puro (3 layers ternárias + output layer), sem HAL
- `--file`: carregar imagem real MNIST
- `--batch <N>: batch inference com `npu_predict_batch()`

### 3.7 — Pesos (weights.h)

- Criar `software/npu_hal/weights.h` stub (arrays zerados) para compilação independente
- O `weights.h` real é **gerado pelo pipeline do Gilvan** em `ai_training/`
- Estrutura esperada: `quant_dense_weights[]`, `output_weights[]`, `output_biases[]`
- Adicionar `weights.h` ao `.gitignore` (regenerado no build)

## Fase 4 (Futura): Deploy Físico e Paper

- 【 】 Gravar imagem final do Linux em SD card
- 【 】 Bootar na FPGA e validar `dmesg`
- 【 】 Carregar driver NPU e executar inferência
- 【 】 Escrever seção **"OS Infrastructure + NPU HAL"** do Paper 1:
  - Configuração de boot (Buildroot, kernel, OpenSBI)
  - Device Tree e mapeamento físico
  - Arquitetura da HAL e do Classifier
  - Integração Linux + NPU + User Space
