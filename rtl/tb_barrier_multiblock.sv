`timescale 1ns/1ps
`default_nettype none

module tb_barrier_multiblock;
  localparam int NUM_WARPS = 4;
  localparam int NUM_BLOCKS = 2;

  logic clk_i;
  logic rst_ni;
  logic clear;
  logic arrive_valid;
  logic [1:0] arrive_warp;
  logic arrive_block;
  logic [2:0] barrier_id;
  logic [15:0] expected_warps;
  logic [3:0] live_warps;
  logic release_valid;
  logic [3:0] release_warps;
  logic deadlock_fault;

  barrier_unit #(
    .NUM_WARPS(NUM_WARPS),
    .NUM_BLOCKS(NUM_BLOCKS),
    .NUM_BARRIERS(8)
  ) dut (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .clear_i(clear),
    .arrive_valid_i(arrive_valid),
    .arrive_warp_i(arrive_warp),
    .arrive_block_i(arrive_block),
    .barrier_id_i(barrier_id),
    .expected_warps_i(expected_warps),
    .live_warps_i(live_warps),
    .release_valid_o(release_valid),
    .release_warps_o(release_warps),
    .deadlock_fault_o(deadlock_fault)
  );

  initial clk_i = 1'b0;
  always #5 clk_i = ~clk_i;

  initial begin
    rst_ni = 1'b0;
    clear = 1'b0;
    arrive_valid = 1'b0;
    arrive_warp = 2'd0;
    arrive_block = 1'b0;
    barrier_id = 3'd1;
    expected_warps = 16'd0;
    live_warps = 4'b1111;

    repeat (3) @(posedge clk_i);
    rst_ni = 1'b1;
    @(negedge clk_i);

    arrive_valid = 1'b1;
    arrive_block = 1'b0;
    arrive_warp = 2'd0;
    @(posedge clk_i);
    #1;
    assert (!release_valid) else $fatal(1, "block0 released after only one warp");

    @(negedge clk_i);
    arrive_block = 1'b1;
    arrive_warp = 2'd2;
    @(posedge clk_i);
    #1;
    assert (!release_valid) else $fatal(1, "block1 was contaminated by block0 arrival");

    @(negedge clk_i);
    arrive_block = 1'b0;
    arrive_warp = 2'd1;
    #1;
    assert (release_valid && (release_warps == 4'b0011))
      else $fatal(1, "block0 release mask mismatch: %04b", release_warps);
    @(posedge clk_i);

    @(negedge clk_i);
    arrive_block = 1'b1;
    arrive_warp = 2'd3;
    #1;
    assert (release_valid && (release_warps == 4'b1100))
      else $fatal(1, "block1 release mask mismatch: %04b", release_warps);
    @(posedge clk_i);

    $display("BARRIER_MULTIBLOCK TEST PASSED");
    $finish;
  end
endmodule

`default_nettype wire
