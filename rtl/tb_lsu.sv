`timescale 1ns/1ps
`default_nettype none

module tb_lsu;
  import aec_pkg::*;

  logic clk_i;
  logic rst_ni;

  logic ex_valid_i;
  logic [15:0] ex_opcode_i;
  logic [1:0] ex_beat_i;
  logic [15:0] ex_pc_i;
  logic [7:0] ex_active_mask_i;
  logic [7:0] ex_dst_reg_i;
  logic [7:0][31:0] ex_src1_data_i;
  logic [7:0][31:0] ex_src2_data_i;
  logic [7:0][31:0] ex_src3_data_i;

  logic busy_o;
  logic load_valid_o;
  logic [1:0] load_beat_o;
  logic [7:0] load_dst_reg_o;
  logic [7:0] load_mask_o;
  logic [7:0][31:0] load_data_o;
  logic fault_valid_o;
  aec_fault_e fault_code_o;
  logic [15:0] fault_pc_o;

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

  logic [7:0] mem [0:65535];
  logic [63:0] awaddr_q;
  logic [63:0] write_addr_eff;
  logic aw_seen_q;
  logic w_seen_q;
  integer init_idx;
  integer axi_idx;
  integer lane;
  integer store_count;
  integer load_count;
  logic [63:0] store_addr_seen [0:15];
  logic [63:0] load_addr_seen [0:15];

  lsu dut (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .ex_valid_i(ex_valid_i),
    .ex_opcode_i(ex_opcode_i),
    .ex_beat_i(ex_beat_i),
    .ex_pc_i(ex_pc_i),
    .ex_active_mask_i(ex_active_mask_i),
    .ex_dst_reg_i(ex_dst_reg_i),
    .ex_src1_data_i(ex_src1_data_i),
    .ex_src2_data_i(ex_src2_data_i),
    .ex_src3_data_i(ex_src3_data_i),
    .busy_o(busy_o),
    .outstanding_o(),
    .load_valid_o(load_valid_o),
    .load_beat_o(load_beat_o),
    .load_dst_reg_o(load_dst_reg_o),
    .load_mask_o(load_mask_o),
    .load_data_o(load_data_o),
    .fault_valid_o(fault_valid_o),
    .fault_code_o(fault_code_o),
    .fault_pc_o(fault_pc_o),
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
    .m_axi_rready(m_axi_rready)
  );

  initial begin
    clk_i = 1'b0;
    forever #5 clk_i = ~clk_i;
  end

  initial begin
    rst_ni = 1'b0;
    ex_valid_i = 1'b0;
    ex_opcode_i = AEC_OP_NOP;
    ex_beat_i = 2'd0;
    ex_pc_i = 16'd0;
    ex_active_mask_i = 8'd0;
    ex_dst_reg_i = 8'd0;
    ex_src1_data_i = '0;
    ex_src2_data_i = '0;
    ex_src3_data_i = '0;
    m_axi_bresp = 2'b00;
    m_axi_rresp = 2'b00;
    m_axi_rlast = 1'b1;

    for (init_idx = 0; init_idx < 65536; init_idx = init_idx + 1) begin
      mem[init_idx] = 8'd0;
    end

    #22;
    rst_ni = 1'b1;
    #20;

    run_scatter_store_test();
    run_gather_load_test();
    run_mask_skip_test();
    run_misaligned_fault_test();

    $display("LSU TEST PASSED");
    $finish;
  end

  task automatic pulse_store(input logic [7:0] mask);
    begin
      ex_active_mask_i = mask;
      ex_beat_i = 2'd2;
      ex_dst_reg_i = 8'd9;
      ex_opcode_i = AEC_OP_ST;
      ex_valid_i = 1'b1;
      #10;
      ex_valid_i = 1'b0;
    end
  endtask

  task automatic pulse_load(input logic [7:0] mask);
    begin
      ex_active_mask_i = mask;
      ex_beat_i = 2'd1;
      ex_dst_reg_i = 8'd12;
      ex_opcode_i = AEC_OP_LD;
      ex_valid_i = 1'b1;
      #10;
      ex_valid_i = 1'b0;
    end
  endtask

  task automatic run_scatter_store_test;
    logic [31:0] expected_addr [0:7];
    integer store_base;
    begin
      store_base = store_count;
      expected_addr[0] = 32'h00001000;
      expected_addr[1] = 32'h00002004;
      expected_addr[2] = 32'h00003008;
      expected_addr[3] = 32'h0000400c;
      expected_addr[4] = 32'h00005010;
      expected_addr[5] = 32'h00006014;
      expected_addr[6] = 32'h00007018;
      expected_addr[7] = 32'h0000801c;

      for (lane = 0; lane < 8; lane = lane + 1) begin
        ex_src1_data_i[lane] = expected_addr[lane];
        ex_src2_data_i[lane] = 32'd0;
        ex_src3_data_i[lane] = 32'h1000_0000 + lane[31:0];
      end
      pulse_store(8'hff);
      wait (!busy_o);
      #20;

      assert ((store_count - store_base) == 8)
        else $fatal(1, "scatter store count mismatch: %0d", store_count - store_base);
      assert (read_u32(32'h00001000) == 32'h1000_0000) else $fatal(1, "scatter lane0 mismatch");
      assert (read_u32(32'h00002004) == 32'h1000_0001) else $fatal(1, "scatter lane1 mismatch");
      assert (read_u32(32'h00003008) == 32'h1000_0002) else $fatal(1, "scatter lane2 mismatch");
      assert (read_u32(32'h0000400c) == 32'h1000_0003) else $fatal(1, "scatter lane3 mismatch");
      assert (read_u32(32'h00005010) == 32'h1000_0004) else $fatal(1, "scatter lane4 mismatch");
      assert (read_u32(32'h00006014) == 32'h1000_0005) else $fatal(1, "scatter lane5 mismatch");
      assert (read_u32(32'h00007018) == 32'h1000_0006) else $fatal(1, "scatter lane6 mismatch");
      assert (read_u32(32'h0000801c) == 32'h1000_0007) else $fatal(1, "scatter lane7 mismatch");
    end
  endtask

  task automatic run_gather_load_test;
    logic [31:0] expected_addr [0:7];
    integer load_base;
    begin
      load_base = load_count;
      expected_addr[0] = 32'h00001120;
      expected_addr[1] = 32'h00002124;
      expected_addr[2] = 32'h00003128;
      expected_addr[3] = 32'h0000412c;
      expected_addr[4] = 32'h00005130;
      expected_addr[5] = 32'h00006134;
      expected_addr[6] = 32'h00007138;
      expected_addr[7] = 32'h0000813c;

      for (lane = 0; lane < 8; lane = lane + 1) begin
        ex_src1_data_i[lane] = expected_addr[lane] - 32'h20;
        ex_src2_data_i[lane] = 32'h20;
        write_u32(expected_addr[lane], 32'h2000_0000 + lane[31:0]);
      end
      pulse_load(8'hff);
      wait (load_valid_o);
      #1;

      assert ((load_count - load_base) == 8)
        else $fatal(1, "gather load count mismatch: %0d", load_count - load_base);
      assert ((load_beat_o == 2'd1) && (load_dst_reg_o == 8'd12) && (load_mask_o == 8'hff))
        else $fatal(1, "gather load control mismatch");
      assert (load_data_o[0] == 32'h2000_0000) else $fatal(1, "gather lane0 mismatch");
      assert (load_data_o[1] == 32'h2000_0001) else $fatal(1, "gather lane1 mismatch");
      assert (load_data_o[2] == 32'h2000_0002) else $fatal(1, "gather lane2 mismatch");
      assert (load_data_o[3] == 32'h2000_0003) else $fatal(1, "gather lane3 mismatch");
      assert (load_data_o[4] == 32'h2000_0004) else $fatal(1, "gather lane4 mismatch");
      assert (load_data_o[5] == 32'h2000_0005) else $fatal(1, "gather lane5 mismatch");
      assert (load_data_o[6] == 32'h2000_0006) else $fatal(1, "gather lane6 mismatch");
      assert (load_data_o[7] == 32'h2000_0007) else $fatal(1, "gather lane7 mismatch");
      #10;
    end
  endtask

  task automatic run_mask_skip_test;
    integer store_base;
    begin
      store_base = store_count;
      for (lane = 0; lane < 8; lane = lane + 1) begin
        ex_src1_data_i[lane] = 32'h00001200 + lane[31:0] * 32'h100;
        ex_src2_data_i[lane] = lane[31:0] * 32'd4;
        ex_src3_data_i[lane] = 32'h3000_0000 + lane[31:0];
      end
      pulse_store(8'b1010_0101);
      wait (!busy_o);
      #20;
      assert ((store_count - store_base) == 4)
        else $fatal(1, "masked store should issue 4 transfers, got %0d", store_count - store_base);
      assert (read_u32(32'h00001200) == 32'h3000_0000)
        else $fatal(1, "masked lane0 store missing");
      assert (read_u32(32'h00001408) == 32'h3000_0002)
        else $fatal(1, "masked lane2 store missing");
      assert (read_u32(32'h00001714) == 32'h3000_0005)
        else $fatal(1, "masked lane5 store missing");
      assert (read_u32(32'h0000191c) == 32'h3000_0007)
        else $fatal(1, "masked lane7 store missing");
      assert (read_u32(32'h00001304) == 32'd0)
        else $fatal(1, "masked lane1 unexpectedly stored");
    end
  endtask

  task automatic run_misaligned_fault_test;
    begin
      ex_pc_i = 16'h0042;
      ex_src1_data_i[0] = 32'h00001202;
      ex_src2_data_i[0] = 32'd0;
      ex_src3_data_i[0] = 32'h4444_5555;
      pulse_store(8'h01);
      wait (fault_valid_o);
      #1;
      assert (fault_code_o == AEC_FAULT_MISALIGNED_ACCESS)
        else $fatal(1, "expected MISALIGNED_ACCESS fault");
      assert (fault_pc_o == 16'h0042)
        else $fatal(1, "fault PC mismatch");
      wait (!busy_o);
      ex_pc_i = 16'd0;
    end
  endtask

  task automatic write_u32(input logic [31:0] addr, input logic [31:0] value);
    begin
      mem[addr[15:0] + 16'd0] = value[7:0];
      mem[addr[15:0] + 16'd1] = value[15:8];
      mem[addr[15:0] + 16'd2] = value[23:16];
      mem[addr[15:0] + 16'd3] = value[31:24];
    end
  endtask

  function automatic logic [31:0] read_u32(input logic [31:0] addr);
    begin
      read_u32 = {mem[addr[15:0] + 16'd3], mem[addr[15:0] + 16'd2],
                  mem[addr[15:0] + 16'd1], mem[addr[15:0] + 16'd0]};
    end
  endfunction

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
      store_count   <= 0;
      load_count    <= 0;
    end else begin
      m_axi_awready <= !aw_seen_q && m_axi_awvalid;
      m_axi_wready  <= !w_seen_q && m_axi_wvalid;
      m_axi_arready <= !m_axi_rvalid && m_axi_arvalid;

      if (m_axi_awvalid && m_axi_awready) begin
        assert (m_axi_awsize == 3'd2)
          else $fatal(1, "AW size is not 32-bit");
        awaddr_q <= m_axi_awaddr;
        aw_seen_q <= 1'b1;
        store_addr_seen[store_count] <= m_axi_awaddr;
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
        aw_seen_q <= 1'b0;
        w_seen_q <= 1'b0;
        store_count <= store_count + 1;
      end

      if (m_axi_arvalid && m_axi_arready) begin
        assert (m_axi_arsize == 3'd2)
          else $fatal(1, "AR size is not 32-bit");
        load_addr_seen[load_count] <= m_axi_araddr;
        for (axi_idx = 0; axi_idx < 64; axi_idx = axi_idx + 1) begin
          m_axi_rdata[axi_idx*8 +: 8] <= mem[m_axi_araddr[15:0] + axi_idx[15:0]];
        end
        m_axi_rvalid <= 1'b1;
      end else if (m_axi_rvalid && m_axi_rready) begin
        m_axi_rvalid <= 1'b0;
        load_count <= load_count + 1;
      end
    end
  end
endmodule

`default_nettype wire
