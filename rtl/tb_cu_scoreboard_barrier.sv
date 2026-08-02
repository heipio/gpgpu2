`timescale 1ns/1ps
`default_nettype none

module tb_cu_scoreboard_barrier;
  import aec_pkg::*;

  localparam logic [127:0] LOADI_R1_SEVEN =
      128'h0055_0090_0001_0000_00000007_00000000;
  localparam logic [127:0] ADD_R2_R1_5 =
      128'h0001_0090_0002_0001_00000005_00000000;
  localparam logic [127:0] BAR_SYNC_0_ALL =
      128'h0044_0000_0000_0000_00000000_00000000;
  localparam logic [127:0] ADD_R3_R2_1 =
      128'h0001_0090_0003_0002_00000001_00000000;
  localparam logic [127:0] HALT_INSTR =
      128'h0045_0000_0000_0000_00000000_00000000;

  logic clk_i;
  logic rst_ni;

  logic [63:0] s_axil_awaddr;
  logic s_axil_awvalid;
  logic s_axil_awready;
  logic [31:0] s_axil_wdata;
  logic [3:0] s_axil_wstrb;
  logic s_axil_wvalid;
  logic s_axil_wready;
  logic [1:0] s_axil_bresp;
  logic s_axil_bvalid;
  logic s_axil_bready;
  logic [63:0] s_axil_araddr;
  logic s_axil_arvalid;
  logic s_axil_arready;
  logic [31:0] s_axil_rdata;
  logic [1:0] s_axil_rresp;
  logic s_axil_rvalid;
  logic s_axil_rready;

  logic [63:0] m_axi_awaddr;
  logic [7:0] m_axi_awlen;
  logic [2:0] m_axi_awsize;
  logic [1:0] m_axi_awburst;
  logic m_axi_awvalid;
  logic m_axi_awready;
  logic [511:0] m_axi_wdata;
  logic [63:0] m_axi_wstrb;
  logic m_axi_wlast;
  logic m_axi_wvalid;
  logic m_axi_wready;
  logic [1:0] m_axi_bresp;
  logic m_axi_bvalid;
  logic m_axi_bready;
  logic [63:0] m_axi_araddr;
  logic [7:0] m_axi_arlen;
  logic [2:0] m_axi_arsize;
  logic [1:0] m_axi_arburst;
  logic m_axi_arvalid;
  logic m_axi_arready;
  logic [511:0] m_axi_rdata;
  logic [1:0] m_axi_rresp;
  logic m_axi_rlast;
  logic m_axi_rvalid;
  logic m_axi_rready;

  logic instr_ready_o;
  logic issue_valid_o;
  logic [1:0] issue_beat_o;
  logic [7:0] physical_active_mask_o;
  logic [15:0] decoded_opcode_o;
  logic [7:0] decoded_dst_reg_o;
  logic [7:0] decoded_src1_reg_o;
  logic [7:0] decoded_src2_reg_o;
  logic [7:0] decoded_src3_reg_o;

  cu_top #(
    .NUM_WARPS(2),
    .USE_EXTERNAL_INSTR(1'b0),
    .TRACE_HALT_FINISH(1'b0)
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
    .instr_valid_i(1'b0),
    .instr_ready_o(instr_ready_o),
    .instr_i(128'd0),
    .warp_active_mask_i(32'h0000_00ff),
    .issue_valid_o(issue_valid_o),
    .issue_ready_i(1'b1),
    .issue_beat_o(issue_beat_o),
    .physical_active_mask_o(physical_active_mask_o),
    .decoded_opcode_o(decoded_opcode_o),
    .decoded_dst_reg_o(decoded_dst_reg_o),
    .decoded_src1_reg_o(decoded_src1_reg_o),
    .decoded_src2_reg_o(decoded_src2_reg_o),
    .decoded_src3_reg_o(decoded_src3_reg_o)
  );

  initial clk_i = 1'b0;
  always #5 clk_i = ~clk_i;

  task automatic axil_write(input logic [63:0] addr, input logic [31:0] data);
    begin
      @(negedge clk_i);
      s_axil_awaddr = addr;
      s_axil_wdata = data;
      s_axil_wstrb = 4'hf;
      s_axil_awvalid = 1'b1;
      s_axil_wvalid = 1'b1;
      wait (s_axil_awready && s_axil_wready);
      @(negedge clk_i);
      s_axil_awvalid = 1'b0;
      s_axil_wvalid = 1'b0;
      wait (s_axil_bvalid);
      @(negedge clk_i);
    end
  endtask

  task automatic axil_read(input logic [63:0] addr, output logic [31:0] data);
    begin
      @(negedge clk_i);
      s_axil_araddr = addr;
      s_axil_arvalid = 1'b1;
      wait (s_axil_arready);
      @(negedge clk_i);
      s_axil_arvalid = 1'b0;
      wait (s_axil_rvalid);
      data = s_axil_rdata;
      @(negedge clk_i);
    end
  endtask

  task automatic write_instr(input int pc, input logic [127:0] instr);
    begin
      axil_write(64'h1000 + pc * 16 + 0, instr[31:0]);
      axil_write(64'h1000 + pc * 16 + 4, instr[63:32]);
      axil_write(64'h1000 + pc * 16 + 8, instr[95:64]);
      axil_write(64'h1000 + pc * 16 + 12, instr[127:96]);
    end
  endtask

  logic [31:0] ctrl;
  logic saw_barrier_release;
  integer poll;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      saw_barrier_release <= 1'b0;
    end else begin
      if (dut.barrier_release_valid) begin
        saw_barrier_release <= 1'b1;
      end
    end
  end

  initial begin
    rst_ni = 1'b0;
    s_axil_awaddr = 64'd0;
    s_axil_awvalid = 1'b0;
    s_axil_wdata = 32'd0;
    s_axil_wstrb = 4'hf;
    s_axil_wvalid = 1'b0;
    s_axil_bready = 1'b1;
    s_axil_araddr = 64'd0;
    s_axil_arvalid = 1'b0;
    s_axil_rready = 1'b1;
    m_axi_awready = 1'b1;
    m_axi_wready = 1'b1;
    m_axi_bresp = 2'b00;
    m_axi_bvalid = 1'b0;
    m_axi_arready = 1'b1;
    m_axi_rdata = 512'd0;
    m_axi_rresp = 2'b00;
    m_axi_rlast = 1'b1;
    m_axi_rvalid = 1'b0;

    repeat (4) @(posedge clk_i);
    rst_ni = 1'b1;
    repeat (4) @(posedge clk_i);

    write_instr(0, LOADI_R1_SEVEN);
    write_instr(1, ADD_R2_R1_5);
    write_instr(2, BAR_SYNC_0_ALL);
    write_instr(3, ADD_R3_R2_1);
    write_instr(4, HALT_INSTR);
    axil_write(64'h0004, 32'd0);
    axil_write(64'h0040, 32'd1);
    axil_write(64'h0044, 32'd64);
    axil_write(64'h0000, 32'd1);

    for (poll = 0; poll < 500; poll = poll + 1) begin
      axil_read(64'h0000, ctrl);
      if (ctrl[1]) begin
        assert (saw_barrier_release)
          else $fatal(1, "dynamic barrier did not release");
        assert (dut.u_vrf_top.g_vrf_lane[0].u_vrf_lane.bank_r1[{1'd0, 8'd2, 2'd0}] == 32'd12)
          else $fatal(1, "warp0 R2 expected 12");
        assert (dut.u_vrf_top.g_vrf_lane[0].u_vrf_lane.bank_r1[{1'd1, 8'd2, 2'd0}] == 32'd12)
          else $fatal(1, "warp1 R2 expected 12");
        assert (dut.u_vrf_top.g_vrf_lane[0].u_vrf_lane.bank_r1[{1'd0, 8'd3, 2'd0}] == 32'd13)
          else $fatal(1, "warp0 R3 expected 13");
        assert (dut.u_vrf_top.g_vrf_lane[0].u_vrf_lane.bank_r1[{1'd1, 8'd3, 2'd0}] == 32'd13)
          else $fatal(1, "warp1 R3 expected 13");
        $display("CU_SCOREBOARD_BARRIER TEST PASSED");
        $finish;
      end
    end
    $fatal(1, "timeout waiting for DONE");
  end
endmodule

`default_nettype wire
