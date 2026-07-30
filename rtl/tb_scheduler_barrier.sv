`timescale 1ns/1ps
`default_nettype none

module tb_scheduler_barrier;
  localparam int NUM_WARPS = 4;

  logic clk_i;
  logic rst_ni;
  logic start;
  logic issue_ready;
  logic branch_valid;
  logic [1:0] branch_warp;
  logic [15:0] branch_pc;
  logic [31:0] branch_mask;
  logic halt_valid;
  logic [1:0] halt_warp;
  logic [31:0] halt_mask;
  logic fetch_valid;
  logic [1:0] fetch_warp;
  logic [15:0] fetch_pc;
  logic [31:0] fetch_mask;
  logic all_done;

  logic clear_bar;
  logic arrive_valid;
  logic [1:0] arrive_warp;
  logic [2:0] barrier_id;
  logic [0:0] arrive_block;
  logic [15:0] expected_warps;
  logic [3:0] live_warps;
  logic release_valid;
  logic [3:0] release_warps;
  logic deadlock_fault;

  warp_scheduler #(
    .NUM_WARPS(NUM_WARPS)
  ) u_sched (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .start_i(start),
    .start_pc_i(16'd7),
    .start_mask_i(32'hffff_ffff),
    .issue_ready_i(issue_ready),
    .branch_valid_i(branch_valid),
    .branch_warp_i(branch_warp),
    .branch_pc_i(branch_pc),
    .branch_mask_i(branch_mask),
    .halt_valid_i(halt_valid),
    .halt_warp_i(halt_warp),
    .halt_mask_i(halt_mask),
    .warp_stall_mask_i('0),
    .fetch_valid_o(fetch_valid),
    .fetch_warp_o(fetch_warp),
    .fetch_pc_o(fetch_pc),
    .fetch_active_mask_o(fetch_mask),
    .live_warps_o(),
    .all_warps_done_o(all_done)
  );

  barrier_unit #(
    .NUM_WARPS(NUM_WARPS),
    .NUM_BLOCKS(1),
    .NUM_BARRIERS(8)
  ) u_bar (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .clear_i(clear_bar),
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

  task automatic sched_tick;
    begin
      issue_ready = 1'b1;
      @(posedge clk_i);
      issue_ready = 1'b0;
      @(posedge clk_i);
    end
  endtask

  initial begin
    rst_ni = 1'b0;
    start = 1'b0;
    issue_ready = 1'b0;
    branch_valid = 1'b0;
    branch_warp = 2'd0;
    branch_pc = 16'd0;
    branch_mask = 32'd0;
    halt_valid = 1'b0;
    halt_warp = 2'd0;
    halt_mask = 32'd0;
    clear_bar = 1'b0;
    arrive_valid = 1'b0;
    arrive_warp = 2'd0;
    arrive_block = 1'b0;
    barrier_id = 3'd2;
    expected_warps = 16'd0;
    live_warps = 4'b0101;

    repeat (4) @(posedge clk_i);
    rst_ni = 1'b1;
    start = 1'b1;
    @(posedge clk_i);
    start = 1'b0;
    @(posedge clk_i);

    assert (fetch_valid && fetch_warp == 2'd0 && fetch_pc == 16'd7)
      else $fatal(1, "initial scheduler output mismatch");
    sched_tick();
    assert (fetch_valid && fetch_warp == 2'd1 && fetch_pc == 16'd7)
      else $fatal(1, "scheduler did not advance to warp1");

    branch_valid = 1'b1;
    branch_warp = 2'd1;
    branch_pc = 16'd23;
    branch_mask = 32'h0000_00ff;
    @(posedge clk_i);
    branch_valid = 1'b0;
    for (int hw = 0; hw < NUM_WARPS; hw = hw + 1) begin
      if (hw != 1) begin
        halt_valid = 1'b1;
        halt_warp = 2'(hw);
        halt_mask = 32'hffff_ffff;
        @(posedge clk_i);
        halt_valid = 1'b0;
        @(posedge clk_i);
      end
    end
    assert (fetch_valid && fetch_warp == 2'd1 && fetch_pc == 16'd23 && fetch_mask == 32'h0000_00ff)
      else $fatal(1, "branch-updated warp state not observed");

    arrive_valid = 1'b1;
    arrive_warp = 2'd0;
    @(posedge clk_i);
    assert (!release_valid) else $fatal(1, "barrier released too early");
    arrive_warp = 2'd2;
    @(posedge clk_i);
    assert (release_valid && release_warps == 4'b0101)
      else $fatal(1, "dynamic barrier release mismatch: valid=%0b mask=%04b", release_valid, release_warps);
    arrive_valid = 1'b0;

    expected_warps = 16'd5;
    arrive_valid = 1'b1;
    arrive_warp = 2'd1;
    @(posedge clk_i);
    assert (deadlock_fault) else $fatal(1, "barrier deadlock fault missing");

    $display("SCHEDULER_BARRIER TEST PASSED");
    $finish;
  end
endmodule

`default_nettype wire
