# Plano de Trabalho — Arthur Oliveira Gomes
**Papel no Projeto:** Hardware Architecture & RTL Design (LiteX, Verilog, SoC Generation)
**Última atualização:** 04/08/2026

> **Snapshot histórico:** este plano registra o escopo de Arthur em 04/08/2026. A organização operacional atual está em `docs/planejamento/direcionamento_pos_gilvan.md`. O alvo de 64 MACs, 0 DSPs, throughput e speedup depende de integração e síntese, e não deve ser tratado como resultado físico.

---

## Marcos do Projeto

| Marco | Previsão | Status |
|:------|:---------|:-------|
| M1 — SoC Base (VexRiscv + LiteX) gerado e sintetizado | Concluído | ✅ |
| M2 — NPU v1 (PIO, 1 MAC, Wishbone Slave) funcional em simulação Verilator | Concluído | ✅ |
| M3 — NPU v2 (alvo de 64 MACs, Wishbone Master DMA, Layer Sequencer) documentada | Concluído no snapshot | ✅ |
| M3b — Golden Model C++ v2 validado (21/21 testes passando) | Concluído | ✅ |
| M3c — `base_soc.py` preparado para RealDigital Urrbana | Concluído | ✅ |
| M4 — SoC final + NPU v2 sintetizados na FPGA Urrbana, bitstream rodando | Ago/2026 — em andamento | ⏳ |
| M5 — Relatório de síntese extraído e documentado, incluindo a verificação do alvo de 0 DSPs | Após M4 | ⏳ |
| M6 — Seção "Hardware" do Paper 1 escrita | Antes da submissão | ⏳ |

---

## Fase 1 (Concluída): Geração e Validação da Infraestrutura Base

- ✅ Definição do core VexRiscv (RV32IMA, variante linux)
- ✅ Utilização do framework LiteX para gerar o SoC com barramento Wishbone, UART, temporizadores
- ✅ Definição do mapa de memória base (0x40000000) e IRQ=10
- ✅ `base_soc.py` preparado para `realdigital_urbana` (importa `litex_boards.targets.realdigital_urbana`)
- ✅ Device Tree `urrbana.dts` escrito para a RealDigital Urrbana (Spartan-7 XC7S50-CSGA324)
- ✅ **FPGA recebida (ago/2026)** — RealDigital Urrbana. Síntese pendente.

## Fase 2 (Concluída): NPU v1 — Prova de Conceito (1 MAC, PIO)

- ✅ Módulo ternary_mac.v — MAC multiplierless (apenas somadores/subtratores para pesos {-1,0,1})
- ✅ Módulo npu_ternaria_top.v — FSM de controle, Wishbone Slave, registradores MMIO
- ✅ Pino irq_out para notificação por interrupção de hardware
- ✅ Memória interna para pesos (BRAM)

## Fase 3 (Concluída): NPU v2 — Arquitetura de Produção

### ✅ 3.1 — Alvo de Array de 64 MACs Paralelos

O design de referência é descrito em `ternary_mac_array.v` (64 instâncias de `ternary_mac`) + `adder_tree_64.v` (6 estágios pipeline, 63 adders). A integração e os recursos físicos dependem de execução e síntese.

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
- ~92K ciclos no modelo de referência para inferência completa com pesos zero; não é uma medida FPGA

### ✅ 3.4 — Testbench Verilog, especificação histórica

Documentado em `tb_npu_v2.v` (372 linhas):

1. Teste de escrita/leitura de registradores via Wishbone Slave
2. Teste do STATUS register (idle, busy, irq bits)
3. Teste de IRQ com timeout
4. Teste de inferência com dados + verificação de resultado
5. RAM externa simulada (262.144 words) respondendo ao Wishbone Master

A execução do testbench está indisponível no shell atual. O registro histórico
de 4/4 não é evidência corrente.

### ✅ 3.5 — Alinhamento do STATUS Register

