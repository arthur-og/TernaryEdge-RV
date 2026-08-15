# Apêndice técnico para a conversa com o Professor Ramon

**Projeto:** Ternary Edge-RV
**Base:** estado atual do repositório consultado em 09/08/2026
**Uso:** handout de consulta durante a apresentação

> **Mensagem central:** o objetivo da reunião é alinhar a arquitetura esperada com a implementação atual antes de declarar desempenho, aceleração ou inferência ponta a ponta.

Este texto separa o que está implementado no código, o que foi observado em simulação, o que aparece apenas como documentação e o que ainda é proposta. Comentários antigos que descrevem uma arquitetura futura não substituem o caminho efetivamente instanciado pelo RTL.

## 1. Objetivo e escopo da conversa

1. Confirmar com Ramon qual deve ser a unidade de trabalho da NPU: uma camada por invocação, várias camadas sequenciais ou uma arquitetura com pós-processamento no hardware.
2. Conferir se o contrato de memória, os registradores, os pesos e os resultados são compatíveis entre RTL, driver, HAL e aplicação.
3. Separar a demonstração matemática da operação ternária da integração real no SoC LiteX, no Linux e na FPGA.
4. Definir os próximos gates de validação antes de medir latência, throughput, recursos ou ganho sobre a CPU.

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

No `base_soc.py`, o CPU é configurado como `vexriscv` com variante `linux` e barramento Wishbone. O wrapper cria uma interface slave para configuração e uma interface master para DMA. A NPU é adicionada como escrava em `0x40000000`, o master entra no crossbar e `irq_out` é conectado à linha 10.

O driver aloca um buffer DMA coerente de 4 MiB, mapeia esse buffer para user space e programa `SRC_ADDR` e `DST_ADDR` com o mesmo endereço físico base. A memória DDR3 e o boot Linux são parte do alvo de integração, não uma execução comprovada neste documento.

## 4. O que o top-level RTL atual realmente faz

### 4.1 Estados da FSM

O pacote `npu_v2_pkg.v` define **11 estados nomeados**:

| Código | Estado |
|---:|---|
| 0 | `ST_IDLE` |
| 1 | `ST_CFG_WEIGHT` |
| 2 | `ST_DMA_WEIGHT` |
| 3 | `ST_CFG_ACT` |
| 4 | `ST_DMA_ACT` |
| 5 | `ST_COMPUTE_BATCH` |
| 6 | `ST_NEXT_OUTPUT` |
| 7 | `ST_WRITE_RESULT` |
| 8 | `ST_LAYER_DONE` |
| 9 | `ST_NEXT_LAYER` |
| 10 | `ST_DONE` |

No top-level atual, a lógica de próxima transição não seleciona `ST_CFG_WEIGHT` nem `ST_DMA_WEIGHT`. A leitura de pesos é disparada dentro de `ST_COMPUTE_BATCH`, pelo subestado `COMPUTE_STEP_LOAD_WEIGHTS`. Portanto, a contagem de 11 estados é a definição do pacote; o caminho ativo usa os estados selecionados pela lógica de transição e os subestados de compute.

O fluxo nominal pode ser resumido assim:

```text
IDLE -> CFG_ACT -> DMA_ACT -> COMPUTE_BATCH
COMPUTE_BATCH -> WRITE_RESULT
WRITE_RESULT -> NEXT_OUTPUT -> COMPUTE_BATCH   (mais neurônios)
WRITE_RESULT -> LAYER_DONE
LAYER_DONE -> NEXT_LAYER -> CFG_ACT             (mais camadas)
LAYER_DONE -> DONE -> IRQ
```

### 4.2 Leituras, compute e write-back

