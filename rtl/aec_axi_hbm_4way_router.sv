`timescale 1ns/1ps
`default_nettype none

module aec_axi_hbm_4way_router #(
  parameter int AXI_ADDR_WIDTH = 64,
  parameter int AXI_DATA_WIDTH = 512
) (
  input  wire logic                       clk_i,
  input  wire logic                       rst_ni,

  input  wire logic [AXI_ADDR_WIDTH-1:0]  s_awaddr_i,
  input  wire logic [7:0]                 s_awlen_i,
  input  wire logic [2:0]                 s_awsize_i,
  input  wire logic [1:0]                 s_awburst_i,
  input  wire logic                       s_awvalid_i,
  output logic                            s_awready_o,
  input  wire logic [AXI_DATA_WIDTH-1:0]  s_wdata_i,
  input  wire logic [AXI_DATA_WIDTH/8-1:0] s_wstrb_i,
  input  wire logic                       s_wlast_i,
  input  wire logic                       s_wvalid_i,
  output logic                            s_wready_o,
  output logic [1:0]                      s_bresp_o,
  output logic                            s_bvalid_o,
  input  wire logic                       s_bready_i,
  input  wire logic [AXI_ADDR_WIDTH-1:0]  s_araddr_i,
  input  wire logic [7:0]                 s_arlen_i,
  input  wire logic [2:0]                 s_arsize_i,
  input  wire logic [1:0]                 s_arburst_i,
  input  wire logic                       s_arvalid_i,
  output logic                            s_arready_o,
  output logic [AXI_DATA_WIDTH-1:0]       s_rdata_o,
  output logic [1:0]                      s_rresp_o,
  output logic                            s_rlast_o,
  output logic                            s_rvalid_o,
  input  wire logic                       s_rready_i,

  output logic [AXI_ADDR_WIDTH-1:0]       m0_awaddr_o,
  output logic [7:0]                      m0_awlen_o,
  output logic [2:0]                      m0_awsize_o,
  output logic [1:0]                      m0_awburst_o,
  output logic                            m0_awvalid_o,
  input  wire logic                       m0_awready_i,
  output logic [AXI_DATA_WIDTH-1:0]       m0_wdata_o,
  output logic [AXI_DATA_WIDTH/8-1:0]     m0_wstrb_o,
  output logic                            m0_wlast_o,
  output logic                            m0_wvalid_o,
  input  wire logic                       m0_wready_i,
  input  wire logic [1:0]                 m0_bresp_i,
  input  wire logic                       m0_bvalid_i,
  output logic                            m0_bready_o,
  output logic [AXI_ADDR_WIDTH-1:0]       m0_araddr_o,
  output logic [7:0]                      m0_arlen_o,
  output logic [2:0]                      m0_arsize_o,
  output logic [1:0]                      m0_arburst_o,
  output logic                            m0_arvalid_o,
  input  wire logic                       m0_arready_i,
  input  wire logic [AXI_DATA_WIDTH-1:0]  m0_rdata_i,
  input  wire logic [1:0]                 m0_rresp_i,
  input  wire logic                       m0_rlast_i,
  input  wire logic                       m0_rvalid_i,
  output logic                            m0_rready_o,

  output logic [AXI_ADDR_WIDTH-1:0]       m1_awaddr_o,
  output logic [7:0]                      m1_awlen_o,
  output logic [2:0]                      m1_awsize_o,
  output logic [1:0]                      m1_awburst_o,
  output logic                            m1_awvalid_o,
  input  wire logic                       m1_awready_i,
  output logic [AXI_DATA_WIDTH-1:0]       m1_wdata_o,
  output logic [AXI_DATA_WIDTH/8-1:0]     m1_wstrb_o,
  output logic                            m1_wlast_o,
  output logic                            m1_wvalid_o,
  input  wire logic                       m1_wready_i,
  input  wire logic [1:0]                 m1_bresp_i,
  input  wire logic                       m1_bvalid_i,
  output logic                            m1_bready_o,
  output logic [AXI_ADDR_WIDTH-1:0]       m1_araddr_o,
  output logic [7:0]                      m1_arlen_o,
  output logic [2:0]                      m1_arsize_o,
  output logic [1:0]                      m1_arburst_o,
  output logic                            m1_arvalid_o,
  input  wire logic                       m1_arready_i,
  input  wire logic [AXI_DATA_WIDTH-1:0]  m1_rdata_i,
  input  wire logic [1:0]                 m1_rresp_i,
  input  wire logic                       m1_rlast_i,
  input  wire logic                       m1_rvalid_i,
  output logic                            m1_rready_o,

  output logic [AXI_ADDR_WIDTH-1:0]       m2_awaddr_o,
  output logic [7:0]                      m2_awlen_o,
  output logic [2:0]                      m2_awsize_o,
  output logic [1:0]                      m2_awburst_o,
  output logic                            m2_awvalid_o,
  input  wire logic                       m2_awready_i,
  output logic [AXI_DATA_WIDTH-1:0]       m2_wdata_o,
  output logic [AXI_DATA_WIDTH/8-1:0]     m2_wstrb_o,
  output logic                            m2_wlast_o,
  output logic                            m2_wvalid_o,
  input  wire logic                       m2_wready_i,
  input  wire logic [1:0]                 m2_bresp_i,
  input  wire logic                       m2_bvalid_i,
  output logic                            m2_bready_o,
  output logic [AXI_ADDR_WIDTH-1:0]       m2_araddr_o,
  output logic [7:0]                      m2_arlen_o,
  output logic [2:0]                      m2_arsize_o,
  output logic [1:0]                      m2_arburst_o,
  output logic                            m2_arvalid_o,
  input  wire logic                       m2_arready_i,
  input  wire logic [AXI_DATA_WIDTH-1:0]  m2_rdata_i,
  input  wire logic [1:0]                 m2_rresp_i,
  input  wire logic                       m2_rlast_i,
  input  wire logic                       m2_rvalid_i,
  output logic                            m2_rready_o,

  output logic [AXI_ADDR_WIDTH-1:0]       m3_awaddr_o,
  output logic [7:0]                      m3_awlen_o,
  output logic [2:0]                      m3_awsize_o,
  output logic [1:0]                      m3_awburst_o,
  output logic                            m3_awvalid_o,
  input  wire logic                       m3_awready_i,
  output logic [AXI_DATA_WIDTH-1:0]       m3_wdata_o,
  output logic [AXI_DATA_WIDTH/8-1:0]     m3_wstrb_o,
  output logic                            m3_wlast_o,
  output logic                            m3_wvalid_o,
  input  wire logic                       m3_wready_i,
  input  wire logic [1:0]                 m3_bresp_i,
  input  wire logic                       m3_bvalid_i,
  output logic                            m3_bready_o,
  output logic [AXI_ADDR_WIDTH-1:0]       m3_araddr_o,
  output logic [7:0]                      m3_arlen_o,
  output logic [2:0]                      m3_arsize_o,
  output logic [1:0]                      m3_arburst_o,
  output logic                            m3_arvalid_o,
  input  wire logic                       m3_arready_i,
  input  wire logic [AXI_DATA_WIDTH-1:0]  m3_rdata_i,
  input  wire logic [1:0]                 m3_rresp_i,
  input  wire logic                       m3_rlast_i,
  input  wire logic                       m3_rvalid_i,
  output logic                            m3_rready_o
);

  logic [1:0] write_bank_q;
  logic [1:0] read_bank_q;

  wire [1:0] aw_bank = s_awaddr_i[31:30];
  wire [1:0] ar_bank = s_araddr_i[31:30];
  wire [AXI_ADDR_WIDTH-1:0] awaddr_bank = {32'd0, 2'b00, s_awaddr_i[29:0]};
  wire [AXI_ADDR_WIDTH-1:0] araddr_bank = {32'd0, 2'b00, s_araddr_i[29:0]};

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      write_bank_q <= 2'd0;
      read_bank_q  <= 2'd0;
    end else begin
      if (s_awvalid_i && s_awready_o) begin
        write_bank_q <= aw_bank;
      end
      if (s_arvalid_i && s_arready_o) begin
        read_bank_q <= ar_bank;
      end
    end
  end

  always_comb begin
    m0_awaddr_o = awaddr_bank; m1_awaddr_o = awaddr_bank; m2_awaddr_o = awaddr_bank; m3_awaddr_o = awaddr_bank;
    m0_awlen_o = s_awlen_i; m1_awlen_o = s_awlen_i; m2_awlen_o = s_awlen_i; m3_awlen_o = s_awlen_i;
    m0_awsize_o = s_awsize_i; m1_awsize_o = s_awsize_i; m2_awsize_o = s_awsize_i; m3_awsize_o = s_awsize_i;
    m0_awburst_o = s_awburst_i; m1_awburst_o = s_awburst_i; m2_awburst_o = s_awburst_i; m3_awburst_o = s_awburst_i;
    m0_awvalid_o = s_awvalid_i && (aw_bank == 2'd0);
    m1_awvalid_o = s_awvalid_i && (aw_bank == 2'd1);
    m2_awvalid_o = s_awvalid_i && (aw_bank == 2'd2);
    m3_awvalid_o = s_awvalid_i && (aw_bank == 2'd3);

    m0_wdata_o = s_wdata_i; m1_wdata_o = s_wdata_i; m2_wdata_o = s_wdata_i; m3_wdata_o = s_wdata_i;
    m0_wstrb_o = s_wstrb_i; m1_wstrb_o = s_wstrb_i; m2_wstrb_o = s_wstrb_i; m3_wstrb_o = s_wstrb_i;
    m0_wlast_o = s_wlast_i; m1_wlast_o = s_wlast_i; m2_wlast_o = s_wlast_i; m3_wlast_o = s_wlast_i;
    m0_wvalid_o = s_wvalid_i && (aw_bank == 2'd0);
    m1_wvalid_o = s_wvalid_i && (aw_bank == 2'd1);
    m2_wvalid_o = s_wvalid_i && (aw_bank == 2'd2);
    m3_wvalid_o = s_wvalid_i && (aw_bank == 2'd3);

    m0_araddr_o = araddr_bank; m1_araddr_o = araddr_bank; m2_araddr_o = araddr_bank; m3_araddr_o = araddr_bank;
    m0_arlen_o = s_arlen_i; m1_arlen_o = s_arlen_i; m2_arlen_o = s_arlen_i; m3_arlen_o = s_arlen_i;
    m0_arsize_o = s_arsize_i; m1_arsize_o = s_arsize_i; m2_arsize_o = s_arsize_i; m3_arsize_o = s_arsize_i;
    m0_arburst_o = s_arburst_i; m1_arburst_o = s_arburst_i; m2_arburst_o = s_arburst_i; m3_arburst_o = s_arburst_i;
    m0_arvalid_o = s_arvalid_i && (ar_bank == 2'd0);
    m1_arvalid_o = s_arvalid_i && (ar_bank == 2'd1);
    m2_arvalid_o = s_arvalid_i && (ar_bank == 2'd2);
    m3_arvalid_o = s_arvalid_i && (ar_bank == 2'd3);

    m0_bready_o = s_bready_i && (write_bank_q == 2'd0);
    m1_bready_o = s_bready_i && (write_bank_q == 2'd1);
    m2_bready_o = s_bready_i && (write_bank_q == 2'd2);
    m3_bready_o = s_bready_i && (write_bank_q == 2'd3);
    m0_rready_o = s_rready_i && (read_bank_q == 2'd0);
    m1_rready_o = s_rready_i && (read_bank_q == 2'd1);
    m2_rready_o = s_rready_i && (read_bank_q == 2'd2);
    m3_rready_o = s_rready_i && (read_bank_q == 2'd3);

    unique case (aw_bank)
      2'd0: begin s_awready_o = m0_awready_i; s_wready_o = m0_wready_i; end
      2'd1: begin s_awready_o = m1_awready_i; s_wready_o = m1_wready_i; end
      2'd2: begin s_awready_o = m2_awready_i; s_wready_o = m2_wready_i; end
      default: begin s_awready_o = m3_awready_i; s_wready_o = m3_wready_i; end
    endcase

    unique case (write_bank_q)
      2'd0: begin s_bvalid_o = m0_bvalid_i; s_bresp_o = m0_bresp_i; end
      2'd1: begin s_bvalid_o = m1_bvalid_i; s_bresp_o = m1_bresp_i; end
      2'd2: begin s_bvalid_o = m2_bvalid_i; s_bresp_o = m2_bresp_i; end
      default: begin s_bvalid_o = m3_bvalid_i; s_bresp_o = m3_bresp_i; end
    endcase

    unique case (ar_bank)
      2'd0: s_arready_o = m0_arready_i;
      2'd1: s_arready_o = m1_arready_i;
      2'd2: s_arready_o = m2_arready_i;
      default: s_arready_o = m3_arready_i;
    endcase

    unique case (read_bank_q)
      2'd0: begin s_rvalid_o = m0_rvalid_i; s_rdata_o = m0_rdata_i; s_rresp_o = m0_rresp_i; s_rlast_o = m0_rlast_i; end
      2'd1: begin s_rvalid_o = m1_rvalid_i; s_rdata_o = m1_rdata_i; s_rresp_o = m1_rresp_i; s_rlast_o = m1_rlast_i; end
      2'd2: begin s_rvalid_o = m2_rvalid_i; s_rdata_o = m2_rdata_i; s_rresp_o = m2_rresp_i; s_rlast_o = m2_rlast_i; end
      default: begin s_rvalid_o = m3_rvalid_i; s_rdata_o = m3_rdata_i; s_rresp_o = m3_rresp_i; s_rlast_o = m3_rlast_i; end
    endcase
  end
endmodule

`default_nettype wire
