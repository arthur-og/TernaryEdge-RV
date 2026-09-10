# Mapa de Memória e Integração (NPU Ternária v2)

**Status:** Contrato de integração atual (24/08/2026)
**Autor:** Arthur Oliveira Gomes (Hardware)
**Destinado atualmente a:** Gustavo (Driver, weights.h, compilação cruzada e validação)

Este documento registra o contrato atual da NPU v2. A integração usa NPU MMIO
em `0x80000000`.

DDR usa `0x40000000`. IRQ é 10 e o formato é little endian. Essas regiões são
distintas.

---

## 1. Parâmetros Globais

| Parâmetro | Valor |
|:----------|:------|
| Arquitetura Alvo | RISC-V RV32IMA |
| Endianness | Little endian (LSB = primeiro peso) |
| Barramento | Wishbone B4 (32 bits dados, 32 bits endereço) |
| Endereço Base NPU MMIO | `0x8000_0000` |
| Endereço Base DDR | `0x4000_0000` |
| Tamanho da Região | 64 KiB (`0x10000`) |
| IRQ | 10 (conectado ao PLIC do VexRiscv) |

---

## 2. Mapa de Registradores (MMIO)

| Offset | Nome | Permissão | Descrição Detalhada |
|:-------|:-----|:-----------|:--------------------|
| `0x00` | `STATUS` | RO | bit 0 busy, bit 1 IRQ, bit 2 done, bit 3 error, layer em bits 15:8 |
| `0x04` | `CONTROL` | WO | bit 0 START, bit 1 CLEAR_IRQ |
| `0x08` | `INPUT_ADDR` | RW | Endereço externo da primeira entrada |
| `0x0C` | `OUTPUT_ADDR` | RW | Endereço externo do resultado INT32 final |
| `0x10` | `WEIGHT_ADDR` | RW | Endereço de pesos empacotados do descritor selecionado |
| `0x14` | `BIAS_ADDR` | RW | Endereço de bias INT32; zero significa bias 0 |
| `0x18` | `SCALE_ADDR` | RW | Endereço de multiplicadores INT32; zero significa escala 1 |
| `0x1C` | `LAYER_COUNT` | RW | Quantidade de descritores, de 1 a 8 |
| `0x20` | `LAYER_INDEX` | RW | Descritor selecionado pelos registradores seguintes |
| `0x24` | `LAYER_INPUTS` | RW | Quantidade de entradas da camada selecionada |
| `0x28` | `LAYER_OUTPUTS` | RW | Quantidade de saídas da camada selecionada |
| `0x2C` | `LAYER_QUANT` | RW | Deslocamento nos bits 5:0, ReLU no bit 8 |
| `0x30` | `RESULT` | RO | Primeira saída final para inspeção rápida |
| `0x34` | `RESULT_WINDOW` | RO | Janela de acumulador indexada pelo descritor selecionado |
| `0x38` | `ERROR_INFO` | RO | Código de erro sticky |
| `0x3C` | `CAPABILITIES` | RO | `0x00080440`: 8 camadas, 1024 ativações, 64 PEs |
| `0x40` | `MAC_CFG` | RW | Deve ser 64; reservado para modos mais estreitos |

Este é o ABI MMIO de 17 registradores, de `0x00` até `0x40`. Não há mapa
alternativo de dez registradores. A janela LiteX/Device Tree reserva 64 KiB;
qualquer offset não listado dentro dessa janela recebe `ERR` Wishbone e não
faz alias com os registradores válidos.

No Device Tree físico protegido, o valor efetivo `reg = <0x80000000
0x10000>` é a fonte de verdade para a abertura de 64 KiB. O comentário legado
que ainda menciona 4 KB nesse arquivo é apenas texto stale e não altera o
contrato ou o valor compilado; sua correção fica no handoff documental de
Gildo, sem editar o Device Tree nesta frente de Arthur.

---

## 3. Fluxo de Operação Típico

```
1. CPU prepara buffer em DDR com pesos empacotados e ativações INT8.
2. Driver programa INPUT_ADDR, OUTPUT_ADDR e os oito descritores possíveis.
3. Driver escreve START em CONTROL.
4. A NPU emite requisições DMA Wishbone Classic de um beat, com CTI=000 e BTE=00.
5. Cada requisição permanece estável até ACK ou ERR. Sem resposta por 256 ciclos, a NPU gera erro de timeout.
6. Os dados locais alimentam 64 PEs ternários e uma árvore registrada 64 para 1.
7. Um acumulador escalar INT32 e o pós-processador registrado de três estágios produzem o valor da camada.
8. A NPU alterna os buffers de ativação bancados e avança pelos descritores configurados.
9. A NPU escreve o resultado final em OUTPUT_ADDR e afirma irq_out.
10. O driver é interrompido, acorda user_app e limpa IRQ.
```

