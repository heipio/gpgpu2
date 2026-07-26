`timescale 1ns/1ps
`default_nettype none

module sfu_lane #(
  parameter int LUT_BITS = 12
) (
  input  wire logic [15:0] opcode_i,
  input  wire logic [2:0]  subop_i,
  input  wire logic [31:0] src_val_i,
  output logic [31:0] result_o
);
  import aec_pkg::*;

  localparam int LUT_ENTRIES = 1 << LUT_BITS;
  localparam logic [31:0] CANONICAL_NAN = 32'h7fc00000;
  localparam logic [31:0] POS_INF       = 32'h7f800000;
  localparam logic [31:0] POS_ZERO      = 32'h00000000;
  localparam logic [31:0] POS_ONE       = 32'h3f800000;

  logic [22:0] rcp_lut [0:LUT_ENTRIES-1];
  logic [22:0] exp2_lut [0:LUT_ENTRIES-1];

  initial begin
    $readmemh("sfu_rcp_lut.mem", rcp_lut);
    $readmemh("sfu_exp2_lut.mem", exp2_lut);
  end

  function automatic logic [22:0] lut_rcp_read(input logic [LUT_BITS-1:0] idx);
    begin
      lut_rcp_read = rcp_lut[idx];
    end
  endfunction

  function automatic logic [22:0] lut_exp2_read(input logic [LUT_BITS-1:0] idx);
    begin
      lut_exp2_read = exp2_lut[idx];
    end
  endfunction

  function automatic logic [31:0] make_inf(input logic sign);
    begin
      make_inf = {sign, 8'hff, 23'd0};
    end
  endfunction

  function automatic logic [31:0] make_zero(input logic sign);
    begin
      make_zero = {sign, 31'd0};
    end
  endfunction

  function automatic logic [31:0] rcp_approx(input logic [31:0] x);
    logic sign;
    logic [7:0] exp_in;
    logic [22:0] frac_in;
    logic [23:0] mant_norm;
    logic [23:0] out_sig;
    logic [22:0] subnormal_frac;
    logic [LUT_BITS-1:0] idx;
    integer eff_exp;
    integer out_exp;
    integer subnormal_shift;
    begin
      sign = x[31];
      exp_in = x[30:23];
      frac_in = x[22:0];
      mant_norm = {1'b1, frac_in};
      out_sig = 24'd0;
      subnormal_frac = 23'd0;
      idx = '0;
      eff_exp = exp_in;
      out_exp = 0;
      subnormal_shift = 0;

      if ((exp_in == 8'hff) && (frac_in != 23'd0)) begin
        rcp_approx = CANONICAL_NAN;
      end else if ((exp_in == 8'd0) && (frac_in == 23'd0)) begin
        rcp_approx = make_inf(sign);
      end else if (exp_in == 8'hff) begin
        rcp_approx = make_zero(sign);
      end else begin
        if (exp_in == 8'd0) begin
          mant_norm = {1'b0, frac_in};
          eff_exp = 1;
          for (int sh = 0; sh < 23; sh = sh + 1) begin
            if (!mant_norm[23] && (mant_norm != 24'd0)) begin
              mant_norm = mant_norm << 1;
              eff_exp = eff_exp - 1;
            end
          end
        end
        idx = mant_norm[22 -: LUT_BITS];
        out_exp = 253 - eff_exp;
        if (out_exp >= 255) begin
          rcp_approx = make_inf(sign);
        end else if (out_exp <= 0) begin
          out_sig = {1'b1, lut_rcp_read(idx)};
          subnormal_shift = 1 - out_exp;
          if (subnormal_shift >= 24) begin
            subnormal_frac = 23'd0;
          end else begin
            subnormal_frac = out_sig >> subnormal_shift;
          end
          rcp_approx = {sign, 8'd0, subnormal_frac};
        end else begin
          rcp_approx = {sign, out_exp[7:0], lut_rcp_read(idx)};
        end
      end
    end
  endfunction

  function automatic logic signed [31:0] f32_to_q12_trunc(input logic [31:0] x);
    logic sign;
    logic [7:0] exp_in;
    logic [22:0] frac_in;
    logic [23:0] mant;
    logic [63:0] mag;
    integer shift;
    begin
      sign = x[31];
      exp_in = x[30:23];
      frac_in = x[22:0];
      mant = (exp_in == 8'd0) ? {1'b0, frac_in} : {1'b1, frac_in};
      shift = integer'(exp_in) - 138;
      if (exp_in == 8'd0) begin
        f32_to_q12_trunc = 32'sd0;
      end else if (shift >= 0) begin
        mag = {40'd0, mant} << shift;
        f32_to_q12_trunc = sign ? -$signed(mag[31:0]) : $signed(mag[31:0]);
      end else if (shift <= -24) begin
        f32_to_q12_trunc = 32'sd0;
      end else begin
        mag = {40'd0, mant} >> (-shift);
        f32_to_q12_trunc = sign ? -$signed(mag[31:0]) : $signed(mag[31:0]);
      end
    end
  endfunction

  function automatic logic [31:0] exp2_approx(input logic [31:0] x);
    logic sign;
    logic [7:0] exp_in;
    logic [22:0] frac_in;
    logic signed [31:0] x_q12;
    logic signed [31:0] whole;
    logic [LUT_BITS-1:0] idx;
    integer out_exp;
    begin
      sign = x[31];
      exp_in = x[30:23];
      frac_in = x[22:0];
      x_q12 = 32'sd0;
      whole = 32'sd0;
      idx = '0;
      out_exp = 0;

      if ((exp_in == 8'hff) && (frac_in != 23'd0)) begin
        exp2_approx = CANONICAL_NAN;
      end else if (x == 32'h7f800000) begin
        exp2_approx = POS_INF;
      end else if (x == 32'hff800000) begin
        exp2_approx = POS_ZERO;
      end else if ((exp_in == 8'd0) && (frac_in == 23'd0)) begin
        exp2_approx = POS_ONE;
      end else if (!sign && (x >= 32'h43000000)) begin
        exp2_approx = POS_INF;
      end else if (sign && ({1'b0, x[30:0]} > 32'h42fc0000)) begin
        exp2_approx = POS_ZERO;
      end else begin
        x_q12 = f32_to_q12_trunc(x);
        whole = x_q12 >>> LUT_BITS;
        idx = x_q12[LUT_BITS-1:0];
        out_exp = whole + 127;
        if (out_exp >= 255) begin
          exp2_approx = POS_INF;
        end else if (out_exp <= 0) begin
          exp2_approx = POS_ZERO;
        end else begin
          exp2_approx = {1'b0, out_exp[7:0], lut_exp2_read(idx)};
        end
      end
    end
  endfunction

  always_comb begin
    unique case (aec_opcode_e'(opcode_i))
      AEC_OP_SFU: begin
        unique case (subop_i)
          3'd0:    result_o = rcp_approx(src_val_i);
          3'd1:    result_o = exp2_approx(src_val_i);
          default: result_o = CANONICAL_NAN;
        endcase
      end
      default: result_o = 32'd0;
    endcase
  end
endmodule

`default_nettype wire
