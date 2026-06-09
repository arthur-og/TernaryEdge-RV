/*
 * npu_sim.cpp — C++ NPU Simulator Implementation
 * Ternary Edge-RV Project
 *
 * This implementation mirrors the Verilog RTL (npu_ternaria_top.v + ternary_mac.v)
 * cycle-by-cycle for bit-accurate simulation.
 *
 * MAC Operation (Multiplierless):
 *   pseudo_prod = (weight == +1) ?  act_in :
 *                 (weight == -1) ? -act_in :
 *                                  0
 *   acc_out = acc_out + pseudo_prod
 *
 * Weight encoding: +1 = 0b01, 0 = 0b00, -1 = 0b11
 */

#include "npu_sim.h"

void NPUSim::reset() {
    // Reset all registers
    memset(m_r, 0, sizeof(m_r));
    memset(m_weight_mem, 0, sizeof(m_weight_mem));
    memset(m_act_mem, 0, sizeof(m_act_mem));

    m_wptr_weight = 0;
    m_wptr_act    = 0;

    m_state        = ST_IDLE;
    m_mac_counter  = 0;
    m_accumulator  = 0;
    m_zero_skipped = 0;

    m_rptr_weight    = 0;
    m_rptr_act       = 0;
    m_weight_sub_idx = 0;

    m_irq           = false;
    m_start_pending = false;
    m_clear_pending = false;

    m_current_act         = 0;
    m_current_weight_raw  = 0;
}

void NPUSim::clock_cycle() {
    // ---------------------------------------------------------------
    // Combinational logic: extract current weight from memory word
    // ---------------------------------------------------------------
    uint32_t weight_word = m_weight_mem[m_rptr_weight];
    uint8_t  raw_weight  = (weight_word >> (m_weight_sub_idx * 2)) & 0x3;
    m_current_weight_raw = raw_weight;
    m_current_act        = m_act_mem[m_rptr_act];

    // ---------------------------------------------------------------
    // Ternary MAC combinational logic
    // ---------------------------------------------------------------
    int32_t act_signed   = static_cast<int8_t>(m_current_act);
    int32_t pseudo_prod;

    // The MULTIPLIERLESS operation:
    //   weight=01 (+1) -> pass activation through
    //   weight=11 (-1) -> negate activation (2's complement)
    //   weight=00 ( 0) -> zero (sparsity optimization!)
    switch (raw_weight) {
        case 0b01: pseudo_prod = act_signed;              break;  // +1: pass through
        case 0b11: pseudo_prod = -act_signed;             break;  // -1: negate
        default:   pseudo_prod = 0;                                 //  0: skip
    }

    // ---------------------------------------------------------------
    // FSM (sequential logic - matches Verilog always blocks)
    // ---------------------------------------------------------------
    bool start_pulse = m_start_pending;
    bool clear_pulse = m_clear_pending;
    m_start_pending = false;
    m_clear_pending = false;

    switch (m_state) {
        case ST_IDLE:
            if (start_pulse) {
                m_mac_counter    = 0;
                m_zero_skipped   = 0;
                m_rptr_weight    = 0;
                m_rptr_act       = 0;
                m_weight_sub_idx = 0;

                if (m_r[REG_DATA_SIZE / 4] == 0) {
                    m_state = ST_DONE;
                } else {
                    m_state = ST_READ_W;
                }
            }
            if (clear_pulse) {
                m_irq = false;
            }
            break;

        case ST_READ_W:
            m_state = ST_READ_A;
            break;

        case ST_READ_A:
            // Both weight and activation are valid now
            m_state = ST_COMPUTE;
            break;

        case ST_COMPUTE:
            // MAC executes (pseudo_prod added to accumulator)
            m_accumulator += pseudo_prod;

            // Sparsity counting
            if (raw_weight == 0b00) {
                m_zero_skipped++;
            }

            m_mac_counter++;

            if (m_mac_counter >= m_r[REG_DATA_SIZE / 4]) {
                // All MACs done
                m_r[REG_RESULT / 4] = m_accumulator;
                m_state = ST_DONE;
                m_irq   = true;  // Fire IRQ!
            } else {
                // Advance pointers for next MAC
                if (m_weight_sub_idx >= 15) {
                    m_rptr_weight++;
                    m_weight_sub_idx = 0;
                } else {
                    m_weight_sub_idx++;
                }
                m_rptr_act++;
                m_state = ST_READ_W;
            }
            break;

        case ST_DONE:
            if (clear_pulse) {
                m_irq = false;
                m_state = ST_IDLE;
            }
            break;
    }
}

