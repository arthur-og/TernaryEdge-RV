/*
 * npu_sim_v2.h — NPU v2 Simulator (64 MACs + DMA + Layer Sequencer)
 * Ternary Edge-RV Project
 *
 * Bit-accurate C++ simulation of npu_ternaria_top_v2.v.
 * Matches the Verilog RTL cycle-by-cycle for golden model verification.
 *
 * Key differences from v1:
 *   - 64 parallel MACs (instead of 1)
 *   - Wishbone Master DMA (autonomous RAM access)
 *   - Layer Sequencer (iterates 3 layers automatically)
 *   - 12K-word weight buffer + 1K activation buffer
 *   - 64 × 32-bit accumulators
 *   - STATUS register: zero_counter at bits [15:8] (aligned with RTL)
 */

#ifndef NPU_SIM_V2_H
#define NPU_SIM_V2_H

#include <cstdint>
#include <cstring>
#include <cstdio>
#include <cassert>

class NPUSimV2 {
public:
    // Register map (matches Verilog `define REG_*)
    enum RegAddr {
        REG_STATUS      = 0x00,
        REG_CONTROL     = 0x04,
        REG_SRC_ADDR    = 0x08,
        REG_DST_ADDR    = 0x0C,
        REG_DMA_SIZE    = 0x10,
        REG_WEIGHT_CFG  = 0x14,
        REG_ACT_CFG     = 0x18,
        REG_RESULT      = 0x1C,
        REG_MAC_CFG     = 0x20,
        REG_LAYER_CFG   = 0x24,
        REG_COUNT       = 10     // 10 registers total
    };

    // Memory sizes
    static const int WEIGHT_BUF_SIZE = 2048;   // Weight tile buffer
    static const int ACT_BUF_SIZE    = 1024;   // Activation buffer

    // Layer config for MNIST MLP
    static const int NUM_LAYERS = 3;
    static const int LAYER_INPUTS[NUM_LAYERS];
    static const int LAYER_OUTPUTS[NUM_LAYERS];
    static const int LAYER_WORDS[NUM_LAYERS];  // Weight words per layer

    NPUSimV2() { reset(); }

    // ---- Core Simulation ----
    void reset();
    void clock_cycle();
    void run_cycles(int n) { for (int i = 0; i < n; i++) clock_cycle(); }

    // ---- Register Access (Wishbone Slave) ----
    void wb_write(uint8_t addr, uint32_t data);
    uint32_t wb_read(uint8_t addr);

    // ---- DMA Buffer Access ----
    // Simulates the Wishbone Master reading from a RAM buffer
    void attach_ram(uint32_t* ram, uint32_t ram_size);
    void set_dma_buffer(const uint32_t* weights, int num_words);
    void set_activations(const uint8_t* acts, int num_acts);

    // ---- High-Level API ----
    void start_inference();
    void wait_for_irq(int timeout = 500000);
    bool irq_received() const { return m_irq; }
    uint32_t get_result() const { return m_cfg_result; }

    // ---- Stats ----
    int get_zero_skipped() const { return m_zero_skipped; }
    int get_total_cycles() const { return m_total_cycles; }
    uint32_t get_accumulator(int idx) const { return m_acc_reg[idx]; }

    // ---- FSM State constants (public for test API) ----
    static const int ST_IDLE_VAL           = 0;
    static const int ST_CFG_ACT_VAL        = 1;
    static const int ST_DMA_ACT_VAL        = 2;
    static const int ST_CFG_WEIGHT_VAL     = 3;
    static const int ST_DMA_WEIGHT_VAL     = 4;
    static const int ST_COMPUTE_BATCH_VAL  = 5;
    static const int ST_NEXT_OUTPUT_VAL    = 6;
    static const int ST_LAYER_DONE_VAL     = 7;
    static const int ST_NEXT_LAYER_VAL     = 8;
    static const int ST_DONE_VAL           = 9;

    // ---- Test API (for golden model verification) ----
    void set_act_buffer(const uint8_t* data, int len);
    void set_weight_buffer(const uint32_t* data, int len);
    void set_state_and_counters(int layer, int output, int batch);
    void force_state(int st) { m_state = static_cast<State>(st); }
    const uint8_t* get_act_buf() const { return m_act_buf; }
    const uint32_t* get_wt_buf() const { return m_wt_buf; }

    // ---- Debug ----
    void dump_status() const;
    void dump_registers() const;

private:
    // ---- Registers ----
    uint32_t m_regs[REG_COUNT];

    // ---- Configuration registers (named) ----
    uint32_t& m_cfg_src_addr   = m_regs[0];  // REG_STATUS
    // Note: actual mapping is: regs[REG_ADDR/4], but using named refs
    uint32_t m_cfg_src;
    uint32_t m_cfg_dst;
    uint32_t m_cfg_dma_size;
    uint32_t m_cfg_weight_cfg;
    uint32_t m_cfg_act_cfg;
    uint32_t m_cfg_result;
    uint32_t m_cfg_mac_cfg;
    uint32_t m_cfg_layer_cfg;

    // ---- Internal Buffers ----
    uint32_t m_wt_buf[WEIGHT_BUF_SIZE];  // Weight tile buffer
    uint8_t  m_act_buf[ACT_BUF_SIZE];    // Activation buffer
    int m_wt_wptr;
    int m_act_wptr;

    // ---- External RAM (DMA simulation) ----
    uint32_t* m_ext_ram;
    uint32_t  m_ext_ram_size;

    // ---- FSM State ----
    enum State {
        ST_IDLE, ST_CFG_ACT, ST_DMA_ACT, ST_CFG_WEIGHT, ST_DMA_WEIGHT,
        ST_COMPUTE_BATCH, ST_NEXT_OUTPUT, ST_LAYER_DONE, ST_NEXT_LAYER, ST_DONE
    };
    State m_state;

    // ---- FSM Counters ----
    int m_cur_layer;
    int m_cur_output;
    int m_cur_in_batch;
    int m_total_ops;
    int m_zero_skipped;
    int m_total_cycles;

    // ---- Accumulators (64 × 32-bit) ----
    int32_t m_acc_reg[64];

    // ---- Control Signals ----
    bool m_irq;
    bool m_start_pending;
    bool m_clear_pending;

    // ---- DMA State ----
    enum DMAState { DMA_IDLE, DMA_ISSUE, DMA_WAIT, DMA_COMPLETE };
    DMAState m_dma_state;
    bool m_dma_read;
    uint32_t m_dma_addr;
    int m_dma_bytes;
    uint32_t m_dma_rdata;
    bool m_dma_done;
    bool m_dma_start;

    // ---- Helper ----
    int get_cycles_for_dma_read(int bytes);
    void run_dma_cycle();
    void process_compute_batch();
};

#endif // NPU_SIM_V2_H