- **Ativações:** `ST_CFG_ACT` dispara uma leitura DMA em `cfg_src_addr + cur_layer * 1024`, com tamanho `layer_in[cur_layer]`. `ST_DMA_ACT` distribui cada palavra recebida em quatro bytes de `act_mem`.
- **Pesos:** no subestado `COMPUTE_STEP_LOAD_WEIGHTS`, o RTL lê 16 bytes, ou quatro words, por lote. O endereço usa `wt_ram_base`, o neurônio atual e `cur_in_batch`.
- **Compute no código atual:** o bloco `COMPUTE_STEP_ACCUMULATE` percorre `m = 0..63`, decodifica o peso, acumula em `batch_acc` e atualiza `acc_reg[0]` uma vez por lote.
- **Resultado:** `ST_WRITE_RESULT` faz uma escrita DMA de 32 bits em `cfg_dst_addr + cur_output * 4`, com `dma_wdata <= acc_reg[0]`; esse write-back ainda depende da regressão Verilog não executada.
- **Próximo neurônio:** `ST_NEXT_OUTPUT` zera `acc_reg[0]`, incrementa `cur_output` e reinicia o lote de entrada.
- **Próxima camada:** `ST_LAYER_DONE` compara `cur_layer + 1` com `cfg_layer_cfg`; `ST_NEXT_LAYER` incrementa `cur_layer`.

 A versão atual do RTL já contém correções mecânicas para os três pontos anteriormente descritos como blockers de fonte: `wt_buf_idx` foi ampliado para alcançar `3'd4`; os consumidores de dados usam diretamente `wb_m_dat_i` no pulso válido de DMA; e a acumulação do lote usa uma variável temporária `batch_acc` antes de atualizar `acc_reg[0]`. Essas mudanças são evidência de inspeção do código-fonte. O runtime/testbench Verilog ainda não foi executado neste ambiente por indisponibilidade das ferramentas, portanto não se deve chamar o caminho de RTL de validado em execução.

Mesmo com essas correções mecânicas no código-fonte, o caminho não deve ser descrito como uma matriz integrada de 64 MACs. `ternary_mac_array.v` e `adder_tree_64.v` existem como módulos separados e são incluídos na lista de fontes do LiteX, mas não há instanciação desses módulos no corpo de `npu_ternaria_top_v2.v`. O top-level usa um loop procedural sobre 64 posições e uma variável temporária `batch_acc`; isso ainda não comprova uma redução de 64 termos em hardware paralelo. Não há base no RTL atual para afirmar 64 MACs integrados por ciclo, lote de um ciclo ou throughput específico.

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

O buffer de ativação do RTL tem 1024 posições de 8 bits. Durante a acumulação, cada ativação é estendida com sinal. O código do user app lê 784 bytes e a HAL copia a imagem para o offset `0x5C000`; isso não coincide automaticamente com a origem que o driver programa para o RTL. O contrato final de ativação precisa ser decidido e testado.

## 6. Controle e IRQ: realidade atual

### 6.1 Registradores expostos

O mapa atual cobre `0x00` até `0x2c`:

| Offset | Nome | Função no código atual |
|---:|---|---|
| `0x00` | `STATUS` | Busy, IRQ e contador de zeros; bits 7:2 permanecem zero no caminho atual |
| `0x04` | `CONTROL` | Start no bit 0, clear no bit 1 |
| `0x08` | `SRC_ADDR` | Base de leitura DMA |
| `0x0c` | `DST_ADDR` | Base de escrita DMA |
| `0x10` | `DMA_SIZE` | Configuração armazenada |
| `0x14` | `WEIGHT_CFG` | Configuração armazenada |
| `0x18` | `ACT_CFG` | Configuração armazenada |
| `0x1c` | `RESULT` | Último `acc_reg[0]` capturado em `ST_DONE` |
| `0x20` | `MAC_CFG` | Configuração armazenada |
| `0x24` | `LAYER_CFG` | Número de camadas usado pela progressão |
| `0x28` | `RESULT_WINDOW` | Leitura de `acc_reg` indexado |
| `0x2c` | `LAYER_CTRL` | Bit 0 de `irq_per_layer` e bits 5:0 de `result_window_idx` |

