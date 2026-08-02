`timescale 1ns/1ps
`default_nettype none

module tb_axi_hbm_4way_router;
  localparam int AXI_ADDR_WIDTH = 64;
  localparam int AXI_DATA_WIDTH = 32;

  logic clk_i;
  logic rst_ni;
  logic [63:0] s_awaddr_i;
  logic [7:0] s_awlen_i;
  logic [2:0] s_awsize_i;
  logic [1:0] s_awburst_i;
  logic s_awvalid_i;
  logic s_awready_o;
  logic [31:0] s_wdata_i;
  logic [3:0] s_wstrb_i;
  logic s_wlast_i;
  logic s_wvalid_i;
  logic s_wready_o;
  logic [1:0] s_bresp_o;
  logic s_bvalid_o;
  logic s_bready_i;
  logic [63:0] s_araddr_i;
  logic [7:0] s_arlen_i;
  logic [2:0] s_arsize_i;
  logic [1:0] s_arburst_i;
  logic s_arvalid_i;
  logic s_arready_o;
  logic [31:0] s_rdata_o;
  logic [1:0] s_rresp_o;
  logic s_rlast_o;
  logic s_rvalid_o;
  logic s_rready_i;

  logic [63:0] m_awaddr [0:3];
  logic [7:0] m_awlen [0:3];
  logic [2:0] m_awsize [0:3];
  logic [1:0] m_awburst [0:3];
  logic [3:0] m_awvalid;
  logic [3:0] m_awready;
  logic [31:0] m_wdata [0:3];
  logic [3:0] m_wstrb [0:3];
  logic [3:0] m_wlast;
  logic [3:0] m_wvalid;
  logic [3:0] m_wready;
  logic [1:0] m_bresp [0:3];
  logic [3:0] m_bvalid;
  logic [3:0] m_bready;
  logic [63:0] m_araddr [0:3];
  logic [7:0] m_arlen [0:3];
  logic [2:0] m_arsize [0:3];
  logic [1:0] m_arburst [0:3];
  logic [3:0] m_arvalid;
  logic [3:0] m_arready;
  logic [31:0] m_rdata [0:3];
  logic [1:0] m_rresp [0:3];
  logic [3:0] m_rlast;
  logic [3:0] m_rvalid;
  logic [3:0] m_rready;
  logic [31:0] last_write [0:3];
  logic [63:0] last_awaddr [0:3];
  integer aw_count [0:3];
  integer index;
  integer phase_q;

  aec_axi_hbm_4way_router #(
    .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
    .AXI_DATA_WIDTH(AXI_DATA_WIDTH)
  ) dut (
    .clk_i(clk_i), .rst_ni(rst_ni),
    .s_awaddr_i(s_awaddr_i), .s_awlen_i(s_awlen_i), .s_awsize_i(s_awsize_i),
    .s_awburst_i(s_awburst_i), .s_awvalid_i(s_awvalid_i), .s_awready_o(s_awready_o),
    .s_wdata_i(s_wdata_i), .s_wstrb_i(s_wstrb_i), .s_wlast_i(s_wlast_i),
    .s_wvalid_i(s_wvalid_i), .s_wready_o(s_wready_o), .s_bresp_o(s_bresp_o),
    .s_bvalid_o(s_bvalid_o), .s_bready_i(s_bready_i),
    .s_araddr_i(s_araddr_i), .s_arlen_i(s_arlen_i), .s_arsize_i(s_arsize_i),
    .s_arburst_i(s_arburst_i), .s_arvalid_i(s_arvalid_i), .s_arready_o(s_arready_o),
    .s_rdata_o(s_rdata_o), .s_rresp_o(s_rresp_o), .s_rlast_o(s_rlast_o),
    .s_rvalid_o(s_rvalid_o), .s_rready_i(s_rready_i),
    .m0_awaddr_o(m_awaddr[0]), .m0_awlen_o(m_awlen[0]), .m0_awsize_o(m_awsize[0]),
    .m0_awburst_o(m_awburst[0]), .m0_awvalid_o(m_awvalid[0]), .m0_awready_i(m_awready[0]),
    .m0_wdata_o(m_wdata[0]), .m0_wstrb_o(m_wstrb[0]), .m0_wlast_o(m_wlast[0]),
    .m0_wvalid_o(m_wvalid[0]), .m0_wready_i(m_wready[0]), .m0_bresp_i(m_bresp[0]),
    .m0_bvalid_i(m_bvalid[0]), .m0_bready_o(m_bready[0]), .m0_araddr_o(m_araddr[0]),
    .m0_arlen_o(m_arlen[0]), .m0_arsize_o(m_arsize[0]), .m0_arburst_o(m_arburst[0]),
    .m0_arvalid_o(m_arvalid[0]), .m0_arready_i(m_arready[0]), .m0_rdata_i(m_rdata[0]),
    .m0_rresp_i(m_rresp[0]), .m0_rlast_i(m_rlast[0]), .m0_rvalid_i(m_rvalid[0]),
    .m0_rready_o(m_rready[0]),
    .m1_awaddr_o(m_awaddr[1]), .m1_awlen_o(m_awlen[1]), .m1_awsize_o(m_awsize[1]),
    .m1_awburst_o(m_awburst[1]), .m1_awvalid_o(m_awvalid[1]), .m1_awready_i(m_awready[1]),
    .m1_wdata_o(m_wdata[1]), .m1_wstrb_o(m_wstrb[1]), .m1_wlast_o(m_wlast[1]),
    .m1_wvalid_o(m_wvalid[1]), .m1_wready_i(m_wready[1]), .m1_bresp_i(m_bresp[1]),
    .m1_bvalid_i(m_bvalid[1]), .m1_bready_o(m_bready[1]), .m1_araddr_o(m_araddr[1]),
    .m1_arlen_o(m_arlen[1]), .m1_arsize_o(m_arsize[1]), .m1_arburst_o(m_arburst[1]),
    .m1_arvalid_o(m_arvalid[1]), .m1_arready_i(m_arready[1]), .m1_rdata_i(m_rdata[1]),
    .m1_rresp_i(m_rresp[1]), .m1_rlast_i(m_rlast[1]), .m1_rvalid_i(m_rvalid[1]),
    .m1_rready_o(m_rready[1]),
    .m2_awaddr_o(m_awaddr[2]), .m2_awlen_o(m_awlen[2]), .m2_awsize_o(m_awsize[2]),
    .m2_awburst_o(m_awburst[2]), .m2_awvalid_o(m_awvalid[2]), .m2_awready_i(m_awready[2]),
    .m2_wdata_o(m_wdata[2]), .m2_wstrb_o(m_wstrb[2]), .m2_wlast_o(m_wlast[2]),
    .m2_wvalid_o(m_wvalid[2]), .m2_wready_i(m_wready[2]), .m2_bresp_i(m_bresp[2]),
    .m2_bvalid_i(m_bvalid[2]), .m2_bready_o(m_bready[2]), .m2_araddr_o(m_araddr[2]),
    .m2_arlen_o(m_arlen[2]), .m2_arsize_o(m_arsize[2]), .m2_arburst_o(m_arburst[2]),
    .m2_arvalid_o(m_arvalid[2]), .m2_arready_i(m_arready[2]), .m2_rdata_i(m_rdata[2]),
    .m2_rresp_i(m_rresp[2]), .m2_rlast_i(m_rlast[2]), .m2_rvalid_i(m_rvalid[2]),
    .m2_rready_o(m_rready[2]),
    .m3_awaddr_o(m_awaddr[3]), .m3_awlen_o(m_awlen[3]), .m3_awsize_o(m_awsize[3]),
    .m3_awburst_o(m_awburst[3]), .m3_awvalid_o(m_awvalid[3]), .m3_awready_i(m_awready[3]),
    .m3_wdata_o(m_wdata[3]), .m3_wstrb_o(m_wstrb[3]), .m3_wlast_o(m_wlast[3]),
    .m3_wvalid_o(m_wvalid[3]), .m3_wready_i(m_wready[3]), .m3_bresp_i(m_bresp[3]),
    .m3_bvalid_i(m_bvalid[3]), .m3_bready_o(m_bready[3]), .m3_araddr_o(m_araddr[3]),
    .m3_arlen_o(m_arlen[3]), .m3_arsize_o(m_arsize[3]), .m3_arburst_o(m_arburst[3]),
    .m3_arvalid_o(m_arvalid[3]), .m3_arready_i(m_arready[3]), .m3_rdata_i(m_rdata[3]),
    .m3_rresp_i(m_rresp[3]), .m3_rlast_i(m_rlast[3]), .m3_rvalid_i(m_rvalid[3]),
    .m3_rready_o(m_rready[3])
  );

  assign m_awready = 4'hf;
  assign m_wready = 4'hf;
  assign m_arready = 4'hf;

  always #5 clk_i = ~clk_i;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      m_bvalid <= 4'd0;
      m_rvalid <= 4'd0;
      for (index = 0; index < 4; index = index + 1) begin
        m_bresp[index] <= 2'b00;
        m_rresp[index] <= 2'b00;
        m_rlast[index] <= 1'b1;
        m_rdata[index] <= 32'd0;
        last_write[index] <= 32'd0;
        last_awaddr[index] <= 64'd0;
        aw_count[index] <= 0;
      end
    end else begin
      for (index = 0; index < 4; index = index + 1) begin
        if (m_awvalid[index]) begin
          last_awaddr[index] <= m_awaddr[index];
          aw_count[index] <= aw_count[index] + 1;
          assert (m_awsize[index] == 3'd2) else $fatal(1, "AW size changed");
        end
        if (m_wvalid[index]) begin
          last_write[index] <= m_wdata[index];
          assert (m_wstrb[index] == 4'hf) else $fatal(1, "write strobe changed");
          assert (m_wlast[index]) else $fatal(1, "single beat write missing WLAST");
          m_bvalid[index] <= 1'b1;
        end else if (m_bvalid[index] && m_bready[index]) begin
          m_bvalid[index] <= 1'b0;
        end
        if (m_arvalid[index]) begin
          assert (m_arsize[index] == 3'd2) else $fatal(1, "AR size changed");
          m_rdata[index] <= 32'hcafe_0000 + index;
          m_rvalid[index] <= 1'b1;
        end else if (m_rvalid[index] && m_rready[index]) begin
          m_rvalid[index] <= 1'b0;
        end
      end
    end
  end

  task automatic write_one(input logic [63:0] addr, input logic [31:0] data, input integer bank);
    begin
      $display("router write bank %0d request", bank);
      @(negedge clk_i);
      s_awaddr_i = addr;
      s_awvalid_i = 1'b1;
      while (!s_awready_o) @(negedge clk_i);
      @(negedge clk_i);
      s_awvalid_i = 1'b0;
      // Deliberately disturb AWADDR before W: W must follow the captured AW bank.
      s_awaddr_i = 64'h0000_0000_c000_0000;
      s_wdata_i = data;
      s_wvalid_i = 1'b1;
      while (!s_wready_o) @(negedge clk_i);
      @(negedge clk_i);
      s_wvalid_i = 1'b0;
      wait (s_bvalid_o);
      @(negedge clk_i);
      s_bready_i = 1'b1;
      @(negedge clk_i);
      s_bready_i = 1'b0;
      assert (last_write[bank] == data) else $fatal(1, "write data bank %0d", bank);
      assert (last_awaddr[bank] == {34'd0, addr[29:0]}) else $fatal(1, "write address bank %0d", bank);
      assert (aw_count[bank] == 1) else $fatal(1, "write bank routing %0d", bank);
      $display("router write bank %0d complete", bank);
    end
  endtask

  task automatic read_one(input logic [63:0] addr, input integer bank);
    begin
      $display("router read bank %0d request", bank);
      @(negedge clk_i);
      s_araddr_i = addr;
      s_arvalid_i = 1'b1;
      while (!s_arready_o) @(negedge clk_i);
      @(negedge clk_i);
      s_arvalid_i = 1'b0;
      wait (s_rvalid_o);
      assert (s_rdata_o == (32'hcafe_0000 + bank)) else $fatal(1, "read data bank %0d", bank);
      assert (s_rlast_o) else $fatal(1, "read last missing");
      @(negedge clk_i);
      s_rready_i = 1'b1;
      @(negedge clk_i);
      s_rready_i = 1'b0;
      $display("router read bank %0d complete", bank);
    end
  endtask

  initial begin
    clk_i = 1'b0;
    rst_ni = 1'b0;
    s_awaddr_i = '0; s_awlen_i = 8'd0; s_awsize_i = 3'd2; s_awburst_i = 2'b01; s_awvalid_i = 1'b0;
    s_wdata_i = '0; s_wstrb_i = 4'hf; s_wlast_i = 1'b1; s_wvalid_i = 1'b0; s_bready_i = 1'b0;
    s_araddr_i = '0; s_arlen_i = 8'd0; s_arsize_i = 3'd2; s_arburst_i = 2'b01; s_arvalid_i = 1'b0; s_rready_i = 1'b0;
    repeat (3) @(posedge clk_i);
    rst_ni = 1'b1;
    phase_q = 1;
    write_one(64'h0000_0000_0000_0100, 32'h1111_0000, 0);
    write_one(64'h0000_0000_4000_0104, 32'h2222_0001, 1);
    write_one(64'h0000_0000_8000_0108, 32'h3333_0002, 2);
    write_one(64'h0000_0000_c000_010c, 32'h4444_0003, 3);
    read_one(64'h0000_0000_0000_0200, 0);
    read_one(64'h0000_0000_4000_0200, 1);
    read_one(64'h0000_0000_8000_0200, 2);
    read_one(64'h0000_0000_c000_0200, 3);
    $display("AXI_HBM_ROUTER TEST PASSED");
    $finish;
  end

  initial begin
    #10000;
    $fatal(1, "AXI HBM router test timeout phase=%0d write_bank=%0d read_bank=%0d", phase_q,
        dut.write_bank_q, dut.read_bank_q);
  end
endmodule

`default_nettype wire
