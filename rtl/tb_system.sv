`timescale 1ns/1ps
`default_nettype none

module tb_system;
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
    .warp_active_mask_i(32'h000000ff),
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
    rst_ni = 1'b1;
    repeat (4) @(posedge clk_i);
    run_host_commands();
    $display("[SYSTEM TEST] PASS host_cmds complete");
    $finish;
  end

  task automatic run_host_commands;
    integer fd;
    integer rc;
    integer dump_fd;
    integer poll_count;
    string op;
    string dump_name;
    logic [63:0] addr;
    logic [31:0] data;
    logic [31:0] mask;
    logic [31:0] expected;
    logic [31:0] read_value;
    logic [31:0] num_words;
    integer word_idx;
    begin
      fd = $fopen("host_cmds.txt", "r");
      if (fd == 0) begin
        $display("[SYSTEM TEST] FAIL cannot open host_cmds.txt");
        $finish;
      end

      while (!$feof(fd)) begin
        op = "";
        rc = $fscanf(fd, "%s", op);
        if (rc != 1) begin
          rc = $fgets(op, fd);
        end else if (op.len() == 0) begin
        end else if (op.substr(0, 0) == "#") begin
          rc = $fgets(op, fd);
        end else if (op == "WRITE_AXI") begin
          rc = $fscanf(fd, "%h %h", addr, data);
          if (rc != 2) begin
            $display("[SYSTEM TEST] FAIL malformed WRITE_AXI");
            $finish;
          end
          host_mm_write32(addr[31:0], data);
        end else if (op == "WRITE_AXIL") begin
          rc = $fscanf(fd, "%h %h", addr, data);
          if (rc != 2) begin
            $display("[SYSTEM TEST] FAIL malformed WRITE_AXIL");
            $finish;
          end
          axi_lite_write(addr, data);
        end else if (op == "POLL_AXIL") begin
          rc = $fscanf(fd, "%h %h %h", addr, mask, expected);
          if (rc != 3) begin
            $display("[SYSTEM TEST] FAIL malformed POLL_AXIL");
            $finish;
          end
          read_value = 32'd0;
          poll_count = 0;
          while (((read_value & mask) != expected) && poll_count < 10000) begin
            axi_lite_read(addr, read_value);
            poll_count = poll_count + 1;
          end
          if ((read_value & mask) != expected) begin
            $display("[SYSTEM TEST] FAIL POLL_AXIL timeout addr=%08x value=%08x mask=%08x expected=%08x",
                     addr[31:0], read_value, mask, expected);
            $finish;
          end
        end else if (op == "DUMP_AXI") begin
          rc = $fscanf(fd, "%h %h %s", addr, num_words, dump_name);
          if (rc != 3) begin
            $display("[SYSTEM TEST] FAIL malformed DUMP_AXI");
            $finish;
          end
          dump_fd = $fopen(dump_name, "w");
          if (dump_fd == 0) begin
            $display("[SYSTEM TEST] FAIL cannot open dump file %s", dump_name);
            $finish;
          end
          for (word_idx = 0; word_idx < num_words; word_idx = word_idx + 1) begin
            host_mm_read32(addr[31:0] + word_idx[31:0] * 32'd4, read_value);
            $fdisplay(dump_fd, "%08x", read_value);
          end
          $fclose(dump_fd);
        end else begin
          $display("[SYSTEM TEST] FAIL unknown host command %s", op);
          $finish;
        end
      end
      $fclose(fd);
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
        $display("[SYSTEM TEST] AXI-Lite write error addr=0x%08x resp=%0d", addr[31:0], s_axil_bresp);
        $finish;
      end
      @(posedge clk_i);
    end
  endtask

  task automatic axi_lite_read(input logic [63:0] addr, output logic [31:0] data);
    begin
      @(posedge clk_i);
      s_axil_araddr <= addr;
      s_axil_arvalid <= 1'b1;
      wait (s_axil_arready);
      @(posedge clk_i);
      s_axil_arvalid <= 1'b0;
      wait (s_axil_rvalid);
      data = s_axil_rdata;
      if (s_axil_rresp != 2'b00) begin
        $display("[SYSTEM TEST] AXI-Lite read error addr=0x%08x resp=%0d", addr[31:0], s_axil_rresp);
        $finish;
      end
      @(posedge clk_i);
    end
  endtask

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
        if (m_axi_awsize != 3'd2) begin
          $display("[SYSTEM TEST] FAIL expected 32-bit store AWSIZE, got %0d", m_axi_awsize);
          $finish;
        end
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
        if (m_axi_arsize != 3'd2) begin
          $display("[SYSTEM TEST] FAIL expected 32-bit load ARSIZE, got %0d", m_axi_arsize);
          $finish;
        end
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
