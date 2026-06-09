# Plano de Trabalho — Arthur Oliveira Gomes
**Papel no Projeto:** Hardware Architecture & RTL Design (LiteX, Verilog, SoC Generation)
**Última atualização:** 10/06/2026

---

## Marcos do Projeto

| Marco | Previsão | Status |
|:------|:---------|:-------|
| M1 — SoC Base (VexRiscv + LiteX) gerado e sintetizado | Concluído | ✅ |
| M2 — NPU v1 (PIO, 1 MAC, Wishbone Slave) funcional em simulação Verilator | Concluído | ✅ |
| M3 — NPU v2 (64 MACs, Wishbone Master DMA, Layer Sequencer) implementada e simulada | Concluído | ✅ |
| M3b — Golden Model C++ v2 validado (21/21 testes passando) | Concluído | ✅ |
| M4 — SoC final + NPU v2 sintetizados na FPGA, bitstream rodando | Após M3 + 1 sem | ⏳ |
| M5 — Relatório de síntese extraído e documentado (0 DSPs, LUTs, FFs) | Após M4 | ⏳ |

---

## Fase 1 (Concluída): Geração e Validação da Infraestrutura Base

- ✅ Definição do core VexRiscv (RV32IMA, variante linux)
- ✅ Utilização do framework LiteX para gerar o SoC com barramento Wishbone, UART, temporizadores
- ✅ Definição do mapa de memória base (0x40000000) e IRQ=10
- ⚠️ **Síntese na FPGA pendente** — aguardando placa física (professor confirmou, E2)

## Fase 2 (Concluída): NPU v1 — Prova de Conceito (1 MAC, PIO)

- ✅ Módulo ternary_mac.v — MAC multiplierless (apenas somadores/subtratores para pesos {-1,0,1})
- ✅ Módulo npu_ternaria_top.v — FSM de controle, Wishbone Slave, registradores MMIO
- ✅ Pino irq_out para notificação por interrupção de hardware
- ✅ Memória interna para pesos (BRAM)

## Fase 3 (Concluída): NPU v2 — Arquitetura de Produção

### ✅ 3.1 — Array de 64 MACs Paralelos

Implementado em `ternary_mac_array.v` (64 instâncias de `ternary_mac`) + `adder_tree_64.v` (6 estágios pipeline, 63 adders).

- **Desempacotamento:** 4 words de 32 bits lidas simultaneamente → 64 pesos de 2 bits desempacotados
- **Adder Tree:** 64 entradas de 9 bits → 15 bits de saída, 6 ciclos de latência pipeline
- **WEIGHT_BRAM_DEPTH:** `npu_v2_pkg.v` define 12.288 palavras (384 Kb)
- **Controle:** Layer Sequencer embutido no top v2

### ✅ 3.2 — Wishbone Master (DMA)

Implementado em `wishbone_master.v` (Wishbone B4 Standard Master):

- **Registradores de Configuração:** `DMA_SRC_ADDR`, `DMA_DST_ADDR`, `DMA_SIZE`, `WEIGHT_CFG`, `ACT_CFG`
- **Burst Reads:** Incrementing burst (CTI=010), clássico handshake stb/ack
- **Result Write-back:** Ao término, resultado escrito em `DMA_DST_ADDR` e IRQ disparada
- **Error Handling:** Aborta e sinaliza erro via pino err_i

### ✅ 3.3 — Layer Sequencer

FSM de 10 estados integrada ao `npu_ternaria_top_v2.v`:

```
IDLE → CFG_ACT → DMA_ACT → CFG_WEIGHT → DMA_WEIGHT → 
  COMPUTE_BATCH → NEXT_OUTPUT → LAYER_DONE → NEXT_LAYER → DONE
```

- 3 layers hard-coded: 784→1024 (50.176 words), 1024→512 (32.768 words), 512→256 (8.192 words)
- ~92K ciclos para inferência completa com pesos zero

### ✅ 3.4 — Testbench Verilog

Implementado em `tb_npu_v2.v` (372 linhas):

1. Teste de escrita/leitura de registradores via Wishbone Slave
2. Teste do STATUS register (idle, busy, irq bits)
3. Teste de IRQ com timeout
4. Teste de inferência com dados + verificação de resultado
5. RAM externa simulada (262.144 words) respondendo ao Wishbone Master

### ✅ 3.5 — Alinhamento do STATUS Register

| Fonte | `zero_counter` | Status |
|:------|:---------------|:-------|
| Verilog (`npu_v2_pkg.v` + `npu_ternaria_top_v2.v`) | bits `[15:8]` | ✅ |
| C++ (`npu_sim_v2.cpp`) | bits `[15:8]` | ✅ Corrigido |
| Driver (`npu_driver.c`) | bits `[15:8]` | ✅ Alinhado |

### ✅ 3.6 — Golden Model C++ v2

Implementado em `npu_sim_v2.cpp` (477 linhas) + `demo_npu_v2.cpp` (257 linhas):

- 6 testes de verificação, 21 checks individuais
- Cobre: registradores, STATUS layout, 64 MACs, zero-skipping, IRQ sync, layer sequencer
- Todos passando

### ✅ 3.7 — Pacote de Definições Compartilhadas

`npu_v2_pkg.v` (50 linhas) contém:
- 10 registradores com `define REG_*`
- `WEIGHT_BRAM_DEPTH`, `ACT_BRAM_DEPTH`, `NUM_MACS`
- 10 estados da FSM (`ST_IDLE` a `ST_DONE`)

---

## Fase 4 (Futura): Síntese Física e Documentação

- 【 】 Timing closure do SoC completo + NPU v2 no FPGA alvo
- 【 】 Extrair relatório de utilização (0 DSPs, LUTs, FFs, BRAM)
- 【 】 Escrever seção de Hardware do Paper 1 (arquitetura multiplierless, 64 MACs, DMA)
