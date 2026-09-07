# Plano de Trabalho — Arthur Oliveira Gomes
**Papel no Projeto:** Hardware Architecture & RTL Design (LiteX, Verilog, SoC Generation)
**Última atualização:** 24/08/2026

> **Estado operacional:** este plano registra o trabalho RTL atual de Arthur. A organização operacional compartilhada está em `docs/planejamento/direcionamento_pos_gilvan.md`. As PEs ternárias evitam multiplicadores no caminho ternário, mas a requantização inclui intencionalmente um multiplicador geral com sinal. A utilização física de DSPs aguarda os relatórios Vivado atuais.

---

## Marcos do Projeto

| Marco | Previsão | Status |
|:------|:---------|:-------|
| M1 — SoC Base (VexRiscv + LiteX) gerado, síntese histórica | Registro histórico | ✅ |
| M2 — NPU v1 (PIO, 1 MAC, Wishbone Slave) funcional em simulação Verilator | Concluído | ✅ |
| M3 — NPU v2, 64 PEs integradas, acumulador escalar, ativações bancadas e pós-processamento de três estágios | Concluído | ✅ |
| M3b — Regressão RTL expandida, matriz de top com 16, 32 e 64 PEs | Concluído | ✅ |
| M3c — `base_soc.py` com propagação de ERR Wishbone e checagem local de proveniência Urbana | Concluído | ✅ |
| M4 — SoC final + NPU v2 sintetizados na FPGA Urbana, bitstream rodando | Pendente | ⏳ |
| M5 — Gate de aceitação dos relatórios Vivado atuais, com recursos e timing | Após M4 | ⏳ |
| M6 — Seção "Hardware" do Paper 1 escrita | Antes da submissão | ⏳ |

---

## Fase 1 (Concluída): Geração e Validação da Infraestrutura Base

- ✅ Definição do core VexRiscv (RV32IMA, variante linux)
- ✅ Utilização do framework LiteX para gerar o SoC com barramento Wishbone, UART, temporizadores
- ✅ Mapa congelado: DDR em `0x40000000`, NPU em `0x80000000` e IRQ 10
- ✅ `base_soc.py` preparado para `realdigital_urbana` (importa `litex_boards.targets.realdigital_urbana`)
- ✅ Device Tree `urrbana.dts` escrito para a RealDigital Urrbana (Spartan-7 XC7S50-CSGA324)
- ✅ **FPGA recebida (ago/2026)** — RealDigital Urrbana. Síntese pendente.

## Fase 2 (Concluída): NPU v1 — Prova de Conceito (1 MAC, PIO)

- ✅ Módulo ternary_mac.v — MAC multiplierless (apenas somadores/subtratores para pesos {-1,0,1})
- ✅ Módulo npu_ternaria_top.v — FSM de controle, Wishbone Slave, registradores MMIO
- ✅ Pino irq_out para notificação por interrupção de hardware
- ✅ Memória interna para pesos (BRAM)

## Fase 3 (Concluída): NPU v2 — Arquitetura de Produção

### ✅ 3.1 — Array Integrado de 64 PEs e Árvore de Soma

O RTL atual integra 64 PEs ternárias em `ternary_mac_array.v` e `adder_tree_64.v`, com árvore de soma pipeline. O acumulador de saída é escalar, as ativações usam bancos dedicados e o pós-processamento tem três estágios em `postprocess_unit.v`.

- **Empacotamento:** cada word de 32 bits contém 16 pesos de 2 bits; a DMA sequencial carrega words em buffers locais packed
- **Adder Tree:** 64 entradas agregadas em pipeline
- **Buffers:** ativações em bancos locais ping-pong e pesos packed locais, sem afirmar uma profundidade BRAM removida do contrato
- **Controle:** o controlador percorre a tabela de descritores fornecida pelo ABI

### ✅ 3.2 — Wishbone Master (DMA)

Implementado em `wishbone_master.v` (Wishbone B4 Standard Master):

- **ABI:** descritor canônico com 17 offsets MMIO de `0x00` a `0x40`, com até 8 descritores de camada
- **Transferência:** DMA sequencial single-beat para buffers packed locais
- **Tratamento de falhas:** `ERR` e timeout são latched e encerram a transferência
- **Integração SoC:** `base_soc.py` propaga `ERR` do caminho Wishbone

### ✅ 3.3 — Controlador de descritores e camadas

