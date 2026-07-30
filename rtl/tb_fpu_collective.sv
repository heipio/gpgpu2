`timescale 1ns/1ps
`default_nettype none

module tb_fpu_collective;
  import aec_pkg::*;

  logic clk_i;
  logic rst_ni;

  logic fpu_start;
  logic fpu_busy;
  logic fpu_write_valid;
  logic [1:0] fpu_write_beat;
  logic [7:0] fpu_write_reg;
  logic [7:0][31:0] fpu_write_data;
  logic [7:0] fpu_write_mask;
  logic [7:0][31:0] fpu_src1;
  logic [7:0][31:0] fpu_src2;
  logic [7:0][31:0] fpu_src3;

  logic coll_start;
  logic coll_busy;
  logic coll_read_enable;
  logic [1:0] coll_read_beat;
  logic [7:0] coll_read_reg1;
  logic [7:0] coll_read_reg2;
  logic [7:0] coll_read_reg3;
  logic [7:0][31:0] coll_read_data1;
  logic [7:0][31:0] coll_read_data2;
  logic coll_write_valid;
  logic [1:0] coll_write_beat;
  logic [7:0] coll_write_reg;
  logic [7:0][31:0] coll_write_data;
  logic [7:0] coll_write_mask;
  logic [15:0] coll_opcode;
  logic [2:0] coll_subop;
  logic [3:0] coll_type;
  logic coll_imm_en;
  logic [31:0] coll_imm;

  fpu_core u_fpu (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .start_i(fpu_start),
    .warp_i(2'd0),
    .opcode_i(AEC_OP_FMA),
    .type_code_i(4'h8),
    .beat_i(2'd2),
    .active_mask_i(8'hff),
    .dst_reg_i(8'd9),
    .src1_data_i(fpu_src1),
    .src2_data_i(fpu_src2),
    .src3_data_i(fpu_src3),
    .busy_o(fpu_busy),
    .write_valid_o(fpu_write_valid),
    .write_warp_o(),
    .write_beat_o(fpu_write_beat),
    .write_reg_o(fpu_write_reg),
    .write_data_o(fpu_write_data),
    .write_mask_o(fpu_write_mask)
  );

  warp_collective_core u_coll (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .start_i(coll_start),
    .warp_i(2'd0),
    .opcode_i(coll_opcode),
    .subop_i(coll_subop),
    .type_code_i(coll_type),
    .imm_en_i(coll_imm_en),
    .logical_active_mask_i(32'hffff_ffff),
    .dst_reg_i(8'd7),
    .src1_reg_i(8'd3),
    .src2_reg_i(8'd4),
    .src2_imm_i(coll_imm),
    .busy_o(coll_busy),
    .vrf_read_enable_o(coll_read_enable),
    .vrf_read_warp_o(),
    .vrf_read_beat_o(coll_read_beat),
    .vrf_read_reg1_o(coll_read_reg1),
    .vrf_read_reg2_o(coll_read_reg2),
    .vrf_read_reg3_o(coll_read_reg3),
    .vrf_read_data1_i(coll_read_data1),
    .vrf_read_data2_i(coll_read_data2),
    .vrf_write_valid_o(coll_write_valid),
    .vrf_write_warp_o(),
    .vrf_write_beat_o(coll_write_beat),
    .vrf_write_reg_o(coll_write_reg),
    .vrf_write_data_o(coll_write_data),
    .vrf_write_mask_o(coll_write_mask)
  );

  initial clk_i = 1'b0;
  always #5 clk_i = ~clk_i;

  always_comb begin
    coll_read_data1 = '0;
    coll_read_data2 = '0;
    for (int lane = 0; lane < PHYSICAL_SIMD_LANES; lane = lane + 1) begin
      coll_read_data1[lane] = 32'd100 + (coll_read_beat * PHYSICAL_SIMD_LANES) + lane;
      coll_read_data2[lane] = 32'd8;
      if (coll_opcode == AEC_OP_REDUCE) begin
        coll_read_data1[lane] = 32'h3f80_0000;
      end
    end
  end

  task automatic pulse_fpu;
    begin
      fpu_start = 1'b1;
      @(posedge clk_i);
      fpu_start = 1'b0;
      repeat (20) begin
        @(posedge clk_i);
        if (fpu_write_valid) begin
          assert (fpu_write_beat == 2'd2) else $fatal(1, "FPU write beat mismatch");
          assert (fpu_write_reg == 8'd9) else $fatal(1, "FPU write reg mismatch");
          assert (fpu_write_mask == 8'hff) else $fatal(1, "FPU write mask mismatch");
          assert (fpu_write_data[0] == 32'h40a0_0000) else $fatal(1, "FPU FMA got %08x expected 40a00000", fpu_write_data[0]);
          return;
        end
      end
      $fatal(1, "FPU timeout");
    end
  endtask

  task automatic run_shfl_xor;
    bit seen0;
    bit seen1;
    begin
      seen0 = 1'b0;
      seen1 = 1'b0;
      coll_opcode = AEC_OP_SHFL;
      coll_subop = 3'd1;
      coll_type = 4'h2;
      coll_imm_en = 1'b1;
      coll_imm = 32'd8;
      coll_start = 1'b1;
      @(posedge clk_i);
      coll_start = 1'b0;
      repeat (80) begin
        @(posedge clk_i);
        if (coll_write_valid && coll_write_beat == 2'd0) begin
          assert (coll_write_data[0] == 32'd108) else $fatal(1, "SHFL lane0 got %0d expected 108", coll_write_data[0]);
          seen0 = 1'b1;
        end
        if (coll_write_valid && coll_write_beat == 2'd1) begin
          assert (coll_write_data[0] == 32'd100) else $fatal(1, "SHFL lane8 got %0d expected 100", coll_write_data[0]);
          seen1 = 1'b1;
        end
        if (seen0 && seen1 && !coll_busy) begin
          return;
        end
      end
      $fatal(1, "SHFL timeout");
    end
  endtask

  task automatic run_reduce_f32;
    begin
      coll_opcode = AEC_OP_REDUCE;
      coll_subop = 3'd0;
      coll_type = 4'h8;
      coll_imm_en = 1'b0;
      coll_imm = 32'd0;
      coll_start = 1'b1;
      @(posedge clk_i);
      coll_start = 1'b0;
      repeat (300) begin
        @(posedge clk_i);
        if (coll_write_valid && coll_write_beat == 2'd0) begin
          assert (coll_write_data[0] == 32'h4200_0000) else $fatal(1, "REDUCE.f32 got %08x expected 42000000", coll_write_data[0]);
          return;
        end
      end
      $fatal(1, "REDUCE timeout");
    end
  endtask

  integer i;
  initial begin
    rst_ni = 1'b0;
    fpu_start = 1'b0;
    coll_start = 1'b0;
    coll_opcode = AEC_OP_NOP;
    coll_subop = 3'd0;
    coll_type = 4'd0;
    coll_imm_en = 1'b0;
    coll_imm = 32'd0;
    for (i = 0; i < PHYSICAL_SIMD_LANES; i = i + 1) begin
      fpu_src1[i] = 32'h3f80_0000;
      fpu_src2[i] = 32'h4000_0000;
      fpu_src3[i] = 32'h4040_0000;
    end
    repeat (4) @(posedge clk_i);
    rst_ni = 1'b1;
    @(posedge clk_i);
    pulse_fpu();
    run_shfl_xor();
    run_reduce_f32();
    $display("FPU_COLLECTIVE TEST PASSED");
    $finish;
  end
endmodule

`default_nettype wire
