IVERILOG ?= iverilog
VVP ?= vvp
VERILATOR ?= verilator
YOSYS ?= yosys
BUILD_DIR ?= build
MATRIX_WIDTHS ?= 16 32 64

RTL = npu_v2_pkg.v wishbone_master.v ternary_mac.v ternary_mac_array.v \
       adder_tree_64.v postprocess_unit.v npu_ternaria_top_v2.v
V2_TB = tb_npu_v2.v
PRIMITIVE_TB = tb_ternary_primitives.v
POSTPROCESS_TB = tb_postprocess_unit.v
WISHBONE_TB = tb_wishbone_master.v
NPU_PES ?= 64

V2_TEST_SOURCES = $(V2_TB) npu_ternaria_top_v2.v wishbone_master.v \
                  ternary_mac_array.v ternary_mac.v adder_tree_64.v \
                  postprocess_unit.v npu_v2_pkg.v

.PHONY: all test test_verilog_2005 test_timing_structure test_matrix test_ternary_primitives test_postprocess_unit \
        test_wishbone_master test_npu_v2 test_npu_v2_matrix lint lint_matrix \
        synth synth_matrix matrix clean

all: test

test: test_verilog_2005 test_timing_structure test_ternary_primitives test_postprocess_unit test_wishbone_master test_npu_v2

test_verilog_2005:
	$(IVERILOG) -g2005 -tnull -I. -s npu_ternaria_top_v2 $(RTL)

test_timing_structure:
	mkdir -p $(BUILD_DIR)
	@set -eu; \
	zero_serial_adders=$$(if rg -U -q "^[[:space:]]*batch_zero_count\\s*=\\s*batch_zero_count\\s*\\+\\s*1'b1" npu_ternaria_top_v2.v; then printf 1; else printf 0; fi); \
	if $(YOSYS) -q -p 'read_verilog -sv -I. $(RTL); hierarchy -top npu_ternaria_top_v2; proc; opt; write_rtlil $(BUILD_DIR)/npu_v2_timing.il; select -assert-none npu_ternaria_top_v2/t:$$mul' >/dev/null 2>&1; then \
		weight_address_muls=0; \
	else \
		weight_address_muls=1; \
	fi; \
	status=0; \
	if [ "$$zero_serial_adders" -ne 0 ]; then \
		printf 'FAIL timing_cone=batch_zero_count_serial_accumulation cells=%s\n' "$$zero_serial_adders"; \
		status=1; \
	else \
		printf 'PASS timing_cone=batch_zero_count_serial_accumulation cells=0\n'; \
	fi; \
	if [ "$$weight_address_muls" -ne 0 ]; then \
		printf 'FAIL timing_cone=weight_address_row_offset_multiplication cells=%s\n' "$$weight_address_muls"; \
		status=1; \
	else \
		printf 'PASS timing_cone=weight_address_row_offset_multiplication cells=0\n'; \
	fi; \
	exit "$$status"

test_matrix: test_npu_v2_matrix

test_ternary_primitives:
	mkdir -p $(BUILD_DIR)
	$(IVERILOG) -g2012 -I. -s tb_ternary_primitives -o $(BUILD_DIR)/ternary_primitives.vvp \
		$(PRIMITIVE_TB) ternary_mac.v adder_tree_64.v
	cd $(BUILD_DIR) && $(VVP) ternary_primitives.vvp

test_postprocess_unit:
	mkdir -p $(BUILD_DIR)
	$(IVERILOG) -g2012 -I. -s tb_postprocess_unit -o $(BUILD_DIR)/postprocess_unit.vvp \
		$(POSTPROCESS_TB) postprocess_unit.v
	cd $(BUILD_DIR) && $(VVP) postprocess_unit.vvp

test_wishbone_master:
	mkdir -p $(BUILD_DIR)
	$(IVERILOG) -g2012 -I. -s tb_wishbone_master -o $(BUILD_DIR)/wishbone_master.vvp \
		$(WISHBONE_TB) wishbone_master.v
	cd $(BUILD_DIR) && $(VVP) wishbone_master.vvp

test_npu_v2:
	mkdir -p $(BUILD_DIR)
	$(IVERILOG) -g2012 -I. -s tb_npu_v2 -Ptb_npu_v2.PHYSICAL_PES=$(NPU_PES) \
		-o $(BUILD_DIR)/npu_v2_$(NPU_PES).vvp $(V2_TEST_SOURCES)
	cd $(BUILD_DIR) && $(VVP) npu_v2_$(NPU_PES).vvp

test_npu_v2_matrix:
	mkdir -p $(BUILD_DIR)/matrix
	set -e; \
	for pes in $(MATRIX_WIDTHS); do \
		$(IVERILOG) -g2012 -I. -s tb_npu_v2 -Ptb_npu_v2.PHYSICAL_PES=$$pes \
			-o $(BUILD_DIR)/matrix/npu_v2_$${pes}.vvp $(V2_TEST_SOURCES); \
		(cd $(BUILD_DIR)/matrix && $(VVP) npu_v2_$${pes}.vvp); \
	done

lint:
	$(VERILATOR) --lint-only --language 1800-2012 -Wall \
		--top-module npu_ternaria_top_v2 \
		-Wno-DECLFILENAME -I. $(RTL)

lint_matrix:
	set -e; \
	for pes in $(MATRIX_WIDTHS); do \
		$(VERILATOR) --lint-only --language 1800-2012 -Wall \
			--top-module npu_ternaria_top_v2 -GNUM_PES=$$pes \
			-Wno-DECLFILENAME -I. $(RTL); \
	done

synth:
	mkdir -p $(BUILD_DIR)
	$(YOSYS) -s synth.ys | tee $(BUILD_DIR)/npu_v2_synthesis.rpt

synth_matrix:
	mkdir -p $(BUILD_DIR)/matrix
	set -e; \
	for pes in $(MATRIX_WIDTHS); do \
		$(YOSYS) -p "read_verilog -sv -I. $(RTL); chparam -set NUM_PES $$pes npu_ternaria_top_v2; hierarchy -top npu_ternaria_top_v2; proc; check; synth -top npu_ternaria_top_v2; check; stat" \
			> $(BUILD_DIR)/matrix/npu_v2_$${pes}_synthesis.rpt; \
		cat $(BUILD_DIR)/matrix/npu_v2_$${pes}_synthesis.rpt; \
	done

matrix: test_matrix lint_matrix synth_matrix

clean:
	rm -rf $(BUILD_DIR)
