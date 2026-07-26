`timescale 1ns/1ps
`default_nettype none

module fp8_decoder (
  input  wire logic [31:0]       packed_fp8_i,
  output logic [3:0][31:0]       f32_bits_o,
  output logic [3:0]             is_nan_o
);
  localparam logic [31:0] CANONICAL_NAN = 32'h7fc00000;

  function automatic logic [31:0] decode_one(input logic [7:0] fp8);
    logic sign;
    logic [3:0] exp;
    logic [2:0] frac;
    logic [2:0] norm_frac;
    logic [7:0] out_exp;
    integer shift_count;
    begin
      sign = fp8[7];
      exp = fp8[6:3];
      frac = fp8[2:0];
      norm_frac = frac;
      out_exp = 8'd0;
      shift_count = 0;

      if ((exp == 4'hf) && (frac == 3'h7)) begin
        decode_one = CANONICAL_NAN;
      end else if (exp == 4'd0) begin
        if (frac == 3'd0) begin
          decode_one = {sign, 31'd0};
        end else begin
          for (int bit_idx = 2; bit_idx >= 0; bit_idx = bit_idx - 1) begin
            if ((norm_frac[2] == 1'b0) && (norm_frac != 3'd0)) begin
              norm_frac = norm_frac << 1;
              shift_count = shift_count + 1;
            end
          end
          out_exp = 127 - 7 - shift_count;
          decode_one = {sign, out_exp, norm_frac[1:0], 21'd0};
        end
      end else begin
        out_exp = (exp == 4'hf) ? 8'd135 : (exp + 120);
        decode_one = {sign, out_exp, frac, 20'd0};
      end
    end
  endfunction

  genvar idx;
  generate
    for (idx = 0; idx < 4; idx = idx + 1) begin : g_decode
      always_comb begin
        f32_bits_o[idx] = decode_one(packed_fp8_i[idx*8 +: 8]);
        is_nan_o[idx] = (packed_fp8_i[idx*8 +: 8] & 8'h7f) == 8'h7f;
      end
    end
  endgenerate
endmodule

`default_nettype wire
