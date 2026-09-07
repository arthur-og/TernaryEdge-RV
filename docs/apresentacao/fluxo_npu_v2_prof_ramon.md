# Apêndice técnico para a conversa com o Professor Ramon

**Projeto:** Ternary Edge-RV
**Base:** estado atual do repositório consultado em 20/08/2026
**Uso:** handout de consulta durante a apresentação

> **Mensagem central:** o objetivo é apresentar uma NPU ternária integrada a um RISC-V, usando MNIST como caso de teste, e alinhar a arquitetura esperada com a implementação atual antes de declarar desempenho, aceleração ou inferência ponta a ponta.

Este texto separa o que está implementado no código, o que foi exercitado pelos testes canônicos, o que aparece apenas como procedimento de handoff e o que ainda depende de execução física. O caminho atual é o RTL v2 integrado ao SoC, não a arquitetura histórica de dez registradores.

## 1. Objetivo e escopo da conversa

1. Apresentar a operação ternária: `w ∈ {-1, 0, +1}` transforma `wx` em `+x`, `0` ou `-x`, sem multiplicador convencional.
2. Explicar a NPU com 64 PEs, adder tree e acumulador INT32, distinguindo o alvo arquitetural do RTL ativo.
3. Conferir se o contrato de memória, os registradores, os pesos e os resultados são compatíveis entre RTL, driver, HAL e aplicação.
4. Separar a demonstração matemática da operação ternária da integração real no SoC LiteX, no Linux e na FPGA.
5. Definir os próximos gates para comparar acurácia, latência, área, DSPs, memória e desempenho CPU versus NPU, sem antecipar resultados não medidos.

O escopo deste apêndice é descritivo. Ele não apresenta uma correção de RTL, não apresenta benchmark e não trata uma proposta de integração como fato atual.

## 2. Legenda de evidência

| Marca | Significado nesta conversa |
|---|---|
| **Implementado** | Existe no caminho atual do código consultado. Isso não prova síntese nem execução física. |
| **Simulado** | Foi exercitado por modelo, teste C++, Python ou testbench. Isso não prova o SoC sintetizado. |
| **Documentado** | Está declarado em configuração, interface ou arquivo de projeto. Pode ainda não ter sido executado. |
| **Proposto** | Mudança sugerida para fechar uma lacuna. Não está disponível no RTL atual. |
| **Não verificado** | Não há evidência de execução ou medição no estado consultado. |

Uma mesma peça pode ter mais de uma leitura. Por exemplo, o driver está implementado como código, mas o probe em Linux na FPGA permanece não verificado.

## 2.1 Ownership operacional após Gilvan

Gilvan saiu da operação diária do projeto. A transição operacional preserva a autoria e separa continuidade histórica de responsabilidade ativa:

| Pessoa | Responsabilidade atual |
|---|---|
| **Gustavo Alexandre dos Santos** | Assumiu a continuidade da frente de Gilvan: manutenção ativa do pipeline de IA, exportação de pesos e contrato `weights.h`, regressão do Golden Model, driver, cross-compilação, coordenação da validação física, benchmarks e resultados do Paper 1. |
| **Gildo Alves de Lima Junior** | Assumiu a frente operacional de OS, HAL, classifier, MicroSD e boot Linux. |
| **Arthur Oliveira Gomes** | Responsável pelo hardware, RTL, SoC e fluxo de síntese/bitstream. |
| **Gilvan Alves Pastor Junior** | Contribuinte histórico da IA e do empacotamento; permanece como quarto autor do Paper 1. |

Essa divisão não transforma intenção em evidência: os contratos de BN/ReLU/fake quant, unidades e offsets de DMA, mapa MMIO e datapath ativo continuam sujeitos aos gates abaixo.

**Critério de fechamento:** resultados não medidos devem permanecer explicitamente marcados como pendentes; a consolidação do Paper 1 depende dos gates técnicos e experimentais.

## 3. Arquitetura atual: LiteX, VexRiscv, Wishbone, DMA, IRQ e RAM

### Visão de componentes

| Componente | Papel observado | Evidência |
|---|---|---|
| LiteX | Gera o SoC e conecta a NPU ao barramento Wishbone. | **Implementado no gerador**, hardware não verificado |
| VexRiscv | Configurado na variante `linux`, com barramento Wishbone. | **Documentado no código** |
| Wishbone slave | CPU acessa os registradores MMIO da NPU. | **Implementado no wrapper e no RTL** |
| Wishbone master | NPU inicia leituras e escritas de DMA na RAM do SoC. | **Implementado no wrapper e no RTL** |
| Driver | Faz `mmap`, configura registradores, espera a IRQ e libera o processo. | **Implementado como código**, probe não verificado |
| RAM compartilhada | Buffer coerente de DMA é mapeado para usuário e usado pelo driver. | **Implementado como código**, DDR real não verificada |
| IRQ | `irq_out` da NPU é ligado à linha 10 do PLIC no gerador LiteX. | **Documentado no SoC**, sinal físico não verificado |

