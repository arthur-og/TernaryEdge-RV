/*
 * ╔══════════════════════════════════════════════════════════════╗
 * ║                                                              ║
 * ║   NPU Ternária — Datapath Multiplierless Completo            ║
 * ║   Ternary Edge-RV Project                                    ║
 * ║   Autor: Arthur Oliveira Gomes                               ║
 * ║                                                              ║
 * ║   "0 DSPs. Apenas Muxes e Somadores."                       ║
 * ║                                                              ║
 * ╚══════════════════════════════════════════════════════════════╝
 *
 * ARQUITETURA:
 * ┌──────────────────────────────────────────────────────────────┐
 * │                    npu_ternaria_top.v                        │
 * │                                                              │
 * │  ┌────────────────────────────────────────────────────────┐  │
 * │  │  Wishbone Slave Interface                              │  │
 * │  │  - Decodifica endereços (0x00 a 0x1C)                  │  │
 * │  │  - Roteia leituras/escritas                            │  │
 * │  └──────────────────────┬─────────────────────────────────┘  │
 * │                          │                                    │
 * │  ┌──────────────────────▼─────────────────────────────────┐  │
 * │  │  Memórias Internas (BRAM)                             │  │
 * │  │  - Weight SRAM: 512 × 32 bits (8192 pesos ternários)  │  │
 * │  │  - Activation SRAM: 1024 × 8 bits                     │  │
 * │  │  - Escrita via Wishbone (auto-incremento)             │  │
 * │  └──────────────────────┬─────────────────────────────────┘  │
 * │                          │                                    │
 * │  ┌──────────────────────▼─────────────────────────────────┐  │
 * │  │  Address Generator + FSM de Processamento              │  │
 * │  │  Estados: IDLE → READ_W → READ_A → COMPUTE → DONE     │  │
 * │  │  - Itera por pesos (2 bits de cada word)               │  │
 * │  │  - Conta sparsity (pesos zero pulados)                 │  │
 * │  └──────────────────────┬─────────────────────────────────┘  │
 * │                          │                                    │
 * │  ┌──────────────────────▼─────────────────────────────────┐  │
 * │  │  ternary_mac (Multiplierless)                          │  │
 * │  │  - Entrada: INT8 × 2 bits                              │  │
 * │  │  - Saída: 32 bits acumulados                           │  │
 * │  │  - Lógica: Mux + Somador (0 DSPs!)                    │  │
 * │  └──────────────────────┬─────────────────────────────────┘  │
 * │                          │                                    │
 * │  ┌──────────────────────▼─────────────────────────────────┐  │
 * │  │  IRQ Generator                                        │  │
 * │  │  - Quando DONE, irq_out = 1 (acorda a CPU do Linux)   │  │
 * │  └────────────────────────────────────────────────────────┘  │
 * └──────────────────────────────────────────────────────────────┘
 *
 * MAPA DE MEMÓRIA (32 bits, Little-Endian):
 *   0x00: STATUS   (RO) — [0]=busy, [1]=irq, [15:8]=zero_skipped
 *   0x04: CONTROL  (WO) — [0]=start, [1]=clear_irq
 *   0x08: SRC_ADDR (RW) — reservado para DMA
 *   0x0C: DST_ADDR (RW) — reservado para DMA
 *   0x10: DATA_SIZE(RW) — número de MACs a processar
 *   0x14: WEIGHT   (WO) — escreve 1 word (16 pesos) na memória (auto-inc)
 *   0x18: ACTIVATION(WO) — escreve 1 ativação na memória (auto-inc)
 *   0x1C: RESULT   (RO) — resultado acumulado final
 */

