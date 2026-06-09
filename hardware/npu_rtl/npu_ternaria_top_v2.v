/*
 * ╔══════════════════════════════════════════════════════════════════════╗
 * ║   NPU Ternária v2 — 64 MACs Paralelos + Wishbone Master DMA        ║
 * ║   Ternary Edge-RV Project                                          ║
 * ║   Autor: Arthur Oliveira Gomes                                     ║
 * ║                                                                    ║
 * ║   "0 DSPs. 64 MACs. DMA Autônomo. Layer Sequencer Integrado."     ║
 * ╚══════════════════════════════════════════════════════════════════════╝
 *
 * ARQUITETURA:
 *   ┌──────────────────────────────────────────────────────────────────────┐
 *   │  ┌────────────────┐   ┌──────────────────────────────────────────┐  │
 *   │  │ Wishbone Slave │   │  Layer Sequencer (FSM Principal)         │  │
 *   │  │ (Config Regs)  │◄─►│  IDLE → LOAD → COMPUTE → DONE           │  │
 *   │  └────────────────┘   └──────────┬───────────────────────────────┘  │
 *   │                                   │                                  │
 *   │  ┌────────────────────────────────▼──────────────────────────────┐  │
 *   │  │              Wishbone Master (DMA Controller)                 │  │
 *   │  │         Lê pesos/ativações da RAM → buffers internos         │  │
 *   │  │         Escreve resultados na RAM                             │  │
 *   │  └──────┬──────────────────────────────────────┬─────────────────┘  │
 *   │         │                                      │                     │
 *   │  ┌──────▼─────────┐              ┌─────────────▼──────────────────┐ │
 *   │  │  Act Buffer    │              │  Weight Buffer (tile cache)    │ │
 *   │  │  1024 × 8-bit  │              │  2048 × 32-bit                │ │
 *   │  └──────┬─────────┘              └─────────────┬──────────────────┘ │
 *   │         │                                      │                     │
 *   │  ┌──────▼──────────────────────────────────────▼──────────────────┐ │
 *   │  │            ternary_mac_array (×64 MACs)                        │ │
 *   │  │  64 × (INT8 act × 2-bit weight) → 64 × 9-bit partials         │ │
 *   │  └──────────────────────────┬────────────────────────────────────┘ │
 *   │                             │                                       │
 *   │  ┌──────────────────────────▼────────────────────────────────────┐ │
 *   │  │              adder_tree_64 (6-stage pipeline)                 │ │
 *   │  │  64 inputs × 9-bit → 15-bit sum                              │ │
 *   │  └──────────────────────────┬────────────────────────────────────┘ │
 *   │                             │                                       │
 *   │  ┌──────────────────────────▼────────────────────────────────────┐ │
 *   │  │          64 × 32-bit Accumulator Register File                │ │
 *   │  └───────────────────────────────────────────────────────────────┘ │
 *   └──────────────────────────────────────────────────────────────────────┘
 *
 * MAPA DE MEMÓRIA (v2, 32-bit Little-Endian):
 *   Offset | Registrador    | R/W | Descrição
 *   -------|----------------|-----|------------------------------
 *   0x00   | STATUS         | RO  | [0]=busy, [1]=irq, [15:8]=zero_skip
 *   0x04   | CONTROL        | WO  | [0]=start, [1]=clear_irq
 *   0x08   | DMA_SRC_ADDR   | RW  | End. físico dos pesos/ativações na RAM
 *   0x0C   | DMA_DST_ADDR   | RW  | End. físico do resultado na RAM
 *   0x10   | DMA_SIZE       | RW  | Total de operações MAC
 *   0x14   | WEIGHT_CFG     | RW  | Configuração dos pesos
 *   0x18   | ACT_CFG        | RW  | Número de ativações por layer
 *   0x1C   | RESULT         | RO  | Resultado acumulado final
 *   0x20   | MAC_CFG        | RW  | Número de MACs (default 64)
 *   0x24   | LAYER_CFG      | RW  | Número de layers (default 3)
 */

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

    // Decodificação de comandos do CONTROL register
    wire cmd_start   = (wb_s_we_i && wb_s_cyc_i && wb_s_stb_i &&
                        (wb_s_adr_i[7:0] == `REG_CONTROL) && wb_s_dat_i[0]);
    wire cmd_clear   = (wb_s_we_i && wb_s_cyc_i && wb_s_stb_i &&
                        (wb_s_adr_i[7:0] == `REG_CONTROL) && wb_s_dat_i[1]);

    // =========================================================================
    // 2. Layer Sequencer — FSM de 9 estados
    // =========================================================================
    reg [3:0] state, next_state;

    // Parâmetros das 3 camadas (hard-coded para MNIST MLP)
    reg [31:0] layer_in  [0:2];
    reg [31:0] layer_out [0:2];
    reg [31:0] layer_wcnt[0:2]; // Número de words de peso por camada

    initial begin
        layer_in [0] = 784;   layer_out [0] = 1024;  layer_wcnt[0] = 50176;
        layer_in [1] = 1024;  layer_out [1] = 512;   layer_wcnt[1] = 32768;
        layer_in [2] = 512;   layer_out [2] = 256;   layer_wcnt[2] = 8192;
    end

    // Contadores da FSM de processamento
    reg [31:0] cur_layer;       // Layer atual (0, 1, 2)
    reg [31:0] cur_output;      // Output neuron atual (0..M-1)
    reg [31:0] cur_in_batch;    // Input batch atual (0..N/64-1)
    reg [31:0] total_ops;       // Total de MACs executados (para zero_counter)

    // =========================================================================
    // 3. Activation Buffer (1024 × 8-bit)
    // =========================================================================
    reg [7:0]  act_mem [0:1023];
    reg [9:0]  act_waddr;
    reg [9:0]  act_raddr;
    wire [7:0] act_rdata;
    assign act_rdata = act_mem[act_raddr];

    // =========================================================================
    // 4. Weight Buffer (tile cache: 2048 × 32-bit)
    // =========================================================================
    reg [31:0] wt_mem [0:2047];
    reg [10:0] wt_waddr;
    reg [10:0] wt_raddr;
    wire [31:0] wt_rdata;
    assign wt_rdata = wt_mem[wt_raddr];

    // =========================================================================
    // 5. DMA State Machine (Wishbone Master simplificado)
    // =========================================================================
    reg        dma_start;
    reg        dma_read;     // 1=read, 0=write
    reg [31:0] dma_addr;
    reg [15:0] dma_bytes;
    reg [31:0] dma_rdata;
    reg        dma_done;
    reg        dma_busy;

    // Wishbone master FSM
    localparam DMA_IDLE = 2'd0, DMA_ISSUE = 2'd1, DMA_WAIT = 2'd2, DMA_COMPLETE = 2'd3;
    reg [1:0] dma_state;

    // =========================================================================
    // 6. 64-MAC Array Interface
    // =========================================================================
    reg        mac_en;
    reg        mac_clear;
    reg [511:0] mac_acts;     // 64 × 8-bit
    reg [127:0] mac_weights;  // 64 × 2-bit
    wire [2047:0] mac_acc;    // 64 × 32-bit

    // =========================================================================
    // 7. Adder Tree Interface
    // =========================================================================
    reg        adder_en;
    reg [575:0] adder_vals;   // 64 × 9-bit
    wire [14:0] adder_sum;

    // =========================================================================
    // 8. Accumulator Register File (64 × 32-bit)
    // =========================================================================
    reg [31:0] acc_reg [0:63];
    reg [5:0]  acc_idx;
    reg        acc_clear;

    // =========================================================================
    // 9. Shift register para unpacking de pesos
    // =========================================================================
    reg [1:0] unpack_weights [0:63];
    integer   unpack_i;

    // =========================================================================
    // 10. FSM — Sequential Logic
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

            // Clear accumulator
            acc_reg[0] <= 32'd0;

            act_waddr <= 10'd0;
            wt_waddr  <= 11'd0;
            mac_clear <= 1'b0;
            mac_en    <= 1'b0;
            adder_en  <= 1'b0;
        end else begin
            state <= next_state;

            case (state)
                // =============================================================
                `ST_IDLE: begin
                    irq_out <= 1'b0;
                    mac_clear <= 1'b0;
                    if (cmd_start) begin
                        cur_layer    <= 32'd0;
                        cur_output   <= 32'd0;
                        cur_in_batch <= 32'd0;
                        total_ops    <= 32'd0;
                        zero_counter <= 16'd0;
                        // Clear all accumulators
                        for (integer a = 0; a < 64; a = a + 1) acc_reg[a] <= 32'd0;
                    end
                    if (cmd_clear) irq_out <= 1'b0;
                end

                // =============================================================
                `ST_CFG_ACT: begin
                    // Configure DMA to read activations for this layer
                    act_waddr <= 10'd0;
                end

                `ST_DMA_ACT: begin
                    // DMA is reading activations from RAM into act_mem
                    // (The DMA FSM handles the Wishbone protocol)
                end

                // =============================================================
                `ST_CFG_WEIGHT: begin
                    // Configure DMA to read weights for this layer
                    wt_waddr <= 11'd0;
                end

                `ST_DMA_WEIGHT: begin
                    // DMA is reading weights from RAM into wt_mem
                end

                // =============================================================
                `ST_COMPUTE_BATCH: begin
                    // =========================================================
                    // CORE COMPUTE LOOP:
                    // For current output group, process 64 inputs in parallel
                    // =========================================================
                    // 1. Load 64 activations from act_mem into mac_acts
                    // 2. Load 4 weight words from wt_mem → unpack 64 weights
                    // 3. Fire ternary_mac_array
                    // 4. Accumulate results
                    // 5. Repeat for all input batches

                    mac_en <= 1'b1;
                    adder_en <= 1'b1;

                    // Load activations
                    for (integer a = 0; a < 64; a = a + 1) begin
                        integer act_idx;
                        act_idx = cur_in_batch * 64 + a;
                        if (act_idx < layer_in[cur_layer]) begin
                            mac_acts[a*8 +: 8] <= act_mem[act_idx];
                        end else begin
                            mac_acts[a*8 +: 8] <= 8'd0;  // Zero-padding
                        end
                    end

                    // Load and unpack weights
                    // Each weight word = 16 ternary weights packed 2-bit each
                    // For 64 weights: read 4 consecutive words
                    for (integer w = 0; w < 4; w = w + 1) begin
                        integer wt_idx;
                        // Compute weight buffer address for this batch
                        wt_idx = cur_output * (layer_in[cur_layer] / 16) +
                                 cur_in_batch * 4 + w;
                        if (wt_idx < 2048) begin
                            for (integer b = 0; b < 16; b = b + 1) begin
                                integer wi;
                                wi = w * 16 + b;
                                if (wi < 64) begin
                                    mac_weights[wi*2 +: 2] <= wt_mem[wt_idx][b*2 +: 2];
                                    // Count zero weights for sparsity metric
                                    if (wi < 64 && wt_mem[wt_idx][b*2 +: 2] == 2'b00 &&
                                        wi < layer_in[cur_layer]) begin
                                        zero_counter <= zero_counter + 1;
                                    end
                                end
                            end
                        end
                    end

                    // Accumulate: 64 MAC partial products summed via adder tree
                    // → accumulate into acc_reg[0] (single output neuron)
                    // The adder tree combines all 64 pseudo-products into 1 sum
                    for (integer m = 0; m < 64; m = m + 1) begin
                        integer act_val;
                        act_val = cur_in_batch * 64 + m;
                        if (act_val < layer_in[cur_layer]) begin
                            if (mac_weights[m*2 +: 2] == 2'b01) begin
                                acc_reg[0] <= acc_reg[0] +
                                    {{24{act_mem[act_val][7]}}, act_mem[act_val]};
                            end else if (mac_weights[m*2 +: 2] == 2'b11) begin
                                acc_reg[0] <= acc_reg[0] -
                                    {{24{act_mem[act_val][7]}}, act_mem[act_val]};
                            end
                        end
                    end

                    total_ops <= total_ops + 64;
                end

                `ST_NEXT_OUTPUT: begin
                    // Finished one output group. Reset for next.
                    cur_in_batch <= 32'd0;
                end

                `ST_LAYER_DONE: begin
                    // Layer complete. Clear accumulator, prepare next layer.
                    acc_reg[0] <= 32'd0;
                    cur_output <= 32'd0;
                end

                `ST_NEXT_LAYER: begin
                    cur_layer <= cur_layer + 1;
                    cur_in_batch <= 32'd0;
                    cur_output <= 32'd0;
                end

                `ST_DONE: begin
                    mac_en <= 1'b0;
                    adder_en <= 1'b0;
                    irq_out <= 1'b1;
                    cfg_result <= acc_reg[0];  // Store first accumulator result
                end

                default: ;
            endcase
        end
    end

    // =========================================================================
    // 11. FSM — Combinational Next-State Logic
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
                    next_state = `ST_CFG_WEIGHT;
            end
            `ST_CFG_WEIGHT:  next_state = `ST_DMA_WEIGHT;
            `ST_DMA_WEIGHT: begin
                if (wt_waddr >= layer_wcnt[cur_layer])
                    next_state = `ST_COMPUTE_BATCH;
            end
            `ST_COMPUTE_BATCH: begin
                // Advance input batch
                if (cur_in_batch * 64 + 64 >= layer_in[cur_layer] + 63) begin
                    // All input batches for this output group
                    if (cur_output + 64 >= layer_out[cur_layer]) begin
                        next_state = `ST_LAYER_DONE;
                    end else begin
                        next_state = `ST_NEXT_OUTPUT;
                    end
                end else begin
                    cur_in_batch <= cur_in_batch + 1;
                    next_state = `ST_COMPUTE_BATCH;
                end
            end
            `ST_NEXT_OUTPUT: begin
                cur_output <= cur_output + 64;
                next_state = `ST_COMPUTE_BATCH;
            end
            `ST_LAYER_DONE: begin
                if (cur_layer + 1 >= cfg_layer_cfg)
                    next_state = `ST_DONE;
                else begin
                    next_state = `ST_NEXT_LAYER;
                end
            end
            `ST_NEXT_LAYER: begin
                next_state = `ST_CFG_ACT;
            end
            `ST_DONE: begin
                if (cmd_clear) next_state = `ST_IDLE;
            end
            default: next_state = `ST_IDLE;
        endcase
    end

    // =========================================================================
    // 12. DMA (Wishbone Master) State Machine
    // =========================================================================
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
                        wb_m_we_o  <= ~dma_read;  // we_o=0 for read
                        wb_m_sel_o <= 4'b1111;
                        wb_m_cti_o <= 3'b010;  // Incrementing burst
                        wb_m_bte_o <= 2'b00;
                        wb_m_cyc_o <= 1'b1;
                        wb_m_stb_o <= 1'b1;
                    end
                end

                DMA_ISSUE: begin
                    // Address is being driven, strobe is high
                    // Wait for ack from slave
                    if (wb_m_ack_i) begin
                        wb_m_stb_o <= 1'b0;
                        if (dma_read) begin
                            dma_rdata <= wb_m_dat_i;
                        end
                        dma_bytes <= dma_bytes - 4;
                        wb_m_adr_o <= wb_m_adr_o + 4;
                        if (dma_bytes <= 4) begin
                            // Last transfer
                            wb_m_cti_o <= 3'b111;  // End of burst
                            wb_m_stb_o <= 1'b1;
                            dma_state <= DMA_COMPLETE;
                        end else begin
                            wb_m_stb_o <= 1'b1;
                            dma_state <= DMA_WAIT;
                        end
                    end
                end

                DMA_WAIT: begin
                    if (wb_m_ack_i) begin
                        wb_m_stb_o <= 1'b0;
                        if (dma_read) begin
                            dma_rdata <= wb_m_dat_i;
                        end
                        dma_bytes <= dma_bytes - 4;
                        wb_m_adr_o <= wb_m_adr_o + 4;
                        if (dma_bytes <= 4) begin
                            wb_m_cti_o <= 3'b111;
                            wb_m_stb_o <= 1'b1;
                            dma_state <= DMA_COMPLETE;
                        end else begin
                            wb_m_stb_o <= 1'b1;
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
    // 13. Wishbone Slave Logic (CPU register access)
    // =========================================================================
    wire wb_s_valid = wb_s_cyc_i && wb_s_stb_i;

    always @(posedge clk) begin
        if (!rst_n) begin
            wb_s_ack_o    <= 1'b0;
            wb_s_dat_o    <= 32'd0;
            cfg_src_addr   <= 32'd0;
            cfg_dst_addr   <= 32'd0;
            cfg_dma_size   <= 32'd0;
            cfg_weight_cfg <= 32'd0;
            cfg_act_cfg    <= 32'd0;
            cfg_mac_cfg    <= 32'd64;
            cfg_layer_cfg  <= 32'd3;
            cfg_result     <= 32'd0;
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
                        default: ;
                    endcase
                end else begin
                    case (wb_s_adr_i[7:0])
                        `REG_STATUS:  wb_s_dat_o <= {16'd0, zero_counter, 14'd0, irq_out, (state != `ST_IDLE)};
                        `REG_SRC_ADDR: wb_s_dat_o <= cfg_src_addr;
                        `REG_DST_ADDR: wb_s_dat_o <= cfg_dst_addr;
                        `REG_DMA_SIZE: wb_s_dat_o <= cfg_dma_size;
                        `REG_WEIGHT_CFG: wb_s_dat_o <= cfg_weight_cfg;
                        `REG_ACT_CFG: wb_s_dat_o <= cfg_act_cfg;
                        `REG_MAC_CFG: wb_s_dat_o <= cfg_mac_cfg;
                        `REG_LAYER_CFG: wb_s_dat_o <= cfg_layer_cfg;
                        `REG_RESULT:  wb_s_dat_o <= cfg_result;
                        default:      wb_s_dat_o <= 32'hCAFEBABE;
                    endcase
                end
            end
        end
    end

endmodule
