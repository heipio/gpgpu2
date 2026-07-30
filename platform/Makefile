PLATFORM ?= xilinx_u280_gen3x16_xdma_1_202211_1
TARGET ?= hw
KERNEL := aec_gpgpu
ROOT := ..
BITSTREAM_DIR := $(ROOT)/bitstream
XO := $(BITSTREAM_DIR)/$(KERNEL).$(TARGET).xo
XCLBIN := $(BITSTREAM_DIR)/$(KERNEL).$(TARGET).xclbin
HOST := $(ROOT)/driver/aec_xrt_host

.PHONY: all env-check check-kernel ipxact host xo xclbin emconfig clean

all: env-check check-kernel host

env-check:
	@which v++ >/dev/null
	@which vivado >/dev/null
	@test -d /opt/xilinx/xrt/include
	@test -d /opt/xilinx/platforms/$(PLATFORM)
	@v++ --version | head -n 3
	@echo "PLATFORM=$(PLATFORM)"

check-kernel:
	vivado -mode batch -source package_kernel.tcl -tclargs --check-only

ipxact:
	vivado -mode batch -source package_kernel.tcl -tclargs --ipxact

host:
	mkdir -p $(ROOT)/driver
	g++ -std=c++14 -O2 -Wall -Wextra -I/opt/xilinx/xrt/include -L/opt/xilinx/xrt/lib -Wl,-rpath,/opt/xilinx/xrt/lib -o $(HOST) $(ROOT)/driver/aec_xrt_host.cpp -lxrt_coreutil -pthread -lrt -ldl

xo: ipxact
	mkdir -p $(BITSTREAM_DIR)
	vivado -mode batch -source package_kernel.tcl -tclargs $(XO)

xclbin: xo
	v++ -l -t $(TARGET) --platform $(PLATFORM) --config connectivity.cfg -o $(XCLBIN) $(XO)

emconfig:
	emconfigutil --platform $(PLATFORM) --od $(BITSTREAM_DIR)

clean:
	rm -rf $(ROOT)/driver/aec_xrt_host $(ROOT)/_x $(BITSTREAM_DIR)/$(KERNEL).*.xo $(BITSTREAM_DIR)/$(KERNEL).*.xclbin vivado*.jou vivado*.log .Xil
