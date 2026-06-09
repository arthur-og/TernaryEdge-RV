# Mapa de Memória e Integração (NPU Ternária v2)

**Status:** Revisado (Versão 2.0 — 09/06/2026)
**Autor:** Arthur Oliveira Gomes (Hardware)
**Destinado a:** Gustavo (Driver) e Gilvan (IA)

Este documento oficializa os endereços e parâmetros de hardware da NPU v2, que agora inclui **64 MACs paralelos** e **Wishbone Master (DMA)** para leitura autônoma da RAM.

---

## 1. Parâmetros Globais

| Parâmetro | Valor |
|:----------|:------|
| Arquitetura Alvo | RISC-V RV32IMA |
| Endianness | Little-Endian (LSB = primeiro peso) |
| Barramento | Wishbone B4 (32 bits dados, 32 bits endereço) |
| Endereço Base | `0x4000_0000` |
| Tamanho da Região | 4 KB (`0x1000`) |
| IRQ | 10 (conectado ao PLIC do VexRiscv) |

---

## 2. Mapa de Registradores (MMIO)

| Offset | Nome | Permissão | Descrição Detalhada |
|:-------|:-----|:-----------|:--------------------|
| `0x00` | `NPU_STATUS` | RO | `[0]` busy, `[1]` irq_pending, `[7:2]` layer_id, `[15:8]` zero_counter (quantos pesos 0 foram pulados na última operação) |
| `0x04` | `NPU_CONTROL` | WO | `[0]` start (1 = inicia inferência), `[1]` clear_irq (1 = limpa interrupção) |
| `0x08` | `DMA_SRC_ADDR` | R/W | Endereço físico na RAM de onde a NPU lê pesos + ativações via Wishbone Master |
| `0x0C` | `DMA_DST_ADDR` | R/W | Endereço físico na RAM onde a NPU escreve o resultado final |
| `0x10` | `DMA_SIZE` | R/W | Número total de operações MAC a executar (soma de todas as 3 layers) |
| `0x14` | `WEIGHT_CFG` | R/W | `[15:0]` = bytes por linha de peso (ex: 64 bytes para alimentar 64 MACs), `[31:16]` = número de linhas |
| `0x18` | `ACT_CFG` | R/W | `[15:0]` = número de ativações de entrada (ex: 784 para layer 1) |
| `0x1C` | `RESULT` | RO | Resultado acumulado final da inferência (para leitura direta, sem DMA) |
| `0x20` | `MAC_CFG` | R/W | `[5:0]` = número de MACs em paralelo (default 64, pode ser reduzido para testar) |
| `0x24` | `LAYER_NUM` | R/W | Número de layers a executar sequencialmente (default: 3) |
| `0x28`–`0xFFC` | Reservado | — | Expansões futuras |

> **Atenção:** Estes offsets substituem a versão anterior (Fase 1). O driver deve ser atualizado para usar `DMA_SIZE` (era `DATA_SIZE`) e incluir `WEIGHT_CFG` e `ACT_CFG`.

---

## 3. Fluxo de Operação Típico

```
1. CPU prepara buffer em RAM com pesos empacotados + ativações INT8
2. Driver: iowrite32(fis_addr, NPU_DMA_SRC_ADDR)
            iowrite32(result_addr, NPU_DMA_DST_ADDR)
            iowrite32(total_mac, NPU_DMA_SIZE)
            iowrite32(weight_cfg, NPU_WEIGHT_CFG)
            iowrite32(act_cfg, NPU_ACT_CFG)
3. Driver: iowrite32(START_BIT, NPU_CONTROL)
4. NPU FSM: IDLE → DMA_RD_WEIGHTS → DMA_RD_ACTS → COMPUTE → DONE
5. NPU lê dados da RAM via Wishbone Master (burst)
6. 64 MACs processam em paralelo
7. Layer Sequencer itera automaticamente as 3 camadas
8. NPU escreve resultado no endereço DMA_DST_ADDR
9. NPU asserta irq_out = 1
10. Driver: interrompido, acorda user_app
11. User_app: lê resultado do buffer DMA
```

---

## 4. Codificação dos Pesos (2-bit Ternary)

| Valor | Codificação | Interpretação |
|:------|:------------|:--------------|
| `+1` | `0b01` | Soma a entrada ao acumulador |
| `0` | `0b00` | Entrada é descartada (zero-skipping) |
| `-1` | `0b11` | Entrada é subtraída do acumulador |

**Ordem de empacotamento:** `weights[0]` ocupa os bits `[1:0]` da palavra (LSB). `weights[15]` ocupa `[31:30]` (MSB). Little-Endian consistente.

---

## 5. Interrupção (IRQ)

- **Pino:** `irq_out` da NPU → controlador PLIC do VexRiscv
- **Comportamento:** `irq_out` sobe quando a inferência completa (todas as layers) e o resultado foi escrito no `DMA_DST_ADDR`. Permanece alto até a CPU escrever `clear_irq = 1` no `NPU_CONTROL`.
- **Driver:** `devm_request_irq(npdev->irq, npu_irq_handler, IRQF_SHARED, ...)`. Handler faz `wake_up_interruptible(&npdev->wait_queue)`.
