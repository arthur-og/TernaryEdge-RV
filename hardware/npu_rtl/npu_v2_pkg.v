/*
 * npu_v2_pkg.v — NPU v2 Shared Definitions Package
 * Ternary Edge-RV Project
 * 
 * Shared parameters, register map, and type definitions
 * for the NPU v2 (64 MACs, Wishbone Master DMA, Layer Sequencer).
 */

// =============================================================================
// Register Map (32-bit Wishbone Slave, Little-Endian)
// =============================================================================
`define REG_STATUS      8'h00   // RO: [0]=busy, [1]=irq, [7:2]=layer_id, [15:8]=zero_counter
`define REG_CONTROL     8'h04   // WO: [0]=start, [1]=clear_irq
`define REG_SRC_ADDR    8'h08   // RW: DMA source (weights/acts in RAM)
`define REG_DST_ADDR    8'h0C   // RW: DMA destination (result in RAM)
`define REG_DMA_SIZE    8'h10   // RW: Total MAC ops to execute
`define REG_WEIGHT_CFG  8'h14   // RW: [15:0]=bytes_per_row, [31:16]=num_rows
`define REG_ACT_CFG     8'h18   // RW: [15:0]=num_activations
`define REG_RESULT      8'h1C   // RO: Final accumulated result
`define REG_MAC_CFG     8'h20   // RW: [5:0]=num_macs (default 64)
`define REG_LAYER_CFG   8'h24   // RW: [7:0]=num_layers (default 3)
`define REG_RESULT_WINDOW 8'h28 // RO: Windowed read of acc_reg[0..63], indexed by [5:0]
`define REG_LAYER_CTRL  8'h2C   // RW: [0]=irq_per_layer, [5:0]=result_window_idx

// =============================================================================
// Memory Sizes
// =============================================================================
`define WEIGHT_BRAM_DEPTH 12288     // 12K words × 32 bits
`define WEIGHT_BRAM_AWIDTH 14       // 2^14 = 16384 > 12288
`define ACT_BRAM_DEPTH    1024      // 1K words × 8 bits
`define ACT_BRAM_AWIDTH   10        // 2^10 = 1024

// =============================================================================
// MAC Array Parameters
// =============================================================================
`define NUM_MACS       64
`define MAC_ACT_WIDTH  8
`define MAC_ACC_WIDTH  32

// =============================================================================
// FSM States
// =============================================================================
`define ST_IDLE          4'd0
`define ST_CFG_WEIGHT    4'd1   // Configure weight DMA read
`define ST_DMA_WEIGHT    4'd2   // Reading weights from RAM
`define ST_CFG_ACT       4'd3   // Configure activation DMA read
`define ST_DMA_ACT       4'd4   // Reading activations from RAM
`define ST_COMPUTE_BATCH 4'd5   // Computing one batch (64 MACs)
`define ST_NEXT_OUTPUT   4'd6   // Moving to next output neuron
`define ST_WRITE_RESULT  4'd7   // DMA write acc_reg to external RAM
`define ST_LAYER_DONE    4'd8   // Layer finished
`define ST_NEXT_LAYER    4'd9   // Transition to next layer
`define ST_DONE          4'd10  // All layers complete, assert IRQ

// Compute sub-steps (used inside ST_COMPUTE_BATCH via compute_step register)
`define COMPUTE_STEP_LOAD_WEIGHTS 2'd0  // DMA read 4 weight words from RAM
`define COMPUTE_STEP_UNPACK       2'd1  // Unpack weights into mac_weights
`define COMPUTE_STEP_ACCUMULATE   2'd2  // Compute 64 MACs and accumulate
