# Plano de Trabalho - Gilvan Alves Pastor Junior
**Papel no Projeto:** Artificial Intelligence & User Space (QAT, C Application, Benchmarking)

---

## Fase 1: Fundamentação, Quantização Extrema e Esparsidade

Antes da implementação, o modelo requer compreensão de técnicas avançadas de TinyML para Redes Neurais Ternárias (TNN).
- **Adoção de QAT e Quantização de Ativações:** Além de restringir pesos a {-1, 0, 1} usando o Straight-Through Estimator (STE), a rede também deverá quantizar os dados de entrada e as saídas das camadas ocultas (Ativações) para formatos inteiros (ex: int8). Isso é crucial para que o hardware não necessite de somadores de ponto flutuante.
- **Treinamento Orientado à Esparsidade (Sparsity-Driven QAT):** O treinamento deve ser modificado para maximizar o número de pesos com valor 0. O desenvolvedor deverá implementar uma Função de Perda Customizada (Custom Loss) ou Regularização L1 agressiva para forçar extrema esparsidade na rede (alvo: > 80% de zeros) sem perder a acurácia de 95% no MNIST.

## Fase 2: Implementação e Treinamento do Modelo

O treinamento da rede não exige o desenvolvimento de algoritmos de quantização do zero. Recomenda-se a utilização de frameworks já estabelecidos na literatura acadêmica e na indústria. O desenvolvimento pode seguir por uma de duas vias principais:
- **Opção A:** Framework Larq (Ecossistema Keras / TensorFlow)
- **Descrição:** Biblioteca Open Source construída sobre o TensorFlow, dedicada a Redes Binárias (BNNs) e Ternárias (TNNs). Destaca-se pela facilidade de implementação.
- **Implementação:** Substituição das chamadas tradicionais tf.keras.layers.Dense pela sua contraparte quantizada larq.layers.QuantDense, procedendo com a parametrização do quantizador ternário para os pesos da respectiva camada.
- **Opção B:** Framework Brevitas (Ecossistema PyTorch)
- **Descrição:** Ferramenta avançada para pesquisa, com foco em integração de modelos quantizados em FPGAs. Costuma ser o padrão em publicações da área.
- **Implementação:** Utilização da classe qnn.QuantLinear, configurando a precisão dos pesos (weight_bit_width=2) e o algoritmo de quantização para o comportamento ternário.
- **Especificações do Modelo e Entregável:** O treinamento será realizado utilizando o dataset MNIST, padronizando um vetor de entrada de tamanho 784 (referente às dimensões 28x28 achatadas). O artefato resultante desta fase deve ser um script Python capaz de treinar o modelo até atingir uma acurácia mínima de 95%, garantindo que os pesos da rede operem exclusivamente no conjunto de valores {-1, 0, 1}.

## Fase 3: Extração de Pesos e Empacotamento (Interface Python/C)

Para a execução de inferência diretamente no sistema embarcado (Bare-Metal Inference), sem a sobrecarga de bibliotecas como o TFLite, os dados treinados precisam ser processados e empacotados. O seguinte pipeline deve ser implementado via script Python: 1. Extração dos Tensores: As matrizes de pesos resultantes do treinamento devem ser extraídas das camadas da rede. Estes valores estatísticos devem ser rigorosamente mapeados e forçados para os números inteiros correspondentes (-1, 0 e 1). 2. Codificação Binária: A representação dos três valores deve ser definida em um formato de 2 bits. Exemplo de codificação sugerida:
- 00 representa o valor numérico 0.
- 01 representa o valor numérico 1.
- 11 representa o valor numérico -1 (representação baseada em complemento de 2). 3. Algoritmo de Empacotamento (Packing): Tendo em vista a otimização de banda de memória em um barramento de 32 bits (ou 64 bits), o envio unitário de pesos de 2 bits é ineficiente. O algoritmo deve agregar 16 pesos de 2 bits por vez, empregando operações de deslocamento de bits (shift bitwise <<) para compor um único registrador do tipo inteiro sem sinal de 32 bits (uint32_t). 4. Exportação do Arquivo Header (weights.h): O script deve serializar o conjunto empacotado em um arquivo textual formatado no padrão da linguagem C, resultando em estruturas de dados prontas para compilação. C // weights.h gerado automaticamente const uint32_t layer1_weights[] = { 0x4F0A11B2, 0x99C2001F, ... };

## Fase 4: Simulador Bit-Accurate, Firmware Bare-Metal e Inferência

A etapa final contempla a codificação de simuladores e programas em C otimizados para manipulação de bits.
- **Simulador Bit-Accurate e Contador de Ciclos:** Criação de um emulador da NPU em linguagem C puríssimo para o User Space. Este código fará o desempacotamento lógico via bitwise shifts e deve incluir contadores de performance que relatem quantas somas foram evitadas graças ao zero-skipping. O resultado deste simulador servirá como o "Golden Model" para o projeto de hardware.
- **Firmware Bare-Metal para Validação RTL:** O desenvolvedor de IA também escreverá o firmware em C de baixo nível (sem Sistema Operacional) que rodará no emulador Verilator para injetar dados nos endereços físicos do barramento Wishbone/AXI, validando o design lógico da placa antes da mesma existir fisicamente.
