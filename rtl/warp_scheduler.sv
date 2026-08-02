`timescale 1ns/1ps
`default_nettype none

module warp_scheduler #(
  parameter int NUM_WARPS = 4
) (
  input  wire logic clk_i,
  input  wire logic rst_ni,
  input  wire logic start_i,
  input  wire logic [15:0] start_pc_i,
  input  wire logic [31:0] start_mask_i,

  input  wire logic issue_ready_i,
  input  wire logic branch_valid_i,
  input  wire logic [$clog2(NUM_WARPS)-1:0] branch_warp_i,
  input  wire logic [15:0] branch_pc_i,
  input  wire logic [31:0] branch_mask_i,
  input  wire logic halt_valid_i,
  input  wire logic [$clog2(NUM_WARPS)-1:0] halt_warp_i,
  input  wire logic [31:0] halt_mask_i,
  input  wire logic [NUM_WARPS-1:0] warp_stall_mask_i,

  output logic fetch_valid_o,
  output logic [$clog2(NUM_WARPS)-1:0] fetch_warp_o,
  output logic [15:0] fetch_pc_o,
  output logic [31:0] fetch_active_mask_o,
  output logic [NUM_WARPS-1:0] live_warps_o,
  output logic all_warps_done_o
);
  localparam int WARP_BITS = (NUM_WARPS <= 1) ? 1 : $clog2(NUM_WARPS);

  logic [15:0] pc_q [0:NUM_WARPS-1];
  logic [31:0] active_mask_q [0:NUM_WARPS-1];
  logic valid_q [0:NUM_WARPS-1];
  logic [WARP_BITS-1:0] rr_q;
  logic [WARP_BITS-1:0] selected_warp;
  logic selected_valid;

  always_comb begin
    selected_valid = 1'b0;
    selected_warp = rr_q;
    for (int off = 0; off < NUM_WARPS; off = off + 1) begin
      automatic int idx;
      idx = (rr_q + off) % NUM_WARPS;
      if (!selected_valid && valid_q[idx] && !warp_stall_mask_i[idx] && (active_mask_q[idx] != 32'd0)) begin
        selected_valid = 1'b1;
        selected_warp = idx[WARP_BITS-1:0];
      end
    end

    fetch_valid_o = selected_valid;
    fetch_warp_o = selected_warp;
    fetch_pc_o = pc_q[selected_warp];
    fetch_active_mask_o = active_mask_q[selected_warp];
    all_warps_done_o = 1'b1;
    for (int w = 0; w < NUM_WARPS; w = w + 1) begin
      live_warps_o[w] = valid_q[w] && (active_mask_q[w] != 32'd0);
      if (valid_q[w] && (active_mask_q[w] != 32'd0)) begin
        all_warps_done_o = 1'b0;
      end
    end
  end

  integer init_warp;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rr_q <= '0;
      for (init_warp = 0; init_warp < NUM_WARPS; init_warp = init_warp + 1) begin
        pc_q[init_warp] <= 16'd0;
        active_mask_q[init_warp] <= 32'd0;
        valid_q[init_warp] <= 1'b0;
      end
    end else begin
      if (start_i) begin
        for (init_warp = 0; init_warp < NUM_WARPS; init_warp = init_warp + 1) begin
          pc_q[init_warp] <= start_pc_i;
          active_mask_q[init_warp] <= start_mask_i;
          valid_q[init_warp] <= 1'b1;
        end
        rr_q <= '0;
      end else begin
        if (branch_valid_i) begin
          pc_q[branch_warp_i] <= branch_pc_i;
          active_mask_q[branch_warp_i] <= branch_mask_i;
          valid_q[branch_warp_i] <= (branch_mask_i != 32'd0);
        end
        if (halt_valid_i) begin
          active_mask_q[halt_warp_i] <= active_mask_q[halt_warp_i] & ~halt_mask_i;
          valid_q[halt_warp_i] <= ((active_mask_q[halt_warp_i] & ~halt_mask_i) != 32'd0);
        end
        if (fetch_valid_o && issue_ready_i) begin
          pc_q[selected_warp] <= pc_q[selected_warp] + 16'd1;
          rr_q <= selected_warp + {{(WARP_BITS-1){1'b0}}, 1'b1};
        end
      end
    end
  end
endmodule

`default_nettype wire
