`timescale 1ns/1ps
`default_nettype none

module tb_cu_pipeline;
  import aec_pkg::*;

  localparam logic [127:0] IADD_R1_R2_R3 =
      128'h0001_0010_0001_0002_00000003_00000000;

  logic clk_i;
  logic rst_ni;

  logic [63:0]  s_axil_awaddr;
  logic         s_axil_awvalid;
  logic         s_axil_awready;
  logic [31:0]  s_axil_wdata;
  logic [3:0]   s_axil_wstrb;
  logic         s_axil_wvalid;
  logic         s_axil_wready;
  logic [1:0]   s_axil_bresp;
  logic         s_axil_bvalid;
  logic         s_axil_bready;
  logic [63:0]  s_axil_araddr;
  logic         s_axil_arvalid;
  logic         s_axil_arready;
  logic [31:0]  s_axil_rdata;
  logic [1:0]   s_axil_rresp;
  logic         s_axil_rvalid;
  logic         s_axil_rready;

  logic [63:0]  m_axi_awaddr;
  logic [7:0]   m_axi_awlen;
  logic [2:0]   m_axi_awsize;
  logic [1:0]   m_axi_awburst;
  logic         m_axi_awvalid;
  logic         m_axi_awready;
  logic [511:0] m_axi_wdata;
  logic [63:0]  m_axi_wstrb;
  logic         m_axi_wlast;
  logic         m_axi_wvalid;
  logic         m_axi_wready;
  logic [1:0]   m_axi_bresp;
  logic         m_axi_bvalid;
  logic         m_axi_bready;
  logic [63:0]  m_axi_araddr;
  logic [7:0]   m_axi_arlen;
  logic [2:0]   m_axi_arsize;
  logic [1:0]   m_axi_arburst;
  logic         m_axi_arvalid;
  logic         m_axi_arready;
  logic [511:0] m_axi_rdata;
  logic [1:0]   m_axi_rresp;
  logic         m_axi_rlast;
  logic         m_axi_rvalid;
  logic         m_axi_rready;

  logic         instr_valid_i;
  logic         instr_ready_o;
  logic [127:0] instr_i;
  logic [31:0]  warp_active_mask_i;
  logic         issue_valid_o;
  logic         issue_ready_i;
  logic [1:0]   issue_beat_o;
  logic [7:0]   physical_active_mask_o;
  logic [15:0]  decoded_opcode_o;
  logic [7:0]   decoded_dst_reg_o;
  logic [7:0]   decoded_src1_reg_o;
  logic [7:0]   decoded_src2_reg_o;
  logic [7:0]   decoded_src3_reg_o;

  cu_top #(
    .USE_EXTERNAL_INSTR(1'b1)
  ) dut (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .s_axil_awaddr(s_axil_awaddr),
    .s_axil_awvalid(s_axil_awvalid),
    .s_axil_awready(s_axil_awready),
    .s_axil_wdata(s_axil_wdata),
    .s_axil_wstrb(s_axil_wstrb),
    .s_axil_wvalid(s_axil_wvalid),
    .s_axil_wready(s_axil_wready),
    .s_axil_bresp(s_axil_bresp),
    .s_axil_bvalid(s_axil_bvalid),
    .s_axil_bready(s_axil_bready),
    .s_axil_araddr(s_axil_araddr),
    .s_axil_arvalid(s_axil_arvalid),
    .s_axil_arready(s_axil_arready),
    .s_axil_rdata(s_axil_rdata),
    .s_axil_rresp(s_axil_rresp),
    .s_axil_rvalid(s_axil_rvalid),
    .s_axil_rready(s_axil_rready),
    .m_axi_awaddr(m_axi_awaddr),
    .m_axi_awlen(m_axi_awlen),
    .m_axi_awsize(m_axi_awsize),
    .m_axi_awburst(m_axi_awburst),
    .m_axi_awvalid(m_axi_awvalid),
    .m_axi_awready(m_axi_awready),
    .m_axi_wdata(m_axi_wdata),
    .m_axi_wstrb(m_axi_wstrb),
    .m_axi_wlast(m_axi_wlast),
    .m_axi_wvalid(m_axi_wvalid),
    .m_axi_wready(m_axi_wready),
    .m_axi_bresp(m_axi_bresp),
    .m_axi_bvalid(m_axi_bvalid),
    .m_axi_bready(m_axi_bready),
    .m_axi_araddr(m_axi_araddr),
    .m_axi_arlen(m_axi_arlen),
    .m_axi_arsize(m_axi_arsize),
    .m_axi_arburst(m_axi_arburst),
    .m_axi_arvalid(m_axi_arvalid),
    .m_axi_arready(m_axi_arready),
    .m_axi_rdata(m_axi_rdata),
    .m_axi_rresp(m_axi_rresp),
    .m_axi_rlast(m_axi_rlast),
    .m_axi_rvalid(m_axi_rvalid),
    .m_axi_rready(m_axi_rready),
    .instr_valid_i(instr_valid_i),
    .instr_ready_o(instr_ready_o),
    .instr_i(instr_i),
    .warp_active_mask_i(warp_active_mask_i),
    .issue_valid_o(issue_valid_o),
    .issue_ready_i(issue_ready_i),
    .issue_beat_o(issue_beat_o),
    .physical_active_mask_o(physical_active_mask_o),
    .decoded_opcode_o(decoded_opcode_o),
    .decoded_dst_reg_o(decoded_dst_reg_o),
    .decoded_src1_reg_o(decoded_src1_reg_o),
    .decoded_src2_reg_o(decoded_src2_reg_o),
    .decoded_src3_reg_o(decoded_src3_reg_o)
  );

  initial begin
    clk_i = 1'b0;
    forever #5 clk_i = ~clk_i;
  end

  initial begin
    rst_ni             = 1'b0;
    s_axil_awaddr      = 64'd0;
    s_axil_awvalid     = 1'b0;
    s_axil_wdata       = 32'd0;
    s_axil_wstrb       = 4'd0;
    s_axil_wvalid      = 1'b0;
    s_axil_bready      = 1'b1;
    s_axil_araddr      = 64'd0;
    s_axil_arvalid     = 1'b0;
    s_axil_rready      = 1'b1;
    m_axi_awready      = 1'b1;
    m_axi_wready       = 1'b1;
    m_axi_bresp        = 2'b00;
    m_axi_bvalid       = 1'b0;
    m_axi_arready      = 1'b1;
    m_axi_rdata        = 512'd0;
    m_axi_rresp        = 2'b00;
    m_axi_rlast        = 1'b0;
    m_axi_rvalid       = 1'b0;
    instr_valid_i      = 1'b0;
    instr_i            = 128'd0;
    warp_active_mask_i = 32'hDEADBEEF;
    issue_ready_i      = 1'b1;

    #22;
    rst_ni = 1'b1;
    #1;

    seed_lane0_vrf();

    #7;
    instr_i       = IADD_R1_R2_R3;
    instr_valid_i = 1'b1;
    #10;
    instr_valid_i = 1'b0;

    #100;
    assert (dut.u_vrf_top.g_vrf_lane[0].u_vrf_lane.bank_r1[{8'd1, 2'd0}] == 32'd107)
      else $fatal(1, "lane0 beat0 R1 writeback mismatch");
    assert (dut.u_vrf_top.g_vrf_lane[0].u_vrf_lane.bank_r1[{8'd1, 2'd1}] == 32'hcafe0001)
      else $fatal(1, "lane0 beat1 inactive lane modified R1");
    assert (dut.u_vrf_top.g_vrf_lane[0].u_vrf_lane.bank_r1[{8'd1, 2'd2}] == 32'd127)
      else $fatal(1, "lane0 beat2 R1 writeback mismatch");
    assert (dut.u_vrf_top.g_vrf_lane[0].u_vrf_lane.bank_r1[{8'd1, 2'd3}] == 32'hcafe0003)
      else $fatal(1, "lane0 beat3 inactive lane modified R1");

    $display("PIPELINE TEST PASSED");
    $finish;
  end

  task automatic seed_lane0_vrf;
    begin
      dut.u_vrf_top.g_vrf_lane[0].u_vrf_lane.bank_r1[{8'd1, 2'd0}] = 32'hcafe0000;
      dut.u_vrf_top.g_vrf_lane[0].u_vrf_lane.bank_r1[{8'd1, 2'd1}] = 32'hcafe0001;
      dut.u_vrf_top.g_vrf_lane[0].u_vrf_lane.bank_r1[{8'd1, 2'd2}] = 32'hcafe0002;
      dut.u_vrf_top.g_vrf_lane[0].u_vrf_lane.bank_r1[{8'd1, 2'd3}] = 32'hcafe0003;

      dut.u_vrf_top.g_vrf_lane[0].u_vrf_lane.bank_r1[{8'd2, 2'd0}] = 32'd100;
      dut.u_vrf_top.g_vrf_lane[0].u_vrf_lane.bank_r1[{8'd2, 2'd1}] = 32'd110;
      dut.u_vrf_top.g_vrf_lane[0].u_vrf_lane.bank_r1[{8'd2, 2'd2}] = 32'd120;
      dut.u_vrf_top.g_vrf_lane[0].u_vrf_lane.bank_r1[{8'd2, 2'd3}] = 32'd130;

      dut.u_vrf_top.g_vrf_lane[0].u_vrf_lane.bank_r2[{8'd3, 2'd0}] = 32'd7;
      dut.u_vrf_top.g_vrf_lane[0].u_vrf_lane.bank_r2[{8'd3, 2'd1}] = 32'd7;
      dut.u_vrf_top.g_vrf_lane[0].u_vrf_lane.bank_r2[{8'd3, 2'd2}] = 32'd7;
      dut.u_vrf_top.g_vrf_lane[0].u_vrf_lane.bank_r2[{8'd3, 2'd3}] = 32'd7;
    end
  endtask
endmodule

`default_nettype wire
