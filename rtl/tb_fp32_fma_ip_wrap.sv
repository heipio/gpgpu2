`timescale 1ns/1ps
`default_nettype none

module tb_fp32_fma_ip_wrap;
  logic clk_i;
  logic rst_ni;
  logic valid_i;
  logic [31:0] a_i;
  logic [31:0] b_i;
  logic [31:0] c_i;
  logic result_valid_o;
  logic [31:0] result_o;

  fp32_fma_ip_wrap dut (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .valid_i(valid_i),
    .a_i(a_i),
    .b_i(b_i),
    .c_i(c_i),
    .result_valid_o(result_valid_o),
    .result_o(result_o)
  );

  initial clk_i = 1'b0;
  always #5 clk_i = ~clk_i;

  initial begin
    rst_ni = 1'b0;
    valid_i = 1'b0;
    a_i = 32'h0000_0000;
    b_i = 32'h0000_0000;
    c_i = 32'h0000_0000;

    repeat (4) @(posedge clk_i);
    rst_ni = 1'b1;

    @(posedge clk_i);
    valid_i = 1'b1;
    a_i = 32'h3fc0_0000; // 1.5
    b_i = 32'h4000_0000; // 2.0
    c_i = 32'h3f80_0000; // 1.0

    @(posedge clk_i);
    valid_i = 1'b0;

    repeat (20) begin
      @(posedge clk_i);
      if (result_valid_o) begin
        if (result_o !== 32'h4080_0000) begin
          $fatal(1, "FMA result mismatch: got %08x expected 40800000", result_o);
        end
        $display("FP32_FMA_IP_WRAP TEST PASSED");
        $finish;
      end
    end

    $fatal(1, "FMA result did not become valid");
  end
endmodule

`default_nettype wire
