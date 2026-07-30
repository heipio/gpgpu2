`timescale 1ns/1ps
`default_nettype none

module tb_soc_host_lifecycle;
  import aec_pkg::*;

  localparam logic [127:0] LOADI_R10_A =
      128'h0055_0090_000a_0000_00001000_00000000;
  localparam logic [127:0] LOADI_R11_B =
      128'h0055_0090_000b_0000_00002000_00000000;
  localparam logic [127:0] LOADI_R12_C =
      128'h0055_0090_000c_0000_00003000_00000000;
  localparam logic [127:0] LD_R1_A =
      128'h0030_0090_0001_000a_00000000_00000002;
  localparam logic [127:0] LD_R2_B =
      128'h0030_0090_0002_000b_00000000_00000002;
  localparam logic [127:0] ADD_R3_R1_R2 =
      128'h0001_0010_0003_0001_00000002_00000000;
  localparam logic [127:0] ST_C_R3 =
      128'h0031_0090_0000_000c_00000000_00030002;
  localparam logic [127:0] FENCE_DEVICE =
      128'h0034_0100_0000_0000_00000000_00000000;
  localparam logic [127:0] HALT_INSTR =
      128'h0045_0000_0000_0000_00000000_00000000;

  logic ap_clk;
  logic ap_rst_n;

  logic [63:0] s_axi_control_awaddr;
  logic s_axi_control_awvalid;
  logic s_axi_control_awready;
  logic [31:0] s_axi_control_wdata;
  logic [3:0] s_axi_control_wstrb;
  logic s_axi_control_wvalid;
  logic s_axi_control_wready;
  logic [1:0] s_axi_control_bresp;
  logic s_axi_control_bvalid;
  logic s_axi_control_bready;
  logic [63:0] s_axi_control_araddr;
  logic s_axi_control_arvalid;
  logic s_axi_control_arready;
  logic [31:0] s_axi_control_rdata;
  logic [1:0] s_axi_control_rresp;
  logic s_axi_control_rvalid;
  logic s_axi_control_rready;

  logic [63:0] m_axi_gmem_awaddr;
  logic [7:0] m_axi_gmem_awlen;
  logic [2:0] m_axi_gmem_awsize;
  logic [1:0] m_axi_gmem_awburst;
  logic m_axi_gmem_awvalid;
  logic m_axi_gmem_awready;
  logic [511:0] m_axi_gmem_wdata;
  logic [63:0] m_axi_gmem_wstrb;
  logic m_axi_gmem_wlast;
  logic m_axi_gmem_wvalid;
  logic m_axi_gmem_wready;
  logic [1:0] m_axi_gmem_bresp;
  logic m_axi_gmem_bvalid;
  logic m_axi_gmem_bready;
  logic [63:0] m_axi_gmem_araddr;
  logic [7:0] m_axi_gmem_arlen;
  logic [2:0] m_axi_gmem_arsize;
  logic [1:0] m_axi_gmem_arburst;
  logic m_axi_gmem_arvalid;
  logic m_axi_gmem_arready;
  logic [511:0] m_axi_gmem_rdata;
  logic [1:0] m_axi_gmem_rresp;
  logic m_axi_gmem_rlast;
  logic m_axi_gmem_rvalid;
  logic m_axi_gmem_rready;
  logic interrupt;

  logic [7:0] mem [0:65535];
  logic [63:0] awaddr_q;
  logic aw_seen_q;
  logic w_seen_q;
  logic [2:0] write_resp_delay_q;
  integer init_idx;
  integer axi_idx;

  aec_soc_top #(
    .NUM_WARPS(2),
    .NUM_BLOCKS(1)
  ) dut (
    .ap_clk(ap_clk),
    .ap_rst_n(ap_rst_n),
    .s_axi_control_awaddr(s_axi_control_awaddr),
    .s_axi_control_awvalid(s_axi_control_awvalid),
    .s_axi_control_awready(s_axi_control_awready),
    .s_axi_control_wdata(s_axi_control_wdata),
    .s_axi_control_wstrb(s_axi_control_wstrb),
    .s_axi_control_wvalid(s_axi_control_wvalid),
    .s_axi_control_wready(s_axi_control_wready),
    .s_axi_control_bresp(s_axi_control_bresp),
    .s_axi_control_bvalid(s_axi_control_bvalid),
    .s_axi_control_bready(s_axi_control_bready),
    .s_axi_control_araddr(s_axi_control_araddr),
    .s_axi_control_arvalid(s_axi_control_arvalid),
    .s_axi_control_arready(s_axi_control_arready),
    .s_axi_control_rdata(s_axi_control_rdata),
    .s_axi_control_rresp(s_axi_control_rresp),
    .s_axi_control_rvalid(s_axi_control_rvalid),
    .s_axi_control_rready(s_axi_control_rready),
    .m_axi_gmem_awaddr(m_axi_gmem_awaddr),
    .m_axi_gmem_awlen(m_axi_gmem_awlen),
    .m_axi_gmem_awsize(m_axi_gmem_awsize),
    .m_axi_gmem_awburst(m_axi_gmem_awburst),
    .m_axi_gmem_awvalid(m_axi_gmem_awvalid),
    .m_axi_gmem_awready(m_axi_gmem_awready),
    .m_axi_gmem_wdata(m_axi_gmem_wdata),
    .m_axi_gmem_wstrb(m_axi_gmem_wstrb),
    .m_axi_gmem_wlast(m_axi_gmem_wlast),
    .m_axi_gmem_wvalid(m_axi_gmem_wvalid),
    .m_axi_gmem_wready(m_axi_gmem_wready),
    .m_axi_gmem_bresp(m_axi_gmem_bresp),
    .m_axi_gmem_bvalid(m_axi_gmem_bvalid),
    .m_axi_gmem_bready(m_axi_gmem_bready),
    .m_axi_gmem_araddr(m_axi_gmem_araddr),
    .m_axi_gmem_arlen(m_axi_gmem_arlen),
    .m_axi_gmem_arsize(m_axi_gmem_arsize),
    .m_axi_gmem_arburst(m_axi_gmem_arburst),
    .m_axi_gmem_arvalid(m_axi_gmem_arvalid),
    .m_axi_gmem_arready(m_axi_gmem_arready),
    .m_axi_gmem_rdata(m_axi_gmem_rdata),
    .m_axi_gmem_rresp(m_axi_gmem_rresp),
    .m_axi_gmem_rlast(m_axi_gmem_rlast),
    .m_axi_gmem_rvalid(m_axi_gmem_rvalid),
    .m_axi_gmem_rready(m_axi_gmem_rready),
    .interrupt(interrupt)
  );

  initial ap_clk = 1'b0;
  always #5 ap_clk = ~ap_clk;

  task automatic host_mm_write32(input logic [31:0] addr, input logic [31:0] data);
    begin
      mem[addr[15:0] + 16'd0] = data[7:0];
      mem[addr[15:0] + 16'd1] = data[15:8];
      mem[addr[15:0] + 16'd2] = data[23:16];
      mem[addr[15:0] + 16'd3] = data[31:24];
    end
  endtask

  task automatic host_mm_read32(input logic [31:0] addr, output logic [31:0] data);
    begin
      data = {mem[addr[15:0] + 16'd3], mem[addr[15:0] + 16'd2],
              mem[addr[15:0] + 16'd1], mem[addr[15:0] + 16'd0]};
    end
  endtask

  task automatic axi_lite_write(input logic [63:0] addr, input logic [31:0] data);
    begin
      @(posedge ap_clk);
      s_axi_control_awaddr <= addr;
      s_axi_control_wdata <= data;
      s_axi_control_wstrb <= 4'hf;
      s_axi_control_awvalid <= 1'b1;
      s_axi_control_wvalid <= 1'b1;
      wait (s_axi_control_awready && s_axi_control_wready);
      @(posedge ap_clk);
      s_axi_control_awvalid <= 1'b0;
      s_axi_control_wvalid <= 1'b0;
      wait (s_axi_control_bvalid);
      assert (s_axi_control_bresp == 2'b00) else $fatal(1, "AXIL write error");
      @(posedge ap_clk);
    end
  endtask

  task automatic axi_lite_read(input logic [63:0] addr, output logic [31:0] data);
    begin
      @(posedge ap_clk);
      s_axi_control_araddr <= addr;
      s_axi_control_arvalid <= 1'b1;
      wait (s_axi_control_arready);
      @(posedge ap_clk);
      s_axi_control_arvalid <= 1'b0;
      wait (s_axi_control_rvalid);
      data = s_axi_control_rdata;
      assert (s_axi_control_rresp == 2'b00) else $fatal(1, "AXIL read error");
      @(posedge ap_clk);
    end
  endtask

  task automatic write_instr(input int pc, input logic [127:0] instr);
    begin
      axi_lite_write(64'h1000 + pc * 16 + 0, instr[31:0]);
      axi_lite_write(64'h1000 + pc * 16 + 4, instr[63:32]);
      axi_lite_write(64'h1000 + pc * 16 + 8, instr[95:64]);
      axi_lite_write(64'h1000 + pc * 16 + 12, instr[127:96]);
    end
  endtask

  logic [31:0] read_value;
  logic [31:0] ctrl;
  logic saw_fence;
  integer poll;

  always_ff @(posedge ap_clk or negedge ap_rst_n) begin
    if (!ap_rst_n) begin
      saw_fence <= 1'b0;
    end else if (dut.u_cu_top.fence_arrive_valid) begin
      saw_fence <= 1'b1;
    end
  end

  initial begin
    for (init_idx = 0; init_idx < 65536; init_idx = init_idx + 1) begin
      mem[init_idx] = 8'd0;
    end

    ap_rst_n = 1'b0;
    s_axi_control_awaddr = 64'd0;
    s_axi_control_awvalid = 1'b0;
    s_axi_control_wdata = 32'd0;
    s_axi_control_wstrb = 4'hf;
    s_axi_control_wvalid = 1'b0;
    s_axi_control_bready = 1'b1;
    s_axi_control_araddr = 64'd0;
    s_axi_control_arvalid = 1'b0;
    s_axi_control_rready = 1'b1;
    m_axi_gmem_bresp = 2'b00;
    m_axi_gmem_rresp = 2'b00;
    m_axi_gmem_rlast = 1'b1;

    repeat (4) @(posedge ap_clk);
    ap_rst_n = 1'b1;
    repeat (4) @(posedge ap_clk);

    axi_lite_read(64'h0020, read_value);
    assert (read_value == 32'haec0_6001) else $fatal(1, "capability magic mismatch");
    axi_lite_read(64'h0024, read_value);
    assert (read_value == 32'h0001_0000) else $fatal(1, "capability version mismatch");
    axi_lite_read(64'h0028, read_value);
    assert (read_value[7:0] == 8'd32 && read_value[15:8] == 8'd8 && read_value[23:16] == 8'd4)
      else $fatal(1, "capability geometry mismatch: %08x", read_value);
    axi_lite_read(64'h002c, read_value);
    assert (read_value[7:0] == 8'hff) else $fatal(1, "capability feature mask missing baseline bits");

    host_mm_write32(32'h1000, 32'd123);
    host_mm_write32(32'h2000, 32'd456);
    host_mm_write32(32'h3000, 32'd0);

    write_instr(0, LOADI_R10_A);
    write_instr(1, LOADI_R11_B);
    write_instr(2, LOADI_R12_C);
    write_instr(3, LD_R1_A);
    write_instr(4, LD_R2_B);
    write_instr(5, ADD_R3_R1_R2);
    write_instr(6, ST_C_R3);
    write_instr(7, FENCE_DEVICE);
    write_instr(8, HALT_INSTR);

    axi_lite_write(64'h0004, 32'd0);
    axi_lite_write(64'h0000, 32'd1);

    for (poll = 0; poll < 2000; poll = poll + 1) begin
      axi_lite_read(64'h0000, ctrl);
      if (ctrl[2]) begin
        $fatal(1, "GPU fault observed");
      end
      if (ctrl[1]) begin
        host_mm_read32(32'h3000, read_value);
        assert (read_value == 32'd579) else $fatal(1, "result mismatch: %0d", read_value);
        assert (saw_fence) else $fatal(1, "FENCE instruction was not observed");
        $display("SOC_HOST_LIFECYCLE TEST PASSED");
        $finish;
      end
    end
    $fatal(1, "timeout waiting for DONE");
  end

  always_ff @(posedge ap_clk or negedge ap_rst_n) begin
    if (!ap_rst_n) begin
      m_axi_gmem_awready <= 1'b0;
      m_axi_gmem_wready  <= 1'b0;
      m_axi_gmem_bvalid  <= 1'b0;
      m_axi_gmem_arready <= 1'b0;
      m_axi_gmem_rdata   <= 512'd0;
      m_axi_gmem_rvalid  <= 1'b0;
      awaddr_q           <= 64'd0;
      aw_seen_q          <= 1'b0;
      w_seen_q           <= 1'b0;
      write_resp_delay_q <= 3'd0;
    end else begin
      m_axi_gmem_awready <= !aw_seen_q && m_axi_gmem_awvalid;
      m_axi_gmem_wready  <= aw_seen_q && !w_seen_q && m_axi_gmem_wvalid;
      m_axi_gmem_arready <= !m_axi_gmem_rvalid && m_axi_gmem_arvalid;

      if (m_axi_gmem_awvalid && m_axi_gmem_awready) begin
        awaddr_q <= m_axi_gmem_awaddr;
        aw_seen_q <= 1'b1;
      end

      if (m_axi_gmem_wvalid && m_axi_gmem_wready) begin
        assert (m_axi_gmem_awsize == 3'd2) else $fatal(1, "expected 32-bit AXI store");
        for (axi_idx = 0; axi_idx < 64; axi_idx = axi_idx + 1) begin
          if (m_axi_gmem_wstrb[axi_idx]) begin
            mem[awaddr_q[15:0] + axi_idx[15:0]] <= m_axi_gmem_wdata[axi_idx*8 +: 8];
          end
        end
        w_seen_q <= 1'b1;
        write_resp_delay_q <= 3'd4;
      end

      if (aw_seen_q && w_seen_q && !m_axi_gmem_bvalid) begin
        if (write_resp_delay_q != 3'd0) begin
          write_resp_delay_q <= write_resp_delay_q - 3'd1;
        end else begin
          m_axi_gmem_bvalid <= 1'b1;
        end
      end else if (m_axi_gmem_bvalid && m_axi_gmem_bready) begin
        m_axi_gmem_bvalid <= 1'b0;
        aw_seen_q <= 1'b0;
        w_seen_q <= 1'b0;
      end

      if (m_axi_gmem_arvalid && m_axi_gmem_arready) begin
        assert (m_axi_gmem_arsize == 3'd2) else $fatal(1, "expected 32-bit AXI load");
        for (axi_idx = 0; axi_idx < 64; axi_idx = axi_idx + 1) begin
          m_axi_gmem_rdata[axi_idx*8 +: 8] <= mem[m_axi_gmem_araddr[15:0] + axi_idx[15:0]];
        end
        m_axi_gmem_rvalid <= 1'b1;
      end else if (m_axi_gmem_rvalid && m_axi_gmem_rready) begin
        m_axi_gmem_rvalid <= 1'b0;
      end
    end
  end

  logic unused_interrupt;
  assign unused_interrupt = interrupt;
endmodule

`default_nettype wire
