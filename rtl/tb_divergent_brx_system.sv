`timescale 1ns/1ps
`default_nettype none

module tb_divergent_brx_system;
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

  logic [7:0] mem [0:65535];
  logic [63:0] awaddr_q;
  logic [63:0] write_addr_eff;
  logic aw_seen_q;
  logic w_seen_q;
  integer init_idx;
  integer axi_idx;
  integer brx_push_seen;
  integer sync_fallthrough_seen;
  integer sync_reconv_seen;
  localparam logic [63:0] CSR_CTRL = 64'h0000;
  localparam logic [63:0] CSR_PC = 64'h0004;
  localparam logic [63:0] IMEM_WINDOW = 64'h1000;

  cu_top #(
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
    .warp_active_mask_i(32'h00000003),
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

  initial begin
    clk_i = 1'b0;
    forever #5 clk_i = ~clk_i;
  end

  initial begin
    for (init_idx = 0; init_idx < 65536; init_idx = init_idx + 1) begin
      mem[init_idx] = 8'd0;
    end

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
    m_axi_bresp = 2'b00;
    m_axi_rresp = 2'b00;
    m_axi_rlast = 1'b1;

    #22;
    seed_lane_gprs();
    rst_ni = 1'b1;
    repeat (4) @(posedge clk_i);
    seed_divergent_program();
    axi_lite_write(CSR_PC, 32'd0);
    axi_lite_write(CSR_CTRL, 32'h00000001);

    fork
      begin : watchdog
        #12000;
        $display("[DIVERGENT BRX TEST] FAIL timeout");
        $finish;
      end
      begin : wait_halt
        wait (dut.trace_halt_seen == 1'b1);
        #30;
        if (brx_push_seen == 0) begin
          $display("[DIVERGENT BRX TEST] FAIL no divergent BRX redirect observed");
        end else if (sync_fallthrough_seen == 0) begin
          $display("[DIVERGENT BRX TEST] FAIL no fallthrough SYNC pop observed");
        end else if (sync_reconv_seen == 0) begin
          $display("[DIVERGENT BRX TEST] FAIL no reconvergence SYNC pop observed");
        end else if ({mem[16'h3003], mem[16'h3002], mem[16'h3001], mem[16'h3000]} != 32'd100) begin
          $display("[DIVERGENT BRX TEST] FAIL lane0 result=%0d",
                   {mem[16'h3003], mem[16'h3002], mem[16'h3001], mem[16'h3000]});
        end else if ({mem[16'h3007], mem[16'h3006], mem[16'h3005], mem[16'h3004]} != 32'd200) begin
          $display("[DIVERGENT BRX TEST] FAIL lane1 result=%0d",
                   {mem[16'h3007], mem[16'h3006], mem[16'h3005], mem[16'h3004]});
        end else begin
          $display("[DIVERGENT BRX TEST] PASS");
        end
        $finish;
      end
    join
  end

  task automatic seed_divergent_program;
    begin
      write_instr(10'd0, 128'h00420010000000000000000000000008); // SSY 8
      write_instr(10'd1, 128'h00200010000000140000001500000000); // SETP.eq P0, R20, R21
      write_instr(10'd2, 128'h00418010000000000000000000000005); // BRX P0, 5
      write_instr(10'd3, 128'h00010010000500050000000c00000000); // fallthrough: R5 += R12
      write_instr(10'd4, 128'h00430010000000000000000000000000); // SYNC to reconverge
      write_instr(10'd5, 128'h00010010000500050000000a00000000); // taken: R5 += R10
      write_instr(10'd6, 128'h00430010000000000000000000000000); // SYNC to fallthrough
      write_instr(10'd7, 128'h00f00010000000000000000000000000); // skipped NOP
      write_instr(10'd8, 128'h00310090000000020000000000050002); // ST [R2+0], R5
      write_instr(10'd9, 128'h00450010000000000000000000000000); // HALT
    end
  endtask

  task automatic write_instr(input logic [9:0] pc, input logic [127:0] instr);
    begin
      axi_lite_write(IMEM_WINDOW + (pc * 64'd16) + 64'd0, instr[31:0]);
      axi_lite_write(IMEM_WINDOW + (pc * 64'd16) + 64'd4, instr[63:32]);
      axi_lite_write(IMEM_WINDOW + (pc * 64'd16) + 64'd8, instr[95:64]);
      axi_lite_write(IMEM_WINDOW + (pc * 64'd16) + 64'd12, instr[127:96]);
    end
  endtask

  task automatic axi_lite_write(input logic [63:0] addr, input logic [31:0] data);
    begin
      @(posedge clk_i);
      s_axil_awaddr <= addr;
      s_axil_wdata <= data;
      s_axil_wstrb <= 4'hf;
      s_axil_awvalid <= 1'b1;
      s_axil_wvalid <= 1'b1;
      wait (s_axil_awready && s_axil_wready);
      @(posedge clk_i);
      s_axil_awvalid <= 1'b0;
      s_axil_wvalid <= 1'b0;
      wait (s_axil_bvalid);
      if (s_axil_bresp != 2'b00) begin
        $display("[DIVERGENT BRX TEST] AXI-Lite write error addr=0x%08x resp=%0d", addr[31:0], s_axil_bresp);
        $finish;
      end
      @(posedge clk_i);
    end
  endtask

  task automatic seed_lane_gprs;
    begin
      dut.u_vrf_top.g_vrf_lane[0].u_vrf_lane.bank_r1[10'd8]   = 32'h00003000;
      dut.u_vrf_top.g_vrf_lane[0].u_vrf_lane.bank_r1[10'd20]  = 32'h00000000;
      dut.u_vrf_top.g_vrf_lane[0].u_vrf_lane.bank_r2[10'd40]  = 32'h00000064;
      dut.u_vrf_top.g_vrf_lane[0].u_vrf_lane.bank_r2[10'd48]  = 32'h000000c8;
      dut.u_vrf_top.g_vrf_lane[0].u_vrf_lane.bank_r1[10'd80]  = 32'h00000001;
      dut.u_vrf_top.g_vrf_lane[0].u_vrf_lane.bank_r2[10'd84]  = 32'h00000001;
      dut.u_vrf_top.g_vrf_lane[0].u_vrf_lane.bank_r2[10'd124] = 32'h00000000;

      dut.u_vrf_top.g_vrf_lane[1].u_vrf_lane.bank_r1[10'd8]   = 32'h00003004;
      dut.u_vrf_top.g_vrf_lane[1].u_vrf_lane.bank_r1[10'd20]  = 32'h00000000;
      dut.u_vrf_top.g_vrf_lane[1].u_vrf_lane.bank_r2[10'd40]  = 32'h00000064;
      dut.u_vrf_top.g_vrf_lane[1].u_vrf_lane.bank_r2[10'd48]  = 32'h000000c8;
      dut.u_vrf_top.g_vrf_lane[1].u_vrf_lane.bank_r1[10'd80]  = 32'h00000002;
      dut.u_vrf_top.g_vrf_lane[1].u_vrf_lane.bank_r2[10'd84]  = 32'h00000001;
      dut.u_vrf_top.g_vrf_lane[1].u_vrf_lane.bank_r2[10'd124] = 32'h00000000;
    end
  endtask

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      brx_push_seen <= 0;
      sync_fallthrough_seen <= 0;
      sync_reconv_seen <= 0;
    end else if (dut.branch_taken) begin
      if ((dut.branch_target == 16'd5) && (dut.branch_mask == 32'h00000001)) begin
        brx_push_seen <= brx_push_seen + 1;
      end
      if ((dut.branch_target == 16'd3) && (dut.branch_mask == 32'h00000002)) begin
        sync_fallthrough_seen <= sync_fallthrough_seen + 1;
      end
      if ((dut.branch_target == 16'd8) && (dut.branch_mask == 32'h00000003)) begin
        sync_reconv_seen <= sync_reconv_seen + 1;
      end
    end
  end

  always_comb begin
    if (m_axi_awvalid && m_axi_awready) begin
      write_addr_eff = m_axi_awaddr;
    end else begin
      write_addr_eff = awaddr_q;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      m_axi_awready <= 1'b0;
      m_axi_wready  <= 1'b0;
      m_axi_bvalid  <= 1'b0;
      m_axi_arready <= 1'b0;
      m_axi_rdata   <= 512'd0;
      m_axi_rvalid  <= 1'b0;
      awaddr_q      <= 64'd0;
      aw_seen_q     <= 1'b0;
      w_seen_q      <= 1'b0;
    end else begin
      m_axi_awready <= !aw_seen_q && m_axi_awvalid;
      m_axi_wready  <= !w_seen_q && m_axi_wvalid;
      m_axi_arready <= !m_axi_rvalid && m_axi_arvalid;

      if (m_axi_awvalid && m_axi_awready) begin
        awaddr_q  <= m_axi_awaddr;
        aw_seen_q <= 1'b1;
      end

      if (m_axi_wvalid && m_axi_wready) begin
        for (axi_idx = 0; axi_idx < 64; axi_idx = axi_idx + 1) begin
          if (m_axi_wstrb[axi_idx]) begin
            mem[write_addr_eff[15:0] + axi_idx[15:0]] <= m_axi_wdata[axi_idx*8 +: 8];
          end
        end
        w_seen_q <= 1'b1;
      end

      if (aw_seen_q && w_seen_q && !m_axi_bvalid) begin
        m_axi_bvalid <= 1'b1;
      end else if (m_axi_bvalid && m_axi_bready) begin
        m_axi_bvalid <= 1'b0;
        aw_seen_q    <= 1'b0;
        w_seen_q     <= 1'b0;
      end

      if (m_axi_arvalid && m_axi_arready) begin
        for (axi_idx = 0; axi_idx < 64; axi_idx = axi_idx + 1) begin
          m_axi_rdata[axi_idx*8 +: 8] <= mem[m_axi_araddr[15:0] + axi_idx[15:0]];
        end
        m_axi_rvalid <= 1'b1;
      end else if (m_axi_rvalid && m_axi_rready) begin
        m_axi_rvalid <= 1'b0;
      end
    end
  end
endmodule

`default_nettype wire
