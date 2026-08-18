# Plano de Execução, Atualização de Documentação e Fechamento — Ternary Edge-RV

**Data de referência:** 17/08/2026  
**Data de entrega (Closeout):** 31/08/2026  
**Objetivo:** Atualizar todas as documentações e checklists do projeto, concluir a integração física na placa RealDigital Urbana (AMD Spartan-7 XC7S50), validar o boot Linux e a aceleração da NPU v2, coletar dados de benchmark e finalizar a versão de submissão do **Paper 1 (SBCCI/LASCAS)**.

---

## 1. Atribuição de Ownership Operacional e Autoria

### Autoria do Paper 1 (Preservada)
A lista oficial de autores no `paper/paper1_template.tex`, `README.md` e em todas as publicações do projeto **permanece intacta**:
1. **Arthur Oliveira Gomes**
2. **Gildo Alves de Lima Junior**
3. **Gustavo Alexandre dos Santos**
4. **Gilvan Alves Pastor Junior**

*Nota:* Conforme diretriz do projeto, as contribuições históricas de Gilvan (pipeline QAT Larq, empacotamento de pesos 2-bit e Golden Model C++ v2) continuam registradas e creditadas.

### Ownership Operacional Ativo (Transição pós-Gilvan)
- **Arthur Oliveira Gomes:** Hardware RTL (NPU v2), SoC LiteX, regressão Verilog, síntese Yosys/openXC7 e geração do Bitstream (`.bit`).
- **Gildo Alves de Lima Junior:** Infraestrutura de OS, Buildroot, Device Tree (`urrbana.dts`), NPU HAL (`libnpu_hal.a`), Classifier (FP32 CPU), preparação do SD Card e boot Linux.
- **Gustavo Alexandre dos Santos:** Kernel Driver (`npu_driver.ko`), contrato do `weights.h` (assumindo a frente de IA/pesos), cross-compilação do driver/HAL/app, protocolo e coleta de benchmarks físicos (CPU × NPU) e redação dos resultados.

---

## 2. Matriz de Atualização da Documentação do Repositório

### 📄 Documentos a Serem Atualizados na Fase de Execução:

1. **`README.md`**:
   - Atualizar a data de status para **17/08/2026**.
   - Atualizar a tabela de atribuição operacional (Arthur: Hardware, Gildo: OS/HAL, Gustavo: Driver & IA/Benchmark, Gilvan: Crédito histórico).
   - Registrar a validação da conexão física JTAG (`openFPGALoader --detect` OK, IDCODE `0x362f093`, FT2232H detectado em `/dev/ttyUSB0` e `/dev/ttyUSB1`).
   - Registrar as flags de síntese do openXC7 (`-nolutram -nowidelut`).
   - Atualizar a matriz de conhecidos/gargalos e prazos para 31/08/2026.

2. **`docs/checklist.md`**:
   - Atualizar data de status para **17/08/2026**.
   - Marcar conexão USB/JTAG como concluída (`[X]`).
   - Atualizar tarefas ativas da Fase 4 para Arthur, Gildo e Gustavo.
   - Preservar o histórico de contribuições de Gilvan nas Fases 1 a 3.

3. **`docs/planejamento/direcionamento_pos_gilvan.md`**:
   - Confirmar a janela operacional de 17/08 a 31/08/2026.
   - Atualizar o status da detecção de hardware FPGA.
   - Alinhar os deliverables finais de cada integrante.

4. **`docs/arquitetura/architecture_contract.md`**:
   - Registrar a resolução dos erros de síntese do openXC7 (`-nolutram` para BRAM de tags e `-nowidelut` para cadeias de multiplexadores).
   - Confirmar a compatibilidade Little-Endian, mapa MMIO (`0x80000000`), DDR3 (`0x40000000`) e IRQ 10.

5. **`nix/ternaryedge.nix`**:
   - Atualizar permissões de udev para o FTDI (`MODE="0666"`, `KERNEL=="ttyUSB[0-9]*"`).

---

## 3. Matriz de Entregáveis Técnicos por Integrante (até 31/08/2026)

### 🔵 Arthur (Hardware & FPGA)
- [ ] **H1:** Gerar o Bitstream `.bit` final em `build/urbana-smoke/gateware/realdigital_urbana.bit` (via openXC7 PnR ou Vivado).
- [ ] **H2:** Extrair relatórios de síntese e utilização de recursos (LUTs, FFs, BRAMs e 0 DSPs para a NPU v2).
- [ ] **H3:** Gravar o bitstream na placa Urbana (`openFPGALoader`) e validar o LED `DONE`.
- [ ] **H4:** Redigir as seções de Hardware do Paper 1 (`paper/paper1_template.tex`).

### 🟢 Gildo (OS, Buildroot, HAL & SD Card)
- [ ] **O1:** Compilar a imagem completa do Buildroot (`software/os_buildroot`) gerando `Image` (Linux 6.18) e `rootfs.tar`.
- [ ] **O2:** Particionar e gravar o Cartão MicroSD (Partição 1: FAT32; Partição 2: ext4 com RootFS).
- [ ] **O3:** Realizar o boot físico do Linux na Urbana, acessar UART (`picocom -b 115200 /dev/ttyUSB1`) e validar `dmesg`.
- [ ] **O4:** Redigir as seções de OS & HAL do Paper 1.

