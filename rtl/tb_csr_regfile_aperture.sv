`timescale 1ns/1ps
`default_nettype none

module tb_csr_regfile_aperture;
  import aec_pkg::*;

  logic clk_i = 1'b0;
  logic rst_ni = 1'b0;
  logic [63:0] awaddr;
  logic awvalid;
  logic awready;
  logic [31:0] wdata;
  logic [3:0] wstrb;
  logic wvalid;
  logic wready;
  logic [1:0] bresp;
  logic bvalid;
  logic bready;
  logic [63:0] araddr;
  logic arvalid;
  logic arready;
  logic [31:0] rdata;
  logic [1:0] rresp;
  logic rvalid;
  logic rready;
  logic start_pulse;
  logic [15:0] start_pc;
  logic imem_we;
  logic [9:0] imem_word_addr;
  logic [31:0] imem_wdata;
  logic [3:0] imem_wstrb;
  logic [9:0] imem_read_word_addr;

  always #5 clk_i = ~clk_i;

  csr_regfile dut (
    .clk_i(clk_i), .rst_ni(rst_ni),
    .s_axil_awaddr(awaddr), .s_axil_awvalid(awvalid), .s_axil_awready(awready),
    .s_axil_wdata(wdata), .s_axil_wstrb(wstrb), .s_axil_wvalid(wvalid),
    .s_axil_wready(wready), .s_axil_bresp(bresp), .s_axil_bvalid(bvalid),
    .s_axil_bready(bready), .s_axil_araddr(araddr), .s_axil_arvalid(arvalid),
    .s_axil_arready(arready), .s_axil_rdata(rdata), .s_axil_rresp(rresp),
    .s_axil_rvalid(rvalid), .s_axil_rready(rready),
    .gpu_done_i(1'b0), .gpu_running_i(1'b0), .fault_valid_i(1'b0),
    .fault_code_i(AEC_FAULT_NONE), .fault_pc_i(16'd0), .fault_meta_i(32'd0),
    .start_pulse_o(start_pulse), .start_pc_o(start_pc), .imem_we_o(imem_we),
    .imem_word_addr_o(imem_word_addr), .imem_wdata_o(imem_wdata),
    .imem_wstrb_o(imem_wstrb), .imem_read_word_addr_o(imem_read_word_addr),
    .imem_rdata_i(32'd0)
  );

  task automatic axil_read(input logic [63:0] addr, output logic [31:0] value);
    begin
      @(posedge clk_i);
      araddr <= addr;
      arvalid <= 1'b1;
      do @(posedge clk_i); while (!arready);
      arvalid <= 1'b0;
      do @(posedge clk_i); while (!rvalid);
      assert (rresp == 2'b00) else $fatal(1, "AXI-Lite read error at %h", addr);
      value = rdata;
      rready <= 1'b1;
      @(posedge clk_i);
      rready <= 1'b0;
    end
  endtask

  logic [31:0] value;
  initial begin
    awaddr = '0; awvalid = 1'b0; wdata = '0; wstrb = 4'hf; wvalid = 1'b0;
    bready = 1'b1; araddr = '0; arvalid = 1'b0; rready = 1'b0;
    repeat (3) @(posedge clk_i);
    rst_ni = 1'b1;

    axil_read(64'h0000_1234_0000_0020, value);
    assert (value == 32'haec0_6001) else $fatal(1, "CAP_MAGIC mismatch: %h", value);
    axil_read(64'h0000_1234_0000_0024, value);
    assert (value == 32'h0001_0000) else $fatal(1, "CAP_VERSION mismatch: %h", value);
    axil_read(64'h0000_1234_0000_002c, value);
    assert (value == 32'h0000_07ff) else $fatal(1, "CAP_FEATURES mismatch: %h", value);
    $display("CSR_REGFILE_APERTURE TEST PASSED");
    $finish;
  end
endmodule

`default_nettype wire
