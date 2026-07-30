`timescale 1ns/1ps
`default_nettype none

module warp_collective_core #(
  parameter int FMA_LATENCY = 1,
  parameter int NUM_WARPS = 4
) (
  input  wire logic        clk_i,
  input  wire logic        rst_ni,

  input  wire logic        start_i,
  input  wire logic [$clog2(NUM_WARPS)-1:0] warp_i,
  input  wire logic [15:0] opcode_i,
  input  wire logic [2:0]  subop_i,
  input  wire logic [3:0]  type_code_i,
  input  wire logic        imm_en_i,
  input  wire logic [31:0] logical_active_mask_i,
  input  wire logic [7:0]  dst_reg_i,
  input  wire logic [7:0]  src1_reg_i,
  input  wire logic [7:0]  src2_reg_i,
  input  wire logic [31:0] src2_imm_i,

  output logic        busy_o,

  output logic        vrf_read_enable_o,
  output logic [$clog2(NUM_WARPS)-1:0] vrf_read_warp_o,
  output logic [1:0]  vrf_read_beat_o,
  output logic [7:0]  vrf_read_reg1_o,
  output logic [7:0]  vrf_read_reg2_o,
  output logic [7:0]  vrf_read_reg3_o,
  input  wire logic [7:0][31:0] vrf_read_data1_i,
  input  wire logic [7:0][31:0] vrf_read_data2_i,

  output logic        vrf_write_valid_o,
  output logic [$clog2(NUM_WARPS)-1:0] vrf_write_warp_o,
  output logic [1:0]  vrf_write_beat_o,
  output logic [7:0]  vrf_write_reg_o,
  output logic [7:0][31:0] vrf_write_data_o,
  output logic [7:0]  vrf_write_mask_o
);
  import aec_pkg::*;
  localparam int WARP_BITS = (NUM_WARPS <= 1) ? 1 : $clog2(NUM_WARPS);

  typedef enum logic [3:0] {
    COLL_IDLE,
    COLL_READ_SETUP,
    COLL_READ_CAPTURE,
    COLL_SHFL_BUILD,
    COLL_REDUCE_STEP,
    COLL_REDUCE_F32_ISSUE,
    COLL_REDUCE_F32_WAIT,
    COLL_WRITE,
    COLL_DONE
  } coll_state_e;

  localparam logic [31:0] FP32_ONE = 32'h3f80_0000;

  coll_state_e state_q;
  logic [WARP_BITS-1:0] warp_q;
  logic [15:0] opcode_q;
  logic [2:0]  subop_q;
  logic [3:0]  type_q;
  logic        imm_en_q;
  logic [31:0] active_mask_q;
  logic [7:0]  dst_q;
  logic [7:0]  src1_q;
  logic [7:0]  src2_q;
  logic [31:0] src2_imm_q;
  logic [1:0]  read_beat_q;
  logic [1:0]  write_beat_q;
  logic [5:0]  reduce_lane_q;
  logic [5:0]  reduce_step_q;

  logic [31:0] lane_val_q [0:31];
  logic [31:0] lane_arg_q [0:31];
  logic [31:0] out_val_q  [0:31];
  logic        live_q     [0:31];

  logic fma_valid;
  logic fma_result_valid;
  logic [31:0] fma_result;

  function automatic logic [4:0] shfl_source_lane(
    input logic [4:0] self_lane,
    input logic [31:0] arg
  );
    logic [4:0] delta;
    begin
      delta = arg[4:0];
      unique case (subop_q)
        3'd0:    shfl_source_lane = arg[4:0];
        3'd1:    shfl_source_lane = self_lane ^ delta;
        3'd2:    shfl_source_lane = (self_lane >= delta) ? (self_lane - delta) : self_lane;
        3'd3:    shfl_source_lane = ((self_lane + delta) < LOGICAL_WARP_WIDTH) ? (self_lane + delta) : self_lane;
        default: shfl_source_lane = self_lane;
      endcase
    end
  endfunction

  function automatic logic [31:0] reduce_u32(
    input logic [31:0] lhs,
    input logic [31:0] rhs
  );
    begin
      unique case (subop_q)
        3'd0:    reduce_u32 = lhs + rhs;
        3'd1:    reduce_u32 = (lhs > rhs) ? lhs : rhs;
        3'd2:    reduce_u32 = (lhs < rhs) ? lhs : rhs;
        3'd3:    reduce_u32 = lhs & rhs;
        3'd4:    reduce_u32 = lhs | rhs;
        3'd5:    reduce_u32 = lhs ^ rhs;
        default: reduce_u32 = lhs;
      endcase
    end
  endfunction

  fp32_fma_ip_wrap #(
    .BEHAVIORAL_LATENCY(FMA_LATENCY)
  ) u_reduce_f32_add (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .valid_i(fma_valid),
    .a_i(FP32_ONE),
    .b_i(lane_val_q[reduce_lane_q]),
    .c_i(lane_val_q[reduce_lane_q + reduce_step_q]),
    .result_valid_o(fma_result_valid),
    .result_o(fma_result)
  );

  always_comb begin
    busy_o = (state_q != COLL_IDLE);
    vrf_read_enable_o = (state_q == COLL_READ_SETUP) || (state_q == COLL_READ_CAPTURE);
    vrf_read_warp_o = warp_q;
    vrf_read_beat_o = read_beat_q;
    vrf_read_reg1_o = src1_q;
    vrf_read_reg2_o = src2_q;
    vrf_read_reg3_o = 8'd0;

    fma_valid = (state_q == COLL_REDUCE_F32_ISSUE);

    vrf_write_valid_o = (state_q == COLL_WRITE);
    vrf_write_warp_o = warp_q;
    vrf_write_beat_o = write_beat_q;
    vrf_write_reg_o = dst_q;
    vrf_write_mask_o = vrf_write_valid_o ? active_mask_q[write_beat_q * PHYSICAL_SIMD_LANES +: PHYSICAL_SIMD_LANES] : 8'd0;
    vrf_write_data_o = '0;
    for (int lane = 0; lane < PHYSICAL_SIMD_LANES; lane = lane + 1) begin
      vrf_write_data_o[lane] = out_val_q[write_beat_q * PHYSICAL_SIMD_LANES + lane];
    end
  end

  integer init_i;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= COLL_IDLE;
      warp_q <= '0;
      opcode_q <= AEC_OP_NOP;
      subop_q <= 3'd0;
      type_q <= 4'd0;
      imm_en_q <= 1'b0;
      active_mask_q <= 32'd0;
      dst_q <= 8'd0;
      src1_q <= 8'd0;
      src2_q <= 8'd0;
      src2_imm_q <= 32'd0;
      read_beat_q <= 2'd0;
      write_beat_q <= 2'd0;
      reduce_lane_q <= 6'd0;
      reduce_step_q <= 6'd1;
      for (init_i = 0; init_i < LOGICAL_WARP_WIDTH; init_i = init_i + 1) begin
        lane_val_q[init_i] <= 32'd0;
        lane_arg_q[init_i] <= 32'd0;
        out_val_q[init_i] <= 32'd0;
        live_q[init_i] <= 1'b0;
      end
    end else begin
      unique case (state_q)
        COLL_IDLE: begin
          if (start_i) begin
            opcode_q <= opcode_i;
            warp_q <= warp_i;
            subop_q <= subop_i;
            type_q <= type_code_i;
            imm_en_q <= imm_en_i;
            active_mask_q <= logical_active_mask_i;
            dst_q <= dst_reg_i;
            src1_q <= src1_reg_i;
            src2_q <= src2_reg_i;
            src2_imm_q <= src2_imm_i;
            read_beat_q <= 2'd0;
            state_q <= COLL_READ_SETUP;
          end
        end
        COLL_READ_SETUP: begin
          state_q <= COLL_READ_CAPTURE;
        end
        COLL_READ_CAPTURE: begin
          for (int lane = 0; lane < PHYSICAL_SIMD_LANES; lane = lane + 1) begin
            lane_val_q[{read_beat_q, lane[2:0]}] <= vrf_read_data1_i[lane];
            lane_arg_q[{read_beat_q, lane[2:0]}] <= imm_en_q ? src2_imm_q : vrf_read_data2_i[lane];
            live_q[{read_beat_q, lane[2:0]}] <= active_mask_q[{read_beat_q, lane[2:0]}];
          end
          if (read_beat_q == 2'd3) begin
            state_q <= (aec_opcode_e'(opcode_q) == AEC_OP_SHFL) ? COLL_SHFL_BUILD : COLL_REDUCE_STEP;
            reduce_lane_q <= 6'd0;
            reduce_step_q <= 6'd1;
          end else begin
            read_beat_q <= read_beat_q + 2'd1;
            state_q <= COLL_READ_SETUP;
          end
        end
        COLL_SHFL_BUILD: begin
          for (int lane = 0; lane < LOGICAL_WARP_WIDTH; lane = lane + 1) begin
            automatic logic [4:0] src_lane;
            src_lane = shfl_source_lane(lane[4:0], lane_arg_q[lane]);
            if (active_mask_q[src_lane]) begin
              out_val_q[lane] <= lane_val_q[src_lane];
            end else begin
              out_val_q[lane] <= lane_val_q[lane];
            end
          end
          write_beat_q <= 2'd0;
          state_q <= COLL_WRITE;
        end
        COLL_REDUCE_STEP: begin
          if (reduce_step_q >= LOGICAL_WARP_WIDTH) begin
            for (int lane = 0; lane < LOGICAL_WARP_WIDTH; lane = lane + 1) begin
              out_val_q[lane] <= lane_val_q[0];
            end
            write_beat_q <= 2'd0;
            state_q <= COLL_WRITE;
          end else if ((reduce_lane_q + reduce_step_q) >= LOGICAL_WARP_WIDTH) begin
            reduce_lane_q <= 6'd0;
            reduce_step_q <= reduce_step_q << 1;
          end else if (!live_q[reduce_lane_q]) begin
            if (live_q[reduce_lane_q + reduce_step_q]) begin
              lane_val_q[reduce_lane_q] <= lane_val_q[reduce_lane_q + reduce_step_q];
              live_q[reduce_lane_q] <= 1'b1;
            end
            reduce_lane_q <= reduce_lane_q + (reduce_step_q << 1);
          end else if (!live_q[reduce_lane_q + reduce_step_q]) begin
            reduce_lane_q <= reduce_lane_q + (reduce_step_q << 1);
          end else if ((type_q == 4'h8) && (subop_q == 3'd0)) begin
            state_q <= COLL_REDUCE_F32_ISSUE;
          end else begin
            lane_val_q[reduce_lane_q] <= reduce_u32(lane_val_q[reduce_lane_q], lane_val_q[reduce_lane_q + reduce_step_q]);
            reduce_lane_q <= reduce_lane_q + (reduce_step_q << 1);
          end
        end
        COLL_REDUCE_F32_ISSUE: begin
          state_q <= COLL_REDUCE_F32_WAIT;
        end
        COLL_REDUCE_F32_WAIT: begin
          if (fma_result_valid) begin
            lane_val_q[reduce_lane_q] <= fma_result;
            reduce_lane_q <= reduce_lane_q + (reduce_step_q << 1);
            state_q <= COLL_REDUCE_STEP;
          end
        end
        COLL_WRITE: begin
          if (write_beat_q == 2'd3) begin
            state_q <= COLL_DONE;
          end else begin
            write_beat_q <= write_beat_q + 2'd1;
          end
        end
        COLL_DONE: begin
          state_q <= COLL_IDLE;
        end
        default: begin
          state_q <= COLL_IDLE;
        end
      endcase
    end
  end
endmodule

`default_nettype wire
