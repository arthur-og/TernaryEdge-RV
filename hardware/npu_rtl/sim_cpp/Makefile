# Makefile — NPU Ternária Simulation Suite
# Ternary Edge-RV Project
#
# Targets:
#   make demo      — NPU v1 C++ simulation
#   make legacy_demo_v2 — historical C++ v2 smoke model
#   make verilog   — NPU v1 Verilog testbench (iverilog)
#   make verilog_v2— NPU v2 Verilog testbench (iverilog)
#   make view      — View waveform (gtkwave)
#   make all       — Run Python and RTL regressions
#   make clean     — Remove compiled artifacts

CXX      = g++
CXXFLAGS = -std=c++11 -Wall -Wextra -O2
IVERILOG = iverilog
VVP      = vvp
GTKWAVE  = gtkwave

# ==============================================================================
# NPU v1 C++ Simulation (1 MAC, PIO)
# ==============================================================================
NPU1_SRCS  = demo_npu.cpp npu_sim.cpp
NPU1_OBJS  = $(NPU1_SRCS:.cpp=.o)
NPU1_BIN   = demo_npu

$(NPU1_BIN): $(NPU1_OBJS)
	$(CXX) $(CXXFLAGS) -o $@ $^

demo: $(NPU1_BIN)
	./$(NPU1_BIN)

# ==============================================================================
# NPU v2 C++ Simulation (64 MACs, DMA, Layer Sequencer)
# ==============================================================================
NPU2_SRCS  = demo_npu_v2.cpp npu_sim_v2.cpp
NPU2_OBJS  = $(NPU2_SRCS:.cpp=.o)
NPU2_BIN   = demo_npu_v2

$(NPU2_BIN): $(NPU2_OBJS)
	$(CXX) $(CXXFLAGS) -o $@ $^

legacy_demo_v2: $(NPU2_BIN)
	./$(NPU2_BIN)

# ==============================================================================
# NPU v1 Verilog Testbench (1 MAC)
# ==============================================================================
VERILOG1_SRC  = ../tb_npu_ternaria_top.v ../npu_ternaria_top.v ../ternary_mac.v
VERILOG1_BIN  = tb_npu.vvp

$(VERILOG1_BIN): $(VERILOG1_SRC)
	$(IVERILOG) -g2012 -o $@ $^

verilog: $(VERILOG1_BIN)
	$(VVP) $(VERILOG1_BIN)

# ==============================================================================
# NPU v2 Verilog Testbench (64 MACs, DMA)
# ==============================================================================
VERILOG2_SRC  = ../tb_npu_v2.v ../npu_ternaria_top_v2.v \
                ../wishbone_master.v \
                ../ternary_mac.v ../ternary_mac_array.v \
                ../adder_tree_64.v ../postprocess_unit.v ../npu_v2_pkg.v
VERILOG2_WIDTHS = 16 32 64
VERILOG2_BIN  = tb_npu_v2_64.vvp

verilog_v2_%: $(VERILOG2_SRC)
	$(IVERILOG) -g2012 -I.. -Ptb_npu_v2.PHYSICAL_PES=$* -o tb_npu_v2_$*.vvp $(VERILOG2_SRC)
	$(VVP) tb_npu_v2_$*.vvp

verilog_v2: verilog_v2_64

verilog_v2_matrix: $(addprefix verilog_v2_,$(VERILOG2_WIDTHS))

VERILOG_PRIMITIVE_SRC = ../tb_ternary_primitives.v ../ternary_mac.v ../adder_tree_64.v
VERILOG_PRIMITIVE_BIN = tb_ternary_primitives.vvp

$(VERILOG_PRIMITIVE_BIN): $(VERILOG_PRIMITIVE_SRC)
	$(IVERILOG) -g2012 -I.. -o $@ $^

verilog_primitives: $(VERILOG_PRIMITIVE_BIN)
	$(VVP) $(VERILOG_PRIMITIVE_BIN)

view: verilog
	$(GTKWAVE) tb_npu.vcd &

view_v2: verilog_v2
	$(GTKWAVE) tb_npu_v2.vcd &

# ==============================================================================
# Python Golden Model
# ==============================================================================
python_test:
	python3 ../python/golden_model.py

# ==============================================================================
# All-in-One
# ==============================================================================
all: demo python_test verilog_primitives verilog_v2

# ==============================================================================
# Cleanup
# ==============================================================================
clean:
	rm -f $(NPU1_OBJS) $(NPU1_BIN)
	rm -f $(NPU2_OBJS) $(NPU2_BIN)
	rm -f *.o *.vvp *.vcd
	rm -f ../*.vcd ../*.vvp

.PHONY: all demo legacy_demo_v2 verilog verilog_v2 verilog_v2_matrix \
	verilog_primitives view view_v2 python_test clean
