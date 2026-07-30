`timescale 1ns/1ps
`default_nettype none

module fetch_decode (
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
  output logic         pred_enable_o
);
  import aec_pkg::*;

  logic [15:0] opcode_bits;

  always_comb begin
    dec_valid_o   = instr_valid_i;

    opcode_bits   = instr_i[127:112];
    opcode_o      = aec_opcode_e'(opcode_bits);
    pred_ctrl_o   = instr_i[111:96];
    dst_o         = instr_i[95:80];
    src1_o        = instr_i[79:64];
    src2_o        = instr_i[63:32];
    src3_o        = instr_i[31:0];

    dst_reg_o     = instr_i[87:80];
    src1_reg_o    = instr_i[71:64];
    src2_reg_o    = instr_i[39:32];
    if (opcode_bits == AEC_OP_ST) begin
      src3_reg_o  = instr_i[23:16];
    end else begin
      src3_reg_o  = instr_i[7:0];
    end

    pred_reg_o    = instr_i[98:96];
    pred_negate_o = instr_i[110];
    pred_enable_o = instr_i[111];
  end
endmodule

`default_nettype wire

