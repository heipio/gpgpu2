`timescale 1ns/1ps
`default_nettype none

module tb_warp_state;
  import aec_pkg::*;

  localparam int NUM_WARPS = 2;

  logic clk_i;
  logic rst_ni;
  logic warp_sel;
  logic write_valid;
  logic [7:0][31:0] write_data;
  logic [7:0] write_mask;
  logic [7:0] pred_write_data;
  logic [7:0][31:0] src1_data;
  logic [7:0][31:0] src2_data;
  logic [7:0][31:0] src3_data;
  logic [7:0] pred_read;

  vrf_top #(
    .NUM_WARPS(NUM_WARPS)
  ) u_vrf (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .issue_warp_i(warp_sel),
    .issue_beat_i(2'd0),
    .src1_reg_i(8'd5),
    .src2_reg_i(8'd5),
    .src3_reg_i(8'd5),
    .src1_data_o(src1_data),
    .src2_data_o(src2_data),
    .src3_data_o(src3_data),
    .mma_read_enable_i(1'b0),
    .mma_read_warp_i(1'b0),
    .mma_read_beat_i(2'd0),
    .mma_read_reg1_i(8'd0),
    .mma_read_reg2_i(8'd0),
    .mma_read_reg3_i(8'd0),
    .write_valid_i(write_valid),
    .write_warp_i(warp_sel),
    .write_beat_i(2'd0),
    .dst_reg_i(8'd5),
    .write_data_i(write_data),
    .write_mask_i(write_mask),
    .mma_write_valid_i(1'b0),
    .mma_write_warp_i(1'b0),
    .mma_write_beat_i(2'd0),
    .mma_write_reg_i(8'd0),
    .mma_write_data_i('0),
    .mma_write_mask_i(8'd0)
  );

  prf_top #(
    .NUM_WARPS(NUM_WARPS)
  ) u_prf (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .read_warp_i(warp_sel),
    .read_beat_i(2'd0),
    .read_pred1_i(4'd2),
    .read_pred2_i(4'hf),
    .read_pred3_i(4'hf),
    .read_mask1_o(pred_read),
    .read_mask2_o(),
    .read_mask3_o(),
    .write_valid_i(write_valid),
    .write_warp_i(warp_sel),
    .write_beat_i(2'd0),
    .write_pred_i(3'd2),
    .write_data_i(pred_write_data),
    .write_mask_i(8'hff)
  );

  initial clk_i = 1'b0;
  always #5 clk_i = ~clk_i;

  task automatic write_warp(
    input logic warp,
    input logic [31:0] value,
    input logic [7:0] pred_value
  );
    begin
      warp_sel = warp;
      for (int lane = 0; lane < PHYSICAL_SIMD_LANES; lane = lane + 1) begin
        write_data[lane] = value + 32'(lane);
      end
      write_mask = 8'hff;
      pred_write_data = pred_value;
      write_valid = 1'b1;
      @(posedge clk_i);
      write_valid = 1'b0;
      @(posedge clk_i);
    end
  endtask

  initial begin
    rst_ni = 1'b0;
    warp_sel = 1'b0;
    write_valid = 1'b0;
    write_mask = 8'd0;
    pred_write_data = 8'd0;
    write_data = '0;
    repeat (4) @(posedge clk_i);
    rst_ni = 1'b1;
    @(posedge clk_i);

    write_warp(1'b0, 32'h1000_0000, 8'haa);
    write_warp(1'b1, 32'h2000_0000, 8'h55);

    warp_sel = 1'b0;
    repeat (2) @(posedge clk_i);
    assert (src1_data[0] == 32'h1000_0000) else $fatal(1, "warp0 VRF polluted: %08x", src1_data[0]);
    assert (pred_read == 8'haa) else $fatal(1, "warp0 PRF polluted: %02x", pred_read);

    warp_sel = 1'b1;
    repeat (2) @(posedge clk_i);
    assert (src1_data[0] == 32'h2000_0000) else $fatal(1, "warp1 VRF polluted: %08x", src1_data[0]);
    assert (pred_read == 8'h55) else $fatal(1, "warp1 PRF polluted: %02x", pred_read);

    $display("WARP_STATE TEST PASSED");
    $finish;
  end
endmodule

`default_nettype wire