Embora vários registradores sejam escritos pelo driver, as dimensões efetivas vêm dos arrays fixos `layer_in`, `layer_out` e `layer_wcnt`. O caminho atual não usa `LAYER_CTRL` para escolher uma camada. O IOCTL documenta `dma_size` como bytes, enquanto a HAL passa a soma das quantidades de words empacotados; essa unidade precisa ser fechada.

### 6.2 `cur_layer` e progresso

Em toda escrita de start reconhecida no estado `ST_IDLE`, o RTL executa `cur_layer <= 32'd0`. Em um único start, `LAYER_CFG` pode permitir a progressão 0, 1, 2 dentro da FSM. Em starts separados, não existe hoje um campo implementado que selecione diretamente a camada 1 ou 2.

`layer_override` é uma **proposta**, não um recurso atual. Para existir, seria necessário definir os bits no contrato de `LAYER_CTRL`, alterar o RTL para usar esse valor no start e atualizar o driver/HAL. O documento não trata essa alteração como implementada.

### 6.3 IRQ

O top-level possui uma única saída `irq_out`. Ela é acionada em `ST_DONE` e o driver acorda a chamada bloqueada após a interrupção. `irq_per_layer` aparece no registrador, mas não é consultado pela lógica atual para gerar interrupções intermediárias. Assim, não é correto apresentar três IRQs por inferência como fato atual.

## 7. Integração entre modelo de AI e software

### 7.1 O modelo treinado

`train_qat_mnist.py` define três blocos `QuantDense` com dimensões 784->1024, 1024->512 e 512->256. Entre eles há `BatchNormalization`, `ReLU` e `fake_quant` em 8 bits no intervalo 0..127. A rede termina com `Dense(10, activation="softmax")`.

Esse é o modelo de treinamento. Não significa que as mesmas operações estejam presentes no top-level RTL, no HAL ou no user app.

### 7.2 O que o gerador exporta

`generate_weights_h.py` filtra somente objetos `QuantDense`. O `weights.h` gerado consultado contém três arrays empacotados:

| Array | Dimensão | Faixa inicial no header |
|---|---:|---:|
| `quant_dense_weights` | 50176 words | `weights.h:9-50193` |
| `quant_dense_1_weights` | 32768 words | `weights.h:50194-82968` |
| `quant_dense_2_weights` | 8192 words | `weights.h:82969-91169` |

Não há arrays de parâmetros de BatchNorm nem arrays de saída FP32 no header consultado. Ao mesmo tempo, `npu_weights.c` tenta copiar `output_weights` e `output_bias` para a DMA. Essa diferença precisa ser resolvida antes de uma compilação e de uma inferência ponta a ponta confiáveis.

### 7.3 O que HAL e user app fazem hoje

- `npu_hal.c` abre `/dev/npu_ternaria`, faz `mmap`, carrega pesos e chama um único `ioctl` com `layer_cfg = 3`.
- A HAL não aplica BatchNorm, ReLU ou fake quant entre camadas. Ela também lê os 256 resultados a partir de `ctx->dma_buffer[i]`, enquanto o próprio código de cópia de entrada usa `0x5C000`.
- `npu_weights.c` usa pesos ternários em `0x1000`, saída FP32 em `0x5C400` e bias em `0x5E800`. O driver, porém, configura `SRC_ADDR` e `DST_ADDR` como o mesmo endereço físico base.
- `user_app.c` tem um modo CPU que executa os três produtos ternários diretamente, mas passa `layer0_out` e `layer1_out`, que são `int32_t`, como `uint8_t *`. Também não há BN, ReLU ou fake quant nesse caminho.
- A chamada a `classifier_run` existe, mas a cadeia completa de dados que deveria produzir uma entrada correta de 256 valores ainda não está validada.

Por isso, não é correto chamar o HAL ou o user app de implementação de BatchNorm, ReLU e quantização inter-layer. Essas operações estão no modelo treinado, não no fluxo atual de software de inferência.

## 8. Status de validação