module npu_ternaria_top (
    // Clock e Reset
    input  wire        clk,
    input  wire        rst_n,         // Reset ativo baixo

    // Wishbone Slave (B4)
    input  wire [31:0] wb_adr_i,
    input  wire [31:0] wb_dat_i,
    input  wire [3:0]  wb_sel_i,
    input  wire        wb_we_i,
    input  wire        wb_cyc_i,
    input  wire        wb_stb_i,
    output reg  [31:0] wb_dat_o,
    output reg         wb_ack_o,

    // Interrupção (IRQ) para o RISC-V
    output reg         irq_out
);

    // =========================================================================
    // 1. Mapa de Memória (Definições)
    // =========================================================================
    localparam REG_STATUS      = 8'h00;
    localparam REG_CONTROL     = 8'h04;
    localparam REG_SRC_ADDR    = 8'h08;
    localparam REG_DST_ADDR    = 8'h0C;
    localparam REG_DATA_SIZE   = 8'h10;
    localparam REG_WEIGHT_DATA = 8'h14;
    localparam REG_ACT_DATA    = 8'h18;
    localparam REG_RESULT      = 8'h1C;

    // =========================================================================
    // 2. Registradores
    // =========================================================================
    reg [31:0] r_src_addr;
    reg [31:0] r_dst_addr;
    reg [31:0] r_data_size;
    reg [31:0] r_result;

    // =========================================================================
    // 3. Memórias Internas (pesos e ativações)
    // =========================================================================
    // weight_mem: 512 posições × 32 bits = 8192 pesos ternários
    reg [31:0] weight_mem [0:511];
    // act_mem: 1024 posições × 8 bits
    reg [7:0]  act_mem    [0:1023];

    // Ponteiros de escrita (auto-incremento quando CPU escreve)
    reg [9:0]  wptr_weight;
    reg [10:0] wptr_act;

    // =========================================================================
    // 4. Máquina de Estados de Processamento (FSM)
    // =========================================================================
    localparam ST_IDLE    = 3'b000;
    localparam ST_READ_W  = 3'b001;   // Lê palavra de peso da SRAM
    localparam ST_READ_A  = 3'b010;   // Lê ativação da SRAM
    localparam ST_COMPUTE = 3'b011;   // MAC executa
    localparam ST_DONE    = 3'b100;   // Resultado pronto, IRQ = 1

    reg [2:0]  state;
    reg [31:0] mac_counter;           // Quantos MACs já foram feitos
    reg [31:0] accumulator;           // Acumulador interno (32 bits)
    reg [15:0] zero_counter;          // Contagem de pesos zero pulados

    // Ponteiros de leitura (para varrer as memórias durante computação)
    reg [9:0]  rptr_weight;
    reg [10:0] rptr_act;
    reg [4:0]  weight_sub_idx;        // Índice do sub-peso (0 a 15) dentro da word

    // Sinais de controle
    wire       cmd_start = (wb_we_i && wb_cyc_i && wb_stb_i && (wb_adr_i[7:0] == REG_CONTROL) && wb_dat_i[0]);
    wire       cmd_clear = (wb_we_i && wb_cyc_i && wb_stb_i && (wb_adr_i[7:0] == REG_CONTROL) && wb_dat_i[1]);
    wire       write_weight = (wb_we_i && wb_cyc_i && wb_stb_i && (wb_adr_i[7:0] == REG_WEIGHT_DATA));
    wire       write_act    = (wb_we_i && wb_cyc_i && wb_stb_i && (wb_adr_i[7:0] == REG_ACT_DATA));

    // =========================================================================
    // 5. Extração do Peso Atual
    // =========================================================================
    // Cada word de 32 bits contém 16 pesos de 2 bits.
    // Little-Endian: peso[0] = bits[1:0], peso[1] = bits[3:2], ...
    wire [31:0] current_weight_word = weight_mem[rptr_weight];
    wire [1:0]  current_weight = (current_weight_word >> (weight_sub_idx * 2)) & 2'b11;
    wire [7:0]  current_act    = act_mem[rptr_act];

    // =========================================================================
    // 6. Instanciação do MAC Multiplierless
    // =========================================================================
    wire [31:0] mac_out;

    ternary_mac #(
        .ACT_WIDTH(8),
        .ACC_WIDTH(32)
    ) u_mac (
        .clk    (clk),
        .rst    (~rst_n),
        .en     ( (state == ST_COMPUTE) ? 1'b1 : 1'b0 ),
        .clear  ( (state == ST_IDLE) ? 1'b1 : 1'b0 ),
        .act_in (current_act),
        .weight (current_weight),
        .acc_out(mac_out)
    );

    // =========================================================================
    // 7. FSM Principal
    // =========================================================================
    always @(posedge clk) begin
        if (~rst_n) begin
            state          <= ST_IDLE;
            mac_counter    <= 32'd0;
            zero_counter   <= 16'd0;
            rptr_weight    <= 10'd0;
            rptr_act       <= 11'd0;
            weight_sub_idx <= 5'd0;
            accumulator    <= 32'd0;
            irq_out        <= 1'b0;
        end else begin
            case (state)
                // =============================================================
                ST_IDLE: begin
                    irq_out <= 1'b0;

                    if (cmd_start) begin
                        // Inicializa todos os contadores
                        mac_counter    <= 32'd0;
                        zero_counter   <= 16'd0;
                        rptr_weight    <= 10'd0;
                        rptr_act       <= 11'd0;
                        weight_sub_idx <= 5'd0;

                        // Se DATA_SIZE = 0, vai direto para DONE
                        if (r_data_size == 32'd0) begin
                            state <= ST_DONE;
                        end else begin
                            state <= ST_READ_W;
                        end
                    end

                    if (cmd_clear) begin
                        irq_out <= 1'b0;
                    end
                end

                // =============================================================
                // Ciclo de Leitura: 1 ciclo para ler peso + 1 ciclo para ativação
                // =============================================================
                ST_READ_W: begin
                    // Peso já está disponível no fio current_weight
                    // (memória síncrona: dado pronto no ciclo seguinte ao endereço)
                    // Na prática, como o endereço foi setado no ST_IDLE ou ST_COMPUTE,
                    // o dado está valido aqui. Vamos para a leitura da ativação.
                    state <= ST_READ_A;
                end

                ST_READ_A: begin
                    // Ativação e peso estão ambos válidos
                    state <= ST_COMPUTE;
                end

                // =============================================================
                ST_COMPUTE: begin
                    // O ternary_mac já computou: pseudo_prod foi somado ao acc_out
                    // Conta sparsity (pesos = 00 são "pulados" eletricamente)
                    if (current_weight == 2'b00) begin
                        zero_counter <= zero_counter + 1;
                    end

                    mac_counter <= mac_counter + 1;

                    // Verifica se terminou
                    if (mac_counter >= (r_data_size - 1)) begin
                        // Último MAC: guarda resultado e termina
                        r_result <= mac_out;
                        state    <= ST_DONE;
                        irq_out  <= 1'b1;   // DISPARA INTERRUPÇÃO!
                    end else begin
                        // Ainda há mais MACs: avança ponteiros
                        // Avança sub-índice ou palavra de peso
                        if (weight_sub_idx >= 5'd15) begin
                            rptr_weight    <= rptr_weight + 1;
                            weight_sub_idx <= 5'd0;
                        end else begin
                            weight_sub_idx <= weight_sub_idx + 1;
                        end
                        // Ativação avança um a um
                        rptr_act <= rptr_act + 1;

                        state <= ST_READ_W;   // Próximo ciclo
                    end
                end

                // =============================================================
                ST_DONE: begin
                    // Fica aqui até a CPU limpar o IRQ
                    if (cmd_clear) begin
                        irq_out <= 1'b0;
                        state   <= ST_IDLE;
                    end
                end
            endcase
        end
    end

    // =========================================================================
    // 8. Lógica Wishbone Slave
    // =========================================================================
    wire wb_valid = wb_cyc_i && wb_stb_i;

    always @(posedge clk) begin
        if (~rst_n) begin
            wb_ack_o     <= 1'b0;
            wb_dat_o     <= 32'd0;
            r_src_addr   <= 32'd0;
            r_dst_addr   <= 32'd0;
            r_data_size  <= 32'd0;
            wptr_weight  <= 10'd0;
            wptr_act     <= 11'd0;
        end else begin
            wb_ack_o <= 1'b0;   // Acknowledge dura 1 ciclo

            if (wb_valid && !wb_ack_o) begin
                wb_ack_o <= 1'b1;

                if (wb_we_i) begin
                    // ---- Escrita do processador na NPU ----
                    case (wb_adr_i[7:0])
                        REG_SRC_ADDR:    r_src_addr  <= wb_dat_i;
                        REG_DST_ADDR:    r_dst_addr  <= wb_dat_i;
                        REG_DATA_SIZE:   r_data_size <= wb_dat_i;

                        REG_WEIGHT_DATA: begin
                            weight_mem[wptr_weight] <= wb_dat_i;
                            wptr_weight <= wptr_weight + 1;  // Auto-incremento
                        end

                        REG_ACT_DATA: begin
                            act_mem[wptr_act] <= wb_dat_i[7:0];
                            wptr_act <= wptr_act + 1;         // Auto-incremento
                        end
                        // REG_CONTROL não armazena valor (start/clear são wires)
                    endcase
                end else begin
                    // ---- Leitura do processador da NPU ----
                    case (wb_adr_i[7:0])
                        REG_STATUS:   wb_dat_o <= {16'd0, zero_counter, 14'd0, irq_out, (state != ST_IDLE)};
                        REG_SRC_ADDR: wb_dat_o <= r_src_addr;
                        REG_DST_ADDR: wb_dat_o <= r_dst_addr;
                        REG_DATA_SIZE: wb_dat_o <= r_data_size;
                        REG_RESULT:   wb_dat_o <= r_result;
                        default:      wb_dat_o <= 32'hCAFEBABE;  // Debug pattern
                    endcase
                end
            end
        end
    end

endmodule