| Fonte | `zero_counter` | Status |
|:------|:---------------|:-------|
| Verilog (`npu_v2_pkg.v` + `npu_ternaria_top_v2.v`) | bits `[15:8]` | ✅ |
| C++ (`npu_sim_v2.cpp`) | bits `[15:8]` | ✅ Corrigido |
| Driver (`npu_driver.c`) | bits `[15:8]` | ✅ Alinhado |

### ✅ 3.6 — Golden Model C++ v2, registro histórico

Implementado em `npu_sim_v2.cpp` (477 linhas) + `demo_npu_v2.cpp` (257 linhas):

- 6 testes de verificação, 21 checks individuais
- Cobre no modelo host: registradores, STATUS layout, alvo de 64 MACs, zero-skipping, IRQ sync, layer sequencer
- Todos passando

### ✅ 3.7 — Pacote de Definições Compartilhadas

`npu_v2_pkg.v` (50 linhas) contém:
- 10 registradores com `define REG_*`
- `WEIGHT_BRAM_DEPTH`, `ACT_BRAM_DEPTH`, `NUM_MACS`
- 10 estados da FSM (`ST_IDLE` a `ST_DONE`)

---

## Fase 4 (Em Andamento): Síntese Física, Métricas e Paper

A RealDigital Urbana chegou em agosto/2026. O caminho crítico do projeto depende agora exclusivamente da síntese FPGA + boot Linux real.

### 4.1 — Síntese FPGA (Opção A ou B)

O notebook do Arthur (i5-5200U, 8 GB RAM) comporta ambas as opções, mas com ressalvas.

**Opção A — Vivado Design Suite 2026.1 + Vivado Basic (Spartan-7 suportado)**
- Prós: Integração LiteX perfeita, wizard completo
- Contras: Instalação 30-70 GB, síntese usa 6-9 GB RAM (swap no note), requer licença Basic gratuita
- Comando: `nix develop .#vivado` e depois `python3 base_soc.py --build --toolchain vivado`

**Opção B — openXC7 (recomendada para o note)**
- Prós: ~600 MB total, usa 1-2 GB RAM, código open-source (ótimo para o paper)
- Contras: Sem wizard, controle primitivos limitados (cativa para SoC LiteX padrão)
- Ferramentas: `yosys synth_xilinx -arch xc7` → `nextpnr-xilinx --chipdb xc7s50csga324.bin` → `fasm2frames` → `xc7frames2bit` → `openFPGALoader`
- Disponibilidade: `nixpkgs` tem `yosys`, `nextpnr-xilinx`, `openfpgaloader`. `prjxray-db` via `snap install openxc7`

### 4.2 — Validação pós-síntese

- 【 】 Gate-level simulation do netlist pós-place-and-route usando `tb_npu_v2.v`
- 【 】 Confirmar timing closure (target: 100 MHz no sistema, DDR3 é ponto crítico)
- 【 】 Flash bitstream para a SPI flash (`--flash` ou `openFPGALoader --flash`)

### 4.3 — Relatório de síntese (comprovação da tese)

- 【 】 Extrair o relatório de recursos e verificar se o alvo de **0 DSPs** se confirma, junto com LUTs, FFs e BRAM utilizados
- 【 】 Comparar com SoC base sem NPU (delta LUTs/FFs/BRAM)
- 【 】 Frequência máxima (Fmax) reportada
- 【 】 Documentar em `docs/arquitetura/sintese_urbbana.md` (a criar)

### 4.4 — Paper 1

- 【 ] **Figura 1** (arquitetura do sistema) — diagrama de blocos TikZ ou gráfico vetorial
- 【 ] **Figura 2** (NPU interna — 64 MAC array + adder tree + DMA + Layer Sequencer)
- 【 ] **Figura 3** (FSM do Layer Sequencer — 10 estados)
- 【 ] Escrever §III-A "Hardware: Multiplierless NPU" (esqueleto existe no `paper1_template.tex`)
- 【 ] Revisar §III-B "Memory-Mapped Register Map" (tabela já está pronta, validar contra RTL)
- 【 ] §II-A "Ternary Neural Networks" (registro de contribuição histórica de Gilvan; ownership atual conforme o direcionamento operacional)
