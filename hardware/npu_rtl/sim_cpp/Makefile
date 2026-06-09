# Makefile — NPU Ternária Simulation Suite
# Ternary Edge-RV Project
#
# Targets:
#   make demo      — Compila e roda a simulação C++ (funciona AGORA!)
#   make verilog   — Compila e roda testbench Verilog (requer iverilog)
#   make view      — Visualiza waveform (requer gtkwave)
#   make clean     — Remove arquivos compilados
#   make all       — Roda tudo

CXX      = g++
CXXFLAGS = -std=c++11 -Wall -Wextra -O2
IVERILOG = iverilog
VVP      = vvp
GTKWAVE  = gtkwave

# ==============================================================================
# Simulação C++ (roda em qualquer PC com g++)
# ==============================================================================
NPU_SRCS  = demo_npu.cpp npu_sim.cpp
NPU_OBJS  = $(NPU_SRCS:.cpp=.o)
NPU_BIN   = demo_npu

$(NPU_BIN): $(NPU_OBJS)
	$(CXX) $(CXXFLAGS) -o $@ $^

demo: $(NPU_BIN)
	./$(NPU_BIN)

# ==============================================================================
# Simulação Verilog (requer iverilog)
# ==============================================================================
VERILOG_SRC = tb_npu_ternaria_top.v npu_ternaria_top.v ternary_mac.v
VERILOG_BIN = tb_npu.vvp

$(VERILOG_BIN): $(VERILOG_SRC)
	$(IVERILOG) -o $@ $^

verilog: $(VERILOG_BIN)
	$(VVP) $(VERILOG_BIN)

view: verilog
	$(GTKWAVE) tb_npu.vcd &

# ==============================================================================
# Python Golden Model
# ==============================================================================
python_test:
	python3 python/golden_model.py

# ==============================================================================
# All-in-One
# ==============================================================================
all: demo

# ==============================================================================
# Cleanup
# ==============================================================================
clean:
	rm -f $(NPU_OBJS) $(NPU_BIN) $(VERILOG_BIN) tb_npu.vcd
	rm -f *.o *.vvp *.vcd

.PHONY: all demo verilog view python_test clean
