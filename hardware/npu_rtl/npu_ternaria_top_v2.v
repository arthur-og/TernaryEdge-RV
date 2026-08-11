/*
 * ╔══════════════════════════════════════════════════════════════════════╗
 * ║   NPU Ternária v2 — 64 MACs Paralelos + Wishbone Master DMA        ║
 * ║   Ternary Edge-RV Project                                          ║
 * ║   Autor: Arthur Oliveira Gomes                                     ║
 * ║                                                                    ║
 * ║   "0 DSPs. 64 MACs. DMA Autônomo. Layer Sequencer Integrado."     ║
 * ║   Rev 2.1 — Correções: DMA funcional, write-back,                  ║
 * ║   clear entre neurônios, pesos on-demand da RAM                   ║
 * ╚══════════════════════════════════════════════════════════════════════╝
 *
 * ARQUITETURA:
 *   ┌──────────────────────────────────────────────────────────────────────┐
 *   │  ┌────────────────┐   ┌──────────────────────────────────────────┐  │
 *   │  │ Wishbone Slave │   │  Layer Sequencer (FSM Principal)         │  │
 *   │  │ (Config Regs)  │◄─►│  IDLE→DMA_ACT→COMPUTE→WRITE→DONE        │  │
 *   │  └────────────────┘   └──────────┬───────────────────────────────┘  │
 *   │                                   │                                  │
 *   │  ┌────────────────────────────────▼──────────────────────────────┐  │
 *   │  │              Wishbone Master (DMA Controller)                 │  │
 *   │  │         Lê ativações da RAM → act_mem | Lê pesos on-demand    │  │
 *   │  │         Escreve resultados na RAM (por neurônio)              │  │
 *   │  └──────┬──────────────────────────────────────┬─────────────────┘  │
 *   │         │                                      │                     │
 *   │  ┌──────▼─────────┐              ┌─────────────▼──────────────────┐ │
 *   │  │  Act Buffer    │              │  Weight Reg File (4×32-bit)    │ │
 *   │  │  1024 × 8-bit  │              │  (carregado on-demand via DMA) │ │
 *   │  └──────┬─────────┘              └─────────────┬──────────────────┘ │
 *   │         │                                      │                     │
 *   │  ┌──────▼──────────────────────────────────────▼──────────────────┐ │
 *   │  │            for-loop sobre 64 MACs (sequential compute)         │ │
 *   │  │  (ternary_mac_array + adder_tree disponíveis p/ Etapa 2)      │ │
 *   │  └──────────────────────────┬────────────────────────────────────┘ │
 *   │                             │                                       │
 *   │  ┌──────────────────────────▼────────────────────────────────────┐ │
 *   │  │              acc_reg[0] (32-bit accumulator)                  │ │
 *   │  │  (64 × 32-bit acc_reg[0:63] disponível p/ Etapa 2)           │ │
 *   │  └───────────────────────────────────────────────────────────────┘ │
 *   └──────────────────────────────────────────────────────────────────────┘
 *
 * MAPA DE MEMÓRIA (v2.1, 32-bit Little-Endian):
 *   Offset | Registrador       | R/W | Descrição
 *   -------|-------------------|-----|------------------------------
 *   0x00   | STATUS            | RO  | [0]=busy, [1]=irq, [15:8]=zero_skip
 *   0x04   | CONTROL           | WO  | [0]=start, [1]=clear_irq
 *   0x08   | DMA_SRC_ADDR      | RW  | End. base dos dados na RAM
 *   0x0C   | DMA_DST_ADDR      | RW  | End. base do resultado na RAM
 *   0x10   | DMA_SIZE          | RW  | Total de operações MAC
 *   0x14   | WEIGHT_CFG        | RW  | Configuração dos pesos
 *   0x18   | ACT_CFG           | RW  | Número de ativações por layer
 *   0x1C   | RESULT            | RO  | Último resultado acumulado
 *   0x20   | MAC_CFG           | RW  | Número de MACs (default 64)
 *   0x24   | LAYER_CFG         | RW  | Número de layers (default 3)
 *   0x28   | RESULT_WINDOW     | RO  | acc_reg[result_window_idx]
 *   0x2C   | LAYER_CTRL        | RW  | [0]=irq_per_layer, [5:0]=win_idx
 */

`timescale 1ns / 1ps

`include "npu_v2_pkg.v"

