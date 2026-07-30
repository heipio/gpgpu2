`timescale 1ns/1ps
`default_nettype none

module tb_scoreboard;
  import aec_pkg::*;

  logic clk_i;
  logic rst_ni;
  logic clear;
  logic check_valid;
  logic [0:0] check_warp;
  logic [15:0] check_opcode;
  logic [3:0] check_type_code;
  logic check_imm_en;
  logic [7:0] check_src1_reg;
  logic [7:0] check_src2_reg;
  logic [7:0] check_src3_reg;
  logic [7:0] check_dst_reg;
  logic hazard;
  logic mark_valid;
  logic [0:0] mark_warp;
  logic [7:0] mark_reg;
  logic [3:0] mark_count;
  logic clear_valid;
  logic [0:0] clear_warp;
  logic [7:0] clear_reg;
  logic [3:0] clear_count;

  scoreboard #(
    .NUM_WARPS(2)
  ) dut (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .clear_i(clear),
    .check_valid_i(check_valid),
    .check_warp_i(check_warp),
    .check_opcode_i(check_opcode),
    .check_type_code_i(check_type_code),
    .check_imm_en_i(check_imm_en),
    .check_src1_reg_i(check_src1_reg),
    .check_src2_reg_i(check_src2_reg),
    .check_src3_reg_i(check_src3_reg),
    .check_dst_reg_i(check_dst_reg),
    .hazard_o(hazard),
    .mark_valid_i(mark_valid),
    .mark_warp_i(mark_warp),
    .mark_reg_i(mark_reg),
    .mark_count_i(mark_count),
    .clear_valid_i(clear_valid),
    .clear_warp_i(clear_warp),
    .clear_reg_i(clear_reg),
    .clear_count_i(clear_count)
  );

  initial clk_i = 1'b0;
  always #5 clk_i = ~clk_i;

  initial begin
    rst_ni = 1'b0;
    clear = 1'b0;
    check_valid = 1'b0;
    check_warp = 1'b0;
    check_opcode = AEC_OP_NOP;
    check_type_code = 4'h2;
    check_imm_en = 1'b0;
    check_src1_reg = 8'd0;
    check_src2_reg = 8'd0;
    check_src3_reg = 8'd0;
    check_dst_reg = 8'd0;
    mark_valid = 1'b0;
    mark_warp = 1'b0;
    mark_reg = 8'd0;
    mark_count = 4'd1;
    clear_valid = 1'b0;
    clear_warp = 1'b0;
    clear_reg = 8'd0;
    clear_count = 4'd1;

    repeat (2) @(posedge clk_i);
    rst_ni = 1'b1;
    @(posedge clk_i);

    @(negedge clk_i);
    mark_valid = 1'b1;
    mark_reg = 8'd5;
    @(negedge clk_i);
    mark_valid = 1'b0;

    check_valid = 1'b1;
    check_opcode = AEC_OP_ADD;
    check_imm_en = 1'b0;
    check_src1_reg = 8'd5;
    check_src2_reg = 8'd6;
    check_dst_reg = 8'd7;
    #1;
    assert (hazard) else $fatal(1, "RAW src1 hazard missing");

    check_src1_reg = 8'd6;
    check_dst_reg = 8'd5;
    #1;
    assert (hazard) else $fatal(1, "WAW dst hazard missing");

    @(negedge clk_i);
    clear_valid = 1'b1;
    clear_reg = 8'd5;
    @(negedge clk_i);
    clear_valid = 1'b0;
    #1;
    assert (!hazard) else $fatal(1, "hazard did not clear");

    @(negedge clk_i);
    mark_valid = 1'b1;
    mark_reg = 8'd9;
    @(negedge clk_i);
    mark_valid = 1'b0;
    check_opcode = AEC_OP_ADD;
    check_imm_en = 1'b1;
    check_src1_reg = 8'd1;
    check_src2_reg = 8'd9;
    check_dst_reg = 8'd2;
    #1;
    assert (!hazard) else $fatal(1, "immediate src2 was treated as a register");

    check_imm_en = 1'b0;
    #1;
    assert (hazard) else $fatal(1, "RAW src2 hazard missing");

    @(negedge clk_i);
    clear_valid = 1'b1;
    clear_reg = 8'd9;
    clear_count = 4'd1;
    @(negedge clk_i);
    clear_valid = 1'b0;

    @(negedge clk_i);
    mark_valid = 1'b1;
    mark_reg = 8'd16;
    mark_count = 4'd8;
    @(negedge clk_i);
    mark_valid = 1'b0;

    check_opcode = AEC_OP_ADD;
    check_imm_en = 1'b0;
    check_src1_reg = 8'd20;
    check_src2_reg = 8'd1;
    check_dst_reg = 8'd2;
    #1;
    assert (hazard) else $fatal(1, "range RAW hazard missing");

    @(negedge clk_i);
    clear_valid = 1'b1;
    clear_reg = 8'd16;
    clear_count = 4'd8;
    @(negedge clk_i);
    clear_valid = 1'b0;

    @(negedge clk_i);
    mark_valid = 1'b1;
    mark_reg = 8'd37;
    mark_count = 4'd1;
    @(negedge clk_i);
    mark_valid = 1'b0;

    check_opcode = AEC_OP_MMA;
    check_type_code = 4'hb;
    check_imm_en = 1'b0;
    check_src1_reg = 8'd8;
    check_src2_reg = 8'd10;
    check_src3_reg = 8'd32;
    check_dst_reg = 8'd64;
    #1;
    assert (hazard) else $fatal(1, "MMA C fragment range hazard missing");

    $display("SCOREBOARD TEST PASSED");
    $finish;
  end
endmodule

`default_nettype wire
