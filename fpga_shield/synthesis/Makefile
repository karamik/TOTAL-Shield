PROJECT_DIR = ./vivado_project
REPORTS_DIR = ./reports
OUTPUT_DIR = ./output

all: clean run

run:
	vivado -mode batch -source run_all.tcl

synthesize:
	vivado -mode batch -source synthesize.tcl

implement: synthesize
	vivado -mode batch -source implement.tcl

bitstream: implement
	vivado -mode batch -source generate_bitstream.tcl

clean:
	rm -rf $(PROJECT_DIR) $(REPORTS_DIR) $(OUTPUT_DIR) *.log *.jou

.PHONY: all run synthesize implement bitstream clean
