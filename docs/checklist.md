📌 CHECKLIST OFICIAL DO PROJETO: TERNARY EDGE-RV 📌

Regra de Ouro do Grupo:
⚠️ [BLOQUEIO]: Se você precisa de algo de outro membro para continuar.
🛠️ [MOCK]: Se alguém te bloqueou, invente um dado falso (Mock), avise no grupo e continue programando. Não espere!

=======================================
🟢 FASE 1: FUNDAMENTAÇÃO E EMULAÇÃO
⏳ Prazo: Semanas 1 a 3 (Duração: 21 dias)
🎯 Objetivo: Todo mundo trabalhando sozinho e validando as ferramentas base.

Arthur (Hardware):
[ ] Instalar dependências do LiteX e Python no PC.
[ ] Gerar o SoC básico com o núcleo VexRiscv (variante linux, estritamente RV32IMA).
[ ] Sintetizar o SoC e testar na placa física (Piscar LED ou Hello World via UART em bare-metal).
[ ] ⚠️ ENTREGAR MAPA DE MEMÓRIA (MOCK): Definir e compartilhar na Fase 1 o Esboço dos Endereços Base (ex: 0x80000000), Offsets, e o número do pino de Interrupção (IRQ) da NPU.
[ ] Definir e formalizar o Endianness (ex: Little-Endian) para o empacotamento dos pesos.

Gildo (Sistema Operacional):
[ ] Instalar e configurar o Buildroot no PC.
[ ] Selecionar a arquitetura RISC-V (RV32IMA) no make menuconfig.
[ ] Compilar imagem genérica e conseguir dar boot no kernel via emulador QEMU.

Gustavo (Driver de Kernel):
[ ] Criar ambiente de compilação de módulos (LKM).
[ ] Escrever código C do driver "Hello World" com <linux/module.h>.
[ ] Compilar o driver e testar os comandos insmod, lsmod e rmmod no QEMU.

Gilvan (Inteligência Artificial):
[ ] Montar ambiente Python e instalar biblioteca de quantização (Larq ou Brevitas).
[ ] Treinar Rede Neural Ternária (TNN) estilo MLP usando o dataset MNIST.
[ ] Validar precisão >95% certificando-se de que os pesos são restritos a -1, 0 e 1.

=======================================
🟡 FASE 2: CONFIGURAÇÃO E EXPORTAÇÃO
⏳ Prazo: Semanas 4 a 7 (Duração: 28 dias)
🎯 Objetivo: Criação das pontes de comunicação. O trabalho de um começa a afetar o outro.

Arthur (Hardware):
[ ] Escrever o código Verilog da NPU Ternária (Apenas Somadores, Subtratores e Mux. ZERO multiplicadores).
[ ] Implementar pino de interrupção (IRQ) em hardware para sinalizar quando a NPU terminar a inferência, para evitar Polling que consome energia.

Gildo (Sistema Operacional):
[ ] Configurar Buildroot para gerar a Cross-Compiler Toolchain estritamente para 32 bits (riscv32-buildroot-linux-gnu-gcc ou equivalente, usando -march=rv32ima -mabi=ilp32).
[ ] ⚠️ ENTREGAR TOOLCHAIN para o Gustavo e Gilvan.
[ ] Escrever o arquivo .dts (Device Tree) criando o "node" da NPU com o endereço base e o pino de interrupção (IRQ) que o Arthur passou.

Gustavo (Driver de Kernel):
[ ] Usar alloc_chrdev_region para criar o dispositivo /dev/npu_ternaria.
[ ] Criar a struct file_operations (mapear .read, .write, .open).
[ ] 🛠️ MOCK: Se o Arthur atrasar o Mapa, use um endereço inventado no código e continue.

Gilvan (Inteligência Artificial):
[ ] Fazer script Python para ler os pesos ternários gerados na Fase 1.
[ ] Empacotar 16 pesos (de 2-bits) dentro de blocos uint32_t (garantir conformidade com a regra de Endianness definida com o Arthur).
[ ] Exportar o arquivo automático weights.h em código C.

=======================================
🟠 FASE 3: LÓGICA E INTEGRAÇÃO (O GARGALO)
⏳ Prazo: Semanas 8 a 13 (Duração: 42 dias) -> Fase mais longa e difícil!
🎯 Objetivo: Fazer os 4 mundos conversarem. Muito debug e Kernel Panic previstos.

Arthur (Hardware):
[ ] Conectar a NPU escrava no barramento principal (Wishbone/AXI) do LiteX.
[ ] Criar Testbench no Verilator simulando o barramento injetando dados na NPU e conferindo a saída.

Gildo (Sistema Operacional):
[ ] Adicionar suporte a FAT32/ext4 no RootFS do Linux (para podermos ler arquivos do SD Card).
[ ] Habilitar temporizadores de alta resolução no Kernel (CONFIG_HIGH_RES_TIMERS).

Gustavo (Driver de Kernel):
[ ] Implementar o ioremap() para mapear o endereço físico do Arthur na memória virtual do Kernel.
[ ] Usar copy_from_user() para puxar dados da IA, e usar writel() para injetar na NPU.
[ ] Implementar request_irq() para o pino de interrupção da NPU. A CPU deve "dormir" (wait_event_interruptible) enquanto a NPU trabalha, acordando apenas via IRQ (sem Polling).

Gilvan (Inteligência Artificial):
[ ] Escrever a Aplicação user_app.c: incluir o weights.h, ler imagem do SD, e abrir o /dev/npu_ternaria.
[ ] Fazer a medição de tempo segregada: 1) Tempo movendo dados para o driver, 2) Tempo de inferência, 3) Tempo de retorno dos resultados.
[ ] 🛠️ MOCK: Não espere o Driver nem a NPU. Faça a função calcular a rede na CPU (software puro) e meça o tempo com <sys/time.h>.

=======================================
🔴 FASE 4: DEPLOY FÍSICO E ARTIGO
⏳ Prazo: Semanas 14 a 16 (Duração: 21 dias)
🎯 Objetivo: Rodar no silício real, extrair os tempos e escrever.

Arthur (Hardware):
[ ] Sintetizar o SoC final + NPU, fechar Timing e gravar o Bitstream na FPGA.
[ ] Extrair relatório de síntese (Comprovar 0 blocos DSP usados, anotar LUTs e FFs).

Gildo (Sistema Operacional):
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

*** Dica de uso para vocês: Mande isso no grupo. Quando o Arthur, por exemplo, terminar o código Verilog, ele copia o texto todo, marca um [x] Escrever o código Verilog da NPU Ternária e envia de novo no grupo. Assim o status do projeto está sempre na última mensagem!