No `base_soc.py`, o CPU é configurado como `vexriscv` com variante `linux` e barramento Wishbone. O wrapper cria uma interface slave para configuração e uma interface master para DMA. O contrato atual fixa a NPU em `0x80000000`, a DDR em `0x40000000` e `irq_out` na IRQ 10. A ligação física ainda aguarda o handoff Vivado e a validação na placa.

O driver aloca um buffer DMA coerente e o ioctl leva offsets em bytes para oito descritores completos. O CPU programa `INPUT_ADDR`, `OUTPUT_ADDR` e os campos de cada descritor; a memória DDR3 e o boot Linux são parte do alvo de integração, não uma execução física comprovada neste documento.

## 4. O que o top-level RTL atual realmente faz

### 4.1 Estados internos da FSM

O pacote `npu_v2_pkg.v` define **20 estados internos**, numerados de `0` a `19`, cobrindo comandos, espera de DMA, configuração de camada, compute, bias, scale, pós-processamento, saída, conclusão e erro. Essa enumeração é detalhe de implementação; não é ABI externo e não deve ser apresentada como mapa de registradores.

O fluxo nominal é controlado por um start único: o CPU programa a entrada, a saída e até oito descritores; o controlador carrega os dados, computa, aplica pós-processamento, grava as ativações ou a saída final, avança ao próximo descritor e termina com IRQ.

### 4.2 Datapath, DMA e write-back

- **PEs:** o top-level instancia 64 PEs ternários para ativações INT8 e pesos codificados em dois bits.
- **Árvore:** a redução 64→1 tem seis estágios registrados e entrega a soma parcial ao acumulador.
- **Acumulador:** um registrador escalar assinado INT32 reúne os lotes de cada neurônio.
- **Pós-processamento:** o pipeline registrado soma bias, aplica signed-scale, arredonda, desloca, limita e satura a saída.
- **Ativações:** dois buffers bancados armazenam valores INT8 e alternam entre camadas.
- **DMA:** não é burst; cada transação é um único beat Wishbone Classic, com `CTI=000`, `BTE=00`, propagação de `ERR` downstream e timeout de 256 ciclos.
- **Resultado:** a saída final é escrita por DMA; camadas ocultas retornam ao buffer de ativação oposto.

### 4.3 Organização da NPU ternária

A organização integrada é:

```text
64 ativações + 64 pesos
          ↓
       64 PEs
          ↓
      adder tree
          ↓
   acumulador INT32
```

Para cada peso `w ∈ {-1, 0, +1}`, o PE produz `-x`, `0` ou `+x`. A árvore registrada reduz os 64 resultados parciais, enquanto o acumulador escalar INT32 soma os lotes necessários para formar a saída do neurônio. Esta organização está integrada ao RTL e coberta pelos testes host-side; a implementação Vivado atual também passou o report gate em 100 MHz.

## 5. Representação dos dados e dimensões do workload

### 5.1 Pesos ternários

| Valor | Código de 2 bits |
|---:|:---:|
| `+1` | `01` |
| `0` | `00` |
| `-1` | `11` |

Cada `uint32_t` carrega 16 pesos. O peso de índice zero ocupa os bits menos significativos; o peso seguinte começa em `j * 2`. A função `pack_weights` usa exatamente essa ordem little-endian.

### 5.2 Camadas e contagens

| Camada | Entrada | Saída | Words de pesos | Words por neurônio |
|---:|---:|---:|---:|---:|
| 0 | 784 | 1024 | 50176 | 49 |
| 1 | 1024 | 512 | 32768 | 64 |
| 2 | 512 | 256 | 8192 | 32 |

Esses números descrevem dimensões e quantidade de dados a mover. São **contagens de workload**, não uma promessa de ciclos, frequência efetiva, throughput ou latência.

O datapath atual pode ser resumido como `ativações INT8 → pesos ternários empacotados → 64 PEs → árvore registrada → acumulador escalar INT32 → bias + signed-scale + round/shift + saturate → próxima ativação`. O pós-processamento e os buffers ping-pong estão implementados no RTL; o modelo treinado/exportado e a execução física são gates separados.

