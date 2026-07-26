`timescale 1ns/1ps
`default_nettype none

module tb_cu_top;
  import aec_pkg::*;

  localparam logic [127:0] FADD_R1_R2_R3 =
      128'h0004_0000_0001_0002_00000003_00000000;

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
    #8;

    instr_i       = FADD_R1_R2_R3;
    instr_valid_i = 1'b1;
    #1;
    assert (decoded_opcode_o == AEC_OP_FADD_F32)
      else $fatal(1, "decoded_opcode_o mismatch: got 0x%04h", decoded_opcode_o);
    assert (decoded_dst_reg_o == 8'd1)
      else $fatal(1, "decoded_dst_reg_o mismatch: got %0d", decoded_dst_reg_o);
    assert (decoded_src1_reg_o == 8'd2)
      else $fatal(1, "decoded_src1_reg_o mismatch: got %0d", decoded_src1_reg_o);
    assert (decoded_src2_reg_o == 8'd3)
      else $fatal(1, "decoded_src2_reg_o mismatch: got %0d", decoded_src2_reg_o);
    assert (decoded_src3_reg_o == 8'd0)
      else $fatal(1, "decoded_src3_reg_o mismatch: got %0d", decoded_src3_reg_o);

    #9;
    instr_valid_i = 1'b0;

    #1;
    check_issue_beat(2'd0, 8'hEF);
    #10;
    check_issue_beat(2'd1, 8'hBE);
    #10;
    check_issue_beat(2'd2, 8'hAD);
    #10;
    check_issue_beat(2'd3, 8'hDE);
    #10;

    assert (issue_valid_o == 1'b0)
      else $fatal(1, "issue_valid_o remained high after four beats");

    $display("TEST PASSED");
    $finish;
  end

  task automatic check_issue_beat(
    input logic [1:0] expected_beat,
    input logic [7:0] expected_mask
  );
    begin
      #1;
      assert (issue_valid_o == 1'b1)
        else $fatal(1, "issue_valid_o low at beat %0d", expected_beat);
      assert (issue_beat_o == expected_beat)
        else $fatal(1, "issue_beat_o mismatch: expected %0d got %0d",
                    expected_beat, issue_beat_o);
      assert (physical_active_mask_o == expected_mask)
        else $fatal(1, "physical_active_mask_o mismatch at beat %0d: expected 0x%02h got 0x%02h",
                    expected_beat, expected_mask, physical_active_mask_o);
    end
  endtask
endmodule

`default_nettype wire
