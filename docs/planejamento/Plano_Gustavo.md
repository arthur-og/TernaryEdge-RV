# Plano de Trabalho — Gustavo Alexandre dos Santos
**Papel no Projeto:** Kernel Driver Development (LKM, MMIO, DMA, Hardware Synchronization)
**Última atualização:** 28/06/2026

---

## Nota sobre mudança de escopo

O `user_app.c` (aplicação de usuário) foi transferido para o Gildo, que o refatorará para usar a NPU HAL. O driver de kernel (`npu_driver.c`) permanece com você — sua interface de ioctl (`struct npu_ioctl_args`) é a base sobre a qual a HAL do Gildo será construída.

---

## Marcos do Projeto

| Marco | Previsão | Status |
|:------|:---------|:-------|
| M1 — Driver "Hello World" carregado no QEMU (insmod/lsmod/rmmod) | Concluído | ✅ |
| M2 — Platform Driver com DT match + DMA Coherent + IRQ + wait_queue | Concluído | ✅ |
| M3 — Driver adaptado para NPU v2 (10 registradores, IOCTL struct) | Concluído | ✅ |
| M4 — Integração física testada na FPGA | Após M3 + FPGA | ⏳ |
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

## Fase 4 (Futura): Deploy Físico e Paper

- 【 】 `insmod` do driver na FPGA física, verificar `dmesg`
- 【 】 Validar IOCTL, IRQ e DMA no hardware real
- 【 】 Escrever seção **"Kernel Driver Design"** do Paper 1: fluxo de memória, sincronização IRQ, overhead de transição
