`timescale 1ns/1ps
`default_nettype none

module vrf_top (
  input  wire logic        clk_i,
  input  wire logic        rst_ni,

  input  wire logic [1:0]  issue_beat_i,
  input  wire logic [7:0]  src1_reg_i,
  input  wire logic [7:0]  src2_reg_i,
  input  wire logic [7:0]  src3_reg_i,
  output logic [7:0][31:0] src1_data_o,
  output logic [7:0][31:0] src2_data_o,
  output logic [7:0][31:0] src3_data_o,

  input  wire logic        write_valid_i,
  input  wire logic [1:0]  write_beat_i,
  input  wire logic [7:0]  dst_reg_i,
  input  wire logic [7:0][31:0] write_data_i,
  input  wire logic [7:0]  write_mask_i
);
  import aec_pkg::*;

  genvar lane;
  generate
    for (lane = 0; lane < PHYSICAL_SIMD_LANES; lane = lane + 1) begin : g_vrf_lane
      vrf_lane u_vrf_lane (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .read_beat_i(issue_beat_i),
        .read_reg1_i(src1_reg_i),
        .read_reg2_i(src2_reg_i),
        .read_reg3_i(src3_reg_i),
        .read_data1_o(src1_data_o[lane]),
        .read_data2_o(src2_data_o[lane]),
        .read_data3_o(src3_data_o[lane]),
        .write_valid_i(write_valid_i && write_mask_i[lane]),
        .write_beat_i(write_beat_i),
        .write_reg_i(dst_reg_i),
        .write_data_i(write_data_i[lane])
      );
    end
  endgenerate
endmodule

`default_nettype wire

