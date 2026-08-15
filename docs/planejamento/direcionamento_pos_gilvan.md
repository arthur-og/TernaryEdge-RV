# Direcionamento pós-Gilvan: organização operacional e fechamento do Paper 1

**Data de referência:** 14/08/2026
**Janela de fechamento proposta:** até 31/08/2026
**Status:** proposta operacional, pendente de confirmação do Professor Ramon e da equipe

> Este documento é a fonte de verdade atual para a transição de responsabilidades e para o escopo de fechamento do Paper 1. As atas e planos anteriores continuam válidos como registros históricos das decisões e entregas de suas respectivas datas.

## 1. Objetivo da reunião

Alinhar com o Professor Ramon e com a equipe a divisão operacional após a saída do Gilvan, separar autoria de responsabilidade ativa, fechar os critérios de evidência do projeto e decidir o escopo possível do Paper 1 até 31/08/2026.

## 2. Status em um parágrafo

O repositório tem uma arquitetura RTL, uma interface de integração entre hardware e software e um pipeline de IA documentados, mas a evidência atual não permite declarar a pilha completa como validada. O que pode ser afirmado hoje é uma auditoria em nível de código do RTL, o modelo C++ v2 com 21/21 testes host-side passando e interfaces documentadas entre RTL, driver, HAL e aplicação; a execução do RTL, a síntese e o bitstream, o boot Linux, a inferência física e qualquer métrica de desempenho, energia ou utilização de recursos ainda dependem de execução e registro de evidências. A organização abaixo é uma proposta provisória para conduzir essa transição sem alterar a lista original de autores do paper.

## 3. Proposta de ownership operacional

| Pessoa | Frente operacional proposta | Entregas principais |
|:--|:--|:--|
| **Arthur** | RTL/SoC, regressão Verilog, síntese e bitstream | Auditoria do RTL e das interfaces, regressão Verilog disponível, síntese da Urbana e bitstream quando o fluxo estiver disponível |
| **Gildo** | Linux/Buildroot, integração kernel-driver, HAL, user-space e boot físico | Imagem Buildroot, integração do driver com a HAL e a aplicação, preparação do SD card, boot Linux e validação do fluxo no hardware |
| **Gustavo** | Pipeline de IA, pesos/exportação, manutenção do golden model C++ e metodologia/resultados de benchmark | Exportação reprodutível dos pesos, manutenção dos testes host-side, protocolo de benchmark, coleta e análise de resultados quando houver plataforma física |

Esta divisão é uma **proposta pendente de confirmação do Professor Ramon e da equipe**. Até essa confirmação, nenhum nome deve ser tratado como owner definitivo para novas obrigações. A transição não altera a autoria do artigo nem apaga as contribuições já registradas.

## 4. Autoria do paper e ownership ativo

### Lista original de autores, preservada

1. Arthur Oliveira Gomes
2. Gildo Alves de Lima Junior
3. Gustavo Alexandre dos Santos
4. Gilvan Alves Pastor Junior

Gilvan continua na lista de autores do Paper 1. A saída ou a mudança de participação operacional não remove autoria e não reescreve as contribuições históricas. A lista acima deve permanecer no template LaTeX, no README e nas referências futuras, salvo decisão acadêmica explícita do Professor Ramon.

### Regra de separação

Autoria registra contribuição acadêmica acumulada. Ownership operacional registra quem conduz a próxima entrega. Uma não substitui a outra.

## 5. Matriz de evidências

| Pode ser afirmado agora | Não pode ser apresentado como resultado atual antes de medir |
|:--|:--|
| Auditoria do RTL em nível de código-fonte, com arquivos e interfaces identificados | `29/29` como resultado atual do projeto |
| C++ v2 com **21/21 testes host-side** passando, com comando e log reproduzíveis | Passagem do RTL em runtime ou em uma execução integrada |
| Interfaces documentadas: mapa MMIO, contrato DMA, Device Tree, IOCTL, HAL e formato de pesos | **64 MACs integrados por ciclo** como resultado medido ou confirmado em hardware |
| Arquitetura proposta, invariantes de codificação e sequência prevista de integração | Valores de síntese, recursos, frequência, timing closure ou utilização de BRAM/LUT/FF/DSP |
| Plano de medição e critérios de aceitação | Boot Linux na FPGA, `insmod`, IRQ/DMA e inferência física |
| Escopo de paper condicionado à evidência que estiver disponível | Speedup, latência, potência, energia ou comparação CPU versus NPU sem CSV e log da execução correspondente |

Qualquer item da coluna da direita deve permanecer como `TBD`, hipótese de projeto ou trabalho pendente. Não preencher tabelas com estimativas para fazer o paper parecer completo.

## 6. Gates de trabalho em ordem de dependência

1. **G0, confirmação de escopo:** Ramon confirma ownership provisório, autoria preservada e escopo de fechamento.
2. **G1, contrato técnico:** Arthur fecha a auditoria de RTL/SoC; Gildo e Gustavo conferem se as interfaces usadas na integração correspondem ao contrato documentado.
3. **G2, evidência host-side:** Gustavo reproduz o C++ v2 em 21/21 e congela o protocolo de benchmark; o resultado continua sendo host-side, não FPGA.
4. **G3, síntese e bitstream:** Arthur executa síntese, verifica timing e gera o bitstream, registrando os relatórios reais. Se o fluxo não executar, o bloqueio deve ser registrado sem inventar valores.
5. **G4, Linux e integração:** Gildo gera a imagem, prepara o SD card e valida boot, driver, HAL e user-space na plataforma física, se G3 estiver aprovado.
6. **G5, inferência e medição:** Gustavo conduz o protocolo de benchmark sobre o fluxo validado por Gildo e coleta CSV, logs e condições de execução. Sem G4, não há resultado físico.
7. **G6, paper e closeout:** a equipe usa somente evidências aceitas, fecha lacunas e escolhe o escopo final até 31/08.