### Contrato de escrita do resultado final (DMA)

A camada final escreve o resultado assim:

- A NPU escreve **um word de 32 bits por neurônio de saída** via DMA single
  beat, com `we=1`, `sel=4'b1111` no endereço `OUTPUT_ADDR + 4*i` para o
  neurônio `i`. O word contém o resultado signed INT32 saturado do
  pós-processador, em **little endian**.
- Não há `stride` nem `padding` entre os resultados: são gravados como um
  array C contíguo de `int32_t[]` no offset configurado de `OUTPUT_ADDR`.
- O acumulador (`acc_reg`) é declarado como `reg signed [31:0]`. Valores
  negativos são válidos e aparecem no resultado final. A HAL deve tratar o
  buffer como `int32_t`, não `uint32_t`.
- O driver deve validar `output_count * 4 <= NPU_DMA_BUFFER_SIZE` antes de
  programar o endereço de saída, para impedir escrita fora do buffer.

Para a rede de produção `784->1024->512->256`, isso dá exatamente 256 palavras
de 32 bits de saída, escritas em 1024 bytes contíguos. Exemplo do caso de teste
canônico: neurônios 0..254 produzem `65024` (`0x0000FE00`), e o neurônio 255
produz `-65024` (`0xFFFF0200`, com sinal). O valor `0xFFFFFC00` (que
corresponderia a `-1024`) não é produzido pelo caso de teste.

## 4. Datapath Atual

O caminho dos PEs é multiplierless: a codificação ternária seleciona zero,
entrada ou entrada negada por multiplexação. A árvore 64 para 1 tem seis
estágios registrados. O acumulador é um único registrador escalar INT32 para a
saída em processamento. Os dois buffers de ativação são bancos indexados por
`NUM_PES`.

O pós-processador tem três estágios registrados. Ele soma bias INT32, calcula
um produto assinado de 65 bits com o multiplicador inteiro de escala, arredonda
empates para longe de zero, desloca, limita a INT32 e satura ativações ocultas
para INT8. Portanto, a requantização usa intencionalmente multiplicação inteira
assinada, mesmo que o caminho ternário dos PEs seja multiplierless.

O DMA não é burst. É um mestre Wishbone Classic de beat único, com propagação
de `ERR` downstream e timeout de 256 ciclos.

---

## 5. Codificação dos Pesos (2-bit Ternary)

| Valor | Codificação | Interpretação |
|:------|:------------|:--------------|
| `+1` | `0b01` | Soma a entrada ao acumulador |
| `0` | `0b00` | Entrada é descartada (zero-skipping) |
| `-1` | `0b11` | Entrada é subtraída do acumulador |

**Ordem de empacotamento:** `weights[0]` ocupa os bits `[1:0]` da palavra (LSB). `weights[15]` ocupa `[31:30]` (MSB). Little endian consistente.

---

## 6. Interrupção (IRQ)

- **Pino:** `irq_out` da NPU → controlador PLIC do VexRiscv
- **Contrato:** `irq_out` sobe quando a inferência completa e o resultado é escrito em `OUTPUT_ADDR`. A execução física ainda não foi comprovada.
- **Driver:** `devm_request_irq(npdev->irq, npu_irq_handler, IRQF_SHARED, ...)`. Handler faz `wake_up_interruptible(&npdev->wait_queue)`.

## 7. Verificação e Handoff

Os comandos canônicos de host são executados a partir da raiz do repositório:

```sh
make -C hardware/npu_rtl test
make -C hardware/npu_rtl test_matrix
make -C hardware/npu_rtl lint_matrix
python3 -m unittest hardware.litex_soc.test_check_vivado_reports
```

O gate de relatórios Vivado é executado após o fluxo Vivado:

```sh
python3 hardware/litex_soc/check_vivado_reports.py
```

Vivado é o fluxo final de produção. openXC7 é apenas corroboração opcional no
host. Recursos, timing, bitstream, IRQ/DMA físico e desempenho continuam
pendentes. Os comandos de síntese e implementação são procedimentos de
handoff, não execuções declaradas.

Artefatos históricos do Vivado são stale e rejeitados pelo gate. Eles omitiram
`postprocess_unit.v` e registraram WNS `-7.392 ns` e TNS `-35888.277 ns`.
