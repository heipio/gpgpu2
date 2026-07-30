`timescale 1ns/1ps
`default_nettype none

module fpu_core #(
  parameter int FMA_LATENCY = 8,
  parameter int NUM_WARPS = 4
) (
  input  wire logic        clk_i,
  input  wire logic        rst_ni,

  input  wire logic        start_i,
  input  wire logic [$clog2(NUM_WARPS)-1:0] warp_i,
  input  wire logic [15:0] opcode_i,
  input  wire logic [3:0]  type_code_i,
  input  wire logic [1:0]  beat_i,
  input  wire logic [7:0]  active_mask_i,
  input  wire logic [7:0]  dst_reg_i,
  input  wire logic [7:0][31:0] src1_data_i,
  input  wire logic [7:0][31:0] src2_data_i,
  input  wire logic [7:0][31:0] src3_data_i,

  output logic        busy_o,
  output logic        write_valid_o,
  output logic [$clog2(NUM_WARPS)-1:0] write_warp_o,
  output logic [1:0]  write_beat_o,
  output logic [7:0]  write_reg_o,
  output logic [7:0][31:0] write_data_o,
  output logic [7:0]  write_mask_o
);
  import aec_pkg::*;
  localparam int WARP_BITS = (NUM_WARPS <= 1) ? 1 : $clog2(NUM_WARPS);

  typedef enum logic [2:0] {
    FPU_IDLE,
    FPU_PREP_0,
    FPU_ISSUE_0,
    FPU_WAIT_0,
    FPU_PREP_1,
    FPU_ISSUE_1,
    FPU_WAIT_1,
    FPU_WRITE
  } fpu_state_e;

  localparam logic [31:0] FP32_ONE  = 32'h3f80_0000;
  localparam logic [31:0] FP32_ZERO = 32'h0000_0000;

  fpu_state_e state_q;
  logic [WARP_BITS-1:0] warp_q;
  logic [15:0] opcode_q;
  logic [1:0]  beat_q;
  logic [7:0]  mask_q;
  logic [7:0]  dst_q;
  logic [7:0][31:0] src1_q;
  logic [7:0][31:0] src2_q;
  logic [7:0][31:0] src3_q;
  logic [7:0][31:0] mul_q;
  logic [7:0][31:0] result_q;
  logic [7:0][31:0] write_data;
  logic [7:0] result_valid;
  logic [7:0][31:0] fma_a;
  logic [7:0][31:0] fma_b;
  logic [7:0][31:0] fma_c;
  logic [7:0][31:0] fma_a_q;
  logic [7:0][31:0] fma_b_q;
  logic [7:0][31:0] fma_c_q;
  logic fma_valid;

  function automatic logic is_f32_op(input logic [15:0] opcode, input logic [3:0] type_code);
    begin
      unique case (aec_opcode_e'(opcode))
        AEC_OP_ADD,
        AEC_OP_SUB,
        AEC_OP_MUL,
        AEC_OP_MAD,
        AEC_OP_FMA: is_f32_op = (type_code == 4'h8);
        default:    is_f32_op = 1'b0;
      endcase
    end
  endfunction

  function automatic logic is_nan(input logic [31:0] bits);
    begin
      is_nan = (bits[30:23] == 8'hff) && (bits[22:0] != 23'd0);
    end
  endfunction

  function automatic logic is_inf(input logic [31:0] bits);
    begin
      is_inf = (bits[30:23] == 8'hff) && (bits[22:0] == 23'd0);
    end
  endfunction

  function automatic logic is_zero(input logic [31:0] bits);
    begin
      is_zero = (bits[30:0] == 31'd0);
    end
  endfunction

  function automatic logic [31:0] canonicalize_or_fix_mul_zero(
    input logic [15:0] opcode,
    input logic [31:0] src1,
    input logic [31:0] src2,
    input logic [31:0] raw_result
  );
    logic zero_mul;
    logic invalid_mul;
    begin
      zero_mul = (opcode == AEC_OP_MUL) && (is_zero(src1) || is_zero(src2));
      invalid_mul = (opcode == AEC_OP_MUL) &&
          ((is_zero(src1) && is_inf(src2)) || (is_inf(src1) && is_zero(src2)));

      if (is_nan(src1) || is_nan(src2) || is_nan(raw_result) || invalid_mul) begin
        canonicalize_or_fix_mul_zero = 32'h7fc0_0000;
      end else if (zero_mul) begin
        canonicalize_or_fix_mul_zero = {src1[31] ^ src2[31], 31'd0};
      end else begin
        canonicalize_or_fix_mul_zero = raw_result;
      end
    end
  endfunction

  genvar lane;
  generate
    for (lane = 0; lane < PHYSICAL_SIMD_LANES; lane = lane + 1) begin : g_fma_lane
      fp32_fma_ip_wrap #(
        .BEHAVIORAL_LATENCY(FMA_LATENCY)
      ) u_fma (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .valid_i(fma_valid),
        .a_i(fma_a[lane]),
        .b_i(fma_b[lane]),
        .c_i(fma_c[lane]),
        .result_valid_o(result_valid[lane]),
        .result_o(result_q[lane])
      );
    end
  endgenerate

  always_comb begin
    busy_o = (state_q != FPU_IDLE);
    fma_valid = (state_q == FPU_ISSUE_0) || (state_q == FPU_ISSUE_1);
    fma_a = fma_a_q;
    fma_b = fma_b_q;
    fma_c = fma_c_q;

    for (int out_lane = 0; out_lane < PHYSICAL_SIMD_LANES; out_lane = out_lane + 1) begin
      write_data[out_lane] = canonicalize_or_fix_mul_zero(
          opcode_q, src1_q[out_lane], src2_q[out_lane], result_q[out_lane]);
    end

    write_valid_o = (state_q == FPU_WRITE);
    write_warp_o  = warp_q;
    write_beat_o  = beat_q;
    write_reg_o   = dst_q;
    write_data_o  = write_data;
    write_mask_o  = write_valid_o ? mask_q : 8'd0;
  end

  integer idx;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= FPU_IDLE;
      warp_q <= '0;
      opcode_q <= AEC_OP_NOP;
      beat_q <= 2'd0;
      mask_q <= 8'd0;
      dst_q <= 8'd0;
      src1_q <= '0;
      src2_q <= '0;
      src3_q <= '0;
      mul_q <= '0;
      fma_a_q <= '0;
      fma_b_q <= '0;
      fma_c_q <= '0;
    end else begin
      unique case (state_q)
        FPU_IDLE: begin
          if (start_i && is_f32_op(opcode_i, type_code_i)) begin
            opcode_q <= opcode_i;
            warp_q <= warp_i;
            beat_q <= beat_i;
            mask_q <= active_mask_i;
            dst_q <= dst_reg_i;
            src1_q <= src1_data_i;
            src2_q <= src2_data_i;
            src3_q <= src3_data_i;
            state_q <= FPU_PREP_0;
          end
        end
        FPU_PREP_0: begin
          for (idx = 0; idx < PHYSICAL_SIMD_LANES; idx = idx + 1) begin
            unique case (aec_opcode_e'(opcode_q))
              AEC_OP_ADD: begin
                fma_a_q[idx] <= FP32_ONE;
                fma_b_q[idx] <= src1_q[idx];
                fma_c_q[idx] <= src2_q[idx];
              end
              AEC_OP_SUB: begin
                fma_a_q[idx] <= FP32_ONE;
                fma_b_q[idx] <= src1_q[idx];
                fma_c_q[idx] <= {~src2_q[idx][31], src2_q[idx][30:0]};
              end
              AEC_OP_MUL,
              AEC_OP_MAD,
              AEC_OP_FMA: begin
                fma_a_q[idx] <= src1_q[idx];
                fma_b_q[idx] <= src2_q[idx];
                fma_c_q[idx] <= (aec_opcode_e'(opcode_q) == AEC_OP_FMA) ? src3_q[idx] : FP32_ZERO;
              end
              default: begin
                fma_a_q[idx] <= FP32_ZERO;
                fma_b_q[idx] <= FP32_ZERO;
                fma_c_q[idx] <= FP32_ZERO;
              end
            endcase
          end
          state_q <= FPU_ISSUE_0;
        end
        FPU_ISSUE_0: begin
          state_q <= FPU_WAIT_0;
        end
        FPU_WAIT_0: begin
          if (&result_valid) begin
            if (aec_opcode_e'(opcode_q) == AEC_OP_MAD) begin
              for (idx = 0; idx < PHYSICAL_SIMD_LANES; idx = idx + 1) begin
                mul_q[idx] <= result_q[idx];
              end
              state_q <= FPU_PREP_1;
            end else begin
              state_q <= FPU_WRITE;
            end
          end
        end
        FPU_PREP_1: begin
          for (idx = 0; idx < PHYSICAL_SIMD_LANES; idx = idx + 1) begin
            fma_a_q[idx] <= FP32_ONE;
            fma_b_q[idx] <= mul_q[idx];
            fma_c_q[idx] <= src3_q[idx];
          end
          state_q <= FPU_ISSUE_1;
        end
        FPU_ISSUE_1: begin
          state_q <= FPU_WAIT_1;
        end
        FPU_WAIT_1: begin
          if (&result_valid) begin
            state_q <= FPU_WRITE;
          end
        end
        FPU_WRITE: begin
          state_q <= FPU_IDLE;
        end
        default: begin
          state_q <= FPU_IDLE;
        end
      endcase
    end
  end
endmodule

`default_nettype wire
