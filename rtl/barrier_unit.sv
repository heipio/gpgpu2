`timescale 1ns/1ps
`default_nettype none

module barrier_unit #(
  parameter int NUM_WARPS = 4,
  parameter int NUM_BLOCKS = 1,
  parameter int NUM_BARRIERS = 8
) (
  input  wire logic clk_i,
  input  wire logic rst_ni,
  input  wire logic clear_i,

  input  wire logic arrive_valid_i,
  input  wire logic [$clog2(NUM_WARPS)-1:0] arrive_warp_i,
  input  wire logic [((NUM_BLOCKS <= 1) ? 1 : $clog2(NUM_BLOCKS))-1:0] arrive_block_i,
  input  wire logic [2:0] barrier_id_i,
  input  wire logic [15:0] expected_warps_i,
  input  wire logic [NUM_WARPS-1:0] live_warps_i,

  output logic release_valid_o,
  output logic [NUM_WARPS-1:0] release_warps_o,
  output logic deadlock_fault_o
);
  localparam int COUNT_BITS = (NUM_WARPS <= 1) ? 1 : $clog2(NUM_WARPS + 1);
  localparam int BLOCK_BITS = (NUM_BLOCKS <= 1) ? 1 : $clog2(NUM_BLOCKS);
  localparam int WARPS_PER_BLOCK = (NUM_BLOCKS <= 1) ? NUM_WARPS : ((NUM_WARPS + NUM_BLOCKS - 1) / NUM_BLOCKS);

  logic [NUM_WARPS-1:0] arrived_q [0:NUM_BLOCKS-1][0:NUM_BARRIERS-1];
  logic [NUM_WARPS-1:0] block_live_mask;
  logic [COUNT_BITS-1:0] expected_count;
  logic [COUNT_BITS-1:0] arrived_count;
  logic [NUM_WARPS-1:0] current_arrived;

  function automatic logic [BLOCK_BITS-1:0] warp_to_block(input int warp_idx);
    begin
      if (NUM_BLOCKS <= 1) begin
        warp_to_block = '0;
      end else begin
        warp_to_block = (warp_idx / WARPS_PER_BLOCK);
      end
    end
  endfunction

  function automatic logic [COUNT_BITS-1:0] popcount(input logic [NUM_WARPS-1:0] value);
    logic [COUNT_BITS-1:0] count;
    begin
      count = '0;
      for (int i = 0; i < NUM_WARPS; i = i + 1) begin
        count = count + {{(COUNT_BITS-1){1'b0}}, value[i]};
      end
      popcount = count;
    end
  endfunction

  always_comb begin
    block_live_mask = '0;
    for (int live_warp = 0; live_warp < NUM_WARPS; live_warp = live_warp + 1) begin
      if (warp_to_block(live_warp) == arrive_block_i) begin
        block_live_mask[live_warp] = live_warps_i[live_warp];
      end
    end
    current_arrived = arrived_q[arrive_block_i][barrier_id_i] |
        (arrive_valid_i ? ({{(NUM_WARPS-1){1'b0}}, 1'b1} << arrive_warp_i) : '0);
    expected_count = (expected_warps_i == 16'd0) ? popcount(block_live_mask) : expected_warps_i[COUNT_BITS-1:0];
    arrived_count = popcount(current_arrived & block_live_mask);
    release_valid_o = arrive_valid_i && (expected_count != '0) && (arrived_count >= expected_count);
    release_warps_o = release_valid_o ? (current_arrived & block_live_mask) : '0;
    deadlock_fault_o = arrive_valid_i && (expected_count > popcount(block_live_mask));
  end

  integer barrier_idx;
  integer block_idx;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      for (block_idx = 0; block_idx < NUM_BLOCKS; block_idx = block_idx + 1) begin
        for (barrier_idx = 0; barrier_idx < NUM_BARRIERS; barrier_idx = barrier_idx + 1) begin
          arrived_q[block_idx][barrier_idx] <= '0;
        end
      end
    end else if (clear_i) begin
      for (block_idx = 0; block_idx < NUM_BLOCKS; block_idx = block_idx + 1) begin
        for (barrier_idx = 0; barrier_idx < NUM_BARRIERS; barrier_idx = barrier_idx + 1) begin
          arrived_q[block_idx][barrier_idx] <= '0;
        end
      end
    end else if (arrive_valid_i) begin
      if (release_valid_o) begin
        arrived_q[arrive_block_i][barrier_id_i] <= '0;
      end else begin
        arrived_q[arrive_block_i][barrier_id_i][arrive_warp_i] <= 1'b1;
      end
    end
  end
endmodule

`default_nettype wire
