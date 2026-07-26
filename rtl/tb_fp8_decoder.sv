`timescale 1ns/1ps
`default_nettype none

module tb_fp8_decoder;
  logic [31:0] packed_fp8;
  logic [3:0][31:0] f32_bits;
  logic [3:0] is_nan;

  fp8_decoder dut (
    .packed_fp8_i(packed_fp8),
    .f32_bits_o(f32_bits),
    .is_nan_o(is_nan)
  );

  initial begin
    packed_fp8 = 32'h7e_38_01_80;
    #1;
    assert (f32_bits[0] == 32'h80000000) else $fatal(1, "-0 decode mismatch");
    assert (f32_bits[1] == 32'h3b000000) else $fatal(1, "min subnormal decode mismatch");
    assert (f32_bits[2] == 32'h3f800000) else $fatal(1, "1.0 decode mismatch");
    assert (f32_bits[3] == 32'h43e00000) else $fatal(1, "448 decode mismatch");
    assert (is_nan == 4'b0000) else $fatal(1, "unexpected NaN flag");

    packed_fp8 = 32'hff_7f_fe_00;
    #1;
    assert (f32_bits[0] == 32'h00000000) else $fatal(1, "+0 decode mismatch");
    assert (f32_bits[1] == 32'hc3e00000) else $fatal(1, "-448 decode mismatch");
    assert (f32_bits[2] == 32'h7fc00000) else $fatal(1, "+NaN decode mismatch");
    assert (f32_bits[3] == 32'h7fc00000) else $fatal(1, "-NaN decode mismatch");
    assert (is_nan == 4'b1100) else $fatal(1, "NaN flag mismatch");

    $display("FP8_DECODER TEST PASSED");
    $finish;
  end
endmodule

`default_nettype wire
