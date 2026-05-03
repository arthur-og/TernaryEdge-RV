Estrutura de Diretórios do Repositório (TernaryEdge-RV)
Plaintext

TernaryEdge-RV/
├── docs/
│   ├── estrutura.md
│   ├── arquitetura/
│   ├── planejamento/       <-- (Nova pasta para os planos detalhados)
│   └── relatorios/         <-- (Agora focada no estado atual e entregas)
├── hardware/
│   ├── litex_soc/
│   └── npu_rtl/
├── software/
│   ├── os_buildroot/
│   ├── npu_driver/
│   └── user_app/
├── ai_training/
│   ├── notebooks/
│   └── scripts/
├── paper/
└── README.md

Documentação da Estrutura do Projeto Atualizada (Para o README.md ou Wiki)

Esta documentação define a arquitetura do repositório, delimitando as responsabilidades de cada diretório de acordo com o planejamento técnico da equipe.
1. docs/ (Documentação e Gerenciamento - PT-BR)

Diretório reservado para o gerenciamento do projeto, definições arquiteturais e acompanhamento contínuo. Todo o conteúdo interno pode ser redigido em português.

    arquitetura/: Contém as especificações técnicas globais do projeto. Inclui o Mapa de Memória (essencial para a integração entre Hardware, SO e Driver), definição dos registradores da NPU e diagramas de bloco do System-on-Chip (SoC).

    planejamento/: Armazena os documentos com os planos de ação detalhados fase a fase para cada frente de desenvolvimento (Plano_Arthur, Plano_Gildo, Plano_Gustavo, Plano_Gilvan). Serve como o roteiro técnico central do projeto.

    relatorios/: Destinado ao acompanhamento do progresso e validação acadêmica.

        Status Atual: Cada membro deve manter um documento ativo e atualizado nesta pasta descrevendo o "estado atual" do seu escopo (o que está funcionando, quais são os bloqueios atuais e próximos passos).

        Entregas: Relatórios formais de conclusão das fases (1 a 4).

2. hardware/ (Escopo: Arthur - Engenharia de Hardware)

Contém todo o código-fonte de descrição de hardware e geração do System-on-Chip (SoC).

    litex_soc/: Scripts em Python baseados no framework LiteX utilizados para gerar o SoC base (com o núcleo VexRiscv), configurar o barramento interno e exportar a Cross-Compiler Toolchain.

    npu_rtl/: Códigos em Verilog/VHDL contendo o projeto lógico da NPU Ternária (Multiplierless). Inclui a implementação matemática dos somadores/multiplexadores, lógica de desempacotamento de dados (unpacking) de 32 bits e os testbenches para simulação (via Verilator/ModelSim).

3. software/ (Escopo: Gildo, Gustavo e Gilvan - Stack de Software)

Diretório unificado contendo as camadas de software que executarão no processador RISC-V físico ou emulado.

    os_buildroot/ (Gildo): Arquivos de configuração da distribuição Linux embarcada gerada via Buildroot. Contém os patches do kernel, configurações do bootloader (OpenSBI e U-Boot) e, de extrema importância, a Device Tree Source (.dts) que mapeia os endereços físicos da NPU.

    npu_driver/ (Gustavo): Código-fonte em linguagem C do Loadable Kernel Module (LKM). Contém as File Operations, as funções de conversão de memória física para virtual (ioremap), além da lógica de comunicação ponta a ponta (códigos usando copy_from_user, write, read) e rotinas de sincronização (Polling/IRQ) para o controle do hardware.

    user_app/ (Gilvan): Aplicação executável (espaço de usuário) escrita em C. Responsável por realizar a leitura do dataset de imagens, acionar o driver e mensurar o tempo de execução (usando funções precisas do kernel como gettimeofday()) para compor os dados de benchmarking.

4. ai_training/ (Escopo: Gilvan - Inteligência Artificial)

Ambiente voltado ao desenvolvimento, treinamento e quantização da Rede Neural Ternária executado diretamente no PC (host).

    notebooks/: Ambientes interativos (Jupyter) para experimentação e validação de técnicas de Quantization-Aware Training (QAT) com frameworks como Larq ou Brevitas.

    scripts/: Código Python automatizado (pipeline) focado em duas frentes: (1) treinar e validar o modelo atingindo as métricas requeridas de acurácia; (2) extrair os tensores, aplicar a codificação binária e empacotar 16 pesos de 2 bits em inteiros de 32 bits. O resultado final gerado aqui é o arquivo header weights.h utilizado na aplicação final.

5. paper/ (Artigo Científico)

Diretório exclusivo para a estruturação do trabalho acadêmico. Contém os arquivos LaTeX, bibliografias e os gráficos exportados do benchmarking comparando os resultados do tempo de inferência entre a NPU acelerada por hardware e a execução puramente por software.