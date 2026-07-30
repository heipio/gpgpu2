`timescale 1ns/1ps
`default_nettype none

module simt_stack #(
  parameter int DEPTH = 8
) (
  input  wire logic        clk_i,
  input  wire logic        rst_ni,

  input  wire logic        push_i,
  input  wire logic [15:0] push_pc_i,
  input  wire logic [31:0] push_mask_i,

  input  wire logic        pop_i,
  output logic [15:0]      pop_pc_o,
  output logic [31:0]      pop_mask_o,

  output logic             empty_o,
  output logic             full_o,
  output logic             overflow_o,
  output logic             underflow_o
);
  localparam int PTR_WIDTH = $clog2(DEPTH + 1);

  logic [15:0] pc_mem   [0:DEPTH-1];
  logic [31:0] mask_mem [0:DEPTH-1];
  logic [PTR_WIDTH-1:0] sp_q;

  assign empty_o = (sp_q == '0);
  assign full_o  = (sp_q == DEPTH[PTR_WIDTH-1:0]);

  always_comb begin
    if (empty_o) begin
      pop_pc_o   = 16'd0;
      pop_mask_o = 32'd0;
    end else begin
      pop_pc_o   = pc_mem[sp_q - 1'b1];
      pop_mask_o = mask_mem[sp_q - 1'b1];
    end
  end

  always_ff @(posedge clk_i) begin
    if (push_i && !pop_i && !full_o) begin
      pc_mem[sp_q]   <= push_pc_i;
      mask_mem[sp_q] <= push_mask_i;
    end else if (push_i && pop_i && !empty_o) begin
      pc_mem[sp_q - 1'b1]   <= push_pc_i;
      mask_mem[sp_q - 1'b1] <= push_mask_i;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      sp_q        <= '0;
      overflow_o  <= 1'b0;
      underflow_o <= 1'b0;
    end else begin
      overflow_o  <= push_i && !pop_i && full_o;
      underflow_o <= pop_i && empty_o;

      unique case ({push_i, pop_i})
        2'b10: begin
          if (!full_o) begin
            sp_q <= sp_q + 1'b1;
          end
        end
        2'b01: begin
          if (!empty_o) begin
            sp_q <= sp_q - 1'b1;
          end
        end
        default: begin
        end
      endcase
    end
  end
endmodule

`default_nettype wire
