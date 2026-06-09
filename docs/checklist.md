📌 CHECKLIST OFICIAL DO PROJETO: TERNARY EDGE-RV 📌
⚠️ ÚLTIMA ATUALIZAÇÃO: 09/06/2026 — Fases do Gildo corrigidas (Plano_Gildo.md), toolchain por build próprio (cada um compila a sua, sem Drive), módulo npu_ternaria_top.v atualizado

Regra de Ouro do Grupo:
⚠️ [BLOQUEIO]: Se você precisa de algo de outro membro para continuar.
🛠️ [MOCK]: Se alguém te bloqueou, invente um dado falso (Mock), avise no grupo e continue programando. Não espere!

=======================================
🟢 FASE 1: FUNDAMENTAÇÃO E EMULAÇÃO
⏳ Prazo: Semanas 1 a 3 (Duração: 21 dias)
🎯 Objetivo: Todo mundo trabalhando sozinho e validando as ferramentas base.

Arthur (Hardware):
[ X ] Instalar dependências do LiteX e Python no PC.
[ X ] Gerar o SoC básico com o núcleo VexRiscv (variante linux, estritamente RV32IMA).
[ ] Sintetizar o SoC e testar na placa física (Piscar LED ou Hello World via UART em bare-metal).
[ X ] ⚠️ ENTREGAR MAPA DE MEMÓRIA (MOCK): Definir e compartilhar na Fase 1 o Esboço dos Endereços Base (ex: 0x40000000), Offsets (STATUS, CONTROL, SRC_ADDR, DST_ADDR, SIZE), e o número do pino de Interrupção (IRQ=10) da NPU.
[ X ] Definir e formalizar o Endianness (Little-Endian) para o empacotamento dos pesos.
[ X ] docs/arquitetura/mapa_de_memoria.md — Documento oficial criado.
[ X ] hardware/litex_soc/requisitos_fpga.md — Requisitos mínimos para o professor.

Status REAL: ✅ Fase 1 quase completa (falta placa física). Fase 2 também concluída (RTL da NPU).

Gildo (Sistema Operacional):
[ X ] Instalar e configurar o Buildroot no PC. [External tree criada]
[ X ] Selecionar a arquitetura RISC-V (RV32IMA) no make menuconfig. [ternaryedge_rv_defconfig]
[ X ] Compilar imagem genérica e conseguir dar boot no kernel via emulador QEMU.
[ X ] ⚠️ ENTREGAR TOOLCHAIN riscv32-buildroot-linux-gnu-gcc para Gustavo e Gilvan. [Buildroot SDK — cada um compila a sua]

Status REAL: ✅ Fase 1 completa. Toolchain disponível via build próprio do Buildroot (ver software/os_buildroot/README.md).

Gustavo (Driver de Kernel):
[ X ] Criar ambiente de compilação de módulos (LKM).
[ X ] Escrever código C do driver "Hello World" com <linux/module.h>.
[ X ] Compilar o driver e testar os comandos insmod, lsmod e rmmod no QEMU.
[ X ] 🚀 AVANÇADO: Já implementou Platform Driver com Device Tree match, DMA Coherent, IRQ, mmap, wait_queue.

Status REAL: ✅ Fase 1 + Fase 2 + Fase 3 (parcial) concluídas. Driver em nível de produção.

Gilvan (Inteligência Artificial):
[ X ] Montar ambiente Python e instalar biblioteca de quantização (Larq).
[ X ] Treinar Rede Neural Ternária (TNN) estilo MLP usando o dataset MNIST.
[ X ] Validar precisão >95% certificando-se de que os pesos são restritos a -1, 0 e 1.
[ X ] Sparsity L1 implementada (regularização forcing zeros).
[ X ] Fake quantization INT8 entre camadas ativada.

Status REAL: ✅ Fase 1 completa. ⚠️ Gap: camada de saída está em FP32 (softmax), não ternária.

=======================================
🟡 FASE 2: CONFIGURAÇÃO E EXPORTAÇÃO
⏳ Prazo: Semanas 4 a 7 (Duração: 28 dias)
🎯 Objetivo: Criação das pontes de comunicação. O trabalho de um começa a afetar o outro.

Arthur (Hardware):
[ X ] Escrever o código Verilog da NPU Ternária (Apenas Somadores, Subtratores e Mux. ZERO multiplicadores).
[ X ] Implementar pino de interrupção (IRQ) em hardware para sinalizar quando a NPU terminar a inferência, para evitar Polling que consome energia.
[ X ] ternary_mac.v — MAC multiplierless com entradas INT8×ternário.
[ X ] npu_ternaria_top.v — Módulo completo com Wishbone Slave + FSM real + memórias internas + IRQ.

Status REAL: ✅ Fase 2 completa. Próximo passo: controlador DMA Master para ler RAM diretamente.

Gildo (Sistema Operacional):
[ X ] Configurar Buildroot para gerar a Cross-Compiler Toolchain estritamente para 32 bits (riscv32-buildroot-linux-gnu-gcc ou equivalente, usando -march=rv32ima -mabi=ilp32).
[ X ] ⚠️ ENTREGAR TOOLCHAIN para o Gustavo e Gilvan. [Buildroot SDK — cada um compila a sua, ver README]
[ X ] Habilitar temporizadores de alta resolução no Kernel (CONFIG_HIGH_RES_TIMERS).

