`timescale 1ns/1ps
`default_nettype none

module tb_sfu_core;
  import aec_pkg::*;

  logic clk_i;
  logic rst_ni;
  logic start_i;
  logic [1:0] warp_i;
  logic [2:0] subop_i;
  logic [1:0] beat_i;
  logic [7:0] active_mask_i;
  logic [7:0] dst_reg_i;
  logic [7:0][31:0] src_data_i;
  logic busy_o;
  logic write_valid_o;
  logic [1:0] write_warp_o;
  logic [1:0] write_beat_o;
  logic [7:0] write_reg_o;
  logic [7:0][31:0] write_data_o;
  logic [7:0] write_mask_o;
  logic [7:0][31:0] reference_data;
  integer cycles;

  sfu_core #(
    .NUM_WARPS(4),
    .COMPUTE_LATENCY(8)
  ) dut (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .start_i(start_i),
    .warp_i(warp_i),
    .subop_i(subop_i),
    .beat_i(beat_i),
    .active_mask_i(active_mask_i),
    .dst_reg_i(dst_reg_i),
    .src_data_i(src_data_i),
    .busy_o(busy_o),
    .write_valid_o(write_valid_o),
    .write_warp_o(write_warp_o),
    .write_beat_o(write_beat_o),
    .write_reg_o(write_reg_o),
    .write_data_o(write_data_o),
    .write_mask_o(write_mask_o)
  );

  genvar lane;
  generate
    for (lane = 0; lane < PHYSICAL_SIMD_LANES; lane = lane + 1) begin : g_reference
      sfu_lane reference_lane (
        .opcode_i(AEC_OP_SFU),
        .subop_i(subop_i),
        .src_val_i(src_data_i[lane]),
        .result_o(reference_data[lane])
      );
    end
  endgenerate

  always #5 clk_i = ~clk_i;

  task automatic run_case(input logic [2:0] subop);
    begin
      subop_i = subop;
      @(negedge clk_i);
      start_i = 1'b1;
      @(negedge clk_i);
      start_i = 1'b0;
      cycles = 0;
      while (!write_valid_o && cycles < 16) begin
        @(posedge clk_i);
        cycles = cycles + 1;
      end
      assert (write_valid_o) else $fatal(1, "SFU result timed out");
      assert (write_warp_o == 2'd2) else $fatal(1, "SFU warp tag mismatch");
      assert (write_beat_o == 2'd3) else $fatal(1, "SFU beat tag mismatch");
      assert (write_reg_o == 8'd19) else $fatal(1, "SFU destination mismatch");
      assert (write_mask_o == 8'hb5) else $fatal(1, "SFU mask mismatch");
      for (int i = 0; i < PHYSICAL_SIMD_LANES; i = i + 1) begin
        assert (write_data_o[i] == reference_data[i])
          else $fatal(1, "SFU lane %0d result mismatch", i);
      end
      @(posedge clk_i);
      assert (!busy_o) else $fatal(1, "SFU did not return to idle");
    end
  endtask

  initial begin
    clk_i = 1'b0;
    rst_ni = 1'b0;
    start_i = 1'b0;
    warp_i = 2'd2;
    subop_i = 3'd0;
    beat_i = 2'd3;
    active_mask_i = 8'hb5;
    dst_reg_i = 8'd19;
    src_data_i[0] = 32'h3f800000;
    src_data_i[1] = 32'h40000000;
    src_data_i[2] = 32'h40400000;
    src_data_i[3] = 32'h40800000;
    src_data_i[4] = 32'hbf800000;
    src_data_i[5] = 32'h00000000;
    src_data_i[6] = 32'h7f800000;
    src_data_i[7] = 32'h7fc00000;

    repeat (3) @(posedge clk_i);
    rst_ni = 1'b1;
    run_case(3'd0);
    run_case(3'd1);
    $display("SFU_CORE TEST PASSED");
    $finish;
  end
endmodule

`default_nettype wire
