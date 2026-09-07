/*
 * Shared v2 contract.
 *
 * The bus is byte addressed, 32 bits wide and little endian.  A layer stores
 * weights output-major: all packed words for neuron 0, then neuron 1, etc.
 * Each word contains 16 weights, with weight[0] in bits [1:0].
 */

`define NPU_MAX_LAYERS       8
`define NPU_ACT_BUFFER_SIZE  1024
`define NPU_NUM_PES          64
`define NPU_ACT_WIDTH        8
`define NPU_PROD_WIDTH       9
`define NPU_ACC_WIDTH        32

/* MMIO register map. */
`define REG_STATUS           8'h00
`define REG_CONTROL          8'h04
`define REG_INPUT_ADDR       8'h08
`define REG_OUTPUT_ADDR      8'h0c
`define REG_WEIGHT_ADDR      8'h10
`define REG_BIAS_ADDR        8'h14
`define REG_SCALE_ADDR       8'h18
`define REG_LAYER_COUNT      8'h1c
`define REG_LAYER_INDEX      8'h20
`define REG_LAYER_INPUTS     8'h24
`define REG_LAYER_OUTPUTS    8'h28
`define REG_LAYER_QUANT      8'h2c
`define REG_RESULT           8'h30
`define REG_RESULT_WINDOW    8'h34
`define REG_ERROR_INFO       8'h38
`define REG_CAPABILITIES     8'h3c
`define REG_MAC_CFG          8'h40

/* Unambiguous source-compatible names for the common old addresses. */
`define REG_SRC_ADDR         `REG_INPUT_ADDR
`define REG_DST_ADDR         `REG_OUTPUT_ADDR

/* CONTROL bits. */
`define CONTROL_START        0
`define CONTROL_CLEAR_IRQ    1

/* LAYER_QUANT fields. */
`define QUANT_SHIFT_LSB      0
`define QUANT_SHIFT_MSB      5
`define QUANT_RELU_BIT       8

/* Internal sequencer states. */
`define ST_IDLE              5'd0
`define ST_INPUT_CMD         5'd1
`define ST_INPUT_WAIT        5'd2
`define ST_LAYER_SETUP       5'd3
`define ST_WEIGHT_CMD        5'd4
`define ST_WEIGHT_WAIT       5'd5
`define ST_COMPUTE_LAUNCH    5'd6
`define ST_COMPUTE_WAIT      5'd7
`define ST_BIAS_CMD          5'd8
`define ST_BIAS_WAIT         5'd9
`define ST_SCALE_CMD         5'd10
`define ST_SCALE_WAIT        5'd11
`define ST_POSTPROCESS       5'd12
`define ST_OUTPUT_CMD        5'd13
`define ST_OUTPUT_WAIT       5'd14
`define ST_NEXT_OUTPUT       5'd15
`define ST_NEXT_LAYER        5'd16
`define ST_DONE              5'd17
`define ST_ERROR             5'd18
`define ST_POSTPROCESS_WAIT  5'd19
