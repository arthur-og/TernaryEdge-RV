/*
 * npu_sim.h — C++ NPU Simulator (Bit-Accurate with Verilog RTL)
 * Ternary Edge-RV Project
 * 
 * This header defines the NPU simulator class that exactly mimics
 * the Verilog behavior of npu_ternaria_top.v + ternary_mac.v.
 * 
 * Use this to:
 *   1. Verify the architecture works (runs on any PC)
 *   2. Generate test vectors for the Verilog simulation
 *   3. Serve as a "golden model" for RTL verification
 */

#ifndef NPU_SIM_H
#define NPU_SIM_H

#include <cstdint>
#include <cstring>
#include <cstdio>

class NPUSim {
public:
    // Register addresses (matches Verilog)
    enum RegAddr {
        REG_STATUS      = 0x00,
        REG_CONTROL     = 0x04,
        REG_SRC_ADDR    = 0x08,
        REG_DST_ADDR    = 0x0C,
        REG_DATA_SIZE   = 0x10,
        REG_WEIGHT_DATA = 0x14,
        REG_ACT_DATA    = 0x18,
        REG_RESULT      = 0x1C
    };

    NPUSim() { reset(); }

    // ---- Hardware Interface ----
    void reset();
    void clock_cycle();  // Single clock cycle
    void run_cycles(int n) { for (int i = 0; i < n; i++) clock_cycle(); }

    // ---- Wishbone Transactions (combines timing) ----
    void wb_write(uint8_t addr, uint32_t data);
    uint32_t wb_read(uint8_t addr);

    // ---- High-Level Test API ----
    void load_weights(const uint32_t* words, int num_words);
    void load_activations(const uint8_t* acts, int num_acts);
    void set_data_size(uint32_t size);
    void start_inference();
    void wait_for_irq(int timeout = 1000);
    bool irq_received() const { return m_irq; }
    uint32_t get_result() const { return m_r[REG_RESULT / 4]; }

    // ---- Statistics ----
    int get_zero_skipped() const { return m_zero_skipped; }

    // ---- Debug ----
    void dump_status() const;

private:
    // Registers (memory-mapped)
    uint32_t m_r[8];  // 8 registers: STATUS, CONTROL, SRC_ADDR, DST_ADDR, DATA_SIZE, WEIGHT, ACT, RESULT

    // Internal SRAM
    static const int WEIGHT_MEM_SIZE = 512;
    static const int ACT_MEM_SIZE = 1024;
    uint32_t m_weight_mem[WEIGHT_MEM_SIZE];
    uint8_t  m_act_mem[ACT_MEM_SIZE];

    // Write pointers (auto-increment)
    int m_wptr_weight;
    int m_wptr_act;

    // FSM state
    enum State { ST_IDLE, ST_READ_W, ST_READ_A, ST_COMPUTE, ST_DONE };
    State m_state;

    // FSM counters
    uint32_t m_mac_counter;
    uint32_t m_accumulator;
    int m_zero_skipped;

    // Memory read pointers
    int m_rptr_weight;
    int m_rptr_act;
    int m_weight_sub_idx;

    // IRQ
    bool m_irq;
    bool m_start_pending;
    bool m_clear_pending;

    // Current operands
    uint8_t  m_current_act;
    uint8_t  m_current_weight_raw; // 2-bit weight
};

#endif // NPU_SIM_H
