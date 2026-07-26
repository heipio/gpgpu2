`timescale 1ns/1ps
`default_nettype none

module if_stage (
  input  wire logic         clk_i,
  input  wire logic         rst_ni,

  output logic [9:0]        imem_addr_o,
  input  wire logic [127:0] imem_data_i,

  input  wire logic         branch_taken_i,
  input  wire logic [15:0]  branch_target_i,
  input  wire logic         flush_i,
  input  wire logic         enable_i,
  input  wire logic         start_i,
  input  wire logic [15:0]  start_pc_i,

  output logic              if_valid_o,
  input  wire logic         if_ready_i,
  output logic [127:0]      instr_o,
  output logic [15:0]       pc_o
);
  logic [15:0] pc_q;
  logic        valid_q;

  assign imem_addr_o = pc_q[9:0];
  assign instr_o     = imem_data_i;
  assign if_valid_o  = enable_i && valid_q && !flush_i;
  assign pc_o        = pc_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      pc_q    <= 16'd0;
      valid_q <= 1'b0;
    end else begin
      if (start_i) begin
        pc_q    <= start_pc_i;
        valid_q <= 1'b1;
      end else if (!enable_i) begin
        valid_q <= 1'b0;
      end else begin
        valid_q <= !flush_i;
      end

      if (enable_i && branch_taken_i) begin
        pc_q <= branch_target_i;
      end else if (enable_i && if_valid_o && if_ready_i) begin
        pc_q <= pc_q + 16'd1;
      end
    end
  end
endmodule

`default_nettype wire
