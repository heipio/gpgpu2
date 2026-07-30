`timescale 1ns/1ps
`default_nettype none

module vrf_top #(
  parameter int NUM_WARPS = 4
) (
  input  wire logic        clk_i,
  input  wire logic        rst_ni,

  input  wire logic [$clog2(NUM_WARPS)-1:0] issue_warp_i,
  input  wire logic [1:0]  issue_beat_i,
  input  wire logic [7:0]  src1_reg_i,
  input  wire logic [7:0]  src2_reg_i,
  input  wire logic [7:0]  src3_reg_i,
  output logic [7:0][31:0] src1_data_o,
  output logic [7:0][31:0] src2_data_o,
  output logic [7:0][31:0] src3_data_o,

  input  wire logic        mma_read_enable_i,
  input  wire logic [$clog2(NUM_WARPS)-1:0] mma_read_warp_i,
  input  wire logic [1:0]  mma_read_beat_i,
  input  wire logic [7:0]  mma_read_reg1_i,
  input  wire logic [7:0]  mma_read_reg2_i,
  input  wire logic [7:0]  mma_read_reg3_i,

  input  wire logic        write_valid_i,
  input  wire logic [$clog2(NUM_WARPS)-1:0] write_warp_i,
  input  wire logic [1:0]  write_beat_i,
  input  wire logic [7:0]  dst_reg_i,
  input  wire logic [7:0][31:0] write_data_i,
  input  wire logic [7:0]  write_mask_i,

  input  wire logic        mma_write_valid_i,
  input  wire logic [$clog2(NUM_WARPS)-1:0] mma_write_warp_i,
  input  wire logic [1:0]  mma_write_beat_i,
  input  wire logic [7:0]  mma_write_reg_i,
  input  wire logic [7:0][31:0] mma_write_data_i,
  input  wire logic [7:0]  mma_write_mask_i
);
  import aec_pkg::*;

  localparam int WARP_BITS = (NUM_WARPS <= 1) ? 1 : $clog2(NUM_WARPS);

  logic [WARP_BITS-1:0] read_warp;
  logic [1:0] read_beat;
  logic [7:0] read_reg1;
  logic [7:0] read_reg2;
  logic [7:0] read_reg3;
  logic       write_valid;
  logic [WARP_BITS-1:0] write_warp;
  logic [1:0] write_beat;
  logic [7:0] write_reg;
  logic [7:0][31:0] write_data;
  logic [7:0] write_mask;

  always_comb begin
    read_warp = mma_read_enable_i ? mma_read_warp_i : issue_warp_i;
    read_beat = mma_read_enable_i ? mma_read_beat_i : issue_beat_i;
    read_reg1 = mma_read_enable_i ? mma_read_reg1_i : src1_reg_i;
    read_reg2 = mma_read_enable_i ? mma_read_reg2_i : src2_reg_i;
    read_reg3 = mma_read_enable_i ? mma_read_reg3_i : src3_reg_i;

    write_valid = mma_write_valid_i ? 1'b1 : write_valid_i;
    write_warp  = mma_write_valid_i ? mma_write_warp_i : write_warp_i;
    write_beat  = mma_write_valid_i ? mma_write_beat_i : write_beat_i;
    write_reg   = mma_write_valid_i ? mma_write_reg_i : dst_reg_i;
    write_data  = mma_write_valid_i ? mma_write_data_i : write_data_i;
    write_mask  = mma_write_valid_i ? mma_write_mask_i : write_mask_i;
  end

  genvar lane;
  generate
    for (lane = 0; lane < PHYSICAL_SIMD_LANES; lane = lane + 1) begin : g_vrf_lane
      vrf_lane #(
        .NUM_WARPS(NUM_WARPS)
      ) u_vrf_lane (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .read_warp_i(read_warp),
        .read_beat_i(read_beat),
        .read_reg1_i(read_reg1),
        .read_reg2_i(read_reg2),
        .read_reg3_i(read_reg3),
        .read_data1_o(src1_data_o[lane]),
        .read_data2_o(src2_data_o[lane]),
        .read_data3_o(src3_data_o[lane]),
        .write_valid_i(write_valid && write_mask[lane]),
        .write_warp_i(write_warp),
        .write_beat_i(write_beat),
        .write_reg_i(write_reg),
        .write_data_i(write_data[lane])
      );
    end
  endgenerate
endmodule

`default_nettype wire

