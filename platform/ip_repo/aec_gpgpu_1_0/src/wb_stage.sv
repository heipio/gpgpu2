`timescale 1ns/1ps
`default_nettype none

module wb_stage #(
  parameter int NUM_WARPS = 4
) (
  input  wire logic        clk_i,
  input  wire logic        rst_ni,

  input  wire logic        ex_valid_i,
  input  wire logic [$clog2(NUM_WARPS)-1:0] ex_warp_i,
  input  wire logic [15:0] ex_opcode_i,
  input  wire logic [3:0]  ex_type_code_i,
  input  wire logic [1:0]  ex_beat_i,
  input  wire logic [7:0]  ex_active_mask_i,
  input  wire logic [7:0]  ex_dst_reg_i,
  input  wire logic [7:0][31:0] ex_result_i,

  input  wire logic        lsu_load_valid_i,
  input  wire logic [$clog2(NUM_WARPS)-1:0] lsu_load_warp_i,
  input  wire logic [1:0]  lsu_load_beat_i,
  input  wire logic [7:0]  lsu_load_dst_reg_i,
  input  wire logic [7:0]  lsu_load_mask_i,
  input  wire logic [7:0][31:0] lsu_load_data_i,

  output logic        vrf_write_valid_o,
  output logic [$clog2(NUM_WARPS)-1:0] vrf_write_warp_o,
  output logic [1:0]  vrf_write_beat_o,
  output logic [7:0]  vrf_write_dst_reg_o,
  output logic [9:0]  vrf_waddr_o,
  output logic [7:0][31:0] vrf_write_data_o,
  output logic [7:0]  vrf_write_mask_o
);
  import aec_pkg::*;
  localparam int WARP_BITS = (NUM_WARPS <= 1) ? 1 : $clog2(NUM_WARPS);

  function automatic logic opcode_writes_vrf(input logic [15:0] opcode, input logic [3:0] type_code);
    begin
      unique case (aec_opcode_e'(opcode))
        AEC_OP_MOV,
        AEC_OP_LOADI,
        AEC_OP_IADD_U32,
        AEC_OP_IMUL_U32,
        AEC_OP_SUB_U32,
        AEC_OP_AND_B32,
        AEC_OP_OR_B32,
        AEC_OP_XOR_B32,
        AEC_OP_SHL_B32,
        AEC_OP_SHR_B32,
        AEC_OP_SFU: opcode_writes_vrf = 1'b1;
        AEC_OP_MAD,
        AEC_OP_FMA,
        AEC_OP_SHFL,
        AEC_OP_REDUCE: opcode_writes_vrf = 1'b0;
        default:        opcode_writes_vrf = 1'b0;
      endcase
      if (((aec_opcode_e'(opcode) == AEC_OP_ADD) ||
           (aec_opcode_e'(opcode) == AEC_OP_SUB) ||
           (aec_opcode_e'(opcode) == AEC_OP_MUL)) && (type_code == 4'h8)) begin
        opcode_writes_vrf = 1'b0;
      end
    end
  endfunction

  logic        write_valid_q;
  logic [WARP_BITS-1:0] write_warp_q;
  logic [1:0]  write_beat_q;
  logic [7:0]  write_dst_reg_q;
  logic [7:0]  write_mask_q;
  logic [7:0][31:0] write_data_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      write_valid_q   <= 1'b0;
      write_warp_q    <= '0;
      write_beat_q    <= 2'd0;
      write_dst_reg_q <= 8'd0;
      write_mask_q    <= 8'd0;
      write_data_q    <= '0;
    end else begin
      if (lsu_load_valid_i) begin
        write_valid_q   <= 1'b1;
        write_warp_q    <= lsu_load_warp_i;
        write_beat_q    <= lsu_load_beat_i;
        write_dst_reg_q <= lsu_load_dst_reg_i;
        write_mask_q    <= lsu_load_mask_i;
        write_data_q    <= lsu_load_data_i;
      end else begin
        write_valid_q   <= ex_valid_i && opcode_writes_vrf(ex_opcode_i, ex_type_code_i);
        write_warp_q    <= ex_warp_i;
        write_beat_q    <= ex_beat_i;
        write_dst_reg_q <= ex_dst_reg_i;
        write_mask_q    <= ex_valid_i ? ex_active_mask_i : 8'd0;
        write_data_q    <= ex_result_i;
      end
    end
  end

  always_comb begin
    vrf_write_valid_o  = write_valid_q;
    vrf_write_warp_o   = write_warp_q;
    vrf_write_beat_o   = write_beat_q;
    vrf_write_dst_reg_o = write_dst_reg_q;
    vrf_waddr_o        = {write_dst_reg_q, write_beat_q};
    vrf_write_data_o   = write_data_q;
    vrf_write_mask_o   = write_valid_q ? write_mask_q : 8'd0;
  end
endmodule

`default_nettype wire
