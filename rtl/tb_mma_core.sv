`timescale 1ns/1ps
`default_nettype none

module tb_mma_core;
  import aec_pkg::*;

  logic clk_i;
  logic rst_ni;
  logic start_i;
  logic busy_o;
  logic done_o;
  logic vrf_read_enable_o;
  logic [1:0] vrf_read_beat_o;
  logic [7:0] vrf_read_reg1_o;
  logic [7:0] vrf_read_reg2_o;
  logic [7:0] vrf_read_reg3_o;
  logic [7:0][31:0] vrf_read_data1_i;
  logic [7:0][31:0] vrf_read_data2_i;
  logic [7:0][31:0] vrf_read_data3_i;
  logic vrf_write_valid_o;
  logic [1:0] vrf_write_beat_o;
  logic [7:0] vrf_write_reg_o;
  logic [7:0][31:0] vrf_write_data_o;
  logic [7:0] vrf_write_mask_o;
  logic fault_valid_o;
  aec_fault_e fault_code_o;
  logic [15:0] fault_pc_o;

  localparam logic [7:0] D_BASE = 8'd16;
  localparam logic [7:0] A_BASE = 8'd2;
  localparam logic [7:0] B_BASE = 8'd4;
  localparam logic [7:0] C_BASE = 8'd24;
  localparam logic [31:0] PACKED_ONES = 32'h3838_3838;
  localparam logic [31:0] ZERO_F32 = 32'h0000_0000;
  localparam logic [31:0] EXPECT_16_F32 = 32'h4180_0000;

  logic [31:0] d_seen [0:31][0:7];
  logic [7:0] write_seen [0:7][0:3];

  mma_core dut (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .start_i(start_i),
    .pc_i(16'h0123),
    .pred_ctrl_i(16'h0058),
    .logical_active_mask_i(32'hffff_ffff),
    .pred_enable_i(1'b0),
    .d_base_i({8'd0, D_BASE}),
    .a_base_i({8'd0, A_BASE}),
    .b_base_i({24'd0, B_BASE}),
    .c_base_i({24'd0, C_BASE}),
    .busy_o(busy_o),
    .done_o(done_o),
    .vrf_read_enable_o(vrf_read_enable_o),
    .vrf_read_beat_o(vrf_read_beat_o),
    .vrf_read_reg1_o(vrf_read_reg1_o),
    .vrf_read_reg2_o(vrf_read_reg2_o),
    .vrf_read_reg3_o(vrf_read_reg3_o),
    .vrf_read_data1_i(vrf_read_data1_i),
    .vrf_read_data2_i(vrf_read_data2_i),
    .vrf_read_data3_i(vrf_read_data3_i),
    .vrf_write_valid_o(vrf_write_valid_o),
    .vrf_write_beat_o(vrf_write_beat_o),
    .vrf_write_reg_o(vrf_write_reg_o),
    .vrf_write_data_o(vrf_write_data_o),
    .vrf_write_mask_o(vrf_write_mask_o),
    .fault_valid_o(fault_valid_o),
    .fault_code_o(fault_code_o),
    .fault_pc_o(fault_pc_o)
  );

  initial clk_i = 1'b0;
  always #5 clk_i = ~clk_i;

  always_comb begin
    vrf_read_data1_i = '0;
    vrf_read_data2_i = '0;
    vrf_read_data3_i = '0;
    for (int lane = 0; lane < PHYSICAL_SIMD_LANES; lane = lane + 1) begin
      if ((vrf_read_reg1_o == A_BASE) || (vrf_read_reg1_o == (A_BASE + 8'd1))) begin
        vrf_read_data1_i[lane] = PACKED_ONES;
      end
      if ((vrf_read_reg2_o == B_BASE) || (vrf_read_reg2_o == (B_BASE + 8'd1))) begin
        vrf_read_data2_i[lane] = PACKED_ONES;
      end
      if ((vrf_read_reg3_o >= C_BASE) && (vrf_read_reg3_o < (C_BASE + 8'd8))) begin
        vrf_read_data3_i[lane] = ZERO_F32;
      end
    end
  end

  always_ff @(posedge clk_i) begin
    if (vrf_write_valid_o) begin
      for (int lane = 0; lane < PHYSICAL_SIMD_LANES; lane = lane + 1) begin
        if (vrf_write_mask_o[lane]) begin
          d_seen[{vrf_write_beat_o, lane[2:0]}][vrf_write_reg_o - D_BASE] <= vrf_write_data_o[lane];
          write_seen[vrf_write_reg_o - D_BASE][vrf_write_beat_o] <= 1'b1;
        end
      end
    end
  end

  integer i;
  integer j;
  initial begin
    rst_ni = 1'b0;
    start_i = 1'b0;
    for (i = 0; i < 32; i = i + 1) begin
      for (j = 0; j < 8; j = j + 1) begin
        d_seen[i][j] = 32'hdead_beef;
      end
    end
    for (i = 0; i < 8; i = i + 1) begin
      for (j = 0; j < 4; j = j + 1) begin
        write_seen[i][j] = 1'b0;
      end
    end

    repeat (4) @(posedge clk_i);
    rst_ni = 1'b1;
    @(posedge clk_i);
    start_i = 1'b1;
    @(posedge clk_i);
    start_i = 1'b0;

    // The reference core serializes 32 lanes x 8 accumulator elements x
    // k=0..15.  With the fixed 8-cycle FMA this needs roughly 41k cycles,
    // plus fragment readout and writeback.  Keep a bounded watchdog without
    // declaring a correct multi-cycle implementation dead prematurely.
    repeat (50000) begin
      @(posedge clk_i);
      if (fault_valid_o) begin
        $fatal(1, "MMA fault code=%0d pc=%04h", fault_code_o, fault_pc_o);
      end
      if (done_o) begin
        for (i = 0; i < 32; i = i + 1) begin
          for (j = 0; j < 8; j = j + 1) begin
            if (d_seen[i][j] !== EXPECT_16_F32) begin
              $fatal(1, "D lane=%0d elem=%0d got=%08x expected=%08x",
                     i, j, d_seen[i][j], EXPECT_16_F32);
            end
          end
        end
        $display("MMA_CORE TEST PASSED");
        $finish;
      end
    end
    $fatal(1, "MMA core timeout");
  end
endmodule

`default_nettype wire
