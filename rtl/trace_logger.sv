`timescale 1ns/1ps
`default_nettype none

`ifndef SYNTHESIS
module trace_logger #(
  parameter bit HALT_FINISH = 1'b1
) (
  input  wire logic        clk_i,
  input  wire logic        rst_ni,
  input  wire logic [15:0] pc_q,
  input  wire logic [15:0] opcode_i,
  input  wire logic        write_valid_i,
  input  wire logic [1:0]  write_beat_i,
  input  wire logic [7:0]  write_mask_i,
  input  wire logic [7:0]  dst_reg_i,
  input  wire logic [7:0][31:0] write_data_i,
  output logic              halt_seen_o
);
  import aec_pkg::*;

  integer fd;

  initial begin
    fd = $fopen("trace_rtl.log", "w");
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      halt_seen_o <= 1'b0;
    end else begin
      if (write_valid_i) begin
        $fdisplay(fd,
                  "[PC=%04h] BEAT=%0d MASK=%02h REG[%0d] <- %08x %08x %08x %08x %08x %08x %08x %08x",
                  pc_q, write_beat_i, write_mask_i, dst_reg_i,
                  write_data_i[7], write_data_i[6], write_data_i[5], write_data_i[4],
                  write_data_i[3], write_data_i[2], write_data_i[1], write_data_i[0]);
      end

      if ((aec_opcode_e'(opcode_i) == AEC_OP_HALT) && !halt_seen_o) begin
        halt_seen_o <= 1'b1;
        $fclose(fd);
        if (HALT_FINISH) begin
          $finish;
        end
      end
    end
  end
endmodule
`endif

`default_nettype wire
