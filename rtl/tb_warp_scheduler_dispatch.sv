`timescale 1ns/1ps
`default_nettype none

module tb_warp_scheduler_dispatch;
  logic clk_i;
  logic rst_ni;
  logic start_i;
  logic [15:0] start_pc_i;
  logic [31:0] start_mask_i;
  logic [31:0] start_grid_x_i;
  logic [31:0] start_block_x_i;
  logic fetch_accept_i;
  logic branch_valid_i;
  logic branch_warp_i;
  logic [15:0] branch_pc_i;
  logic [31:0] branch_mask_i;
  logic halt_valid_i;
  logic halt_warp_i;
  logic [31:0] halt_mask_i;
  logic halt_pending_i;
  logic halt_pending_warp_i;
  logic [1:0] warp_stall_mask_i;
  logic epoch_query_warp_i;
  logic fetch_valid_o;
  logic fetch_warp_o;
  logic [15:0] fetch_pc_o;
  logic [31:0] fetch_active_mask_o;
  logic [31:0] fetch_ctaid_x_o;
  logic [31:0] fetch_warpid_o;
  logic [7:0] fetch_epoch_o;
  logic [7:0] epoch_query_o;
  logic [1:0] live_warps_o;
  logic all_warps_done_o;

  warp_scheduler #(.NUM_WARPS(2)) dut (.*);

  initial clk_i = 1'b0;
  always #5 clk_i = ~clk_i;

  task automatic halt_slot(input logic slot);
    begin
      @(negedge clk_i);
      halt_warp_i = slot;
      halt_mask_i = 32'hffff_ffff;
      halt_valid_i = 1'b1;
      @(negedge clk_i);
      halt_valid_i = 1'b0;
    end
  endtask

  initial begin
    rst_ni = 1'b0;
    start_i = 1'b0;
    start_pc_i = 16'h20;
    start_mask_i = 32'hffff_ffff;
    start_grid_x_i = 32'd2;
    start_block_x_i = 32'd64;
    fetch_accept_i = 1'b0;
    branch_valid_i = 1'b0;
    branch_warp_i = 1'b0;
    branch_pc_i = 16'd0;
    branch_mask_i = 32'd0;
    halt_valid_i = 1'b0;
    halt_warp_i = 1'b0;
    halt_mask_i = 32'd0;
    halt_pending_i = 1'b0;
    halt_pending_warp_i = 1'b0;
    warp_stall_mask_i = 2'b00;
    epoch_query_warp_i = 1'b0;

    repeat (2) @(posedge clk_i);
    rst_ni = 1'b1;
    @(negedge clk_i);
    start_i = 1'b1;
    @(negedge clk_i);
    start_i = 1'b0;
    // Launch descriptors are intentionally expanded into resident slots over
    // successive cycles to keep START off the scheduler critical path.
    repeat (3) @(posedge clk_i);

    assert (dut.ctaid_x_q[0] == 0 && dut.warpid_q[0] == 0) else $fatal(1, "slot0 launch tag");
    assert (dut.ctaid_x_q[1] == 0 && dut.warpid_q[1] == 1) else $fatal(1, "slot1 launch tag");
    assert (dut.active_mask_q[0] == 32'hffff_ffff && dut.active_mask_q[1] == 32'hffff_ffff)
      else $fatal(1, "block.x=64 masks");

    @(negedge clk_i);
    branch_warp_i = 1'b0;
    branch_pc_i = 16'h44;
    branch_mask_i = 32'hffff_ffff;
    branch_valid_i = 1'b1;
    @(negedge clk_i);
    branch_valid_i = 1'b0;
    assert (dut.fetch_epoch_q[0] == 8'd1) else $fatal(1, "redirect did not epoch warp0");
    assert (dut.fetch_epoch_q[1] == 8'd0) else $fatal(1, "redirect leaked into warp1");

    halt_slot(1'b0);
    assert (dut.ctaid_x_q[0] == 32'd1 && dut.warpid_q[0] == 32'd0)
      else $fatal(1, "slot0 did not receive block1 warp0");
    halt_slot(1'b1);
    assert (dut.ctaid_x_q[1] == 32'd1 && dut.warpid_q[1] == 32'd1)
      else $fatal(1, "slot1 did not receive block1 warp1");
    halt_slot(1'b0);
    halt_slot(1'b1);
    assert (all_warps_done_o) else $fatal(1, "all work items did not retire");
    $display("WARP_SCHEDULER_DISPATCH TEST PASSED");
    $finish;
  end
endmodule

`default_nettype wire
