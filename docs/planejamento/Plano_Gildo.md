# Plano de Trabalho — Gildo Alves de Lima Junior
**Papel no Projeto:** OS Infrastructure + NPU Complement Software (HAL, Classifier, Buildroot Packages)
**Última atualização:** 04/08/2026

> **Snapshot histórico:** este plano registra o escopo de Gildo em 04/08/2026. Gildo continua responsável por OS, Buildroot, HAL, classifier, MicroSD e boot Linux. Gustavo é o responsável atual pelo pipeline de IA, exportação e contrato `weights.h`, Golden Model, compilação cruzada RV32, coordenação de validação física, benchmarks CPU versus NPU e resultados e discussão do Paper 1.

> **Mapa de memória:** o snapshot registra o node NPU em `0x40000000`, enquanto a documentação atual do LiteX usa `0x80000000` como candidato. A divergência deve ser validada entre mapa LiteX, RTL, Device Tree, driver e HAL antes da integração.

---

## Filosofia Central

**Quanto menos complexa a NPU (puramente ternária, sem FP32), mais complexo o software que a completa.**

A NPU v2 tem como alvo executar 3 camadas de MACs ternários {+1,0,-1} em hardware, ainda sem validação FPGA end-to-end. Toda a lógica de **classificação final** (256→10 com pesos FP32, softmax, argmax), **gerenciamento de pesos** e **abstração da HAL** é responsabilidade do software, e este é o seu domínio.

Você constrói a ponte entre o hardware especializado e o usuário final.

---

## Marcos do Projeto

| Marco | Previsão | Status |
|:------|:---------|:-------|
| M1 — Buildroot + QEMU boot funcional (RV32IMA) | Concluído | ✅ |
| M2 — Toolchain exportada via SDK (cada um compila a sua) | Concluído | ✅ |
| M3 — Device Tree (.dts) com node da NPU v2 finalizada | 28/06 | ✅ |
| M4 — HAL + Classifier implementados e integrados | Ago/2026 | ✅ |
| M5 — Buildroot packages (npu-ternaria, npu-hal, user-app) configurados | Ago/2026 | ✅ |
| M6 — user_app refatorado para usar HAL + preparação do teste CPU vs NPU | Ago/2026 | ✅ (libnpu_hal.a validada nativa; não é validação física) |
| M7 — Suporte a FAT32/ext4 + deploy físico no SD card | Em andamento | ⏳ |
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

## Fase 3 (Concluída): Device Tree, HAL + Classifier, Buildroot Packages

### 3.1 — Device Tree (.dts) para NPU v2, registro histórico ✅

Entregue em `setup_qemu/ternaryedge.dts` e `hardware/litex_soc/urrbana.dts`:
- Node NPU em `0x40000000` com IRQ=10
- Compatível com driver existente (`ternaryedge,npu-ternaria`)
- `urrbana.dts` específico para RealDigital Urrbana (Spartan-7 XC7S50, 128 MB DDR3 @ `0x80000000`)

### 3.2 — NPU HAL (Hardware Abstraction Layer) ✅

Implementado em `software/npu_hal/` (API pública: `npu_hal.h`, `npu_hal_internal.h`, implementação em `npu_hal.c`):

```c
npu_ctx_t *npu_init(void);                          // Abre device + mmap DMA
int        npu_load_weights(npu_ctx_t *ctx);         // Copia pesos → DMA
npu_result_t npu_predict(npu_ctx_t *ctx, const uint8_t *image);
void       npu_predict_batch(npu_ctx_t *ctx, const uint8_t *images, int n, npu_result_t *results);
void       npu_deinit(npu_ctx_t *ctx);
void       npu_print_result(const npu_result_t *result, int label);
```

### 3.3 — NPU Classifier (Output Layer CPU) ✅

Implementado em `software/npu_hal/npu_classifier.c`:

```c
void classifier_run(const float weights[10][256], const float bias[10],
                    const int32_t npu_output[256],
                    float scores[10], float *confidence, int *predicted);
```

Argmax + softmax sobre os 256 int32 brutos do NPU.

### 3.4 — NPU Weights Loader ✅

Implementado em `software/npu_hal/npu_weights.c`:
- Carrega os 3 arrays do `weights.h` (formato pipeline QAT) para o buffer DMA nos offsets definidos
- Fornece os pesos FP32 da output layer para o classifier

### 3.5 — Buildroot packages ✅

Pacotes entregues em `software/os_buildroot/package/`:

| Package | Tipo | Source |
|---------|------|--------|
| `npu-ternaria` | Kernel module (`kernel-module`) | `software/npu_driver/` |
| `npu-hal` | Biblioteca estática (`generic-package`) | `software/npu_hal/` |
| `user-app` | Binário usuário (`generic-package`) | `software/user_app/` |

Atualizações aplicadas em `Config.in`, `external.mk`, `configs/ternaryedge_rv_defconfig`.

### 3.6 — user_app.c refatorado ✅

Entregue em `software/user_app/user_app.c` (133 linhas):
- API padrão: `npu_init()` → `npu_load_weights()` → `npu_predict()` → `npu_print_result()`
- `--cpu`: baseline CPU puro (3 layers ternárias + output layer), sem HAL
- `--file <path>`: carregar imagem real MNIST
- `--batch <N>`: batch inference com `npu_predict_batch()`

### 3.7 — Pesos (weights.h) ✅

- Registro histórico de `weights.h` com 91.169 linhas, gerado pelo pipeline histórico de Gilvan
- O header atual contém os símbolos FP32, mas os valores de fallback `0.01`/`0.1` não são parâmetros treinados validados; Gustavo mantém a exportação e o contrato
- `weights.h` configunrado no `.gitignore` em produces do pipeline

## Fase 4 (Em Andamento): Deploy Físico e Paper

- 【 】 Gerar imagem final Buildroot (kernel 6.18.7 + OpenSBI 1.6 + RootFS com `BR2_PACKAGE_NPU_TERNARIA`, `BR2_PACKAGE_NPU_HAL`, `BR2_PACKAGE_USER_APP` habilitados)
- 【 】 Partitionar SD card: partição 1 FAT32 (~64 MB boot), partição 2 ext4 (RootFS)
- 【 】 Gravar `boot.scr`, `Image`, `rv32.dtb` (gerado pelo LiteX/light) na partição de boot
- 【 】 Gravar RootFS Buildroot na partição ext4
- 【 】 Bootar na FPGA Urrbana e validar `dmesg` (sem kernel panic, LiteX peripherals OK, SD detectado)
- 【 】 Apoiar Gustavo na validação da toolchain cross-compile: driver `.ko`, libnpu_hal.a, user_app binary
- 【 ] **Revisão recomendada** antes da integração FPGA: `npu_hal.c:76` lê `ctx->dma_buffer[i]` como uint8_t — se RTL escreve 32 bits/neurônio, deveria ser `((int32_t*)ctx->dma_buffer)[i]`. Confirmar com Arthur e Gustavo durante a validação do contrato.
- 【 】 Escrever seção **"OS Infrastructure + NPU HAL"** do Paper 1:
  - Configuração de boot (Buildroot, kernel, OpenSBI)
  - Device Tree e mapeamento físico
  - Arquitetura da HAL e do Classifier
  - Integração Linux + NPU + User Space