Status REAL: ✅ Toolchain configurada no Buildroot + HIGH_RES_TIMERS ativado. Cada membro compila a sua (ver software/os_buildroot/README.md).

Gustavo (Driver de Kernel):
[ X ] Usar register_chrdev para criar o dispositivo /dev/npu_ternaria.
[ X ] Criar a struct file_operations (.mmap, .unlocked_ioctl, .open, .release).
[ X ] 🛠️ MOCK: Como o Arthur não tinha o mapa no início, usou endereço 0x40000000 no QEMU e continuou.
[ X ] Já fez a injeção do DT virtual no QEMU para testar o driver sem FPGA.
[ X ] Já implementou: dma_alloc_coherent(), dma_mmap_coherent(), ioremap(), request_irq(), wait_queue.

Status REAL: ✅ Fase 2 totalmente completa e extrapolada para Fase 3.

Gilvan (Inteligência Artificial):
[ X ] Fazer script Python para ler os pesos ternários gerados na Fase 1. [pack_weights.py]
[ X ] Empacotar 16 pesos (de 2-bits) dentro de blocos uint32_t (Little-Endian). [pack_weights.py]
[ X ] Exportar o arquivo automático weights.h em código C. [generate_weights_h.py → weights.h gerado!]
[ X ] 3 layers ternárias exportadas: quant_dense (784→1024, 50176 words), quant_dense_1 (1024→512, 32768 words), quant_dense_2 (512→256, 8192 words).
[ X ] Total: 91.136 words = 364 KB de pesos compactados.

Status REAL: ✅ Fase 2 completa.

=======================================
🟠 FASE 3: LÓGICA E INTEGRAÇÃO (O GARGALO)
⏳ Prazo: Semanas 8 a 13 (Duração: 42 dias) -> Fase mais longa e difícil!
🎯 Objetivo: Fazer os 4 mundos conversarem. Muito debug e Kernel Panic previstos.

Arthur (Hardware):
[ ] Conectar a NPU como Wishbone Master (DMA) no barramento principal do LiteX para ler RAM automaticamente.
[ ] Substituir FSM dummy do npu_ternaria_top.v por controlador real de layers (Layer Sequencer).
[ ] Criar Testbench no Verilator simulando o barramento injetando dados da NPU.

Gildo (Sistema Operacional):
[ ] ⚠️ Escrever o arquivo .dts (Device Tree) criando o "node" da NPU com o endereço base (0x40000000) e o pino de interrupção (IRQ=10) que o Arthur passou.

Status REAL: ⏳ .dts pendente — depende do mapa de memória oficial do Arthur.

Gustavo (Driver de Kernel):
[ X ] ioremap() — JÁ IMPLEMENTADO via devm_ioremap_resource() no probe.
[ ] copy_from_user() + writel() — Driver atual usa DMA (mmap), não copy_from_user. Precisa-se verificar se a interface IOCTL está completa.
[ X ] request_irq() — JÁ IMPLEMENTADO via devm_request_irq() com IRQF_SHARED.
[ X ] wait_event_interruptible() — JÁ IMPLEMENTADO no ioctl NPU_IOCTL_START_INFERENCE.

Status REAL: 🚀 Gustavo está muito adiantado. Quase tudo da Fase 3 já feito no driver.

Gilvan (Inteligência Artificial):
[ ] Escrever a Aplicação user_app.c completa: incluir o weights.h, ler imagem do SD, e abrir o /dev/npu_ternaria.
[ ] Fazer a medição de tempo segregada: 1) Tempo movendo dados para o driver, 2) Tempo de inferência, 3) Tempo de retorno dos resultados.
[ ] 🛠️ MOCK: Não espere o Driver nem a NPU. Faça a função calcular a rede na CPU (software puro) e meça o tempo com <sys/time.h>.

Status REAL: ⏳ dummy_app.c existe (esqueleto criado pelo Gustavo). Gilvan precisa implementar a lógica real de inferência (forward pass C+weights.h).

=======================================
🔴 FASE 4: DEPLOY FÍSICO E ARTIGO
⏳ Prazo: Semanas 14 a 16 (Duração: 21 dias)
🎯 Objetivo: Rodar no silício real, extrair os tempos e escrever.

Arthur (Hardware):
[ ] Sintetizar o SoC final + NPU, fechar Timing e gravar o Bitstream na FPGA.
[ ] Extrair relatório de síntese (Comprovar 0 blocos DSP usados, anotar LUTs e FFs).

Gildo (Sistema Operacional):
[ ] Adicionar suporte a FAT32/ext4 no RootFS do Linux.
[ ] Gravar a imagem final do Linux no SD Card/Flash e bootar na placa física.

Gustavo (Driver de Kernel):
[ ] Dar o insmod do driver na placa física.
[ ] Verificar os logs usando o comando dmesg para garantir que o kernel não deu Page Fault ao acessar a NPU física.

Gilvan (Inteligência Artificial):
[ ] Executar a inferência completa de imagens de teste direto na placa.
[ ] Salvar os milissegundos em um arquivo .csv provando que a NPU bateu a CPU.

TRABALHO EM EQUIPE (ARTIGO):
[ ] Gilvan e Gildo: Gerar gráficos de tempo (Tempo CPU vs Tempo NPU).
[ ] Arthur: Escrever sobre a arquitetura Multiplierless.
[ ] Gustavo: Escrever sobre o fluxo de memória (MMIO e Overhead).
[ ] Todos: Abstract, Introdução e Conclusão.