module npu_ternaria_top_v2 (
    // ===== Clock e Reset =====
    input  wire        clk,
    input  wire        rst_n,

    // ===== Wishbone Slave (CPU → NPU) =====
    input  wire [31:0] wb_s_adr_i,
    input  wire [31:0] wb_s_dat_i,
    input  wire [3:0]  wb_s_sel_i,
    input  wire        wb_s_we_i,
    input  wire        wb_s_cyc_i,
    input  wire        wb_s_stb_i,
    output reg  [31:0] wb_s_dat_o,
    output reg         wb_s_ack_o,

    // ===== Wishbone Master (NPU → RAM) =====
    output reg  [31:0] wb_m_adr_o,
    output reg  [31:0] wb_m_dat_o,
    output reg  [3:0]  wb_m_sel_o,
    output reg         wb_m_we_o,
    output reg         wb_m_cyc_o,
    output reg         wb_m_stb_o,
    output reg  [2:0]  wb_m_cti_o,
    output reg  [1:0]  wb_m_bte_o,
    input  wire [31:0] wb_m_dat_i,
    input  wire        wb_m_ack_i,
    input  wire        wb_m_err_i,

    // ===== Interrupção =====
    output reg         irq_out
);

    // =========================================================================
    // 1. Registradores de Configuração (acessados via Wishbone Slave)
    // =========================================================================
    reg [31:0] cfg_src_addr;
    reg [31:0] cfg_dst_addr;
    reg [31:0] cfg_dma_size;
    reg [31:0] cfg_weight_cfg;
    reg [31:0] cfg_act_cfg;
    reg [31:0] cfg_mac_cfg;
    reg [31:0] cfg_layer_cfg;
    reg [31:0] cfg_result;
    reg [15:0] zero_counter;
    reg [31:0] cfg_layer_ctrl;  // [0]=irq_per_layer, [5:0]=result_window_idx

    // Decodificação de comandos do CONTROL register
    wire cmd_start   = (wb_s_we_i && wb_s_cyc_i && wb_s_stb_i &&
                        (wb_s_adr_i[7:0] == `REG_CONTROL) && wb_s_dat_i[0]);
    wire cmd_clear   = (wb_s_we_i && wb_s_cyc_i && wb_s_stb_i &&
                        (wb_s_adr_i[7:0] == `REG_CONTROL) && wb_s_dat_i[1]);

    // =========================================================================
    // 2. Layer Sequencer — FSM
    // =========================================================================
    reg [3:0] state, next_state;
    reg [1:0] compute_step;  // Sub-estados dentro de ST_COMPUTE_BATCH

    reg [31:0] layer_in  [0:2];
    reg [31:0] layer_out [0:2];
    reg [31:0] layer_wcnt[0:2];

    initial begin
        layer_in [0] = 784;   layer_out [0] = 1024;  layer_wcnt[0] = 50176;
        layer_in [1] = 1024;  layer_out [1] = 512;   layer_wcnt[1] = 32768;
        layer_in [2] = 512;   layer_out [2] = 256;   layer_wcnt[2] = 8192;
    end

    reg [31:0] cur_layer;
    reg [31:0] cur_output;
    reg [31:0] cur_in_batch;
    reg [31:0] total_ops;
    wire       final_input_batch;
    assign final_input_batch =
        ((cur_in_batch + 32'd1) * 32'd64 >= layer_in[cur_layer]);

    // =========================================================================
    // 3. Activation Buffer (1024 × 8-bit)
    // =========================================================================
    reg [7:0]  act_mem [0:1023];
    reg [10:0] act_waddr;
    reg [9:0]  act_raddr;
    wire [7:0] act_rdata;
    assign act_rdata = act_mem[act_raddr];

    // =========================================================================
    // 4. Weight Buffer (tile cache, não usado no compute on-demand)
    // =========================================================================
    reg [31:0] wt_mem [0:2047];
    reg [10:0] wt_waddr;

    // =========================================================================
    // 5. DMA Signals and State Machine (Wishbone Master)
    // =========================================================================
    reg        dma_start;
    reg        dma_read;
    reg [31:0] dma_addr;
    reg [15:0] dma_bytes;
    reg [31:0] dma_wdata;      // Write data for DMA write operations
    reg        dma_done;
    reg        dma_busy;
    wire       dma_word_valid;  // Combinational: pulses when ack received on read
    reg [31:0] dma_rdata;

    localparam DMA_IDLE = 2'd0, DMA_ISSUE = 2'd1, DMA_WAIT = 2'd2, DMA_COMPLETE = 2'd3;
    reg [1:0] dma_state;

    // =========================================================================
    // 6. 64-MAC Array Interface (instanciado para Etapa 2)
    // =========================================================================
    reg        mac_en;
    reg        mac_clear;
    reg [511:0] mac_acts;
    reg [127:0] mac_weights;
    wire [2047:0] mac_acc;

    // =========================================================================
    // 7. Adder Tree Interface (instanciado para Etapa 2)
    // =========================================================================
    reg        adder_en;
    reg [575:0] adder_vals;
    wire [14:0] adder_sum;

    // =========================================================================
    // 8. Accumulator Register File (64 × 32-bit)
    // =========================================================================
    reg [31:0] acc_reg [0:63];
    reg        acc_clear;

    // =========================================================================
    // 9. Weight temp buffer (4 × 32-bit para o batch atual)
    // =========================================================================
    reg [31:0] wt_buf [0:3];
    reg [2:0]  wt_buf_idx;

    // =========================================================================
    // 10. Address helper wires
    // =========================================================================
    // Byte offset do início dos pesos na RAM para a camada atual
    wire [31:0] layer_weight_offset =
        (cur_layer == 0) ? 32'd0 :
        (cur_layer == 1) ? (layer_wcnt[0] * 4) :
                           ((layer_wcnt[0] + layer_wcnt[1]) * 4);

    // Endereço base dos pesos na RAM para a camada atual
    // Layout: cfg_src_addr + 4096 (área de ativações) + offset da camada
    wire [31:0] wt_ram_base = cfg_src_addr + 4096 + layer_weight_offset;

    // Número de words de peso por neurônio de saída nesta camada
    wire [15:0] words_per_output = layer_in[cur_layer] / 16;

    // =========================================================================
    // 11. FSM — Sequential Logic (unificado com compute_step advancement)
    // =========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            state        <= `ST_IDLE;
            irq_out      <= 1'b0;
            cur_layer    <= 32'd0;
            cur_output   <= 32'd0;
            cur_in_batch <= 32'd0;
            total_ops    <= 32'd0;
            zero_counter <= 16'd0;
            compute_step <= `COMPUTE_STEP_LOAD_WEIGHTS;
            wt_buf_idx   <= 3'd0;

            for (integer a = 0; a < 64; a = a + 1) acc_reg[a] <= 32'd0;
            for (integer w = 0; w < 4; w = w + 1) wt_buf[w] <= 32'd0;

            act_waddr <= 11'd0;
            wt_waddr  <= 11'd0;
            mac_clear <= 1'b0;
            mac_en    <= 1'b0;
            adder_en  <= 1'b0;

            dma_start     <= 1'b0;
            dma_done      <= 1'b0;
            dma_busy      <= 1'b0;
        end else begin
            state <= next_state;

            dma_start     <= 1'b0;

            case (state)
                // =============================================================
                `ST_IDLE: begin
                    irq_out   <= 1'b0;
                    mac_clear <= 1'b0;
                    if (cmd_start) begin
                        cur_layer    <= 32'd0;
                        cur_output   <= 32'd0;
                        cur_in_batch <= 32'd0;
                        total_ops    <= 32'd0;
                        zero_counter <= 16'd0;
                        compute_step <= `COMPUTE_STEP_LOAD_WEIGHTS;
                        wt_buf_idx   <= 3'd0;
                        for (integer a = 0; a < 64; a = a + 1) acc_reg[a] <= 32'd0;
                    end
                    if (cmd_clear) irq_out <= 1'b0;
                end

                // =============================================================
                `ST_CFG_ACT: begin
                    act_waddr   <= 11'd0;
                    compute_step <= `COMPUTE_STEP_LOAD_WEIGHTS;
                    wt_buf_idx   <= 3'd0;
                    dma_start <= 1'b1;
                    dma_addr  <= cfg_src_addr + (cur_layer * 1024);
                    dma_bytes <= layer_in[cur_layer];
                    dma_read  <= 1'b1;
                end

                `ST_DMA_ACT: begin
                    if (dma_word_valid) begin
                        act_mem[act_waddr + 0] <= wb_m_dat_i[7:0];
                        act_mem[act_waddr + 1] <= wb_m_dat_i[15:8];
                        act_mem[act_waddr + 2] <= wb_m_dat_i[23:16];
                        act_mem[act_waddr + 3] <= wb_m_dat_i[31:24];
                        act_waddr <= act_waddr + 4;
                    end
                end

                // =============================================================
                // COMPUTE — multi-ciclo: LOAD_WEIGHTS → ACCUMULATE
                // =============================================================
                `ST_COMPUTE_BATCH: begin : compute_batch_logic
                    integer m;
                    integer act_idx;
                    integer w_idx;
                    integer b_idx;
                    integer batch_zero_count;
                    reg [1:0] w_val;
                    reg signed [31:0] batch_acc;
                    reg signed [31:0] act_value;

                    if (dma_word_valid &&
                        compute_step == `COMPUTE_STEP_LOAD_WEIGHTS) begin
                        if (wt_buf_idx < 3'd4) begin
                            wt_buf[wt_buf_idx] <= wb_m_dat_i;
                            if (wt_buf_idx == 3'd3)
                                wt_buf_idx <= 3'd4;
                            else
                                wt_buf_idx <= wt_buf_idx + 3'd1;
                        end
                    end

                    case (compute_step)
                        `COMPUTE_STEP_LOAD_WEIGHTS: begin
                            // Só dispara o DMA na primeira vez (wt_buf_idx == 0)
                            if (wt_buf_idx == 3'd0 && !dma_busy) begin
                                dma_start <= 1'b1;
                                dma_addr  <= wt_ram_base
                                           + (cur_output * words_per_output * 4)
                                           + (cur_in_batch * 16);
                                dma_bytes <= 16;
                                dma_read  <= 1'b1;
                            end

                            // The fourth acknowledged word completes this tile;
                            // wait for DMA idle before accumulating it.
                            if (wt_buf_idx == 3'd4 &&
                                !dma_busy && !dma_word_valid) begin
                                compute_step <= `COMPUTE_STEP_ACCUMULATE;
                            end
                        end

                        `COMPUTE_STEP_ACCUMULATE: begin
                            batch_acc = $signed(acc_reg[0]);
                            batch_zero_count = 0;

                            for (m = 0; m < 64; m = m + 1) begin
                                act_idx = cur_in_batch * 64 + m;
                                w_idx = m / 16;
                                b_idx = (m % 16) * 2;
                                w_val = wt_buf[w_idx][b_idx +: 2];
                                if (act_idx < layer_in[cur_layer]) begin
                                    act_value = $signed({{24{act_mem[act_idx][7]}},
                                                         act_mem[act_idx]});
                                    if (w_val == 2'b01) begin
                                        batch_acc = batch_acc + act_value;
                                    end else if (w_val == 2'b11) begin
                                        batch_acc = batch_acc - act_value;
                                    end else if (w_val == 2'b00) begin
                                        batch_zero_count = batch_zero_count + 1;
                                    end
                                end
                            end

                            acc_reg[0] <= batch_acc;
                            zero_counter <= zero_counter + batch_zero_count;
                            total_ops <= total_ops + 64;

                            // Avança batch ou termina este neurônio
                            if (final_input_batch) begin
                                // Último batch — vai para WRITE_RESULT
                                // (next_state cuida da transição)
                            end else begin
                                cur_in_batch <= cur_in_batch + 1;
                                compute_step <= `COMPUTE_STEP_LOAD_WEIGHTS;
                                wt_buf_idx   <= 3'd0;
                            end
                        end
                    endcase
                end

                // =============================================================
                `ST_WRITE_RESULT: begin
                    if (!dma_busy && !dma_done) begin
                        dma_start <= 1'b1;
                        dma_addr  <= cfg_dst_addr + (cur_output * 4);
                        dma_bytes <= 4;
                        dma_read  <= 1'b0;
                        dma_wdata <= acc_reg[0];
                    end
                end

                // =============================================================
                `ST_NEXT_OUTPUT: begin
                    acc_reg[0]    <= 32'd0;
                    cur_output    <= cur_output + 1;
                    cur_in_batch  <= 32'd0;
                    compute_step  <= `COMPUTE_STEP_LOAD_WEIGHTS;
                    wt_buf_idx    <= 3'd0;
                end

                // =============================================================
                `ST_LAYER_DONE: begin
                    cur_output    <= 32'd0;
                    cur_in_batch  <= 32'd0;
                    compute_step  <= `COMPUTE_STEP_LOAD_WEIGHTS;
                    wt_buf_idx    <= 3'd0;
                end

                // =============================================================
                `ST_NEXT_LAYER: begin
                    cur_layer    <= cur_layer + 1;
                    cur_output   <= 32'd0;
                    cur_in_batch <= 32'd0;
                    compute_step <= `COMPUTE_STEP_LOAD_WEIGHTS;
                    wt_buf_idx   <= 3'd0;
                    for (integer a = 0; a < 64; a = a + 1) acc_reg[a] <= 32'd0;
                end

                // =============================================================
                `ST_DONE: begin
                    mac_en   <= 1'b0;
                    adder_en <= 1'b0;
                    if (cmd_clear)
                        irq_out <= 1'b0;
                    else
                        irq_out <= 1'b1;
                end

                default: ;
            endcase
        end
    end

    // =========================================================================
    // 12. FSM — Combinational Next-State Logic
    // =========================================================================
    always @(*) begin
        next_state = state;
        case (state)
            `ST_IDLE: begin
                if (cmd_start) next_state = `ST_CFG_ACT;
            end

            `ST_CFG_ACT:   next_state = `ST_DMA_ACT;

            `ST_DMA_ACT: begin
                if (act_waddr >= layer_in[cur_layer])
                    next_state = `ST_COMPUTE_BATCH;
            end

            `ST_COMPUTE_BATCH: begin
                if (compute_step == `COMPUTE_STEP_ACCUMULATE) begin
                    if (final_input_batch) begin
                        next_state = `ST_WRITE_RESULT;
                    end
                end
            end

            `ST_WRITE_RESULT: begin
                if (dma_done) begin
                    if (cur_output + 1 >= layer_out[cur_layer])
                        next_state = `ST_LAYER_DONE;
                    else
                        next_state = `ST_NEXT_OUTPUT;
                end
            end

            `ST_NEXT_OUTPUT:  next_state = `ST_COMPUTE_BATCH;
            `ST_LAYER_DONE: begin
                if (cur_layer + 1 >= cfg_layer_cfg)
                    next_state = `ST_DONE;
                else
                    next_state = `ST_NEXT_LAYER;
            end
            `ST_NEXT_LAYER:   next_state = `ST_CFG_ACT;
            `ST_DONE: begin
                if (cmd_clear) next_state = `ST_IDLE;
            end
            default:          next_state = `ST_IDLE;
        endcase
    end

    // =========================================================================
    // 13. DMA (Wishbone Master) State Machine
    // =========================================================================
    // dma_word_valid pulses for 1 cycle when ack received on a read transfer
    assign dma_word_valid = (dma_state == DMA_ISSUE || dma_state == DMA_WAIT)
                          && wb_m_ack_i && dma_read;

    always @(posedge clk) begin
        if (!rst_n) begin
            dma_state <= DMA_IDLE;
            dma_busy  <= 1'b0;
            dma_done  <= 1'b0;
            dma_rdata <= 32'd0;
            wb_m_cyc_o <= 1'b0;
            wb_m_stb_o <= 1'b0;
            wb_m_we_o  <= 1'b0;
            wb_m_adr_o <= 32'd0;
            wb_m_dat_o <= 32'd0;
            wb_m_sel_o <= 4'b0000;
            wb_m_cti_o <= 3'b000;
            wb_m_bte_o <= 2'b00;
        end else begin
            case (dma_state)
                DMA_IDLE: begin
                    dma_done <= 1'b0;
                    if (dma_start) begin
                        dma_state <= DMA_ISSUE;
                        dma_busy  <= 1'b1;
                        wb_m_adr_o <= dma_addr;
                        wb_m_we_o  <= ~dma_read;
                        wb_m_sel_o <= 4'b1111;
                        wb_m_cti_o <= 3'b010;
                        wb_m_bte_o <= 2'b00;
                        wb_m_cyc_o <= 1'b1;
                        wb_m_stb_o <= 1'b1;
                        if (!dma_read) begin
                            wb_m_dat_o <= dma_wdata;
                        end
                    end
                end

                DMA_ISSUE: begin
                    wb_m_stb_o <= 1'b1;
                    if (wb_m_ack_i) begin
                        dma_bytes <= dma_bytes - 4;
                        wb_m_adr_o <= wb_m_adr_o + 4;
                        if (dma_bytes <= 4) begin
                            wb_m_cti_o <= 3'b111;
                            dma_state <= DMA_COMPLETE;
                        end else begin
                            dma_state <= DMA_WAIT;
                        end
                    end
                end

                DMA_WAIT: begin
                    wb_m_stb_o <= 1'b1;
                    if (wb_m_ack_i) begin
                        dma_bytes <= dma_bytes - 4;
                        wb_m_adr_o <= wb_m_adr_o + 4;
                        if (dma_bytes <= 4) begin
                            wb_m_cti_o <= 3'b111;
                            dma_state <= DMA_COMPLETE;
                        end
                    end
                end

                DMA_COMPLETE: begin
                    wb_m_cyc_o <= 1'b0;
                    wb_m_stb_o <= 1'b0;
                    dma_busy   <= 1'b0;
                    dma_done   <= 1'b1;
                    dma_state  <= DMA_IDLE;
                end
            endcase
        end
    end

    // =========================================================================
    // 14. Wishbone Slave Logic (CPU register access)
    // =========================================================================
    wire wb_s_valid = wb_s_cyc_i && wb_s_stb_i;

    always @(posedge clk) begin
        if (!rst_n) begin
            wb_s_ack_o     <= 1'b0;
            wb_s_dat_o     <= 32'd0;
            cfg_src_addr   <= 32'd0;
            cfg_dst_addr   <= 32'd0;
            cfg_dma_size   <= 32'd0;
            cfg_weight_cfg <= 32'd0;
            cfg_act_cfg    <= 32'd0;
            cfg_mac_cfg    <= 32'd64;
            cfg_layer_cfg  <= 32'd3;
            cfg_result     <= 32'd0;
            cfg_layer_ctrl <= 32'd0;
        end else begin
            wb_s_ack_o <= 1'b0;

            if (wb_s_valid && !wb_s_ack_o) begin
                wb_s_ack_o <= 1'b1;

                if (wb_s_we_i) begin
                    case (wb_s_adr_i[7:0])
                        `REG_SRC_ADDR:   cfg_src_addr   <= wb_s_dat_i;
                        `REG_DST_ADDR:   cfg_dst_addr   <= wb_s_dat_i;
                        `REG_DMA_SIZE:   cfg_dma_size   <= wb_s_dat_i;
                        `REG_WEIGHT_CFG: cfg_weight_cfg <= wb_s_dat_i;
                        `REG_ACT_CFG:    cfg_act_cfg    <= wb_s_dat_i;
                        `REG_MAC_CFG:    cfg_mac_cfg    <= wb_s_dat_i;
                        `REG_LAYER_CFG:  cfg_layer_cfg  <= wb_s_dat_i;
                        `REG_LAYER_CTRL: cfg_layer_ctrl <= wb_s_dat_i;
                        default: ;
                    endcase
                end else begin
                    case (wb_s_adr_i[7:0])
                        `REG_STATUS: begin
                            wb_s_dat_o <= {16'd0, zero_counter[7:0],
                                           cur_layer[5:0], irq_out,
                                           (state != `ST_IDLE)};
                        end
                        `REG_SRC_ADDR:     wb_s_dat_o <= cfg_src_addr;
                        `REG_DST_ADDR:     wb_s_dat_o <= cfg_dst_addr;
                        `REG_DMA_SIZE:     wb_s_dat_o <= cfg_dma_size;
                        `REG_WEIGHT_CFG:   wb_s_dat_o <= cfg_weight_cfg;
                        `REG_ACT_CFG:      wb_s_dat_o <= cfg_act_cfg;
                        `REG_MAC_CFG:      wb_s_dat_o <= cfg_mac_cfg;
                        `REG_LAYER_CFG:    wb_s_dat_o <= cfg_layer_cfg;
                        `REG_RESULT:       wb_s_dat_o <= cfg_result;
                        `REG_RESULT_WINDOW: begin
                            wb_s_dat_o <= acc_reg[cfg_layer_ctrl[5:0]];
                        end
                        `REG_LAYER_CTRL:   wb_s_dat_o <= cfg_layer_ctrl;
                        default:           wb_s_dat_o <= 32'hCAFEBABE;
                    endcase
                end
            end
        end
    end

    // =========================================================================
    // 15. Update cfg_result at ST_DONE (captura acc_reg[0] para leitura via MMIO)
    // =========================================================================
    always @(posedge clk) begin
        if (state == `ST_DONE) begin
            cfg_result <= acc_reg[0];
        end
    end

endmodule