Os buffers de ativação do RTL têm 1024 posições INT8 assinadas por banco, indexadas por `NUM_PES`, e alternam entre camadas. Durante a acumulação, cada ativação é estendida com sinal. O contrato de exportação e os offsets do software ainda precisam ser validados end-to-end.

## 6. Controle e IRQ: realidade atual

### 6.1 Registradores expostos

O ABI atual cobre **17 registradores**, de `0x00` até `0x40`:

| Offset | Nome | Função no código atual |
|---:|---|---|
| `0x00` | `STATUS` | Busy, IRQ, done, error e camada em bits `[15:8]` |
| `0x04` | `CONTROL` | START no bit 0, CLEAR_IRQ no bit 1 |
| `0x08` | `INPUT_ADDR` | Endereço externo da primeira entrada |
| `0x0c` | `OUTPUT_ADDR` | Endereço externo do resultado INT32 final |
| `0x10` | `WEIGHT_ADDR` | Endereço de pesos do descritor selecionado |
| `0x14` | `BIAS_ADDR` | Endereço de bias INT32 do descritor |
| `0x18` | `SCALE_ADDR` | Endereço de multiplicador INT32 do descritor |
| `0x1c` | `LAYER_COUNT` | Quantidade de descritores, de 1 a 8 |
| `0x20` | `LAYER_INDEX` | Descritor selecionado pelos campos seguintes |
| `0x24` | `LAYER_INPUTS` | Quantidade de entradas do descritor |
| `0x28` | `LAYER_OUTPUTS` | Quantidade de saídas do descritor |
| `0x2c` | `LAYER_QUANT` | Shift nos bits 5:0 e ReLU no bit 8 |
| `0x30` | `RESULT` | Primeira saída final para inspeção |
| `0x34` | `RESULT_WINDOW` | Janela de acumulador do descritor selecionado |
| `0x38` | `ERROR_INFO` | Código de erro sticky |
| `0x3c` | `CAPABILITIES` | Capacidades: 8 camadas, 1024 ativações, 64 PEs |
| `0x40` | `MAC_CFG` | Configuração de 64 PEs |

Não há mapa alternativo de dez registradores. `STATUS` expõe busy/IRQ/done/error e a camada corrente em `[15:8]`; não há `zero_counter` no contrato atual. `LAYER_COUNT` seleciona de 1 a 8 descritores, e `LAYER_INDEX` escolhe qual descritor os campos de peso, bias, scale, dimensões e quantização configuram.

### 6.2 Descritores e progresso

O CPU escreve `INPUT_ADDR`, `OUTPUT_ADDR`, `LAYER_COUNT` e os campos de até oito descritores, depois escreve `CONTROL.START` uma vez. O controlador percorre os descritores configurados, alterna os buffers bancados e só devolve o resultado final à RAM externa. A enumeração interna de estados 0..19 não faz parte deste ABI.

### 6.3 IRQ

O top-level possui uma única saída `irq_out`, ligada à IRQ 10 no contrato LiteX. Ela é acionada quando a execução termina e o driver pode acordar a chamada bloqueada. A ligação física do PLIC, do driver e da DMA ainda não foi comprovada na placa.

## 7. Integração entre modelo de AI e software

### 7.1 O modelo treinado

`train_qat_mnist.py` define três blocos `QuantDense` com dimensões 784->1024, 1024->512 e 512->256. Entre eles há `BatchNormalization`, `ReLU` e `fake_quant` em 8 bits no intervalo 0..127. A rede termina com `Dense(10, activation="softmax")`.

Esse é o modelo de treinamento. O RTL atual implementa o pós-processamento fixed-point necessário ao caminho de camadas; a correspondência completa com parâmetros exportados, HAL e aplicação ainda depende de validação end-to-end.

### 7.2 O que o gerador exporta

`generate_weights_h.py` empacota objetos `QuantDense` e trata a saída `Dense` separadamente, mas não exporta os parâmetros de BatchNorm. O `weights.h` gerado consultado contém três arrays empacotados e símbolos de saída FP32:

| Array | Dimensão | Faixa inicial no header |
|---|---:|---:|
| `quant_dense_weights` | 50176 words | `weights.h:9-50193` |
| `quant_dense_1_weights` | 32768 words | `weights.h:50194-82968` |
| `quant_dense_2_weights` | 8192 words | `weights.h:82969-91169` |
| `output_weights` | 2560 FP32 symbols | presentes no header com valor fallback `0.01`; parâmetros treinados não validados |
| `output_bias` | 10 FP32 symbols | presentes no header com valor fallback `0.1`; parâmetros treinados não validados |

