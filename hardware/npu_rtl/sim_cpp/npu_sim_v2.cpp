/*
 * npu_sim_v2.cpp — NPU v2 Simulator Implementation
 * Ternary Edge-RV Project
 *
 * Bit-accurate C++ simulation of npu_ternaria_top_v2.v.
 * Mirrors the Verilog RTL cycle-by-cycle for golden model verification.
 *
 * Architecture:
 *   - 64 parallel multiplierless MACs
 *   - Wishbone Master DMA (reads weights/activations from external RAM)
 *   - Layer Sequencer (3 layers: 784→1024, 1024→512, 512→256)
 *   - 64 × 32-bit accumulator register file
 *   - STATUS: zero_counter at bits [15:8] (fixed to match RTL v2)
 */

#include "npu_sim_v2.h"

// Layer configuration (matches NPU v2 Verilog)
const int NPUSimV2::LAYER_INPUTS[3]  = { 784, 1024, 512 };
const int NPUSimV2::LAYER_OUTPUTS[3] = { 1024, 512, 256 };
const int NPUSimV2::LAYER_WORDS[3]   = { 50176, 32768, 8192 };

// =============================================================================
// Reset
// =============================================================================
void NPUSimV2::reset() {
    memset(m_regs, 0, sizeof(m_regs));
    memset(m_wt_buf, 0, sizeof(m_wt_buf));
    memset(m_act_buf, 0, sizeof(m_act_buf));
    memset(m_acc_reg, 0, sizeof(m_acc_reg));

    m_cfg_src = 0;
    m_cfg_dst = 0;
    m_cfg_dma_size = 0;
    m_cfg_weight_cfg = 0;
    m_cfg_act_cfg = 0;
    m_cfg_result = 0;
    m_cfg_mac_cfg = 64;
    m_cfg_layer_cfg = 3;

    m_wt_wptr = 0;
    m_act_wptr = 0;
    m_ext_ram = nullptr;
    m_ext_ram_size = 0;

    m_state = ST_IDLE;
    m_cur_layer = 0;
    m_cur_output = 0;
    m_cur_in_batch = 0;
    m_total_ops = 0;
    m_zero_skipped = 0;
    m_total_cycles = 0;

    m_irq = false;
    m_start_pending = false;
    m_clear_pending = false;

    m_dma_state = DMA_IDLE;
    m_dma_read = true;
    m_dma_addr = 0;
    m_dma_bytes = 0;
    m_dma_rdata = 0;
    m_dma_done = false;
    m_dma_start = false;
}

// =============================================================================
// Attach External RAM (for DMA simulation)
// =============================================================================
void NPUSimV2::attach_ram(uint32_t* ram, uint32_t ram_size) {
    m_ext_ram = ram;
    m_ext_ram_size = ram_size;
}

void NPUSimV2::set_dma_buffer(const uint32_t* weights, int num_words) {
    if (m_ext_ram && num_words * 4 <= (int)m_ext_ram_size) {
        memcpy(m_ext_ram, weights, num_words * sizeof(uint32_t));
    }
}

void NPUSimV2::set_activations(const uint8_t* acts, int num_acts) {
    if (m_ext_ram && num_acts * 4 <= (int)m_ext_ram_size) {
        // Store activations in the first part of extended RAM
        memcpy(m_ext_ram, acts, num_acts * sizeof(uint8_t));
    }
}

// =============================================================================
// DMA Simulation (Wishbone Master)
// =============================================================================
void NPUSimV2::run_dma_cycle() {
    switch (m_dma_state) {
        case DMA_IDLE:
            m_dma_done = false;
            if (m_dma_start) {
                m_dma_state = DMA_ISSUE;
                m_dma_start = false;
            }
            break;

        case DMA_ISSUE:
            // First word: address + strobe
            // Simulate 2-cycle Wishbone handshake (issue + ack)
            if (m_dma_read && m_ext_ram) {
                if (m_dma_addr / 4 < m_ext_ram_size) {
                    m_dma_rdata = m_ext_ram[m_dma_addr / 4];
                } else {
                    m_dma_rdata = 0;
                }
            }
            m_dma_bytes -= 4;
            m_dma_addr += 4;
            // Fall through to check if done

            if (m_dma_bytes <= 0) {
                m_dma_done = true;
                m_dma_state = DMA_IDLE;
            } else {
                m_dma_state = DMA_WAIT;
            }
            break;

        case DMA_WAIT:
            // Subsequent words: burst read
            if (m_dma_read && m_ext_ram) {
                if (m_dma_addr / 4 < m_ext_ram_size) {
                    m_dma_rdata = m_ext_ram[m_dma_addr / 4];
                } else {
                    m_dma_rdata = 0;
                }
            }
            m_dma_bytes -= 4;
            m_dma_addr += 4;

            if (m_dma_bytes <= 0) {
                m_dma_done = true;
                m_dma_state = DMA_IDLE;
            }
            // If not done, stay in WAIT (next word will be read next cycle)
            break;

        case DMA_COMPLETE:
            m_dma_done = true;
            m_dma_state = DMA_IDLE;
            break;
    }
}