## 7. Cronograma de fechamento proposto

| Data | Marco | Critério de saída |
|:--|:--|:--|
| **14/08** | Conversa com Ramon e registro da transição | As três decisões da seção 10 têm resposta ou ficam marcadas como pendentes |
| **15 a 17/08** | G1 e G2 | Auditoria de RTL, interfaces revisadas e log C++ v2 21/21 anexado |
| **18 a 20/08** | G3 | Relatório real de síntese/timing e bitstream, ou bloqueio documentado |
| **21 a 24/08** | G4 | Imagem Buildroot, boot console, `dmesg`, driver, HAL e aplicação, ou fallback acionado |
| **25 a 27/08** | G5 | CSV, comandos, configuração e logs de inferência física, somente se G4 passar |
| **28 a 30/08** | G6, redação e revisão | Tabelas preenchidas apenas com evidência, referências internas e escopo aprovado |
| **31/08** | Closeout | Versão de submissão ou versão de escopo reduzido entregue, com lista explícita de limitações |

### Escopo de fallback se não houver evidência física

Se a FPGA não produzir evidência de síntese, boot ou inferência até o prazo, o Paper 1 deve ser fechado como um trabalho de arquitetura e verificação host-side. Esse escopo pode incluir a proposta do NPU multiplierless, o contrato RV32IMA/Wishbone, a integração planejada Linux/driver/HAL, o pipeline QAT e o C++ v2 com 21/21 testes host-side. Deve excluir resultados de speedup, latência, potência, recursos, timing, boot Linux, inferência física e qualquer frase que sugira validação end-to-end. A seção de trabalho futuro deve registrar a validação FPGA como etapa necessária, não como resultado já obtido.

## 8. Deliverables e evidências de aceitação

### Arthur

**Deliverables:**

- Auditoria source-level do RTL, SoC, mapa MMIO, DMA, IRQ e pontos de integração.
- Regressão Verilog executada, quando o simulador e o testbench estiverem disponíveis, com comando e log.
- Relatório de síntese e timing da Urbana, mais bitstream, somente se o fluxo completar.
- Seção de hardware do paper, distinguindo arquitetura proposta de resultado medido.

**Evidência de aceitação:** arquivos auditados e checklist com referências de linha; log de regressão; relatório gerado pela ferramenta; bitstream identificável; ou, na ausência do fluxo físico, bloqueio reproduzível e escopo de fallback registrado.

### Gildo

**Deliverables:**

- Imagem Buildroot com kernel, Device Tree, driver, HAL e user-space integrados.
- Procedimento de gravação do SD card e comando de boot.
- Validação do caminho driver, HAL e aplicação no hardware, se o bitstream estiver disponível.
- Seção de Linux, Buildroot, integração kernel-driver, HAL e user-space do paper.

**Evidência de aceitação:** artefato ou checksum da imagem; configuração usada; console de boot; saída de `dmesg`; presença do device node; comandos de compilação e execução; e logs de falha quando uma dependência bloquear a validação.

### Gustavo

**Deliverables:**

- Pipeline de IA e exportação de pesos reproduzíveis, com formato e versão registrados.
- Manutenção do golden model C++ v2 e log host-side com 21/21 testes.
- Protocolo de benchmark com dataset, número de amostras, comandos, campos CSV e condições de execução.
- CSV, logs, gráficos e seção de resultados somente para execuções físicas realmente medidas.

**Evidência de aceitação:** comando reproduzível para exportação; manifesto dos pesos; log 21/21; protocolo versionado; CSV bruto com origem identificada; e análise que não transforme ausência de medição em número estimado.

### Equipe e paper

**Deliverables:** revisão de consistência, preservação dos quatro autores, tabela de limitações e decisão final entre escopo físico e fallback.
**Evidência de aceitação:** template sem métricas fabricadas, referências para logs e relatórios, e aprovação explícita do escopo pelo Professor Ramon.

## 9. Script curto para Arthur falar com o Professor Ramon

> Professor Ramon, depois da saída do Gilvan, queremos separar autoria de ownership operacional. Propomos Arthur no RTL, SoC, regressão e síntese; Gildo no Linux, Buildroot, integração do driver, HAL, user-space e boot; e Gustavo no pipeline de IA, pesos, golden model e metodologia de benchmark. Hoje temos auditoria de código, interfaces documentadas e 21/21 testes host-side do C++ v2, mas ainda não temos runtime RTL, síntese, boot Linux ou inferência física. Queremos confirmar essa divisão e saber se, sem evidência da FPGA até 31/08, o senhor aprova um paper de arquitetura e verificação host-side, sem speedup, latência ou potência.

## 10. Três decisões a solicitar

1. **Ownership:** o Professor Ramon e a equipe confirmam a divisão Arthur, Gildo e Gustavo como proposta operacional provisória até a próxima revisão?
2. **Escopo acadêmico:** se a evidência física não estiver disponível até 31/08, o Paper 1 será submetido no escopo de arquitetura e verificação host-side, sem resultados de desempenho ou energia?
3. **Aceitação e prazo:** quais artefatos e logs o Professor Ramon considera suficientes para o closeout, e 31/08/2026 é a data de corte para escolher entre o escopo físico e o fallback?

## 11. Regra de manutenção deste direcionamento

Atualizações de ownership, evidência ou escopo devem ser feitas primeiro neste documento. README, status, checklist, contrato de arquitetura e template do paper devem apontar para esta fonte de verdade e nunca transformar uma meta ou uma hipótese em resultado medido.
