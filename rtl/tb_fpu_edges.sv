`timescale 1ns/1ps
`default_nettype none

module tb_fpu_edges;
  import aec_pkg::*;

  logic clk_i;
  logic rst_ni;
  logic start;
  logic [15:0] opcode;
  logic busy;
  logic write_valid;
  logic [1:0] write_beat;
  logic [7:0] write_reg;
  logic [7:0][31:0] src1;
  logic [7:0][31:0] src2;
  logic [7:0][31:0] src3;
  logic [7:0][31:0] write_data;
  logic [7:0] write_mask;

  fpu_core u_fpu (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .start_i(start),
    .warp_i(2'd0),
    .opcode_i(opcode),
    .type_code_i(4'h8),
    .beat_i(2'd0),
    .active_mask_i(8'hff),
    .dst_reg_i(8'd9),
    .src1_data_i(src1),
    .src2_data_i(src2),
    .src3_data_i(src3),
    .busy_o(busy),
    .write_valid_o(write_valid),
    .write_warp_o(),
    .write_beat_o(write_beat),
    .write_reg_o(write_reg),
    .write_data_o(write_data),
    .write_mask_o(write_mask)
  );

  initial clk_i = 1'b0;
  always #5 clk_i = ~clk_i;

  task automatic set_all(
    input logic [31:0] a,
    input logic [31:0] b,
    input logic [31:0] c
  );
    begin
      for (int lane = 0; lane < PHYSICAL_SIMD_LANES; lane = lane + 1) begin
        src1[lane] = a;
        src2[lane] = b;
        src3[lane] = c;
      end
    end
  endtask

  task automatic expect_lane0(
    input logic [15:0] op,
    input logic [31:0] a,
    input logic [31:0] b,
    input logic [31:0] c,
    input logic [31:0] expected
  );
    begin
      opcode = op;
      set_all(a, b, c);
      @(negedge clk_i);
      start = 1'b1;
      @(posedge clk_i);
      @(negedge clk_i);
      start = 1'b0;
      repeat (40) begin
        @(posedge clk_i);
        if (write_valid) begin
          assert (write_mask == 8'hff) else $fatal(1, "write mask mismatch");
          assert (write_data[0] == expected)
            else $fatal(1, "op %04x got %08x expected %08x", op, write_data[0], expected);
          return;
        end
      end
      $fatal(1, "FPU edge-case timeout for op %04x", op);
    end
  endtask

  initial begin
    rst_ni = 1'b0;
    start = 1'b0;
    opcode = AEC_OP_NOP;
    set_all(32'd0, 32'd0, 32'd0);
    repeat (4) @(posedge clk_i);
    rst_ni = 1'b1;
    @(posedge clk_i);

    expect_lane0(AEC_OP_MUL, 32'hbf80_0000, 32'h0000_0000, 32'd0, 32'h8000_0000);
    expect_lane0(AEC_OP_MUL, 32'h8000_0000, 32'hc000_0000, 32'd0, 32'h0000_0000);
    expect_lane0(AEC_OP_MUL, 32'h7f80_0000, 32'h0000_0000, 32'd0, 32'h7fc0_0000);
    expect_lane0(AEC_OP_ADD, 32'h7fa1_2345, 32'h3f80_0000, 32'd0, 32'h7fc0_0000);
    expect_lane0(AEC_OP_FMA, 32'h7fa1_2345, 32'h3f80_0000, 32'h4000_0000, 32'h7fc0_0000);

    $display("FPU_EDGES TEST PASSED");
    $finish;
  end
endmodule

`default_nettype wire