// =============================================================================
// Compute Batch (64 MACs in parallel)
// =============================================================================
void NPUSimV2::process_compute_batch() {
    // Process 64 input activations × 64 weights → sum into 1 accumulator
    //
    // Architecture: 64 MACs compute 64 partial products (one per input),
    // which are summed by the adder tree and accumulated into acc[0].
    //
    // This corresponds to computing 1 output neuron with 64 input activations.
    // The outer loop (in the FSM) iterates over all output neurons.
    //
    // Layout: weight words stored as [output_neuron][input_group][4_words]
    //   Each "output neuron slice" has N/16 weight words.
    //   Each "input group of 64" spans 4 consecutive weight words.
    int batch_base = m_cur_in_batch * 64;
    int num_inputs = LAYER_INPUTS[m_cur_layer];

    // Accumulate all 64 MAC results into acc[0] (adder tree simulation)
    int32_t tree_sum = 0;

    for (int k = 0; k < 64; k++) {
        int act_idx = batch_base + k;
        if (act_idx >= num_inputs) break;  // Zero-padding for last partial batch

        int8_t act = static_cast<int8_t>(m_act_buf[act_idx]);

        // Read 1 weight word (16 weights), pick weight k%16
        // For this output neuron (m_cur_output), the weight words are at:
        //   m_cur_output * (num_inputs/16) + (batch_base + k) / 16
        int words_per_output = num_inputs / 16;  // e.g., 49 for layer 0
        int word_addr = m_cur_output * words_per_output + (batch_base + k) / 16;

        if (word_addr < WEIGHT_BUF_SIZE) {
            uint32_t w_word = m_wt_buf[word_addr];
            uint8_t weight = (w_word >> ((k % 16) * 2)) & 0x03;

            // Multiplierless MAC
            int32_t pseudo_prod;
            if (weight == 0b01) {
                pseudo_prod = act;                    // weight = +1
            } else if (weight == 0b11) {
                pseudo_prod = -act;                   // weight = -1
            } else {
                pseudo_prod = 0;                      // weight = 0 (sparsity)
                m_zero_skipped++;
            }
            tree_sum += pseudo_prod;
        }
    }

    // All 64 partial products summed → accumulate into output neuron 0
    m_acc_reg[0] += tree_sum;
    m_total_ops += 64;
}

