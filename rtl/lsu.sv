`timescale 1ns/1ps
`default_nettype none

module lsu #(
  parameter int AXI_ADDR_WIDTH = 64,
  parameter int AXI_DATA_WIDTH = 512
) (
  input  wire logic                       clk_i,
  input  wire logic                       rst_ni,

  input  wire logic                       ex_valid_i,
  input  wire logic [15:0]                ex_opcode_i,
  input  wire logic [1:0]                 ex_beat_i,
  input  wire logic [15:0]                ex_pc_i,
  input  wire logic [7:0]                 ex_active_mask_i,
  input  wire logic [7:0]                 ex_dst_reg_i,
  input  wire logic [7:0][31:0]           ex_src1_data_i,
  input  wire logic [7:0][31:0]           ex_src2_data_i,
  input  wire logic [7:0][31:0]           ex_src3_data_i,

  output logic                            busy_o,
  output logic                            load_valid_o,
  output logic [1:0]                      load_beat_o,
  output logic [7:0]                      load_dst_reg_o,
  output logic [7:0]                      load_mask_o,
  output logic [7:0][31:0]                load_data_o,

  output logic                            fault_valid_o,
  output aec_pkg::aec_fault_e             fault_code_o,
  output logic [15:0]                     fault_pc_o,

  output logic [AXI_ADDR_WIDTH-1:0]       m_axi_awaddr,
  output logic [7:0]                      m_axi_awlen,
  output logic [2:0]                      m_axi_awsize,
  output logic [1:0]                      m_axi_awburst,
  output logic                            m_axi_awvalid,
  input  wire logic                       m_axi_awready,
  output logic [AXI_DATA_WIDTH-1:0]       m_axi_wdata,
  output logic [AXI_DATA_WIDTH/8-1:0]     m_axi_wstrb,
  output logic                            m_axi_wlast,
  output logic                            m_axi_wvalid,
  input  wire logic                       m_axi_wready,
  input  wire logic [1:0]                 m_axi_bresp,
  input  wire logic                       m_axi_bvalid,
  output logic                            m_axi_bready,
  output logic [AXI_ADDR_WIDTH-1:0]       m_axi_araddr,
  output logic [7:0]                      m_axi_arlen,
  output logic [2:0]                      m_axi_arsize,
  output logic [1:0]                      m_axi_arburst,
  output logic                            m_axi_arvalid,
  input  wire logic                       m_axi_arready,
  input  wire logic [AXI_DATA_WIDTH-1:0]  m_axi_rdata,
  input  wire logic [1:0]                 m_axi_rresp,
  input  wire logic                       m_axi_rlast,
  input  wire logic                       m_axi_rvalid,
  output logic                            m_axi_rready
);
  import aec_pkg::*;

  localparam int AXI_STRB_WIDTH = AXI_DATA_WIDTH / 8;
  localparam int BYTE_OFFSET_BITS = $clog2(AXI_STRB_WIDTH);
  localparam logic [31:0] SIM_MEM_LIMIT_BYTES = 32'h0001_0000;

  typedef enum logic [2:0] {
    LSU_IDLE,
    LSU_NEXT_LANE,
    LSU_STORE_ADDR_DATA,
    LSU_STORE_RESP,
    LSU_LOAD_ADDR,
    LSU_LOAD_DATA,
    LSU_DONE
  } lsu_state_e;

  lsu_state_e state_q;
  logic is_load_q;
  logic [1:0] beat_q;
  logic [7:0] dst_reg_q;
  logic [7:0] mask_q;
  logic [15:0] pc_q;
  logic [2:0] lane_idx_q;
  logic [7:0][31:0] src1_data_q;
  logic [7:0][31:0] src2_data_q;
  logic [7:0][31:0] src3_data_q;
  logic [7:0][31:0] load_data_q;
  logic [AXI_ADDR_WIDTH-1:0] addr_q;
  logic [BYTE_OFFSET_BITS-1:0] byte_offset_q;
  logic aw_done_q;
  logic w_done_q;

  wire active_any = |ex_active_mask_i;
  wire start_ld = ex_valid_i && active_any && (aec_opcode_e'(ex_opcode_i) == AEC_OP_LD);
  wire start_st = ex_valid_i && active_any && (aec_opcode_e'(ex_opcode_i) == AEC_OP_ST);
  wire [31:0] lane_addr = src1_data_q[lane_idx_q] + src2_data_q[lane_idx_q];
  wire lane_misaligned = |lane_addr[1:0];
  wire lane_addr_error = (lane_addr > (SIM_MEM_LIMIT_BYTES - 32'd4));
  wire at_last_lane = (lane_idx_q == 3'd7);

  function automatic logic [AXI_ADDR_WIDTH-1:0] align_axi_addr(input logic [31:0] addr);
    logic [AXI_ADDR_WIDTH-1:0] widened;
    begin
      widened = {{(AXI_ADDR_WIDTH-32){1'b0}}, addr};
      widened[BYTE_OFFSET_BITS-1:0] = '0;
      align_axi_addr = widened;
    end
  endfunction

  function automatic logic [AXI_DATA_WIDTH-1:0] build_wdata(
    input logic [31:0] value,
    input logic [BYTE_OFFSET_BITS-1:0] byte_offset
  );
    logic [AXI_DATA_WIDTH-1:0] data;
    begin
      data = '0;
      data[byte_offset * 8 +: 32] = value;
      build_wdata = data;
    end
  endfunction

  function automatic logic [AXI_STRB_WIDTH-1:0] build_wstrb(
    input logic [BYTE_OFFSET_BITS-1:0] byte_offset
  );
    logic [AXI_STRB_WIDTH-1:0] strb;
    begin
      strb = '0;
      strb[byte_offset +: 4] = 4'hf;
      build_wstrb = strb;
    end
  endfunction

  function automatic logic [31:0] pick_rdata(
    input logic [AXI_DATA_WIDTH-1:0] data,
    input logic [BYTE_OFFSET_BITS-1:0] byte_offset
  );
    begin
      pick_rdata = data[byte_offset * 8 +: 32];
    end
  endfunction

  integer lane_init;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q        <= LSU_IDLE;
      is_load_q      <= 1'b0;
      beat_q         <= 2'd0;
      dst_reg_q      <= 8'd0;
      pc_q           <= 16'd0;
      mask_q         <= 8'd0;
      lane_idx_q     <= 3'd0;
      src1_data_q    <= '0;
      src2_data_q    <= '0;
      src3_data_q    <= '0;
      load_data_q    <= '0;
      addr_q         <= '0;
      byte_offset_q  <= '0;
      aw_done_q      <= 1'b0;
      w_done_q       <= 1'b0;
      load_valid_o   <= 1'b0;
      load_beat_o    <= 2'd0;
      load_dst_reg_o <= 8'd0;
      load_mask_o    <= 8'd0;
      load_data_o    <= '0;
      fault_valid_o  <= 1'b0;
      fault_code_o   <= AEC_FAULT_NONE;
      fault_pc_o     <= 16'd0;
    end else begin
      load_valid_o <= 1'b0;
      fault_valid_o <= 1'b0;

      unique case (state_q)
        LSU_IDLE: begin
          aw_done_q <= 1'b0;
          w_done_q  <= 1'b0;
          if (start_ld || start_st) begin
            state_q     <= LSU_NEXT_LANE;
            is_load_q   <= start_ld;
            beat_q      <= ex_beat_i;
            dst_reg_q   <= ex_dst_reg_i;
            pc_q        <= ex_pc_i;
            mask_q      <= ex_active_mask_i;
            lane_idx_q  <= 3'd0;
            src1_data_q <= ex_src1_data_i;
            src2_data_q <= ex_src2_data_i;
            src3_data_q <= ex_src3_data_i;
            for (lane_init = 0; lane_init < PHYSICAL_SIMD_LANES; lane_init = lane_init + 1) begin
              load_data_q[lane_init] <= 32'd0;
            end
          end
        end

        LSU_NEXT_LANE: begin
          aw_done_q <= 1'b0;
          w_done_q  <= 1'b0;
          if (!mask_q[lane_idx_q]) begin
            if (at_last_lane) begin
              state_q <= LSU_DONE;
            end else begin
              lane_idx_q <= lane_idx_q + 3'd1;
            end
          end else begin
            if (lane_misaligned || lane_addr_error) begin
              fault_valid_o <= 1'b1;
              fault_code_o  <= lane_misaligned ? AEC_FAULT_MISALIGNED_ACCESS : AEC_FAULT_ADDRESS_ERROR;
              fault_pc_o    <= pc_q;
              state_q       <= LSU_DONE;
              mask_q        <= 8'd0;
            end else begin
              addr_q        <= align_axi_addr(lane_addr);
              byte_offset_q <= lane_addr[BYTE_OFFSET_BITS-1:0];
              state_q       <= is_load_q ? LSU_LOAD_ADDR : LSU_STORE_ADDR_DATA;
            end
          end
        end

        LSU_STORE_ADDR_DATA: begin
          if (m_axi_awvalid && m_axi_awready) begin
            aw_done_q <= 1'b1;
          end
          if (m_axi_wvalid && m_axi_wready) begin
            w_done_q <= 1'b1;
          end
          if ((aw_done_q || (m_axi_awvalid && m_axi_awready)) &&
              (w_done_q || (m_axi_wvalid && m_axi_wready))) begin
            state_q <= LSU_STORE_RESP;
          end
        end

        LSU_STORE_RESP: begin
          if (m_axi_bvalid) begin
            if (at_last_lane) begin
              state_q <= LSU_DONE;
            end else begin
              lane_idx_q <= lane_idx_q + 3'd1;
              state_q    <= LSU_NEXT_LANE;
            end
          end
        end

        LSU_LOAD_ADDR: begin
          if (m_axi_arvalid && m_axi_arready) begin
            state_q <= LSU_LOAD_DATA;
          end
        end

        LSU_LOAD_DATA: begin
          if (m_axi_rvalid) begin
            load_data_q[lane_idx_q] <= pick_rdata(m_axi_rdata, byte_offset_q);
            if (at_last_lane) begin
              state_q <= LSU_DONE;
            end else begin
              lane_idx_q <= lane_idx_q + 3'd1;
              state_q    <= LSU_NEXT_LANE;
            end
          end
        end

        LSU_DONE: begin
          state_q <= LSU_IDLE;
          if (is_load_q) begin
            load_valid_o   <= 1'b1;
            load_beat_o    <= beat_q;
            load_dst_reg_o <= dst_reg_q;
            load_mask_o    <= mask_q;
            load_data_o    <= load_data_q;
          end
        end

        default: begin
          state_q <= LSU_IDLE;
        end
      endcase
    end
  end

  always_comb begin
    busy_o        = (state_q != LSU_IDLE);

    m_axi_awaddr  = addr_q;
    m_axi_awlen   = 8'd0;
    m_axi_awsize  = 3'd2;
    m_axi_awburst = 2'b01;
    m_axi_awvalid = (state_q == LSU_STORE_ADDR_DATA) && !aw_done_q;

    m_axi_wdata   = build_wdata(src3_data_q[lane_idx_q], byte_offset_q);
    m_axi_wstrb   = build_wstrb(byte_offset_q);
    m_axi_wlast   = 1'b1;
    m_axi_wvalid  = (state_q == LSU_STORE_ADDR_DATA) && !w_done_q;

    m_axi_bready  = (state_q == LSU_STORE_RESP);

    m_axi_araddr  = addr_q;
    m_axi_arlen   = 8'd0;
    m_axi_arsize  = 3'd2;
    m_axi_arburst = 2'b01;
    m_axi_arvalid = (state_q == LSU_LOAD_ADDR);
    m_axi_rready  = (state_q == LSU_LOAD_DATA);
  end

  logic unused_axi_resp;
  assign unused_axi_resp = ^{m_axi_bresp, m_axi_rresp, m_axi_rlast};
endmodule

`default_nettype wire
