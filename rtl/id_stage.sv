`timescale 1ns/1ps
`default_nettype none

module id_stage (
  input  wire logic         instr_valid_i,
  input  wire logic [127:0] instr_i,

  output logic         dec_valid_o,
  output aec_pkg::aec_opcode_e opcode_o,
  output logic [15:0]  pred_ctrl_o,
  output logic [15:0]  dst_o,
  output logic [15:0]  src1_o,
  output logic [31:0]  src2_o,
  output logic [31:0]  src3_o,

  output logic [7:0]   dst_reg_o,
  output logic [7:0]   src1_reg_o,
  output logic [7:0]   src2_reg_o,
  output logic [7:0]   src3_reg_o,
  output logic [2:0]   pred_reg_o,
  output logic         pred_negate_o,
  output logic         pred_enable_o,
  output logic [3:0]   pred_sel_o,
  output logic         illegal_opcode_o
);
  import aec_pkg::*;

  localparam logic [3:0] PRED_PT = 4'hf;

  function automatic logic opcode_known(input logic [15:0] opcode);
    begin
      unique case (opcode)
        AEC_OP_NOP,
        AEC_OP_MOV,
        AEC_OP_LOADI,
        AEC_OP_LOADI64,
        AEC_OP_IADD_U32,
        AEC_OP_IMUL_U32,
        AEC_OP_MAD_F32,
        AEC_OP_FMA_F32,
        AEC_OP_SETP,
        AEC_OP_CMPP,
        AEC_OP_SUB_U32,
        AEC_OP_AND_B32,
        AEC_OP_OR_B32,
        AEC_OP_XOR_B32,
        AEC_OP_SHL_B32,
        AEC_OP_SHR_B32,
        AEC_OP_LD,
        AEC_OP_ST,
        AEC_OP_FENCE,
        AEC_OP_BRA,
        AEC_OP_BRX,
        AEC_OP_SSY,
        AEC_OP_SYNC,
        AEC_OP_BAR_SYNC,
        AEC_OP_SHFL,
        AEC_OP_REDUCE_ADD,
        AEC_OP_SFU,
        AEC_OP_MMA_E4M3,
        AEC_OP_HALT: opcode_known = 1'b1;
        default:    opcode_known = 1'b0;
      endcase
    end
  endfunction

  fetch_decode u_fetch_decode (
    .instr_valid_i(instr_valid_i),
    .instr_i(instr_i),
    .dec_valid_o(dec_valid_o),
    .opcode_o(opcode_o),
    .pred_ctrl_o(pred_ctrl_o),
    .dst_o(dst_o),
    .src1_o(src1_o),
    .src2_o(src2_o),
    .src3_o(src3_o),
    .dst_reg_o(dst_reg_o),
    .src1_reg_o(src1_reg_o),
    .src2_reg_o(src2_reg_o),
    .src3_reg_o(src3_reg_o),
    .pred_reg_o(pred_reg_o),
    .pred_negate_o(pred_negate_o),
    .pred_enable_o(pred_enable_o)
  );

  always_comb begin
    pred_sel_o       = pred_enable_o ? {pred_negate_o, pred_reg_o} : PRED_PT;
    illegal_opcode_o = dec_valid_o && !opcode_known(instr_i[127:112]);
  end
endmodule

`default_nettype wire