// =============================================================================
// Clock Cycle (matches Verilog always block)
// =============================================================================
void NPUSimV2::clock_cycle() {
    m_total_cycles++;

    // ---- Process start/clear pulses ----
    bool start_pulse = m_start_pending;
    bool clear_pulse = m_clear_pending;
    m_start_pending = false;
    m_clear_pending = false;

    // ---- FSM ----
    switch (m_state) {
        case ST_IDLE:
            m_irq = false;
            if (start_pulse) {
                m_cur_layer = 0;
                m_cur_output = 0;
                m_cur_in_batch = 0;
                m_total_ops = 0;
                m_zero_skipped = 0;
                memset(m_acc_reg, 0, sizeof(m_acc_reg));
                m_state = ST_CFG_ACT;
            }
            if (clear_pulse) m_irq = false;
            break;

        // =============================================================
        // LOAD ACTIVATIONS via DMA
        // =============================================================
        case ST_CFG_ACT: {
            // Configure DMA read: activations start at cfg_src + layer_offset
            m_act_wptr = 0;
            m_dma_addr = m_cfg_src + m_cur_layer * 1024;
            m_dma_bytes = LAYER_INPUTS[m_cur_layer];
            m_dma_read = true;
            m_dma_start = true;
            m_state = ST_DMA_ACT;
            break;
        }

        case ST_DMA_ACT: {
            run_dma_cycle();
            if (m_dma_done) {
                // DMA transfer complete — data is already in m_dma_rdata
                // For simulation, we read from ext_ram directly
                uint32_t* src = m_ext_ram + (m_cfg_src + m_cur_layer * 1024) / 4;
                int bytes = LAYER_INPUTS[m_cur_layer];
                for (int i = 0; i < bytes && i < ACT_BUF_SIZE; i++) {
                    m_act_buf[i] = reinterpret_cast<uint8_t*>(src)[i];
                }
                m_act_wptr = bytes;
                m_state = ST_CFG_WEIGHT;
            }
            break;
        }

        // =============================================================
        // LOAD WEIGHTS via DMA
        // =============================================================
        case ST_CFG_WEIGHT: {
            m_wt_wptr = 0;
            // Weights stored after activations in RAM
            m_dma_addr = m_cfg_src + 4096 + m_cur_layer * 131072;
            m_dma_bytes = LAYER_WORDS[m_cur_layer] * 4;  // 4 bytes per word
            m_dma_read = true;
            m_dma_start = true;
            m_state = ST_DMA_WEIGHT;
            break;
        }

        case ST_DMA_WEIGHT: {
            run_dma_cycle();
            if (m_dma_done) {
                // Copy weight data from ext_ram to weight buffer
                uint32_t* src = m_ext_ram + (m_cfg_src + 4096 + m_cur_layer * 131072) / 4;
                int words = LAYER_WORDS[m_cur_layer];
                int to_copy = (words < WEIGHT_BUF_SIZE) ? words : WEIGHT_BUF_SIZE;
                memcpy(m_wt_buf, src, to_copy * sizeof(uint32_t));
                m_wt_wptr = to_copy;
                m_state = ST_COMPUTE_BATCH;
            }
            break;
        }

        // =============================================================
        // COMPUTE: 64 MACs per batch
        // =============================================================
        case ST_COMPUTE_BATCH: {
            process_compute_batch();

            // Advance input batch
            m_cur_in_batch++;
            int num_batches = (LAYER_INPUTS[m_cur_layer] + 63) / 64;

            if (m_cur_in_batch >= num_batches) {
                // All inputs processed for this output group
                m_cur_in_batch = 0;
                m_cur_output += 64;

                if (m_cur_output >= LAYER_OUTPUTS[m_cur_layer]) {
                    m_state = ST_LAYER_DONE;
                } else {
                    m_state = ST_NEXT_OUTPUT;
                }
            }
            // Else: stay in ST_COMPUTE_BATCH for next input batch
            break;
        }

        case ST_NEXT_OUTPUT: {
            memset(m_acc_reg, 0, sizeof(m_acc_reg));
            m_cur_output += 64;
            m_state = ST_COMPUTE_BATCH;
            break;
        }

        case ST_NEXT_LAYER: {
            m_cur_layer++;
            m_state = ST_CFG_ACT;
            break;
        }

        case ST_LAYER_DONE: {
            // Layer complete — advance to next or finish
            m_cur_layer++;
            if (m_cur_layer >= (int)m_cfg_layer_cfg) {
                m_cfg_result = m_acc_reg[0];  // Store final result
                m_state = ST_DONE;
                m_irq = true;
            } else {
                memset(m_acc_reg, 0, sizeof(m_acc_reg));
                m_cur_output = 0;
                m_cur_in_batch = 0;
                m_state = ST_CFG_ACT;  // Load next layer's activations
            }
            break;
        }

        case ST_DONE: {
            // Wait for clear
            if (clear_pulse) {
                m_irq = false;
                m_state = ST_IDLE;
            }
            break;
        }
    }
}

// =============================================================================
// Wishbone Slave: Register Write
// =============================================================================
void NPUSimV2::wb_write(uint8_t addr, uint32_t data) {
    switch (addr) {
        case REG_CONTROL:
            if (data & 0x01) m_start_pending = true;
            if (data & 0x02) m_clear_pending = true;
            return;

        case REG_SRC_ADDR:   m_cfg_src      = data; return;
        case REG_DST_ADDR:   m_cfg_dst      = data; return;
        case REG_DMA_SIZE:   m_cfg_dma_size  = data; return;
        case REG_WEIGHT_CFG: m_cfg_weight_cfg = data; return;
        case REG_ACT_CFG:    m_cfg_act_cfg   = data; return;
        case REG_MAC_CFG:    m_cfg_mac_cfg   = data; return;
        case REG_LAYER_CFG:  m_cfg_layer_cfg = data; return;

        default:
            break;
    }
}