O CPU fornece até 8 descritores no ABI canônico, e o controlador os processa
sequencialmente. Os estados internos são detalhes de implementação, incluindo
esperas de pós-processamento e tratamento de erro; o pacote atual os define
de `0` a `19`, sem que essa enumeração seja um contrato externo.

### ✅ 3.4 — Regressão RTL atual

Os testes atuais cobrem as primitivas ternárias, pós-processamento, Wishbone e o top NPU. A matriz de top executa configurações de 16, 32 e 64 PEs, e a matriz de lint Verilator passa. `make test` executa apenas o Verilog atual.

O registro histórico de 4/4 não é usado como evidência corrente.

### ✅ 3.5 — STATUS Register

O STATUS atual reporta a camada corrente nos bits `[15:8]`, além dos bits de
busy, IRQ, done e error. Esse layout é o contrato vigente do RTL e do driver.

### ✅ 3.6 — Golden Model C++ v2, registro histórico

Implementado em `npu_sim_v2.cpp` (477 linhas) + `demo_npu_v2.cpp` (257 linhas):

- 6 testes de verificação, 21 checks individuais
- Cobre no modelo host: registradores, STATUS layout, referência de 64 PEs, zero-skipping, IRQ sync, layer sequencer
- O resultado 21/21 é preservado como registro histórico do modelo host. A gate canônica de Arthur é a regressão RTL Icarus e a matriz de lint Verilator.

### ✅ 3.7 — Pacote de Definições Compartilhadas

`npu_v2_pkg.v` contém o contrato atual:
- 17 offsets MMIO de `0x00` a `0x40`
- `NPU_MAX_LAYERS=8` e `NPU_NUM_PES=64`
- STATUS com camada nos bits `[15:8]`
- Estados internos de `0` a `19`, incluindo `ST_POSTPROCESS_WAIT`, sem
  enumerar uma FSM simplificada como ABI externo

---

## Fase 4 (Em Andamento): Síntese Física, Métricas e Paper

A RealDigital Urbana chegou em agosto/2026. A implementação física, o boot Linux e a validação end-to-end continuam pendentes.

### 4.1 — Síntese FPGA com Vivado

O notebook do Arthur (i5-5200U, 8 GB RAM) tem limitações para esta etapa pesada.

**Vivado Design Suite 2026.1 + Vivado Basic**
- Shell puro Nix com wrapper em `nix/vivado.nix`
- A forma de validação é `nix develop path:.#vivado`, pois `nix/vivado.nix` está atualmente não rastreado e ainda não foi incluído em commit
- O build Vivado é uma etapa pesada executada pelo usuário, não uma gate leve do host

Os checks Nix e a checagem local de proveniência da Urbana já foram validados. Isso não substitui a execução Vivado atual.

### 4.2 — Validação pós-síntese

- 【 】 Executar o build Vivado atual
- 【 】 Aceitar recursos e timing somente após `python3 hardware/litex_soc/check_vivado_reports.py`
- 【 】 Confirmar timing closure e carregar o bitstream, sem tratar intenção como resultado

### 4.3 — Relatório de síntese (comprovação da tese)

- 【 】 Extrair o relatório de recursos atual, incluindo a utilização física de DSPs, LUTs, FFs e BRAM
- 【 】 Comparar com SoC base sem NPU (delta LUTs/FFs/BRAM)
- 【 】 Frequência máxima (Fmax) reportada
- 【 】 Documentar em `docs/arquitetura/sintese_urbbana.md` (a criar)

Relatórios Vivado históricos estão explicitamente rejeitados como evidência atual. O Tcl gerado omitia `postprocess_unit.v`, os artefatos são anteriores ao RTL atual, e registravam WNS de `-7.392 ns` e TNS de `-35888.277 ns`.

### 4.4 — Paper 1

- 【 ] **Figura 1** (arquitetura do sistema) — diagrama de blocos TikZ ou gráfico vetorial
- 【 ] **Figura 2** (NPU interna, 64 PE array + adder tree + DMA + Layer Sequencer)
- 【 ] **Figura 3** (controlador de descritores, pós-processamento e tratamento de erro)
- 【 ] Escrever §III-A "Hardware: Multiplierless NPU" (esqueleto existe no `paper1_template.tex`)
- 【 ] Revisar §III-B "Memory-Mapped Register Map" (tabela já está pronta, validar contra RTL)
- 【 ] §II-A "Ternary Neural Networks" (registro de contribuição histórica de Gilvan; ownership atual conforme o direcionamento operacional)
