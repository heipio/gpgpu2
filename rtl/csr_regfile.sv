`timescale 1ns/1ps
`default_nettype none

module csr_regfile #(
  parameter int AXI_ADDR_WIDTH = 64
) (
  input  wire logic                      clk_i,
  input  wire logic                      rst_ni,

  input  wire logic [AXI_ADDR_WIDTH-1:0] s_axil_awaddr,
  input  wire logic                      s_axil_awvalid,
  output logic                           s_axil_awready,
  input  wire logic [31:0]               s_axil_wdata,
  input  wire logic [3:0]                s_axil_wstrb,
  input  wire logic                      s_axil_wvalid,
  output logic                           s_axil_wready,
  output logic [1:0]                     s_axil_bresp,
  output logic                           s_axil_bvalid,
  input  wire logic                      s_axil_bready,
  input  wire logic [AXI_ADDR_WIDTH-1:0] s_axil_araddr,
  input  wire logic                      s_axil_arvalid,
  output logic                           s_axil_arready,
  output logic [31:0]                    s_axil_rdata,
  output logic [1:0]                     s_axil_rresp,
  output logic                           s_axil_rvalid,
  input  wire logic                      s_axil_rready,

  input  wire logic                      gpu_done_i,
  input  wire logic                      gpu_running_i,
  input  wire logic                      fault_valid_i,
  input  wire aec_pkg::aec_fault_e       fault_code_i,
  input  wire logic [15:0]               fault_pc_i,
  output logic                           start_pulse_o,
  output logic [15:0]                    start_pc_o,

  output logic                           imem_we_o,
  output logic [9:0]                     imem_word_addr_o,
  output logic [31:0]                    imem_wdata_o,
  output logic [3:0]                     imem_wstrb_o,
  output logic [9:0]                     imem_read_word_addr_o,
  input  wire logic [31:0]               imem_rdata_i
);
  import aec_pkg::*;

  localparam logic [AXI_ADDR_WIDTH-1:0] CSR_CTRL_ADDR  = 'h0000;
  localparam logic [AXI_ADDR_WIDTH-1:0] CSR_PC_ADDR    = 'h0004;
  localparam logic [AXI_ADDR_WIDTH-1:0] CSR_STATUS_ADDR = 'h0008;
  localparam logic [AXI_ADDR_WIDTH-1:0] CSR_FAULT_CODE_ADDR = 'h000c;
  localparam logic [AXI_ADDR_WIDTH-1:0] CSR_FAULT_PC_ADDR = 'h0010;
  localparam logic [AXI_ADDR_WIDTH-1:0] IMEM_BASE_ADDR = 'h1000;
  localparam logic [AXI_ADDR_WIDTH-1:0] IMEM_LAST_ADDR = 'h1fff;

  logic [AXI_ADDR_WIDTH-1:0] awaddr_q;
  logic [31:0]              wdata_q;
  logic [3:0]               wstrb_q;
  logic                     aw_seen_q;
  logic                     w_seen_q;
  logic [15:0]              start_pc_q;
  logic                     done_q;
  logic                     fault_q;
  aec_fault_e               fault_code_q;
  logic [15:0]              fault_pc_q;

  wire write_fire = aw_seen_q && w_seen_q && !s_axil_bvalid;
  wire write_is_ctrl = (awaddr_q == CSR_CTRL_ADDR);
  wire write_is_pc = (awaddr_q == CSR_PC_ADDR);
  wire write_is_status = (awaddr_q == CSR_STATUS_ADDR);
  wire write_is_fault_code = (awaddr_q == CSR_FAULT_CODE_ADDR);
  wire write_is_fault_pc = (awaddr_q == CSR_FAULT_PC_ADDR);
  wire write_is_imem = (awaddr_q >= IMEM_BASE_ADDR) && (awaddr_q <= IMEM_LAST_ADDR);
  wire write_imem_strobe_ok = !write_is_imem || (wstrb_q == 4'hf);
  wire read_is_ctrl = (s_axil_araddr == CSR_CTRL_ADDR);
  wire read_is_pc = (s_axil_araddr == CSR_PC_ADDR);
  wire read_is_status = (s_axil_araddr == CSR_STATUS_ADDR);
  wire read_is_fault_code = (s_axil_araddr == CSR_FAULT_CODE_ADDR);
  wire read_is_fault_pc = (s_axil_araddr == CSR_FAULT_PC_ADDR);
  wire read_is_imem = (s_axil_araddr >= IMEM_BASE_ADDR) && (s_axil_araddr <= IMEM_LAST_ADDR);
  wire write_is_known = write_is_ctrl || write_is_pc || write_is_status ||
      write_is_fault_code || write_is_fault_pc || write_is_imem;
  wire read_is_known = read_is_ctrl || read_is_pc || read_is_status ||
      read_is_fault_code || read_is_fault_pc || read_is_imem;

  assign start_pc_o = start_pc_q;
  assign imem_word_addr_o = (awaddr_q - IMEM_BASE_ADDR) >> 2;
  assign imem_wdata_o = wdata_q;
  assign imem_wstrb_o = wstrb_q;
  assign imem_read_word_addr_o = (s_axil_araddr - IMEM_BASE_ADDR) >> 2;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      s_axil_awready <= 1'b0;
      s_axil_wready  <= 1'b0;
      s_axil_bresp   <= 2'b00;
      s_axil_bvalid  <= 1'b0;
      s_axil_arready <= 1'b0;
      s_axil_rdata   <= 32'd0;
      s_axil_rresp   <= 2'b00;
      s_axil_rvalid  <= 1'b0;
      awaddr_q       <= '0;
      wdata_q        <= 32'd0;
      wstrb_q        <= 4'd0;
      aw_seen_q      <= 1'b0;
      w_seen_q       <= 1'b0;
      start_pc_q     <= 16'd0;
      done_q         <= 1'b0;
      fault_q        <= 1'b0;
      fault_code_q   <= AEC_FAULT_NONE;
      fault_pc_q     <= 16'd0;
      start_pulse_o  <= 1'b0;
      imem_we_o      <= 1'b0;
    end else begin
      s_axil_awready <= 1'b0;
      s_axil_wready  <= 1'b0;
      s_axil_arready <= 1'b0;
      start_pulse_o  <= 1'b0;
      imem_we_o      <= 1'b0;

      if (gpu_done_i) begin
        done_q <= 1'b1;
      end

      if (fault_valid_i && !fault_q) begin
        fault_q      <= 1'b1;
        fault_code_q <= fault_code_i;
        fault_pc_q   <= fault_pc_i;
      end

      if (!aw_seen_q && !s_axil_bvalid && s_axil_awvalid) begin
        s_axil_awready <= 1'b1;
        awaddr_q       <= s_axil_awaddr;
        aw_seen_q      <= 1'b1;
      end

      if (!w_seen_q && !s_axil_bvalid && s_axil_wvalid) begin
        s_axil_wready <= 1'b1;
        wdata_q       <= s_axil_wdata;
        wstrb_q       <= s_axil_wstrb;
        w_seen_q      <= 1'b1;
      end

      if (write_fire) begin
        s_axil_bvalid <= 1'b1;
        s_axil_bresp  <= write_is_known && write_imem_strobe_ok ? 2'b00 : 2'b10;
        if (write_is_ctrl) begin
          if (wdata_q[0]) begin
            start_pulse_o <= 1'b1;
            done_q <= 1'b0;
          end
          if (wdata_q[1]) begin
            done_q <= 1'b0;
          end
          if (wdata_q[2]) begin
            fault_q      <= 1'b0;
            fault_code_q <= AEC_FAULT_NONE;
            fault_pc_q   <= 16'd0;
          end
        end else if (write_is_pc) begin
          start_pc_q <= wdata_q[15:0];
        end else if (write_is_status) begin
          if (wdata_q[1]) begin
            done_q <= 1'b0;
          end
          if (wdata_q[2]) begin
            fault_q      <= 1'b0;
            fault_code_q <= AEC_FAULT_NONE;
            fault_pc_q   <= 16'd0;
          end
        end else if (write_is_imem && write_imem_strobe_ok) begin
          imem_we_o <= 1'b1;
        end
        aw_seen_q <= 1'b0;
        w_seen_q  <= 1'b0;
      end else if (s_axil_bvalid && s_axil_bready) begin
        s_axil_bvalid <= 1'b0;
      end

      if (!s_axil_rvalid && s_axil_arvalid) begin
        s_axil_arready <= 1'b1;
        s_axil_rresp   <= read_is_known ? 2'b00 : 2'b10;
        if (read_is_ctrl) begin
          s_axil_rdata <= {29'd0, fault_q, done_q, 1'b0};
        end else if (read_is_pc) begin
          s_axil_rdata <= {16'd0, start_pc_q};
        end else if (read_is_status) begin
          s_axil_rdata <= {29'd0, fault_q, done_q, gpu_running_i};
        end else if (read_is_fault_code) begin
          s_axil_rdata <= {28'd0, fault_code_q};
        end else if (read_is_fault_pc) begin
          s_axil_rdata <= {16'd0, fault_pc_q};
        end else if (read_is_imem) begin
          s_axil_rdata <= imem_rdata_i;
        end else begin
          s_axil_rdata <= 32'd0;
        end
        s_axil_rvalid <= 1'b1;
      end else if (s_axil_rvalid && s_axil_rready) begin
        s_axil_rvalid <= 1'b0;
      end
    end
  end
endmodule

`default_nettype wire
