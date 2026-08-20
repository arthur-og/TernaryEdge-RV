# Mapa de Memória e Integração (NPU Ternária v2)

**Status:** Registro histórico (Versão 2.0 — 09/06/2026), mantido para rastreabilidade
**Autor:** Arthur Oliveira Gomes (Hardware)
**Destinado atualmente a:** Gustavo (Driver, weights.h, compilação cruzada e validação)

Este documento registra os endereços e parâmetros propostos para a NPU v2, com alvo de **64 MACs paralelos** e **Wishbone Master (DMA)** para leitura autônoma da RAM. O alvo de paralelismo, o uso de DSP e o desempenho dependem de execução RTL e síntese.

> **Conflito de endereço:** este snapshot antigo lista `0x40000000` como base da NPU. A documentação atual do LiteX usa `0x80000000` como candidato para o MMIO da NPU. A divergência deve ser validada no mapa gerado pelo LiteX e alinhada entre RTL, Device Tree, driver e HAL. Nenhum dos dois endereços deve ser tratado como final sem essa validação.

---

## 1. Parâmetros Globais

| Parâmetro | Valor |
|:----------|:------|
| Arquitetura Alvo | RISC-V RV32IMA |
| Endianness | Little-Endian (LSB = primeiro peso) |
| Barramento | Wishbone B4 (32 bits dados, 32 bits endereço) |
| Endereço Base atual candidato | `0x8000_0000` (LiteX; pendente de validação cruzada) |
| Endereço Base do snapshot histórico | `0x4000_0000` (não final) |
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
| `0x20` | `MAC_CFG` | R/W | `[5:0]` = alvo de MACs em paralelo (design default 64, pode ser reduzido para testar) |
| `0x24` | `LAYER_CFG` | R/W | Número de layers a executar sequencialmente (default de projeto: 3; validar contra RTL) |
| `0x28`–`0xFFC` | Reservado | — | Expansões futuras |

> **Nota do snapshot:** Estes offsets substituíam a versão anterior (Fase 1). O alinhamento corrente do driver deve ser validado junto com o endereço MMIO, `DMA_SIZE`, `WEIGHT_CFG` e `ACT_CFG`.

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
6. O alvo de 64 MACs processa em paralelo, sujeito a validação RTL e síntese
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
- **Comportamento projetado:** `irq_out` deve subir quando a inferência completa e o resultado for escrito no `DMA_DST_ADDR`. A execução no hardware ainda não foi comprovada.
- **Driver:** `devm_request_irq(npdev->irq, npu_irq_handler, IRQF_SHARED, ...)`. Handler faz `wake_up_interruptible(&npdev->wait_queue)`.
