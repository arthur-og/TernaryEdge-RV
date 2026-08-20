# Plano de Trabalho — Gustavo Alexandre dos Santos
**Papel no Projeto:** AI Pipeline, Weights, Golden Model, Kernel Driver, RV32 Cross-Compilation, Physical Validation and Benchmarks
**Última atualização:** 04/08/2026

> **Ownership operacional atual:** Gustavo conduz a manutenção do pipeline de IA, a exportação de pesos e o contrato `weights.h`, a regressão e manutenção dos Golden Models, o driver de kernel, a compilação cruzada RV32, a coordenação da validação física, os benchmarks CPU versus NPU e os resultados e discussão do Paper 1. Gildo mantém OS, Buildroot, HAL, classifier, MicroSD e boot Linux. Arthur mantém RTL, LiteX, síntese e bitstream. Gilvan permanece como contribuidor histórico e quarto autor.

---

## Nota sobre mudança de escopo

O `user_app.c` (aplicação de usuário) foi transferido para o Gildo, que o refatorou para usar a NPU HAL. O driver de kernel (`npu_driver.c` v3.0) permanece com Gustavo, que também assumiu a manutenção operacional do pipeline de IA, do contrato `weights.h`, dos Golden Models e da coordenação de validação. Gildo construiu a HAL sobre a interface ioctl fornecida por Gustavo (`struct npu_ioctl_args` compartilhada em `software/include/npu_ioctl.h`).

---

## Marcos do Projeto

| Marco | Previsão | Status |
|:------|:---------|:-------|
| M1 — Driver "Hello World" carregado no QEMU (insmod/lsmod/rmmod) | Concluído | ✅ |
| M2 — Platform Driver com DT match + DMA Coherent + IRQ + wait_queue | Concluído | ✅ |
| M3 — Driver adaptado para NPU v2 (10 registradores, IOCTL struct) | Concluído | ✅ |
| M4 — Integração física na FPGA Urrbana | Ago/2026 — pendente | ⏳ |
| M5 — Seção "Kernel Driver Design" do Paper 1 escrita | Antes prazo final | ⏳ |

---

## Fase 1 (Concluída): Fundamentação e Ambiente

- ✅ Ambiente de compilação LKM configurado
- ✅ Driver "Hello World" compilado e testado no QEMU
- ✅ Toolchain própria compilada via Buildroot SDK

## Fase 2 (Concluída): Estrutura do Driver

- ✅ `register_chrdev` → `/dev/npu_ternaria`
- ✅ `struct file_operations` (.mmap, .unlocked_ioctl, .open, .release)
- ✅ Platform Driver com match via Device Tree
- ✅ `dma_alloc_coherent()` + `dma_mmap_coherent()` para buffer compartilhado
- ✅ `ioremap()` via `devm_ioremap_resource()` no probe
- ✅ `devm_request_irq()` com `IRQF_SHARED` e `wait_event_interruptible()`

## Fase 3 (Concluída no snapshot): Adaptação para NPU v2 (DMA + alvo de 64 MACs)

### Contexto

A NPU v2 introduziu **Wishbone Master** — ela mesma lê dados da RAM via DMA. O driver já estava escrito para DMA (com `dma_alloc_coherent`, `dma_mmap_coherent`), então se encaixou perfeitamente.

### Ajustes realizados (npu_driver.c v3.0):

1. **Offsets dos registradores alinhados com o mapa v2:**
   ```c
   #define NPU_REG_STATUS      0x00  /* RO */
   #define NPU_REG_CONTROL     0x04  /* WO */
   #define NPU_REG_SRC_ADDR    0x08  /* RW */
   #define NPU_REG_DST_ADDR    0x0C  /* RW */
   #define NPU_REG_DMA_SIZE    0x10  /* RW */
   #define NPU_REG_WEIGHT_CFG  0x14  /* RW */
   #define NPU_REG_ACT_CFG     0x18  /* RW */
   #define NPU_REG_RESULT      0x1C  /* RO */
   #define NPU_REG_MAC_CFG     0x20  /* RW */
   #define NPU_REG_LAYER_CFG   0x24  /* RW */
   ```

2. **IOCTL com struct npu_ioctl_args:**
   ```c
   struct npu_ioctl_args {
       uint32_t dma_size;
       uint32_t weight_cfg;
       uint32_t act_cfg;
       uint32_t mac_cfg;
       uint32_t layer_cfg;
   };
   ```
   Pipeline START_INFERENCE: SRC_ADDR → DST_ADDR → DMA_SIZE → WEIGHT_CFG → ACT_CFG → MAC_CFG → LAYER_CFG → wmb() → CONTROL.start → wait_event

