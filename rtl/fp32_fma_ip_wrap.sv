`timescale 1ns/1ps
`default_nettype none

module fp32_fma_ip_wrap #(
  parameter int BEHAVIORAL_LATENCY = 1
) (
  input  wire logic        clk_i,
  input  wire logic        rst_ni,
  input  wire logic        valid_i,
  input  wire logic [31:0] a_i,
  input  wire logic [31:0] b_i,
  input  wire logic [31:0] c_i,
  output logic        result_valid_o,
  output logic [31:0] result_o
);
`ifdef AEC_USE_XILINX_FP_IP
  aec_fp32_fma u_aec_fp32_fma (
    .aclk(clk_i),
    .aclken(1'b1),
    .aresetn(rst_ni),
    .s_axis_a_tvalid(valid_i),
    .s_axis_a_tdata(a_i),
    .s_axis_b_tvalid(valid_i),
    .s_axis_b_tdata(b_i),
    .s_axis_c_tvalid(valid_i),
    .s_axis_c_tdata(c_i),
    .s_axis_operation_tvalid(valid_i),
    .s_axis_operation_tdata(8'h00),
    .m_axis_result_tvalid(result_valid_o),
    .m_axis_result_tdata(result_o)
  );
`else
  logic [BEHAVIORAL_LATENCY-1:0] valid_pipe_q;
  logic [31:0] result_pipe_q [0:BEHAVIORAL_LATENCY-1];

`ifndef SYNTHESIS
  shortreal a_sr;
  shortreal b_sr;
  shortreal c_sr;
  shortreal y_sr;
`endif

  integer pipe_idx;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      valid_pipe_q <= '0;
      for (pipe_idx = 0; pipe_idx < BEHAVIORAL_LATENCY; pipe_idx = pipe_idx + 1) begin
        result_pipe_q[pipe_idx] <= 32'd0;
      end
    end else begin
      valid_pipe_q[0] <= valid_i;
`ifndef SYNTHESIS
      a_sr = $bitstoshortreal(a_i);
      b_sr = $bitstoshortreal(b_i);
      c_sr = $bitstoshortreal(c_i);
      y_sr = a_sr * b_sr + c_sr;
      result_pipe_q[0] <= $shortrealtobits(y_sr);
`else
      result_pipe_q[0] <= 32'd0;
`endif
      for (pipe_idx = 1; pipe_idx < BEHAVIORAL_LATENCY; pipe_idx = pipe_idx + 1) begin
        valid_pipe_q[pipe_idx] <= valid_pipe_q[pipe_idx - 1];
        result_pipe_q[pipe_idx] <= result_pipe_q[pipe_idx - 1];
      end
    end
  end

  always_comb begin
    result_valid_o = valid_pipe_q[BEHAVIORAL_LATENCY-1];
    result_o       = result_pipe_q[BEHAVIORAL_LATENCY-1];
  end
`endif
endmodule

`default_nettype wire
