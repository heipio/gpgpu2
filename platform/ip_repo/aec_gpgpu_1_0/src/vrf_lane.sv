`timescale 1ns/1ps
`default_nettype none

module vrf_lane #(
  parameter int NUM_WARPS = 4
) (
  input  wire logic       clk_i,
  input  wire logic       rst_ni,

  input  wire logic [$clog2(NUM_WARPS)-1:0] read_warp_i,
  input  wire logic [1:0] read_beat_i,
  input  wire logic [7:0] read_reg1_i,
  input  wire logic [7:0] read_reg2_i,
  input  wire logic [7:0] read_reg3_i,
  output logic [31:0] read_data1_o,
  output logic [31:0] read_data2_o,
  output logic [31:0] read_data3_o,

  input  wire logic       write_valid_i,
  input  wire logic [$clog2(NUM_WARPS)-1:0] write_warp_i,
  input  wire logic [1:0] write_beat_i,
  input  wire logic [7:0] write_reg_i,
  input  wire logic [31:0] write_data_i
);
  import aec_pkg::*;

  localparam int WARP_BITS = (NUM_WARPS <= 1) ? 1 : $clog2(NUM_WARPS);
  localparam int VRF_DEPTH = 1024 * NUM_WARPS;
  localparam int VRF_ADDR_BITS = 10 + WARP_BITS;

  logic [VRF_ADDR_BITS-1:0] read_addr1;
  logic [VRF_ADDR_BITS-1:0] read_addr2;
  logic [VRF_ADDR_BITS-1:0] read_addr3;
  logic [VRF_ADDR_BITS-1:0] write_addr;

  (* ram_style = "block" *) logic [31:0] bank_r1 [0:VRF_DEPTH-1];
  (* ram_style = "block" *) logic [31:0] bank_r2 [0:VRF_DEPTH-1];
  (* ram_style = "block" *) logic [31:0] bank_r3 [0:VRF_DEPTH-1];

  integer init_idx;
  initial begin
    for (init_idx = 0; init_idx < VRF_DEPTH; init_idx = init_idx + 1) begin
      bank_r1[init_idx] = 32'd0;
      bank_r2[init_idx] = 32'd0;
      bank_r3[init_idx] = 32'd0;
    end
  end

  assign read_addr1 = {read_warp_i[WARP_BITS-1:0], read_reg1_i, read_beat_i};
  assign read_addr2 = {read_warp_i[WARP_BITS-1:0], read_reg2_i, read_beat_i};
  assign read_addr3 = {read_warp_i[WARP_BITS-1:0], read_reg3_i, read_beat_i};
  assign write_addr = {write_warp_i[WARP_BITS-1:0], write_reg_i, write_beat_i};

  always_ff @(posedge clk_i) begin
    if (write_valid_i) begin
      bank_r1[write_addr] <= write_data_i;
      bank_r2[write_addr] <= write_data_i;
      bank_r3[write_addr] <= write_data_i;
    end

    read_data1_o <= bank_r1[read_addr1];
    read_data2_o <= bank_r2[read_addr2];
    read_data3_o <= bank_r3[read_addr3];
  end
endmodule

`default_nettype wire