3. **IRQ handler:** `iowrite32(CLEAR_IRQ, CONTROL)` → `wake_up_interruptible()`

### IOCTL Header

`software/include/npu_ioctl.h` define:
- `struct npu_ioctl_args` (5 campos)
- `NPU_IOCTL_START_INFERENCE` com macro `_IOW()`
- `NPU_DMA_BUFFER_SIZE` (4 MB)

> Este header é compartilhado com a HAL do Gildo e com o user_app.

## Fase 4 (Em Andamento): Deploy Físico e Paper

A RealDigital Urrbana (Spartan-7 XC7S50-CSGA324) foi recebida em agosto/2026. Síntese do SoC + NPU v2 e boot Linux na FPGA estão pendentes, com Arthur responsável por RTL, LiteX, síntese e bitstream e Gildo responsável por OS, Buildroot, HAL, MicroSD e boot. Gustavo coordena a validação do driver e da cadeia física. Não há inferência FPGA end-to-end ou benchmark CPU versus NPU comprovado.

### Evidência corrente de host

- C++ Golden Model v1: 8/8 checks.
- C++ Golden Model v2: 21/21 checks.
- Python AI pipeline: 5/5 checks.
- IOCTL ABI: check aprovado.
- Verilog testbench: indisponível no shell atual; o registro histórico 4/4 não é uma execução corrente.
- `weights.h`: símbolos FP32 presentes, com valores de fallback `0.01`/`0.1` não validados como parâmetros treinados.

O alvo de 64 MACs, 0 DSPs, throughput e speedup permanece intenção de projeto
ou depende de síntese e medição. Não há resultado físico comprovado.

- 【 】 Manter o pipeline de IA e o contrato de exportação `weights.h`
- 【 】 Regressar e manter os Golden Models C++ v1 e v2

- 【 ] Cross-compilar `npu_driver.ko` usando a toolchain Buildroot (`riscv32-buildroot-linux-gnu-`)
- 【 ] Enviar o `.ko` para a Urrbana (scp via UART/USB, ou gravar na partição ext4 do SD)
- 【 】 `insmod npu_driver.ko` na FPGA Urrbana
- 【 】 Verificar `dmesg` — esperar as mensagens:
  - `Ternary NPU v2 probing...`
  - `MMIO at the validated LiteX base (older snapshot: 0x40000000; current LiteX candidate: 0x80000000)`
  - `IRQ 10 registered`
  - `DMA buffer: virt=... phys=... size=4194304`
  - `NPU v2 probe successful. /dev/npu_ternaria ready.`
- 【 】 Confirmar que `/dev/npu_ternaria` aparece em `/dev/` (permissões 0666 ou via udev)
- 【 】 Validar IRQ — ao disparar `ioctl(NPU_IOCTL_START_INFERENCE)`, verificar `dmesg`:
  - Sem `npu_irq_handler` em loop (IRQ storm) → sinaliza IRQ limpo no hardware
  - Sem `wait_event` sem `wake_up` → sinaliza IRQ não chega (provável crossbar DMA mismatch)
- 【 】 Validar DMA — ao escrever pesos/ativações via mmap e iniciar inference, verificar dados são lidos corretamente da RAM. Validar resultado contra os Golden Models históricos, cuja manutenção corrente é de Gustavo.
- 【 】 Escrever seção **"Kernel Driver Design"** do Paper 1:
  - Camada de abstração (Platform Driver, Device Tree binding)
  - Fluxo MMIO (iowrite32 em 8 registradores de configuração)
  - DMA Coherent Buffer (`dma_alloc_coherent`, `dma_mmap_coherent`)
  - Sincronização IRQ (`devm_request_irq`, `wait_event_interruptible`)
  - Overhead de transição kernel/user space (μs)
  - Quick comparison com polling após medição; sem resultado físico, registrar como análise teórica
- 【 】 Coordenar com Arthur e Gildo a validação física de driver, HAL, boot, IRQ e DMA
- 【 】 Executar benchmark CPU versus NPU somente após a cadeia FPGA end-to-end ser comprovada
- 【 】 Escrever a seção de Resultados e Discussão do Paper 1 com dados observados, sem usar placeholders como 9.3x