| Evidência | Leitura correta |
|---|---|
| C++ golden model v2 | **PASS:** 21/21 casos executados |
| Runtime/testbench RTL Verilog | **NÃO EXECUTADO:** ferramentas indisponíveis no ambiente consultado |
| Contrato HAL/weights | **ABERTO:** exportação, símbolos, transforms, offsets e unidades ainda não fecham |
| FPGA e benchmark | **PENDENTES:** síntese, timing, boot, IRQ/DMA físicos, inferência e métricas ainda não executados |

O resultado C++ v2 de 21/21 casos é evidência de simulação host-side. Ele não comprova execução do RTL Verilog, síntese, fechamento de timing, recursos reais, boot Linux, probe do driver, transferência DMA no hardware, inferência física ou benchmark real.

No estado consultado, permanecem **não verificados**:

- execução do runtime/testbench Verilog do patch atual;
- síntese e relatório de recursos da FPGA;
- bitstream carregado na placa;
- boot Linux no SoC LiteX/VexRiscv alvo;
- `insmod` e probe efetivo do driver;
- IRQ e DMA funcionando na placa;
- inferência MNIST ponta a ponta com pesos gerados;
- benchmark CPU versus NPU e qualquer ganho numérico.

Não há base atual para afirmar 9,3x de speedup, 64 MACs por ciclo, uma carga de um ciclo, recursos medidos ou inferência completa.

## 9. Próximos gates mínimos e perguntas para Ramon

### Gates mínimos

1. **Contrato do datapath:** decidir se o caminho ativo continuará no loop procedural que atualiza `acc_reg[0]` ou se `ternary_mac_array.v` e `adder_tree_64.v` serão realmente integrados e conectados.
2. **Contrato de camada:** decidir entre um start por camada e um sequenciador autônomo. Se a primeira opção for escolhida, especificar e implementar `layer_override`.
3. **Contrato de memória:** fixar offsets para ativações, pesos e resultados e alinhar RTL, driver, HAL e aplicação em um único mapa testável.
4. **Contrato de pós-processamento:** exportar BN e saída FP32, implementar BN/ReLU/fake quant no software, ou alterar o modelo para uma forma compatível com o hardware escolhido.
5. **Executar e testar a FSM/DMA:** executar a regressão Verilog do patch atual, cobrindo o loader de pesos, os dados DMA, a acumulação com `batch_acc` e o write-back por neurônio.
6. **Regressão do caminho real:** exercitar o top-level RTL corrigido com vetores não nulos, sem depender apenas do simulador C++.
7. **Validação física:** sintetizar, gerar bitstream, inicializar Linux, fazer probe do driver, testar IRQ/DMA e só então medir a inferência.

### Perguntas para a decisão arquitetural

- O resultado de cada camada deve voltar ao CPU para BN, ReLU e quantização, ou essas operações devem migrar para hardware?
- Uma IRQ por inferência é suficiente, ou a arquitetura precisa de interrupção por camada? Se for por camada, qual será o contrato de clear e re-start?
- `SRC_ADDR` aponta para o início das ativações, para o início do bloco de pesos ou para um descritor? O mapa deve ser único para RTL e software.
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
| `hardware/npu_rtl/sim_cpp/demo_npu_v2.cpp` | `8-16`, `34-41`, `236-256` |
| `hardware/npu_rtl/python/golden_model.py` | `232-267` |
| `hardware/npu_rtl/tb_npu_v2.v` | `341-380` |
| `docs/relatorios/status_atual.md` | registro histórico de simulação; não substitui a evidência atual de 21/21 no C++ v2 nem prova física |

**Conclusão para a apresentação:** a contribuição atual pode ser apresentada como uma base RTL com correções de fonte, evidência C++ v2 de 21/21 casos e software parcialmente integrado, com lacunas explícitas no contrato de camadas, pós-processamento e memória. O runtime Verilog ainda não foi executado, e qualquer afirmação de desempenho deve esperar a arquitetura ser alinhada e o fluxo ser validado na implementação física.
