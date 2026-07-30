`timescale 1ns/1ps
`default_nettype none

module sfu_core #(
  parameter int NUM_WARPS = 4,
  parameter int COMPUTE_LATENCY = 8
) (
  input  wire logic        clk_i,
  input  wire logic        rst_ni,

  input  wire logic        start_i,
  input  wire logic [$clog2(NUM_WARPS)-1:0] warp_i,
  input  wire logic [2:0]  subop_i,
  input  wire logic [1:0]  beat_i,
  input  wire logic [7:0]  active_mask_i,
  input  wire logic [7:0]  dst_reg_i,
  input  wire logic [7:0][31:0] src_data_i,

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
  localparam int LATENCY_BITS = (COMPUTE_LATENCY <= 1) ? 1 : $clog2(COMPUTE_LATENCY + 1);
  localparam logic [LATENCY_BITS-1:0] COMPUTE_LATENCY_CYCLES = COMPUTE_LATENCY;

  typedef enum logic [1:0] {
    SFU_IDLE,
    SFU_WAIT,
    SFU_WRITE
  } sfu_state_e;

  sfu_state_e state_q;
  logic [LATENCY_BITS-1:0] wait_count_q;
  logic [WARP_BITS-1:0] warp_q;
  logic [2:0]  subop_q;
  logic [1:0]  beat_q;
  logic [7:0]  mask_q;
  logic [7:0]  dst_q;
  logic [7:0][31:0] src_q;
  logic [7:0][31:0] result_comb;
  logic [7:0][31:0] result_q;

  genvar lane;
  generate
    for (lane = 0; lane < PHYSICAL_SIMD_LANES; lane = lane + 1) begin : g_sfu_lane
      sfu_lane u_sfu_lane (
        .opcode_i(AEC_OP_SFU),
        .subop_i(subop_q),
        .src_val_i(src_q[lane]),
        .result_o(result_comb[lane])
      );
    end
  endgenerate

  always_comb begin
    busy_o = (state_q != SFU_IDLE);
    write_valid_o = (state_q == SFU_WRITE);
    write_warp_o = warp_q;
    write_beat_o = beat_q;
    write_reg_o = dst_q;
    write_data_o = result_q;
    write_mask_o = write_valid_o ? mask_q : 8'd0;
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= SFU_IDLE;
      wait_count_q <= '0;
      warp_q <= '0;
      subop_q <= 3'd0;
      beat_q <= 2'd0;
      mask_q <= 8'd0;
      dst_q <= 8'd0;
      src_q <= '0;
      result_q <= '0;
    end else begin
      unique case (state_q)
        SFU_IDLE: begin
          if (start_i) begin
            warp_q <= warp_i;
            subop_q <= subop_i;
            beat_q <= beat_i;
            mask_q <= active_mask_i;
            dst_q <= dst_reg_i;
            src_q <= src_data_i;
            wait_count_q <= COMPUTE_LATENCY_CYCLES;
            state_q <= SFU_WAIT;
          end
        end
        SFU_WAIT: begin
          if (wait_count_q <= {{(LATENCY_BITS-1){1'b0}}, 1'b1}) begin
            wait_count_q <= '0;
            result_q <= result_comb;
            state_q <= SFU_WRITE;
          end else begin
            wait_count_q <= wait_count_q - {{(LATENCY_BITS-1){1'b0}}, 1'b1};
          end
        end
        SFU_WRITE: begin
          state_q <= SFU_IDLE;
        end
        default: begin
          state_q <= SFU_IDLE;
        end
      endcase
    end
  end
endmodule

`default_nettype wire
