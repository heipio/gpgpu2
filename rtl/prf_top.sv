`timescale 1ns/1ps
`default_nettype none

module prf_top (
  input  wire logic       clk_i,
  input  wire logic       rst_ni,

  input  wire logic [1:0] read_beat_i,
  input  wire logic [3:0] read_pred1_i,
  input  wire logic [3:0] read_pred2_i,
  input  wire logic [3:0] read_pred3_i,
  output logic [7:0] read_mask1_o,
  output logic [7:0] read_mask2_o,
  output logic [7:0] read_mask3_o,

  input  wire logic       write_valid_i,
  input  wire logic [1:0] write_beat_i,
  input  wire logic [2:0] write_pred_i,
  input  wire logic [7:0] write_data_i,
  input  wire logic [7:0] write_mask_i
);
  import aec_pkg::*;

  localparam logic [3:0] PRED_PT = 4'hf;

  logic [7:0] pred_mem [0:7][0:ISSUE_BEATS-1];

  integer pred_idx;
  integer beat_idx;

  function automatic logic [7:0] read_pred_mask(
    input logic [3:0] pred,
    input logic [1:0] beat
  );
    begin
      if (pred == PRED_PT) begin
        read_pred_mask = 8'hff;
      end else if (pred[3] == 1'b0) begin
        read_pred_mask = pred_mem[pred[2:0]][beat];
      end else begin
        read_pred_mask = ~pred_mem[pred[2:0]][beat];
      end
    end
  endfunction

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      for (pred_idx = 0; pred_idx < 8; pred_idx = pred_idx + 1) begin
        for (beat_idx = 0; beat_idx < ISSUE_BEATS; beat_idx = beat_idx + 1) begin
          pred_mem[pred_idx][beat_idx] <= 8'h00;
        end
      end
    end else if (write_valid_i) begin
      pred_mem[write_pred_i][write_beat_i] <=
          (pred_mem[write_pred_i][write_beat_i] & ~write_mask_i) |
          (write_data_i & write_mask_i);
    end
  end

  always_comb begin
    read_mask1_o = read_pred_mask(read_pred1_i, read_beat_i);
    read_mask2_o = read_pred_mask(read_pred2_i, read_beat_i);
    read_mask3_o = read_pred_mask(read_pred3_i, read_beat_i);
  end
endmodule

`default_nettype wire