// =============================================================================
// Wishbone Slave: Register Read
// =============================================================================
uint32_t NPUSimV2::wb_read(uint8_t addr) {
    switch (addr) {
        case REG_STATUS:
            // [15:8] = zero_counter (aligned with RTL v2!)
            // [1] = irq, [0] = busy
            return (static_cast<uint32_t>(m_zero_skipped) << 8) |
                   (m_irq ? 0x02 : 0x00) |
                   ((m_state != ST_IDLE) ? 0x01 : 0x00);

        case REG_SRC_ADDR:   return m_cfg_src;
        case REG_DST_ADDR:   return m_cfg_dst;
        case REG_DMA_SIZE:   return m_cfg_dma_size;
        case REG_WEIGHT_CFG: return m_cfg_weight_cfg;
        case REG_ACT_CFG:    return m_cfg_act_cfg;
        case REG_MAC_CFG:    return m_cfg_mac_cfg;
        case REG_LAYER_CFG:  return m_cfg_layer_cfg;
        case REG_RESULT:     return m_cfg_result;

        default:
            return 0xDEADBEEF;
    }
}

// =============================================================================
// Test API
// =============================================================================
void NPUSimV2::set_act_buffer(const uint8_t* data, int len) {
    int to_copy = (len < ACT_BUF_SIZE) ? len : ACT_BUF_SIZE;
    memcpy(m_act_buf, data, to_copy);
    m_act_wptr = to_copy;
}

void NPUSimV2::set_weight_buffer(const uint32_t* data, int len) {
    int to_copy = (len < WEIGHT_BUF_SIZE) ? len : WEIGHT_BUF_SIZE;
    memcpy(m_wt_buf, data, to_copy * sizeof(uint32_t));
    m_wt_wptr = to_copy;
}

void NPUSimV2::set_state_and_counters(int layer, int output, int batch) {
    m_cur_layer = layer;
    m_cur_output = output;
    m_cur_in_batch = batch;
    m_state = ST_COMPUTE_BATCH;
}

// =============================================================================
// High-Level API
// =============================================================================
void NPUSimV2::start_inference() {
    m_start_pending = true;
}

void NPUSimV2::wait_for_irq(int timeout) {
    int cycles = 0;
    while (!m_irq && cycles < timeout) {
        clock_cycle();
        cycles++;
    }
    if (cycles >= timeout) {
        printf("[NPUv2][WARNING] Timeout waiting for IRQ! (%d cycles)\n", timeout);
    }
}

// =============================================================================
// Debug
// =============================================================================
void NPUSimV2::dump_status() const {
    const char* state_names[] = {
        "IDLE", "CFG_ACT", "DMA_ACT", "CFG_WEIGHT", "DMA_WEIGHT",
        "COMPUTE_BATCH", "NEXT_OUTPUT", "LAYER_DONE", "NEXT_LAYER", "DONE"
    };
    printf("=== NPU v2 Status ===\n");
    printf("  State:       %s\n", state_names[m_state]);
    printf("  Layer:       %d/3\n", m_cur_layer);
    printf("  Output:      %d/1024\n", m_cur_output);
    printf("  Batch:       %d\n", m_cur_in_batch);
    printf("  IRQ:         %s\n", m_irq ? "ASSERTED" : "deasserted");
    printf("  Total Ops:   %d\n", m_total_ops);
    printf("  Zero skip:   %d\n", m_zero_skipped);
    printf("  Cycles:      %d\n", m_total_cycles);
    printf("  Acc[0]:      %d (0x%08X)\n", m_acc_reg[0], m_acc_reg[0]);
    printf("===================\n");
}

void NPUSimV2::dump_registers() const {
    printf("=== NPU v2 Registers ===\n");
    printf("  CFG_SRC_ADDR:   0x%08X\n", m_cfg_src);
    printf("  CFG_DST_ADDR:   0x%08X\n", m_cfg_dst);
    printf("  CFG_DMA_SIZE:   %u\n", m_cfg_dma_size);
    printf("  CFG_WEIGHT_CFG: 0x%08X\n", m_cfg_weight_cfg);
    printf("  CFG_ACT_CFG:    0x%08X\n", m_cfg_act_cfg);
    printf("  CFG_MAC_CFG:    %u\n", m_cfg_mac_cfg);
    printf("  CFG_LAYER_CFG:  %u\n", m_cfg_layer_cfg);
    printf("  RESULT:         %d (0x%08X)\n", m_cfg_result, m_cfg_result);
    printf("======================\n");
}