Não há arrays de parâmetros de BatchNorm no header consultado. Os símbolos de saída FP32 existem, mas os valores `0.01`/`0.1` são fallback e não parâmetros treinados validados. Ao mesmo tempo, `npu_weights.c` tenta copiar `output_weights` e `output_bias` para a DMA. Essa diferença precisa ser resolvida antes de uma compilação e de uma inferência ponta a ponta confiáveis.

### 7.3 O que HAL e user app fazem hoje

- O ioctl carrega offsets em bytes e oito descritores completos; o driver valida dimensões, alinhamento, footprints de pesos e compatibilidade entre camadas antes de programar o ABI MMIO.
- O RTL aplica bias, signed-scale, round/shift, clamp e saturação em seis estágios registrados e alterna os buffers bancados de ativações entre descritores. A ReLU é aplicada nas camadas ocultas; a normalização explícita da entrada e a classificação final permanecem no software.
- O exportador atual deve fornecer bias INT32 e multiplicadores por camada para que o pós-processamento use parâmetros treinados; a fixture versionada sem esses arrays usa bias zero e escala identidade.
- A camada final `256→10` e softmax continuam no classificador CPU documentado; seus parâmetros treinados e o caminho físico ainda não foram validados.

Portanto, é preciso separar o pós-processamento implementado no RTL do contrato completo de modelo e software: a presença do pipeline hardware não comprova que os pesos exportados e o fluxo físico reproduzem o modelo treinado.

### 7.4 Execução autônoma entre camadas

O top-level atual faz a saída de uma camada alimentar diretamente a próxima, sem devolver cada resultado ao fluxo de controle da CPU. O controlador usa dois buffers internos bancados em **ping-pong**:

```text
Input
  ↓
Layer 0 → Bias + signed-scale + round/shift + saturate → Buffer B
  ↓
Layer 1 → Bias + signed-scale + round/shift + saturate → Buffer A
  ↓
Layer final → Resultado
```

Enquanto um banco é escrito, o outro fornece as ativações da próxima camada. O pós-processador registrado soma bias, aplica multiplicação signed-scale, arredonda ties-away-from-zero, desloca, limita a INT32 e satura ativações ocultas para INT8. O fluxo autônomo e os buffers ping-pong são implementação atual do RTL; modelo exportado e física permanecem gates.

## 8. Status de validação

| Evidência | Leitura correta |
|---|---|
| Icarus RTL focado | **PASS:** primitivas, pós-processamento, Wishbone e top-level atual |
| Matriz top-level | **PASS:** configurações de 16, 32 e 64 PEs |
| Verilator lint matrix | **PASS:** lint nas configurações de 16, 32 e 64 PEs |
| Report gate unit tests | **PASS:** 14/14 testes unitários |
| C++ golden model v2 | **HISTÓRICO/SECUNDÁRIO:** 21/21; não é prova canônica do RTL atual |
| FPGA e benchmark | **PARCIAL:** Vivado, timing, recursos e bitstream passaram o gate; programação, boot, IRQ/DMA físicos, inferência e métricas permanecem pendentes |

Os testes Icarus focados, a matriz 16/32/64, o lint Verilator e a síntese genérica são evidência host-side do RTL. Os 14/14 testes unitários do report gate validam o checker; o Vivado atual passou o gate físico com WNS +0.065 ns, TNS 0 e 0 endpoints de setup violados. Isso ainda não comprova boot Linux, probe do driver, transferência DMA/IRQ na placa, inferência física ou benchmark real. O C++ v2 21/21 é histórico/secundário.

Artefatos históricos do Vivado são rejeitados pelo report gate: omitiram `postprocess_unit.v` e registraram WNS `-7.392 ns` e TNS `-35888.277 ns`. Esses valores são falhas históricas, não métricas atuais de produção.

No estado consultado, permanecem **não verificados**:

- programação efetiva e operação do bitstream na placa;
- boot Linux no SoC LiteX/VexRiscv alvo;
- `insmod` e probe efetivo do driver;
- IRQ e DMA funcionando na placa;
- inferência MNIST ponta a ponta com pesos gerados;
- benchmark CPU versus NPU, desempenho, potência, energia e qualquer ganho numérico.

Não há base atual para afirmar speedup, ciclos, frequência, recursos medidos, timing fechado, bitstream, inferência completa, potência ou energia.

## 9. Próximos gates mínimos e perguntas para Ramon

### Gates mínimos

