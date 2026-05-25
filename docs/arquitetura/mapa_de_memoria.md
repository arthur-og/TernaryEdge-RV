# Mapa de Memória e Integração (NPU Ternária)

**Status:** Definido (Fase 1)
**Autor:** Arthur Oliveira Gomes (Hardware)
**Destinada a:** Gustavo (Driver) e Gilvan (IA)

Este documento oficializa os endereços e parâmetros de hardware que devem ser utilizados no Kernel Driver e na Aplicação em C. Isso garante que o software possa ser finalizado antes mesmo da FPGA estar programada.

## 1. Parâmetros Globais
* **Arquitetura Alvo:** RISC-V (RV32IMA)
* **Endianness:** Little-Endian (Padrão RISC-V. A IA deve empacotar os pesos `uint32_t` neste formato).
* **Barramento de Integração:** Wishbone (32 bits de dados, 32 bits de endereço).

## 2. Mapa de Memória (MMIO)
A NPU está mapeada como um periférico de I/O no barramento do SoC LiteX.

* **Endereço Físico Base:** `0x40000000`
* **Tamanho da Região:** `4 KB` (`0x1000`)
* **Pino de Interrupção (IRQ):** `10` (Conectado ao controlador de interrupções do VexRiscv).

## 3. Offsets dos Registradores (Proposta Wishbone)
O driver do Kernel deve aplicar os seguintes *offsets* em relação ao Endereço Base (`0x40000000`) para acessar os registradores da NPU via `ioread32` e `iowrite32`:

| Offset | Nome | Permissão | Descrição |
| :--- | :--- | :--- | :--- |
| `0x00` | `NPU_STATUS` | Read-Only | Retorna o status atual. `0` = Ocioso, `1` = Processando. |
| `0x04` | `NPU_CONTROL` | Write-Only | Comandos de controle. Escrever `1` inicia a inferência. |
| `0x08` | `DMA_SRC_ADDR`| Read/Write | Endereço físico da memória RAM onde os pesos/imagens estão armazenados (Configurado pelo Driver). |
| `0x0C` | `DMA_DST_ADDR`| Read/Write | Endereço físico na RAM onde a NPU deve salvar as predições de saída. |
| `0x10` | `DATA_SIZE` | Read/Write | Quantidade total de bytes que a NPU deve processar nesta transação. |

> **Aviso ao time de Software:** Podem utilizar esses valores definitivamente em seus códigos (como no `.dts` do QEMU e no LKM). O SoC de hardware será forçado a respeitar esta topologia.
