# Simulate the LFSR testbench with GHDL + UVVM
# Usage: make        -> compile, elaborate, run, write wave.vcd
#        make clean  -> remove build files

UVVM_LIBS := $(HOME)/Projects/uvvm_build/ghdl
GHDL      := ghdl
GHDLFLAGS := --std=08 -frelaxed -fsynopsys -P$(UVVM_LIBS)
TB        := tb_lfsr_uvvm
SRC       := src/lfsr.vhd src/$(TB).vhd

all: run

analyze: $(SRC)
	$(GHDL) -a $(GHDLFLAGS) $(SRC)

elab: analyze
	$(GHDL) -e $(GHDLFLAGS) $(TB)

run: elab
	$(GHDL) -r $(GHDLFLAGS) $(TB) --vcd=wave.vcd

clean:
	rm -f *.o $(TB) wave.vcd work-obj08.cf UVVM_Alert.txt UVVM_Log.txt build.log

.PHONY: all analyze elab run clean