1. **G1 · Report gate Vivado:** Vivado é user-run/heavy; depois executar `python3 hardware/litex_soc/check_vivado_reports.py`.
2. **G2 · Síntese e bitstream:** gerar relatório de LUTs, FFs, BRAM, DSPs e timing para a FPGA Urbana.
3. **G3 · Imagem de OS:** fechar Buildroot, MicroSD e boot Linux no SoC LiteX/VexRiscv.
4. **G4 · Contrato de camada e validação física:** validar driver, IRQ, DMA, offsets e o caminho de até oito descritores na placa.
5. **G5 · Benchmark:** medir acurácia, latência, memória e desempenho CPU versus NPU, com metodologia reproduzível.
6. **G6 · Paper 1:** consolidar resultados medidos e declarar explicitamente as pendências restantes.
7. **Contrato de pós-processamento:** alinhar bias, signed-scale, round/shift, saturação e parâmetros exportados ao modelo treinado.
8. **Regressão do caminho real:** manter a regressão Icarus, a matriz 16/32/64 e o lint Verilator como evidência canônica antes da validação física.

### Perguntas para a decisão arquitetural

- O resultado de cada camada deve voltar ao CPU para BN, ReLU e quantização, ou essas operações devem migrar para hardware?
- Uma IRQ por inferência é suficiente, ou a arquitetura precisa de interrupção por camada? Se for por camada, qual será o contrato de clear e re-start?
- `INPUT_ADDR` e `OUTPUT_ADDR` apontam para as regiões DDR definidas pelo SoC, e os oito descritores devem permanecer alinhados entre RTL, driver, HAL e aplicação?
- A saída FP32 e seus biases serão exportados pelo pipeline atual, ou a rede será alterada para eliminar essa dependência?
- O que Ramon aceitará como evidência de desempenho: simulação, síntese, medição na placa ou comparação com um baseline definido?

## 10. Índice de fontes

As faixas abaixo apontam para o código consultado, não para a apresentação histórica:

| Fonte | Trechos relevantes |
|---|---|
| `hardware/litex_soc/base_soc.py` | `34-47`, `52-115`, `121-181` |
| `hardware/npu_rtl/npu_v2_pkg.v` | `12-23`, `36-58` |
| `hardware/npu_rtl/npu_ternaria_top_v2.v` | `97-112`, `117-209`, `214-442`, `447-601` |
| `hardware/npu_rtl/ternary_mac_array.v` | `19-51` |
| `hardware/npu_rtl/adder_tree_64.v` | `21-133` |
| `ai_training/scripts/pack_weights.py` | `4-10`, `16-58` |
| `ai_training/scripts/train_qat_mnist.py` | `27-58` |
| `ai_training/scripts/generate_weights_h.py` | `45-93` |
| `software/user_app/weights.h` | `9-91169` |
| `software/npu_driver/npu_driver.c` | `54-67`, `96-164`, `190-243` |
| `software/include/npu_ioctl.h` | `20-42` |
| `software/npu_hal/npu_hal.c` | `16-91` |
| `software/npu_hal/npu_weights.c` | `6-32` |
| `software/user_app/user_app.c` | `10-70`, `98-133` |
| `hardware/npu_rtl/run_demo.sh` | `58-94` |
| `hardware/npu_rtl/sim_cpp/demo_npu_v2.cpp` | evidência histórica/secundária; não substitui a regressão Icarus canônica |
| `hardware/npu_rtl/python/golden_model.py` | `232-267` |
| `hardware/npu_rtl/tb_npu_v2.v` | `341-380` |
 | `docs/relatorios/status_atual.md` | registro histórico; não substitui a evidência canônica Icarus 16/32/64, Verilator lint, síntese genérica e 14/14 do report gate nem prova de operação na placa |

**Conclusão para a apresentação:** a contribuição atual pode ser apresentada como uma NPU ternária RTL integrada com 64 PEs, árvore registrada, acumulador escalar INT32, buffers ping-pong, pós-processamento em seis estágios registrados e controlador de até oito descritores. A evidência host-side inclui Icarus, matriz 16/32/64, lint Verilator e síntese genérica; o report gate tem 14/14 testes unitários, enquanto o Vivado atual passou em 100 MHz com WNS +0.065 ns, TNS 0 e 0 endpoints de setup violados. Programação da placa, boot, IRQ/DMA físicos, inferência, desempenho, potência e energia continuam pendentes. Gilvan saiu da operação diária, Gildo assumiu a frente de OS/HAL/boot, Gustavo assumiu a continuidade da frente de IA/driver/validação, e os créditos históricos de Gilvan permanecem preservados.
