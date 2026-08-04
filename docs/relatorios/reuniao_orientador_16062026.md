# Reunião com Orientador — 16/06/2026
## Pauta para Discussão

---

## 1. 🚀 O que foi entregue desde a última reunião

### Fase 3 Completa — NPU v2 (Arthur)

A NPU v2 foi completamente implementada em RTL e validada via golden model C++. As principais entregas:

**Hardware (RTL):**
| Módulo | Funcionalidade |
|--------|---------------|
| `npu_v2_pkg.v` | Definições compartilhadas (10 registradores, estados FSM, constantes) |
| `npu_ternaria_top_v2.v` | Top-level integrado (547 linhas) — FSM de 10 estados + Layer Sequencer |
| `ternary_mac_array.v` | 64 MACs multiplierless operando em paralelo (0 DSPs) |
| `adder_tree_64.v` | Árvore de soma pipeline de 6 estágios (63 adders, 64→1) |
| `wishbone_master.v` | Controlador Wishbone B4 Master para DMA (burst reads) |
| `tb_npu_v2.v` | Testbench auto-verificável com RAM externa simulada |

**Golden Model C++ (validação):**
| Simulação | Testes | Resultado |
|:----------|-------:|:----------|
| NPU v1 (1 MAC, PIO) | 8 | **8/8** ✅ |
| NPU v2 (64 MACs, DMA, Layer Sequencer) | 21 | **21/21** ✅ |
| **Total** | **29** | **29/29** ✅ |

**Arquitetura da NPU v2:**
```
64 MACs paralelos → adder tree pipeline (6 estágios) → 1 acumulador
    └─ 1 ciclo: 64 ativações × 64 pesos ternários
    └─ Throughput: ~10.67 MACs/ciclo (pipelined)
    └─ Layer 1 (784→1024): 13.312 ciclos vs 802.816 (1 MAC) = 60× speedup

Layer Sequencer (FSM 10 estados):
    IDLE → CFG_ACT → DMA_ACT → CFG_WEIGHT → DMA_WEIGHT →
        COMPUTE_BATCH → NEXT_OUTPUT → LAYER_DONE → NEXT_LAYER → DONE
    └─ 3 layers automáticas: 784→1024→512→256
    └─ ~92.000 ciclos para inferência completa (50 MHz → ~1.84 ms)
```

**Software:**
| Componente | Status |
|------------|--------|
| Driver kernel (`npu_driver.c` v3.0) | Offsets v2, IOCTL com struct args (5 campos), IRQ handler |
| Device Tree QEMU + FPGA | `setup_qemu/ternaryedge.dts` + `urrbana.dts` — IRQ=10 |
| Kernel config fragment | `kernel-npu.cfg` — FAT/EXT4, HIGH_RES_TIMERS |
| SoC base com NPU v2 | `base_soc.py` — wrapper v2, Wishbone slave+master, IRQ 10 |
| **NPU HAL + Classifier** | 🔄 **Em andamento (Gildo)** — nova responsabilidade |

**Mudança organizacional importante:**
- Gildo assume a **NPU HAL + Classifier + Buildroot Packages** — escopo expandido
- Gilvan transfere `user_app.c` para Gildo e foca no pipeline de IA + golden model
- Filosofia: *quanto menos complexa a NPU, mais complexo o software que a completa*

---

## 2. 📊 Status dos Membros

| Membro | Papel | Fase | % | Status |
|--------|-------|:----:|:-:|:-------|
| **Arthur** | Hardware RTL/SoC | 3.5/4 | 95% | F1✅ F2✅ **F3✅** F4▶️ |
| **Gustavo** | Driver Kernel | 3.5/4 | 95% | F1✅ F2✅ **F3✅** F4▶️ |
| **Gilvan** | IA + Golden Model | 3.0/4 | 85% | F1✅ F2✅ **F3✅** (weights + golden) |
| **Gildo** | OS + HAL + Classifier | 3.0/4 | 60% | F1✅ F2✅ **F3⏳** (HAL/Classifier) |

---

## 3. ⚠️ Bloqueios e Riscos

### 🔴 **Crítico: FPGA física** (Item #1 para o professor)
**Sem a placa FPGA não podemos sintetizar o SoC real, carregar o driver Linux e executar a inferência no silício.** O projeto inteiro está validado em simulação C++ (29/29 testes), mas a FPGA é necessária para:
- Extrair métricas reais de latência (μs) e comparar CPU vs NPU
- Medir consumo de energia (eficiência energética)
- Validar timings reais do Wishbone (setup/hold, burst)
- Gerar os dados experimentais para o Paper 1

