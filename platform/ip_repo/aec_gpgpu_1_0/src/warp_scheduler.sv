`timescale 1ns/1ps
`default_nettype none

// Resident warp scheduler and launch work distributor.  Work descriptors are
// stored per slot so the fetch critical path contains no divide/modulo logic.
module warp_scheduler #(
  parameter int NUM_WARPS = 4
) (
  input  wire logic clk_i,
  input  wire logic rst_ni,
  input  wire logic start_i,
  input  wire logic [15:0] start_pc_i,
  input  wire logic [31:0] start_mask_i,
  input  wire logic [31:0] start_grid_x_i,
  input  wire logic [31:0] start_block_x_i,

  input  wire logic fetch_accept_i,
  input  wire logic branch_valid_i,
  input  wire logic [$clog2(NUM_WARPS)-1:0] branch_warp_i,
  input  wire logic [15:0] branch_pc_i,
  input  wire logic [31:0] branch_mask_i,
  input  wire logic halt_valid_i,
  input  wire logic [$clog2(NUM_WARPS)-1:0] halt_warp_i,
  input  wire logic [31:0] halt_mask_i,
  input  wire logic halt_pending_i,
  input  wire logic [$clog2(NUM_WARPS)-1:0] halt_pending_warp_i,
  input  wire logic [NUM_WARPS-1:0] warp_stall_mask_i,
  input  wire logic [$clog2(NUM_WARPS)-1:0] epoch_query_warp_i,

  output logic fetch_valid_o,
  output logic [$clog2(NUM_WARPS)-1:0] fetch_warp_o,
  output logic [15:0] fetch_pc_o,
  output logic [31:0] fetch_active_mask_o,
  output logic [31:0] fetch_ctaid_x_o,
  output logic [31:0] fetch_warpid_o,
  output logic [7:0] fetch_epoch_o,
  output logic [7:0] epoch_query_o,
  output logic [NUM_WARPS-1:0] live_warps_o,
  output logic all_warps_done_o
);
  localparam int WARP_BITS = (NUM_WARPS <= 1) ? 1 : $clog2(NUM_WARPS);

  logic [15:0] pc_q [0:NUM_WARPS-1];
  logic [31:0] active_mask_q [0:NUM_WARPS-1];
  logic [31:0] ctaid_x_q [0:NUM_WARPS-1];
  logic [31:0] warpid_q [0:NUM_WARPS-1];
  logic valid_q [0:NUM_WARPS-1];
  logic halt_hold_q [0:NUM_WARPS-1];
  logic [7:0] fetch_epoch_q [0:NUM_WARPS-1];
  logic [WARP_BITS-1:0] rr_q;
  logic [WARP_BITS-1:0] selected_warp;
  logic selected_valid;

  logic [15:0] start_pc_q;
  logic [31:0] start_mask_q;
  logic [31:0] grid_x_q;
  logic [31:0] block_x_q;
  logic [31:0] warps_per_block_q;
  logic [31:0] next_ctaid_x_q;
  logic [31:0] next_warpid_q;
  logic [WARP_BITS:0] fill_slot_q;
  logic launch_setup_q;

  function automatic logic [31:0] mask_for_warp(input logic [31:0] warp_id);
    logic [31:0] lane_base;
    logic [31:0] lanes_left;
    begin
      lane_base = warp_id << 5;
      if (lane_base >= block_x_q) begin
        mask_for_warp = 32'd0;
      end else begin
        lanes_left = block_x_q - lane_base;
        if (lanes_left >= 32) begin
          mask_for_warp = 32'hffff_ffff;
        end else begin
          mask_for_warp = (32'h1 << lanes_left) - 32'h1;
        end
      end
    end
  endfunction

  function automatic logic [31:0] initial_mask_for_warp(input logic [31:0] warp_id);
    logic [31:0] natural_mask;
    begin
      natural_mask = mask_for_warp(warp_id);
      initial_mask_for_warp = (natural_mask == 32'hffff_ffff) ? start_mask_q : natural_mask;
    end
  endfunction

  task automatic advance_dispatch_cursor;
    begin
      if (next_warpid_q + 32'd1 >= warps_per_block_q) begin
        next_warpid_q <= 32'd0;
        next_ctaid_x_q <= next_ctaid_x_q + 32'd1;
      end else begin
        next_warpid_q <= next_warpid_q + 32'd1;
      end
    end
  endtask

  always_comb begin
    selected_valid = 1'b0;
    selected_warp = rr_q;
    for (int off = 0; off < NUM_WARPS; off = off + 1) begin
      automatic int idx;
      idx = (rr_q + off) % NUM_WARPS;
      if (!selected_valid && valid_q[idx] && !halt_hold_q[idx] && !warp_stall_mask_i[idx] &&
          (active_mask_q[idx] != 32'd0)) begin
        selected_valid = 1'b1;
        selected_warp = idx[WARP_BITS-1:0];
      end
    end

    fetch_valid_o = selected_valid;
    fetch_warp_o = selected_warp;
    fetch_pc_o = pc_q[selected_warp];
    fetch_active_mask_o = active_mask_q[selected_warp];
    fetch_ctaid_x_o = ctaid_x_q[selected_warp];
    fetch_warpid_o = warpid_q[selected_warp];
    fetch_epoch_o = fetch_epoch_q[selected_warp];
    epoch_query_o = fetch_epoch_q[epoch_query_warp_i];
    all_warps_done_o = !launch_setup_q;
    for (int w = 0; w < NUM_WARPS; w = w + 1) begin
      live_warps_o[w] = valid_q[w] && (active_mask_q[w] != 32'd0);
      if (live_warps_o[w]) begin
        all_warps_done_o = 1'b0;
      end
    end
  end

  integer init_warp;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rr_q <= '0;
      start_pc_q <= 16'd0;
      start_mask_q <= 32'hffff_ffff;
      grid_x_q <= 32'd1;
      block_x_q <= 32'd32;
      warps_per_block_q <= 32'd1;
      next_ctaid_x_q <= 32'd0;
      next_warpid_q <= 32'd0;
      fill_slot_q <= '0;
      launch_setup_q <= 1'b0;
      for (init_warp = 0; init_warp < NUM_WARPS; init_warp = init_warp + 1) begin
        pc_q[init_warp] <= 16'd0;
        active_mask_q[init_warp] <= 32'd0;
        ctaid_x_q[init_warp] <= 32'd0;
        warpid_q[init_warp] <= 32'd0;
        valid_q[init_warp] <= 1'b0;
        halt_hold_q[init_warp] <= 1'b0;
        fetch_epoch_q[init_warp] <= 8'd0;
      end
    end else if (start_i) begin
      start_pc_q <= start_pc_i;
      start_mask_q <= start_mask_i;
      grid_x_q <= (start_grid_x_i == 0) ? 32'd1 : start_grid_x_i;
      block_x_q <= (start_block_x_i == 0) ? 32'd32 : start_block_x_i;
      warps_per_block_q <= (((start_block_x_i == 0) ? 32'd32 : start_block_x_i) + 32'd31) >> 5;
      next_ctaid_x_q <= 32'd0;
      next_warpid_q <= 32'd0;
      fill_slot_q <= '0;
      launch_setup_q <= 1'b1;
      for (init_warp = 0; init_warp < NUM_WARPS; init_warp = init_warp + 1) begin
        pc_q[init_warp] <= start_pc_i;
        ctaid_x_q[init_warp] <= 32'd0;
        warpid_q[init_warp] <= 32'd0;
        active_mask_q[init_warp] <= 32'd0;
        valid_q[init_warp] <= 1'b0;
        halt_hold_q[init_warp] <= 1'b0;
        fetch_epoch_q[init_warp] <= 8'd0;
      end
      rr_q <= '0;
    end else begin
      // Populate resident slots over separate cycles.  This deliberately keeps
      // launch arithmetic out of the START-to-warp-state timing path.
      if (launch_setup_q) begin
        if ((fill_slot_q < NUM_WARPS) && (next_ctaid_x_q < grid_x_q)) begin
          pc_q[fill_slot_q] <= start_pc_q;
          ctaid_x_q[fill_slot_q] <= next_ctaid_x_q;
          warpid_q[fill_slot_q] <= next_warpid_q;
          active_mask_q[fill_slot_q] <= initial_mask_for_warp(next_warpid_q);
          valid_q[fill_slot_q] <= initial_mask_for_warp(next_warpid_q) != 32'd0;
          halt_hold_q[fill_slot_q] <= 1'b0;
          fetch_epoch_q[fill_slot_q] <= 8'd0;
          fill_slot_q <= fill_slot_q + 1'b1;
          advance_dispatch_cursor();
        end else begin
          launch_setup_q <= 1'b0;
        end
      end
      if (branch_valid_i) begin
        pc_q[branch_warp_i] <= branch_pc_i;
        active_mask_q[branch_warp_i] <= branch_mask_i;
        valid_q[branch_warp_i] <= (branch_mask_i != 32'd0);
        fetch_epoch_q[branch_warp_i] <= fetch_epoch_q[branch_warp_i] + 8'd1;
      end
      if (halt_pending_i) begin
        halt_hold_q[halt_pending_warp_i] <= 1'b1;
        fetch_epoch_q[halt_pending_warp_i] <= fetch_epoch_q[halt_pending_warp_i] + 8'd1;
      end
      if (halt_valid_i) begin
        if (!launch_setup_q && (active_mask_q[halt_warp_i] & ~halt_mask_i) == 32'd0 &&
            next_ctaid_x_q < grid_x_q) begin
          pc_q[halt_warp_i] <= start_pc_q;
          ctaid_x_q[halt_warp_i] <= next_ctaid_x_q;
          warpid_q[halt_warp_i] <= next_warpid_q;
          active_mask_q[halt_warp_i] <= initial_mask_for_warp(next_warpid_q);
          valid_q[halt_warp_i] <= (initial_mask_for_warp(next_warpid_q) != 32'd0);
          halt_hold_q[halt_warp_i] <= 1'b0;
          advance_dispatch_cursor();
        end else begin
          active_mask_q[halt_warp_i] <= active_mask_q[halt_warp_i] & ~halt_mask_i;
          valid_q[halt_warp_i] <= ((active_mask_q[halt_warp_i] & ~halt_mask_i) != 32'd0);
          halt_hold_q[halt_warp_i] <= 1'b0;
        end
      end
      if (fetch_valid_o && fetch_accept_i) begin
        pc_q[selected_warp] <= pc_q[selected_warp] + 16'd1;
        rr_q <= selected_warp + {{(WARP_BITS-1){1'b0}}, 1'b1};
      end
    end
  end
endmodule

`default_nettype wire