### 🟡 Gustavo (Driver, IA/Pesos & Benchmarks)
- [ ] **D1:** Atualizar `ai_training/scripts/generate_weights_h.py` para exportar `output_weights` e `output_bias` FP32, gerando `software/user_app/weights.h` completo.
- [ ] **D2:** Cross-compilar o driver `npu_driver.ko`, `libnpu_hal.a` e `user_app` com a toolchain do Buildroot.
- [ ] **D3:** Carregar o driver na placa real (`insmod npu_driver.ko`), checar `dmesg` e nó `/dev/npu_ternaria`.
- [ ] **D4:** Executar benchmark físico (`user_app --cpu`, `--file`, `--batch 100`) e gerar `benchmark_npu.csv`.
- [ ] **D5:** Redigir as seções de Kernel Driver e Resultados no Paper 1.

---

## 4. Cronograma de Execução (17 a 31 de Agosto de 2026)

| Data | Marco / Fase | Entregas Esperadas | Responsáveis |
|:---|:---|:---|:---|
| **17–19/08** | **Marco 1: Contratos, Docs & Bitstream** | Atualização de todas as docs (`README.md`, `checklist.md`, `architecture_contract.md`); `weights.h` completo; Bitstream `.bit` pronto. | Gustavo, Arthur & Gildo |
| **20–23/08** | **Marco 2: OS Buildroot & SD Card** | Imagem Buildroot pronta; SD Card gravado; Binários (`.ko`, `libnpu_hal.a`, `user_app`) cross-compilados. | Gildo & Gustavo |
| **24–27/08** | **Marco 3: Boot Físico & Integração** | Boot Linux na Urbana OK; `insmod npu_driver.ko` OK; `/dev/npu_ternaria` funcional; 1ª inferência física executada. | Gildo, Gustavo & Arthur |
| **28–30/08** | **Marco 4: Benchmarks & Redação** | Arquivo `benchmark.csv` gerado; Gráficos e tabelas inseridos em `paper1_template.tex`; Revisão final do texto. | Gustavo, Gildo & Arthur |
| **31/08/2026** | **Marco 5: Closeout & Submissão** | Versão final do Paper 1 pronta para submissão no SBCCI/LASCAS. | Toda a Equipe |

---

## 5. Todos Executáveis (Work Plan)

## Todos

- [ ] 1. [docs/ & README.md] Atualizar README.md, docs/checklist.md, docs/planejamento/direcionamento_pos_gilvan.md e docs/arquitetura/architecture_contract.md para 17/08/2026 - expect todas as documentacoes e checklists sincronizadas sem dados desatualizados
  - Recommended task executor category: `writing`
- [ ] 2. [nix/ternaryedge.nix] Atualizar regras udev do FTDI (MODE=0666, ttyUSB[0-9]*) - expect acesso sem erros de permissao em qualquer maquina NixOS
  - Recommended task executor category: `quick`
- [ ] 3. [software/user_app/weights.h] Atualizar generate_weights_h.py para exportar output_weights e output_bias FP32 - expect HAL compilar sem erros de simbolos ausentes
  - Recommended task executor category: `quick`
- [ ] 4. [hardware/litex_soc/] Gerar e validar bitstream final realdigital_urbana.bit - expect arquivo .bit gerado e LED DONE aceso na placa
  - Recommended task executor category: `unspecified-high`
- [ ] 5. [software/os_buildroot/] Compilar imagem Buildroot (kernel 6.18 + rootfs) - expect Image e rootfs.tar gerados em output/images/
  - Recommended task executor category: `deep`
- [ ] 6. [software/npu_driver/ & software/user_app/] Cross-compilar npu_driver.ko, libnpu_hal.a e user_app com a toolchain Buildroot - expect binarios RISC-V 32-bit gerados
  - Recommended task executor category: `quick`
- [ ] 7. [hardware & SDCard] Gravar SDCard com 2 particoes, bootar Linux na Urbana e carregar driver npu_driver.ko - expect dmesg OK e /dev/npu_ternaria criado
  - Recommended task executor category: `unspecified-high`
- [ ] 8. [software/user_app/] Executar benchmark comparativo CPU vs NPU na placa fisica - expect benchmark_npu.csv gerado com tempos medidos
  - Recommended task executor category: `unspecified-high`
- [ ] 9. [paper/paper1_template.tex] Preencher secoes do Paper 1 com dados reais e autoria preservada (Arthur, Gildo, Gustavo, Gilvan) - expect paper1_template.tex pronto para submissao
  - Recommended task executor category: `writing`

---

## Final verification wave

- [ ] F1. Verificar se README.md e docs/checklist.md refletem o status exato de 17/08/2026 com conexao JTAG OK e papeis pós-Gilvan
- [ ] F2. Verificar se weights.h contem todos os simbolos exigidos pela HAL (quant_dense_weights e output_weights/bias)
- [ ] F3. Verificar se a simulacao Verilog npu_v2 continua passando em 100% dos testes
- [ ] F4. Verificar se a lista de autores do Paper 1 contem exatamente os 4 integrantes originais (Arthur, Gildo, Gustavo, Gilvan)
