`timescale 1ns/1ps
`default_nettype none

module scoreboard #(
  parameter int NUM_WARPS = 4
) (
  input  wire logic clk_i,
  input  wire logic rst_ni,
  input  wire logic clear_i,

  input  wire logic check_valid_i,
  input  wire logic [$clog2(NUM_WARPS)-1:0] check_warp_i,
  input  wire logic [15:0] check_opcode_i,
  input  wire logic [3:0]  check_type_code_i,
  input  wire logic        check_imm_en_i,
  input  wire logic [7:0]  check_src1_reg_i,
  input  wire logic [7:0]  check_src2_reg_i,
  input  wire logic [7:0]  check_src3_reg_i,
  input  wire logic [7:0]  check_dst_reg_i,
  output logic             hazard_o,

  input  wire logic        mark_valid_i,
  input  wire logic [$clog2(NUM_WARPS)-1:0] mark_warp_i,
  input  wire logic [7:0]  mark_reg_i,
  input  wire logic [3:0]  mark_count_i,

  input  wire logic        clear_valid_i,
  input  wire logic [$clog2(NUM_WARPS)-1:0] clear_warp_i,
  input  wire logic [7:0]  clear_reg_i,
  input  wire logic [3:0]  clear_count_i
);
  import aec_pkg::*;
  localparam int WARP_BITS = (NUM_WARPS <= 1) ? 1 : $clog2(NUM_WARPS);

  logic [255:0] pending_q [0:NUM_WARPS-1];

  function automatic logic opcode_writes_gpr(input logic [15:0] opcode, input logic [3:0] type_code);
    begin
      opcode_writes_gpr = 1'b0;
      unique case (aec_opcode_e'(opcode))
        AEC_OP_ADD,
        AEC_OP_SUB,
        AEC_OP_MUL,
        AEC_OP_MAD,
        AEC_OP_FMA,
        AEC_OP_AND,
        AEC_OP_OR,
        AEC_OP_XOR,
        AEC_OP_SHL,
        AEC_OP_SHR,
        AEC_OP_MOV,
        AEC_OP_LOADI,
        AEC_OP_LD,
        AEC_OP_SFU,
        AEC_OP_SHFL,
        AEC_OP_REDUCE,
        AEC_OP_MMA: opcode_writes_gpr = 1'b1;
        default:    opcode_writes_gpr = 1'b0;
      endcase
      if (type_code == 4'h0) begin
        opcode_writes_gpr = opcode_writes_gpr;
      end
    end
  endfunction

  function automatic logic uses_src1(input logic [15:0] opcode);
    begin
      unique case (aec_opcode_e'(opcode))
        AEC_OP_LOADI,
        AEC_OP_BRA,
        AEC_OP_SSY,
        AEC_OP_SYNC,
        AEC_OP_BAR_SYNC,
        AEC_OP_FENCE,
        AEC_OP_HALT,
        AEC_OP_NOP: uses_src1 = 1'b0;
        default:    uses_src1 = 1'b1;
      endcase
    end
  endfunction

  function automatic logic uses_src2(input logic [15:0] opcode, input logic imm_en);
    begin
      uses_src2 = 1'b0;
      unique case (aec_opcode_e'(opcode))
        AEC_OP_ADD,
        AEC_OP_SUB,
        AEC_OP_MUL,
        AEC_OP_MAD,
        AEC_OP_FMA,
        AEC_OP_AND,
        AEC_OP_OR,
        AEC_OP_XOR,
        AEC_OP_SHL,
        AEC_OP_SHR,
        AEC_OP_SETP,
        AEC_OP_CMPP,
        AEC_OP_SHFL,
        AEC_OP_REDUCE: uses_src2 = !imm_en;
        AEC_OP_MMA:    uses_src2 = 1'b1;
        default:       uses_src2 = 1'b0;
      endcase
    end
  endfunction

  function automatic logic uses_src3(input logic [15:0] opcode);
    begin
      unique case (aec_opcode_e'(opcode))
        AEC_OP_MAD,
        AEC_OP_FMA,
        AEC_OP_ST,
        AEC_OP_MMA: uses_src3 = 1'b1;
        default:    uses_src3 = 1'b0;
      endcase
    end
  endfunction

  function automatic logic [3:0] operand_span(
    input logic [15:0] opcode,
    input logic [1:0]  operand_sel,
    input logic [3:0]  explicit_count
  );
    begin
      operand_span = (explicit_count == 4'd0) ? 4'd1 : explicit_count;
      if (aec_opcode_e'(opcode) == AEC_OP_MMA) begin
        unique case (operand_sel)
          2'd0:    operand_span = 4'd8;
          2'd1:    operand_span = 4'd2;
          2'd2:    operand_span = 4'd2;
          default: operand_span = 4'd8;
        endcase
      end
    end
  endfunction

  function automatic logic range_pending(
    input logic [255:0] pending,
    input logic [7:0] base_reg,
    input logic [3:0] count
  );
    logic hit;
    begin
      hit = 1'b0;
      for (int reg_off = 0; reg_off < 8; reg_off = reg_off + 1) begin
        if (reg_off < count) begin
          hit = hit || pending[base_reg + reg_off[7:0]];
        end
      end
      range_pending = hit;
    end
  endfunction

  function automatic logic [255:0] range_mask(input logic [7:0] base_reg, input logic [3:0] count);
    logic [255:0] mask;
    begin
      mask = 256'd0;
      for (int reg_off = 0; reg_off < 8; reg_off = reg_off + 1) begin
        if (reg_off < count) begin
          mask[base_reg + reg_off[7:0]] = 1'b1;
        end
      end
      range_mask = mask;
    end
  endfunction

  logic raw_src1;
  logic raw_src2;
  logic raw_src3;
  logic waw_dst;

  always_comb begin
    raw_src1 = uses_src1(check_opcode_i) &&
        range_pending(pending_q[check_warp_i], check_src1_reg_i, operand_span(check_opcode_i, 2'd1, 4'd1));
    raw_src2 = uses_src2(check_opcode_i, check_imm_en_i) &&
        range_pending(pending_q[check_warp_i], check_src2_reg_i, operand_span(check_opcode_i, 2'd2, 4'd1));
    raw_src3 = uses_src3(check_opcode_i) &&
        range_pending(pending_q[check_warp_i], check_src3_reg_i, operand_span(check_opcode_i, 2'd3, 4'd1));
    waw_dst  = opcode_writes_gpr(check_opcode_i, check_type_code_i) &&
        range_pending(pending_q[check_warp_i], check_dst_reg_i, operand_span(check_opcode_i, 2'd0, 4'd1));
    hazard_o = check_valid_i && (raw_src1 || raw_src2 || raw_src3 || waw_dst);
  end

  integer warp_idx;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      for (warp_idx = 0; warp_idx < NUM_WARPS; warp_idx = warp_idx + 1) begin
        pending_q[warp_idx] <= 256'd0;
      end
    end else if (clear_i) begin
      for (warp_idx = 0; warp_idx < NUM_WARPS; warp_idx = warp_idx + 1) begin
        pending_q[warp_idx] <= 256'd0;
      end
    end else begin
      if (clear_valid_i) begin
        pending_q[clear_warp_i] <= pending_q[clear_warp_i] &
            ~range_mask(clear_reg_i, (clear_count_i == 4'd0) ? 4'd1 : clear_count_i);
      end
      if (mark_valid_i) begin
        pending_q[mark_warp_i] <= pending_q[mark_warp_i] |
            range_mask(mark_reg_i, (mark_count_i == 4'd0) ? 4'd1 : mark_count_i);
      end
    end
  end

  logic [WARP_BITS-1:0] unused_warp_bits;
  assign unused_warp_bits = '0;
endmodule

`default_nettype wire
