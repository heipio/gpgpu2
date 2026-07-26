`timescale 1ns/1ps
`default_nettype none

module issue_stage (
  input  wire logic        clk_i,
  input  wire logic        rst_ni,

  input  wire logic        dec_valid_i,
  output logic        dec_ready_o,

  input  wire logic [31:0] logical_active_mask_i,

  output logic        issue_valid_o,
  input  wire logic        issue_ready_i,
  output logic [1:0]  issue_beat_o,
  output logic [7:0]  physical_active_mask_o,
  output logic        issue_first_o,
  output logic        issue_last_o,
  output logic        busy_o
);
  import aec_pkg::*;

  localparam logic [1:0] LAST_BEAT = 2'd3;

  logic [1:0]  beat_q;
  logic [31:0] active_mask_q;
  logic        busy_q;

  wire advance_issue = busy_q && issue_ready_i;

  assign dec_ready_o  = !busy_q;
  assign issue_valid_o = busy_q;
  assign issue_beat_o  = beat_q;
  assign issue_first_o = busy_q && (beat_q == 2'd0);
  assign issue_last_o  = busy_q && (beat_q == LAST_BEAT);
  assign busy_o        = busy_q;

  always_comb begin
    unique case (beat_q)
      2'd0: physical_active_mask_o = active_mask_q[7:0];
      2'd1: physical_active_mask_o = active_mask_q[15:8];
      2'd2: physical_active_mask_o = active_mask_q[23:16];
      default: physical_active_mask_o = active_mask_q[31:24];
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      beat_q        <= 2'd0;
      active_mask_q <= '0;
      busy_q        <= 1'b0;
    end else begin
      if (!busy_q) begin
        if (dec_valid_i) begin
          beat_q        <= 2'd0;
          active_mask_q <= logical_active_mask_i;
          busy_q        <= 1'b1;
        end
      end else if (advance_issue) begin
        if (beat_q == LAST_BEAT) begin
          beat_q        <= 2'd0;
          busy_q        <= 1'b0;
        end else begin
          beat_q        <= beat_q + 2'd1;
        end
      end
    end
  end
endmodule

`default_nettype wire