void NPUSim::wb_write(uint8_t addr, uint32_t data) {
    // Extract register index (word-aligned)
    int reg_idx = (addr & 0x1F) / 4;

    switch (addr) {
        case REG_CONTROL:
            // Bit 0 = Start, Bit 1 = Clear IRQ
            if (data & 0x01) m_start_pending = true;
            if (data & 0x02) m_clear_pending = true;
            // Note: CONTROL doesn't store its value (WO)
            return;

        case REG_WEIGHT_DATA:
            if (m_wptr_weight < WEIGHT_MEM_SIZE) {
                m_weight_mem[m_wptr_weight] = data;
                m_wptr_weight++;
            }
            return;

        case REG_ACT_DATA:
            if (m_wptr_act < ACT_MEM_SIZE) {
                m_act_mem[m_wptr_act] = static_cast<uint8_t>(data & 0xFF);
                m_wptr_act++;
            }
            return;

        default:
            if (reg_idx >= 0 && reg_idx < 8) {
                m_r[reg_idx] = data;
            }
            break;
    }
}

uint32_t NPUSim::wb_read(uint8_t addr) {
    int reg_idx = (addr & 0x1F) / 4;

    switch (addr) {
        case REG_STATUS:
            // [31:16] = zero_skipped, [15:2] = 0, [1] = irq, [0] = busy
            return (static_cast<uint32_t>(m_zero_skipped) << 16) |
                   (m_irq ? 0x02 : 0x00) |
                   ((m_state != ST_IDLE) ? 0x01 : 0x00);

        default:
            if (reg_idx >= 0 && reg_idx < 8) {
                return m_r[reg_idx];
            }
            return 0xDEADBEEF;
    }
}

void NPUSim::load_weights(const uint32_t* words, int num_words) {
    m_wptr_weight = 0;
    int to_copy = (num_words < WEIGHT_MEM_SIZE) ? num_words : WEIGHT_MEM_SIZE;
    memcpy(m_weight_mem, words, to_copy * sizeof(uint32_t));
    m_wptr_weight = to_copy;
}

void NPUSim::load_activations(const uint8_t* acts, int num_acts) {
    m_wptr_act = 0;
    int to_copy = (num_acts < ACT_MEM_SIZE) ? num_acts : ACT_MEM_SIZE;
    memcpy(m_act_mem, acts, to_copy * sizeof(uint8_t));
    m_wptr_act = to_copy;
}

void NPUSim::set_data_size(uint32_t size) {
    m_r[REG_DATA_SIZE / 4] = size;
}

void NPUSim::start_inference() {
    m_start_pending = true;
}

void NPUSim::wait_for_irq(int timeout) {
    int cycles = 0;
    while (!m_irq && cycles < timeout) {
        clock_cycle();
        cycles++;
    }
    if (cycles >= timeout) {
        printf("[NPU][WARNING] Timeout waiting for IRQ! (%d cycles)\n", timeout);
    }
}

void NPUSim::dump_status() const {
    const char* state_names[] = { "IDLE", "READ_W", "READ_A", "COMPUTE", "DONE" };
    printf("=== NPU Status ===\n");
    printf("  State:       %s\n", state_names[m_state]);
    printf("  IRQ:         %s\n", m_irq ? "ASSERTED" : "deasserted");
    printf("  MAC count:   %u\n", m_mac_counter);
    printf("  Accumulator: %d\n", m_accumulator);
    printf("  Zero skipped:%d\n", m_zero_skipped);
    printf("  Result:      %u (0x%08X)\n", m_r[REG_RESULT / 4], m_r[REG_RESULT / 4]);
    printf("  Weight ptr:  %d[sub=%d]\n", m_rptr_weight, m_weight_sub_idx);
    printf("  Act ptr:     %d\n", m_rptr_act);
    printf("==================\n");
}
