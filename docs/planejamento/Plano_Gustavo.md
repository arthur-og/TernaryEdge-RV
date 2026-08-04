# Plano de Trabalho — Gustavo Alexandre dos Santos
**Papel no Projeto:** Kernel Driver Development (LKM, MMIO, DMA, Hardware Synchronization)
**Última atualização:** 04/08/2026

---

## Nota sobre mudança de escopo

O `user_app.c` (aplicação de usuário) foi transferido para o Gildo, que o refatorou com sucesso para usar a NPU HAL (entregue em agosto/2026). O driver de kernel (`npu_driver.c` v3.0) permanece com você e está code-complete. O Gildo construiu a HAL sobre a interface ioctl que você forneceu (`struct npu_ioctl_args` compartilhada em `software/include/npu_ioctl.h`).

---

## Marcos do Projeto

| Marco | Previsão | Status |
|:------|:---------|:-------|
| M1 — Driver "Hello World" carregado no QEMU (insmod/lsmod/rmmod) | Concluído | ✅ |
| M2 — Platform Driver com DT match + DMA Coherent + IRQ + wait_queue | Concluído | ✅ |
| M3 — Driver adaptado para NPU v2 (10 registradores, IOCTL struct) | Concluído | ✅ |
| M4 — Integração física testada na FPGA Urrbana | Ago/2026 — em andamento | ⏳ |
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

## Fase 3 (Concluída): Adaptação para NPU v2 (DMA + 64 MACs)

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

A RealDigital Urrbana (Spartan-7 XC7S50-CSGA324) foi recebida em agosto/2026. Síntese do SoC + NPU v2 e boot Linux na FPGA estão pendentes (camada davidjl do Arthur seguido do Gildo). Após o boot você poderá validar o driver no silício.

- 【 ] Cross-compilar `npu_driver.ko` usando a toolchain Buildroot (`riscv32-buildroot-linux-gnu-`)
- 【 ] Enviar o `.ko` para a Urrbana (scp via UART/USB, ou gravar na partição ext4 do SD)
- 【 】 `insmod npu_driver.ko` na FPGA Urrbana
- 【 】 Verificar `dmesg` — esperar as mensagens:
  - `Ternary NPU v2 probing...`
  - `MMIO at 0x40000000 (size=65536)`
  - `IRQ 10 registered`
  - `DMA buffer: virt=... phys=... size=4194304`
  - `NPU v2 probe successful. /dev/npu_ternaria ready.`
- 【 】 Confirmar que `/dev/npu_ternaria` aparece em `/dev/` (permissões 0666 ou via udev)
- 【 】 Validar IRQ — ao disparar `ioctl(NPU_IOCTL_START_INFERENCE)`, verificar `dmesg`:
  - Sem `npu_irq_handler` em loop (IRQ storm) → sinaliza IRQ limpo no hardware
  - Sem `wait_event` sem `wake_up` → sinaliza IRQ não chega (provável crossbar DMA mismatch)
- 【 】 Validar DMA — ao escrever pesos/ativações via mmap e iniciar inference, verificar dados são lidos corretamente da RAM. Validar resultado contra golden model do Gilvan.
- 【 】 Escrever seção **"Kernel Driver Design"** do Paper 1:
  - Camada de abstração (Platform Driver, Device Tree binding)
  - Fluxo MMIO (iowrite32 em 8 registradores de configuração)
  - DMA Coherent Buffer (`dma_alloc_coherent`, `dma_mmap_coherent`)
  - Sincronização IRQ (`devm_request_irq`, `wait_event_interruptible`)
  - Overhead de transição kernel/user space (μs)
  - Quick comparison com polling (teórico ou micro-benchmark)
