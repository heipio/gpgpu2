`timescale 1ns/1ps
`default_nettype none

module alu_lane (
  input  wire logic [15:0] opcode_i,
  input  wire logic [31:0] src1_val_i,
  input  wire logic [31:0] src2_val_i,
  input  wire logic [31:0] src3_val_i,
  output logic [31:0] result_o
);
  import aec_pkg::*;

  always_comb begin
    unique case (aec_opcode_e'(opcode_i))
      AEC_OP_MOV: begin
        result_o = src1_val_i;
      end

      AEC_OP_LOADI: begin
        result_o = src2_val_i;
      end

      AEC_OP_IADD_U32: begin
        result_o = src1_val_i + src2_val_i;
      end

      AEC_OP_IMUL_U32: begin
        result_o = src1_val_i * src2_val_i;
      end

      AEC_OP_SUB_U32: begin
        result_o = src1_val_i - src2_val_i;
      end

      AEC_OP_AND_B32: begin
        result_o = src1_val_i & src2_val_i;
      end

      AEC_OP_OR_B32: begin
        result_o = src1_val_i | src2_val_i;
      end

      AEC_OP_XOR_B32: begin
        result_o = src1_val_i ^ src2_val_i;
      end

      AEC_OP_SHL_B32: begin
        result_o = src1_val_i << (src2_val_i & 32'd31);
      end

      AEC_OP_SHR_B32: begin
        result_o = src1_val_i >> (src2_val_i & 32'd31);
      end

      AEC_OP_MAD_F32,
      AEC_OP_FMA_F32: begin
        result_o = 32'd0;
      end

      default: begin
        result_o = 32'd0;
      end
    endcase
  end

  logic unused_src3;
  assign unused_src3 = ^src3_val_i;
endmodule

`default_nettype wire