**O que precisamos do professor:**
- Definição de qual placa FPGA será usada (sugestões no `requisitos_fpga.md`: Arty A7, DE10-Nano, ULX3S)
- Previsão de quando a placa estará disponível
- Se possível, acceso remoto ou laboratório para testes

### 🟡 **Pendências dos membros:**
| Pendência | Dono | Impacto |
|-----------|------|---------|
| HAL + Classifier não implementados | Gildo | User space sem abstração |
| Buildroot packages não configurados | Gildo | Build incompleto |
| Compilar `.ko` do driver para RV32 | Gustavo + Gildo | Sem toolchain compilada ainda |

---

## 4. 🎯 Próximos Passos (Fase 4)

| Prioridade | Tarefa | Dono |
|:----------:|--------|:----:|
| 🔴 | Conseguir FPGA + sintetizar SoC | Professor + Arthur |
| 🔴 | Implementar NPU HAL + Classifier | Gildo |
| 🟡 | Configurar Buildroot packages | Gildo |
| 🟡 | Compilar driver + HAL para RV32 | Gildo + Gustavo |
| 🟢 | Iniciar escrita do Paper 1 (seções individuais) | **Equipe toda** |

### Cronograma estimado para Paper 1:
| Marco | Previsão |
|:------|:---------|
| FPGA disponível | ? (depende do professor) |
| Boot Linux + driver na FPGA | 2 semanas após FPGA |
| Inferência funcional no silício + métricas | 3 semanas após FPGA |
| Rascunho completo do Paper 1 | 4 semanas |
| Submissão (SBCCI/LASCAS) | conforme prazo da conferência |

---

## 5. 💡 Perguntas para o Orientador

1. **FPGA:** Qual placa? Quando? Há acesso remoto ou precisamos ir ao laboratório?
2. **Escopo acadêmico:** O projeto atual (NPU puramente multiplierless, 0 DSPs, acelerando 3 layers ternárias em Linux embarcado) é suficiente para o TCC/artigo, ou o senhor espera algo adicional? (ex: suporte a convoluções, batch processing, maior profundidade de layers)
3. **Paper:** SBCCI ou LASCAS? Qual o prazo de submissão? O senhor prefere um artigo mais curto (4-6 páginas SBCCI) ou mais longo (LASCAS)?
4. **Publicação anterior:** Podemos estender o `paper1_template.tex` que já criamos, ou o senhor tem template/modelo próprio?
5. **Metodologia:** A validação via golden model C++ (29 testes, bit-accurate) é aceitável como "verificação funcional", ou o senhor espera simulação formal (Verilator) com waves antes da FPGA?

---

## 6. 📈 Métricas para Mostrar

| Métrica | Valor |
|:--------|:------|
| Aceleração teórica (64 MACs vs 1 MAC) | **60×** na camada 1 |
| Ciclos totais (3 layers, inferência) | **~92.000 ciclos** |
| Tempo estimado @ 50 MHz | **~1,84 ms** |
| DSPs utilizados | **0** (zero — totalmente multiplierless) |
| Pesos por ciclo (throughput) | **64 MACs/ciclo** |
| Camadas iteradas automaticamente | **3** (784→1024→512→256) |
| Precisão do modelo MNIST | **>95%** |
| Testes de validação | **29/29 (100%)** |
| Arquivos no repositório | **~75** |
| Linhas de RTL Verilog | **~1.600** |
| Linhas de C++ golden model | **~900** |
| **Nova camada: NPU HAL** | 📝 Em especificação por Gildo |

---

## 📝 Adendo (agosto/2026)

Esta ata reflete o estado na data da reunião (16/06/2026). Atualizações posteriores para registro:

- ✅ **FPGA recebida:** RealDigital Urrbana (AMD Spartan-7 XC7S50-CSGA324, 128 MB DDR3, MicroSD). Bloqueio crítico #1 resolvido.
- ✅ **Fase 3 100% completa:** Além do relatado acima, Gildo entregou a NPU HAL completa (`npu_hal.c`, `npu_classifier.c`, `npu_weights.c`), os packages Buildroot (`npu-ternaria`, `npu-hal`, `user-app`) e o `user_app.c` refatorado com flags `--cpu`/`--file`/`--batch`. `weights.h` real já está no repositório.
- ✅ **`base_soc.py`** preparado para `litex_boards.realdigital_urbana` (importa o target correto).
- ⏳ **Fase 4 iniciada:** Caminho crítico agora é físico — síntese FPGA, boot Linux, `insmod`, benchmark real. Tudo documentado em `docs/relatorios/status_atual.md` (atualizado em 04/08/2026).

---

