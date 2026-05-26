/*
 * Wrapper NPU Ternária com Interface Wishbone e IRQ Generator
 * Projeto: Ternary Edge-RV
 * Autor: Arthur Oliveira Gomes
 *
 * Descrição:
 * Este é o módulo Top-Level do acelerador. Ele se conecta ao SoC LiteX
 * usando o barramento Wishbone. 
 *
 * NOTA PARA A EQUIPE DE SOFTWARE (MVP da Fase 2):
 * Para desbloquear o driver do Gustavo, esta versão inicial simula
 * o tempo de processamento baseado no DATA_SIZE recebido e dispara
 * a interrupção física (IRQ) para acordar a CPU do Linux. A NPU real de 
 * DMA (Wishbone Master) será integrada assim que o Verilator validar os ciclos.
 */

module npu_core_wb (
    // Sinais de Clock e Reset do Sistema
    input  wire        clk,
    input  wire        rst,

    // Interface Slave Wishbone (B4)
    input  wire [31:0] wb_adr_i, // Endereço
    input  wire [31:0] wb_dat_i, // Dados escritos pela CPU
    input  wire [3:0]  wb_sel_i, // Byte select
    input  wire        wb_we_i,  // Write Enable
    input  wire        wb_cyc_i, // Cycle valid
    input  wire        wb_stb_i, // Strobe
    output reg  [31:0] wb_dat_o, // Dados lidos pela CPU
    output reg         wb_ack_o, // Acknowledge

    // Sinal de Interrupção para o VexRiscv (Linux)
    output reg         irq_out
);

    // =========================================================================
    // 1. Definição do Mapa de Memória (Alinhado com docs/mapa_de_memoria.md)
    // =========================================================================
    localparam REG_STATUS   = 8'h00; // [Read-Only] 0 = Idle, 1 = Busy
    localparam REG_CONTROL  = 8'h04; // [Write-Only] bit 0 = Start, bit 1 = Clear IRQ
    localparam REG_SRC_ADDR = 8'h08; // [R/W] Base Address dos Pesos/Imagens
    localparam REG_DST_ADDR = 8'h0C; // [R/W] Base Address dos Resultados
    localparam REG_SIZE     = 8'h10; // [R/W] Quantidade de bytes

    // Registradores Físicos
    reg [31:0] r_src_addr;
    reg [31:0] r_dst_addr;
    reg [31:0] r_size;
    reg        r_busy;

    // =========================================================================
    // 2. Máquina de Estados (FSM) de Processamento "Dummy/Mock"
    // =========================================================================
    // Ela espera o START, aguarda um tempo proporcional ao SIZE (para
    // simular o ciclo de clock da rede) e levanta o IRQ.
    
    localparam ST_IDLE = 2'b00;
    localparam ST_BUSY = 2'b01;
    localparam ST_DONE = 2'b10;

    reg [1:0]  state;
    reg [31:0] delay_counter;
    wire       cmd_start = (wb_we_i && wb_cyc_i && wb_stb_i && (wb_adr_i[7:0] == REG_CONTROL) && wb_dat_i[0]);
    wire       cmd_clear = (wb_we_i && wb_cyc_i && wb_stb_i && (wb_adr_i[7:0] == REG_CONTROL) && wb_dat_i[1]);

    always @(posedge clk) begin
        if (rst) begin
            state         <= ST_IDLE;
            r_busy        <= 1'b0;
            irq_out       <= 1'b0;
            delay_counter <= 32'd0;
        end else begin
            case (state)
                ST_IDLE: begin
                    r_busy <= 1'b0;
                    if (cmd_start) begin
                        state         <= ST_BUSY;
                        r_busy        <= 1'b1;
                        delay_counter <= r_size; // Tempo proporcional à IA
                        irq_out       <= 1'b0;
                    end
                    if (cmd_clear) begin
                        irq_out <= 1'b0; // Software ack do IRQ
                    end
                end

                ST_BUSY: begin
                    if (delay_counter > 0) begin
                        delay_counter <= delay_counter - 1;
                    end else begin
                        state   <= ST_DONE;
                        irq_out <= 1'b1; // DISPARA INTERRUPÇÃO PARA ACORDAR A CPU!
                    end
                end

                ST_DONE: begin
                    r_busy <= 1'b0;
                    if (cmd_clear) begin
                        irq_out <= 1'b0;
                        state   <= ST_IDLE;
                    end
                end
            endcase
        end
    end

    // =========================================================================
    // 3. Controle de Leitura e Escrita Wishbone (Slave)
    // =========================================================================
    wire wb_valid_access = wb_cyc_i && wb_stb_i;

    always @(posedge clk) begin
        if (rst) begin
            wb_ack_o   <= 1'b0;
            wb_dat_o   <= 32'd0;
            r_src_addr <= 32'd0;
            r_dst_addr <= 32'd0;
            r_size     <= 32'd0;
        end else begin
            wb_ack_o <= 1'b0; // Acknowledge padrão desce em 1 ciclo

            if (wb_valid_access && !wb_ack_o) begin
                wb_ack_o <= 1'b1; // Responde a transação

                // Escrita da CPU -> NPU
                if (wb_we_i) begin
                    case (wb_adr_i[7:0])
                        REG_SRC_ADDR: r_src_addr <= wb_dat_i;
                        REG_DST_ADDR: r_dst_addr <= wb_dat_i;
                        REG_SIZE:     r_size     <= wb_dat_i;
                        // Nota: REG_CONTROL não armazena valor, gera o 'cmd_start' via wire.
                    endcase
                end 
                // Leitura da CPU <- NPU
                else begin
                    case (wb_adr_i[7:0])
                        REG_STATUS:   wb_dat_o <= {30'd0, irq_out, r_busy}; // bit 0 = busy, bit 1 = irq_pending
                        REG_SRC_ADDR: wb_dat_o <= r_src_addr;
                        REG_DST_ADDR: wb_dat_o <= r_dst_addr;
                        REG_SIZE:     wb_dat_o <= r_size;
                        default:      wb_dat_o <= 32'hDEADBEEF; // Debug
                    endcase
                end
            end
        end
    end

endmodule
