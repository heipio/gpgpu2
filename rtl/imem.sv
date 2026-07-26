`timescale 1ns/1ps
`default_nettype none

module imem (
  input  wire logic         clk_i,
  input  wire logic         axil_we_i,
  input  wire logic [9:0]   axil_word_addr_i,
  input  wire logic [31:0]  axil_wdata_i,
  input  wire logic [3:0]   axil_wstrb_i,
  input  wire logic [9:0]   axil_read_word_addr_i,
  output logic [31:0]       axil_rdata_o,
  input  wire logic [9:0]   if_addr_i,
  output logic [127:0]      if_data_o
);
  localparam int IMEM_DEPTH          = 1024;
  localparam int IMEM_INSTR_BITS     = 128;
  localparam int IMEM_MEMORY_SIZE    = IMEM_DEPTH * IMEM_INSTR_BITS;
  localparam int HOST_ADDR_WIDTH     = 12;
  localparam int GPU_ADDR_WIDTH      = 10;

  logic [HOST_ADDR_WIDTH-1:0] host_write_addr;
  logic [GPU_ADDR_WIDTH-1:0]  gpu_read_addr;
  logic                      host_write_en;
  logic unused_axil_read;
  logic unused_axil_wstrb;

  assign host_write_addr = {2'b00, axil_word_addr_i};
  assign gpu_read_addr   = if_addr_i;
  assign host_write_en   = axil_we_i;
  assign axil_rdata_o    = 32'd0;

  xpm_memory_sdpram #(
    .ADDR_WIDTH_A(HOST_ADDR_WIDTH),
    .ADDR_WIDTH_B(GPU_ADDR_WIDTH),
    .AUTO_SLEEP_TIME(0),
    .BYTE_WRITE_WIDTH_A(32),
    .CASCADE_HEIGHT(0),
    .CLOCKING_MODE("common_clock"),
    .ECC_MODE("no_ecc"),
    .MEMORY_INIT_FILE("none"),
    .MEMORY_INIT_PARAM("0"),
    .MEMORY_OPTIMIZATION("true"),
    .MEMORY_PRIMITIVE("block"),
    .MEMORY_SIZE(IMEM_MEMORY_SIZE),
    .MESSAGE_CONTROL(0),
    .READ_DATA_WIDTH_B(IMEM_INSTR_BITS),
    .READ_LATENCY_B(1),
    .READ_RESET_VALUE_B("0"),
    .RST_MODE_A("SYNC"),
    .RST_MODE_B("SYNC"),
    .SIM_ASSERT_CHK(0),
    .USE_EMBEDDED_CONSTRAINT(0),
    .USE_MEM_INIT(0),
    .USE_MEM_INIT_MMI(0),
    .WAKEUP_TIME("disable_sleep"),
    .WRITE_DATA_WIDTH_A(32),
    .WRITE_MODE_B("read_first"),
    .WRITE_PROTECT(1)
  ) u_imem_xpm (
    .clka(clk_i),
    .ena(host_write_en),
    .wea(host_write_en),
    .addra(host_write_addr),
    .dina(axil_wdata_i),
    .injectdbiterra(1'b0),
    .injectsbiterra(1'b0),
    .sleep(1'b0),
    .clkb(clk_i),
    .rstb(1'b0),
    .enb(1'b1),
    .regceb(1'b1),
    .addrb(gpu_read_addr),
    .doutb(if_data_o),
    .dbiterrb(),
    .sbiterrb()
  );

  assign unused_axil_read = ^axil_read_word_addr_i;
  assign unused_axil_wstrb = ^axil_wstrb_i;
endmodule

`default_nettype wire
