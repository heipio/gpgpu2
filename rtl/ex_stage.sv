`timescale 1ns/1ps
`default_nettype none

module ex_stage #(
  parameter int NUM_WARPS = 4
) (
  input  wire logic        clk_i,
  input  wire logic        rst_ni,

  input  wire logic        issue_valid_i,
  input  wire logic [$clog2(NUM_WARPS)-1:0] issue_warp_i,
  input  wire logic [15:0] issue_opcode_i,
  input  wire logic [1:0]  issue_beat_i,
  input  wire logic [7:0]  physical_active_mask_i,
  input  wire logic [7:0]  dst_reg_i,
  input  wire logic [15:0] src1_sel_i,
  input  wire logic        imm_en_i,
  input  wire logic [2:0]  subop_i,
  input  wire logic [3:0]  type_code_i,
  input  wire logic [2:0]  pred_reg_i,
  input  wire logic        pred_negate_i,
  input  wire logic        pred_enable_i,
  input  wire logic [7:0]  predicate_mask_i,
  input  wire logic [31:0] logical_active_mask_i,
  input  wire logic [31:0] issue_ctaid_x_i,
  input  wire logic [31:0] issue_warpid_i,
  input  wire logic [31:0] issue_nctaid_x_i,
  input  wire logic [15:0] issue_pc_i,
  input  wire logic [31:0] src2_imm_i,
  input  wire logic [31:0] src3_imm_i,

  input  wire logic [7:0][31:0] src1_data_i,
  input  wire logic [7:0][31:0] src2_data_i,
  input  wire logic [7:0][31:0] src3_data_i,

  output logic        ex_valid_o,
  output logic [$clog2(NUM_WARPS)-1:0] ex_warp_o,
  output logic [15:0] ex_opcode_o,
  output logic [3:0]  ex_type_code_o,
  output logic [1:0]  ex_beat_o,
  output logic [7:0]  ex_active_mask_o,
  output logic [7:0]  ex_dst_reg_o,
  output logic [15:0] ex_pc_o,
  output logic [7:0][31:0] ex_result_o,
  output logic [7:0][31:0] ex_src1_data_o,
  output logic [7:0][31:0] ex_src2_data_o,
  output logic [7:0][31:0] ex_src3_data_o,
  output logic [31:0] ex_src2_imm_o,

  output logic        prf_write_valid_o,
  output logic [1:0]  prf_write_beat_o,
  output logic [2:0]  prf_write_pred_o,
  output logic [7:0]  prf_write_data_o,
  output logic [7:0]  prf_write_mask_o,

  output logic        branch_taken_o,
  output logic [$clog2(NUM_WARPS)-1:0] branch_warp_o,
  output logic [15:0] branch_target_o,
  output logic [31:0] branch_mask_o,
  output logic        simt_stack_fault_o
);
  import aec_pkg::*;
  localparam int WARP_BITS = (NUM_WARPS <= 1) ? 1 : $clog2(NUM_WARPS);

  logic        valid_q;
  logic [WARP_BITS-1:0] warp_q;
  logic [15:0] opcode_q;
  logic [1:0]  beat_q;
  logic [7:0]  active_mask_q;
  logic [7:0]  dst_reg_q;
  logic [15:0] src1_sel_q;
  logic        imm_en_q;
  logic [2:0]  subop_q;
  logic [3:0]  type_code_q;
  logic [2:0]  pred_reg_q;
  logic        pred_negate_q;
  logic        pred_enable_q;
  logic [7:0]  predicate_mask_q;
  logic [31:0] logical_active_mask_q;
  logic [31:0] ctaid_x_q;
  logic [31:0] warpid_q;
  logic [31:0] nctaid_x_q;
  logic [15:0] pc_q;
  logic [31:0] src2_imm_q;
  logic [31:0] src3_imm_q;
  logic        calc_valid_q;
  logic [WARP_BITS-1:0] calc_warp_q;
  logic [15:0] calc_opcode_q;
  logic [3:0]  calc_type_code_q;
  logic [1:0]  calc_beat_q;
  logic [7:0]  calc_active_mask_q;
  logic [7:0]  calc_dst_reg_q;
  logic [15:0] calc_src1_sel_q;
  logic        calc_imm_en_q;
  logic [2:0]  calc_subop_q;
  logic [15:0] calc_pc_q;
  logic [31:0] calc_src2_imm_q;
  logic [31:0] calc_src3_imm_q;
  logic [31:0] calc_logical_active_mask_q;
  logic [31:0] calc_ctaid_x_q;
  logic [31:0] calc_warpid_q;
  logic [31:0] calc_nctaid_x_q;
  logic [7:0][31:0] calc_src1_data_q;
  logic [7:0][31:0] calc_src2_data_q;
  logic [7:0][31:0] calc_src3_data_q;
  logic        ex_valid_q;
  logic [WARP_BITS-1:0] ex_warp_q;
  logic [15:0] ex_opcode_q;
  logic [3:0]  ex_type_code_q;
  logic [1:0]  ex_beat_q;
  logic [7:0]  ex_active_mask_q;
  logic [7:0]  ex_dst_reg_q;
  logic [15:0] ex_pc_q;
  logic [7:0][31:0] ex_result_q;
  logic [7:0][31:0] ex_src1_data_q;
  logic [7:0][31:0] ex_src2_data_q;
  logic [7:0][31:0] ex_src3_data_q;
  logic [31:0] ex_src2_imm_q;
  logic [7:0][31:0] alu_result;
  logic [7:0][31:0] alu_src2_data;
  logic [7:0][31:0] result_mux;
  logic [7:0][31:0] src2_data_mux;
  logic [31:0] branch_pred_mask_q [0:NUM_WARPS-1][0:7];
  logic [7:0]  guarded_active_mask;
  logic [7:0]  pred_write_data;
  logic [31:0] taken_mask;
  logic [31:0] fallthrough_mask;
  logic        stack_push;
  logic [15:0] stack_push_pc;
  logic [31:0] stack_push_mask;
  logic        stack_pop;
  logic [NUM_WARPS-1:0] stack_push_warp;
  logic [NUM_WARPS-1:0] stack_pop_warp;
  logic [15:0] stack_pop_pc [0:NUM_WARPS-1];
  logic [31:0] stack_pop_mask [0:NUM_WARPS-1];
  logic [NUM_WARPS-1:0] stack_empty;
  logic [NUM_WARPS-1:0] stack_full;
  logic [NUM_WARPS-1:0] stack_overflow;
  logic [NUM_WARPS-1:0] stack_underflow;
  localparam logic [15:0] AEC_SR_LANEID = 16'h0100;
  localparam logic [15:0] AEC_SR_WARPID = 16'h0101;
  localparam logic [15:0] AEC_SR_CTAID_X = 16'h0102;
  localparam logic [15:0] AEC_SR_NCTAID_X = 16'h0103;
  localparam logic [15:0] AEC_SR_ACTIVEMASK = 16'h0104;
  localparam logic [15:0] AEC_SRC_IMM   = 16'hffff;

  function automatic logic is_control_op(input logic [15:0] opcode);
    begin
      unique case (aec_opcode_e'(opcode))
        AEC_OP_BRA,
        AEC_OP_BRX,
        AEC_OP_SSY,
        AEC_OP_SYNC,
        AEC_OP_BAR_SYNC: is_control_op = 1'b1;
        default:         is_control_op = 1'b0;
      endcase
    end
  endfunction

  function automatic logic cmp_result(
    input logic [31:0] lhs,
    input logic [31:0] rhs,
    input logic [31:0] cmp_code
  );
    begin
      unique case (cmp_code[3:0])
        4'd0:    cmp_result = (lhs == rhs);
        4'd1:    cmp_result = (lhs != rhs);
        4'd2:    cmp_result = (lhs < rhs);
        4'd3:    cmp_result = (lhs <= rhs);
        4'd4:    cmp_result = (lhs > rhs);
        4'd5:    cmp_result = (lhs >= rhs);
        default: cmp_result = 1'b0;
      endcase
    end
  endfunction

  genvar stack_warp;
  generate
    for (stack_warp = 0; stack_warp < NUM_WARPS; stack_warp = stack_warp + 1) begin : g_simt_stack
      simt_stack #(
        .DEPTH(8)
      ) u_simt_stack (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .push_i(stack_push_warp[stack_warp]),
        .push_pc_i(stack_push_pc),
        .push_mask_i(stack_push_mask),
        .pop_i(stack_pop_warp[stack_warp]),
        .pop_pc_o(stack_pop_pc[stack_warp]),
        .pop_mask_o(stack_pop_mask[stack_warp]),
        .empty_o(stack_empty[stack_warp]),
        .full_o(stack_full[stack_warp]),
        .overflow_o(stack_overflow[stack_warp]),
        .underflow_o(stack_underflow[stack_warp])
      );
    end
  endgenerate

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      valid_q       <= 1'b0;
      warp_q        <= '0;
      opcode_q      <= AEC_OP_NOP;
      beat_q        <= 2'd0;
      active_mask_q <= 8'd0;
      dst_reg_q     <= 8'd0;
      src1_sel_q     <= 16'd0;
      imm_en_q       <= 1'b0;
      subop_q        <= 3'd0;
      type_code_q    <= 4'd0;
      pred_reg_q    <= 3'd0;
      pred_negate_q  <= 1'b0;
      pred_enable_q  <= 1'b0;
      predicate_mask_q <= 8'hff;
      logical_active_mask_q <= 32'd0;
      ctaid_x_q <= 32'd0;
      warpid_q <= 32'd0;
      nctaid_x_q <= 32'd0;
      pc_q          <= 16'd0;
      src2_imm_q    <= 32'd0;
      src3_imm_q    <= 32'd0;
      calc_valid_q       <= 1'b0;
      calc_warp_q        <= '0;
      calc_opcode_q      <= AEC_OP_NOP;
      calc_type_code_q   <= 4'd0;
      calc_beat_q        <= 2'd0;
      calc_active_mask_q <= 8'd0;
      calc_dst_reg_q     <= 8'd0;
      calc_src1_sel_q    <= 16'd0;
      calc_imm_en_q      <= 1'b0;
      calc_subop_q       <= 3'd0;
      calc_pc_q          <= 16'd0;
      calc_src2_imm_q    <= 32'd0;
      calc_src3_imm_q    <= 32'd0;
      calc_logical_active_mask_q <= 32'd0;
      calc_ctaid_x_q <= 32'd0;
      calc_warpid_q <= 32'd0;
      calc_nctaid_x_q <= 32'd0;
      calc_src1_data_q   <= '0;
      calc_src2_data_q   <= '0;
      calc_src3_data_q   <= '0;
      ex_valid_q       <= 1'b0;
      ex_warp_q        <= '0;
      ex_opcode_q      <= AEC_OP_NOP;
      ex_type_code_q   <= 4'd0;
      ex_beat_q        <= 2'd0;
      ex_active_mask_q <= 8'd0;
      ex_dst_reg_q     <= 8'd0;
      ex_pc_q          <= 16'd0;
      ex_result_q      <= '0;
      ex_src1_data_q   <= '0;
      ex_src2_data_q   <= '0;
      ex_src3_data_q   <= '0;
      ex_src2_imm_q    <= 32'd0;
    end else begin
      valid_q       <= issue_valid_i;
      warp_q        <= issue_warp_i;
      opcode_q      <= issue_opcode_i;
      beat_q        <= issue_beat_i;
      active_mask_q <= physical_active_mask_i;
      dst_reg_q     <= dst_reg_i;
      src1_sel_q     <= src1_sel_i;
      imm_en_q       <= imm_en_i;
      subop_q        <= subop_i;
      type_code_q    <= type_code_i;
      pred_reg_q    <= pred_reg_i;
      pred_negate_q  <= pred_negate_i;
      pred_enable_q  <= pred_enable_i;
      predicate_mask_q <= predicate_mask_i;
      logical_active_mask_q <= logical_active_mask_i;
      ctaid_x_q <= issue_ctaid_x_i;
      warpid_q <= issue_warpid_i;
      nctaid_x_q <= issue_nctaid_x_i;
      pc_q          <= issue_pc_i;
      src2_imm_q    <= src2_imm_i;
      src3_imm_q    <= src3_imm_i;

      calc_valid_q       <= valid_q;
      calc_warp_q        <= warp_q;
      calc_opcode_q      <= opcode_q;
      calc_type_code_q   <= type_code_q;
      calc_beat_q        <= beat_q;
      calc_active_mask_q <= guarded_active_mask;
      calc_dst_reg_q     <= dst_reg_q;
      calc_src1_sel_q    <= src1_sel_q;
      calc_imm_en_q      <= imm_en_q;
      calc_subop_q       <= subop_q;
      calc_pc_q          <= pc_q;
      calc_src2_imm_q    <= src2_imm_q;
      calc_src3_imm_q    <= src3_imm_q;
      calc_logical_active_mask_q <= logical_active_mask_q;
      calc_ctaid_x_q <= ctaid_x_q;
      calc_warpid_q <= warpid_q;
      calc_nctaid_x_q <= nctaid_x_q;
      calc_src1_data_q   <= src1_data_i;
      calc_src2_data_q   <= src2_data_i;
      calc_src3_data_q   <= src3_data_i;

      ex_valid_q       <= calc_valid_q;
      ex_warp_q        <= calc_warp_q;
      ex_opcode_q      <= calc_opcode_q;
      ex_type_code_q   <= calc_type_code_q;
      ex_beat_q        <= calc_beat_q;
      ex_active_mask_q <= calc_active_mask_q;
      ex_dst_reg_q     <= calc_dst_reg_q;
      ex_pc_q          <= calc_pc_q;
      ex_result_q      <= result_mux;
      ex_src1_data_q   <= calc_src1_data_q;
      ex_src2_data_q   <= src2_data_mux;
      ex_src3_data_q   <= calc_src3_data_q;
      ex_src2_imm_q    <= calc_src2_imm_q;
    end
  end

  integer pred_idx;
  integer pred_lane;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      for (int pred_warp = 0; pred_warp < NUM_WARPS; pred_warp = pred_warp + 1) begin
        for (pred_idx = 0; pred_idx < 8; pred_idx = pred_idx + 1) begin
          branch_pred_mask_q[pred_warp][pred_idx] <= 32'd0;
        end
      end
    end else if (valid_q &&
        ((aec_opcode_e'(opcode_q) == AEC_OP_SETP) || (aec_opcode_e'(opcode_q) == AEC_OP_CMPP))) begin
      for (pred_lane = 0; pred_lane < PHYSICAL_SIMD_LANES; pred_lane = pred_lane + 1) begin
        if (guarded_active_mask[pred_lane]) begin
          branch_pred_mask_q[warp_q][dst_reg_q[2:0]][{beat_q, pred_lane[2:0]}] <=
              cmp_result(src1_data_i[pred_lane], src2_data_i[pred_lane], {29'd0, subop_q});
        end
      end
    end
  end

  genvar lane;
  generate
    for (lane = 0; lane < PHYSICAL_SIMD_LANES; lane = lane + 1) begin : g_alu_lane
      assign alu_src2_data[lane] = calc_imm_en_q ? calc_src2_imm_q : calc_src2_data_q[lane];

      alu_lane u_alu_lane (
        .opcode_i(calc_opcode_q),
        .src1_val_i(calc_src1_data_q[lane]),
        .src2_val_i(alu_src2_data[lane]),
        .src3_val_i(calc_src3_data_q[lane]),
        .result_o(alu_result[lane])
      );

    end
  endgenerate

  always_comb begin
    guarded_active_mask = active_mask_q & predicate_mask_q;
  end

  always_comb begin
    pred_write_data = 8'd0;
    for (int pred_write_lane = 0; pred_write_lane < PHYSICAL_SIMD_LANES; pred_write_lane = pred_write_lane + 1) begin
      pred_write_data[pred_write_lane] = cmp_result(
          src1_data_i[pred_write_lane],
          src2_data_i[pred_write_lane],
          {29'd0, subop_q}
      );
    end
  end

  always_comb begin
    taken_mask = 32'd0;
    fallthrough_mask = 32'd0;
    for (int branch_lane = 0; branch_lane < LOGICAL_WARP_WIDTH; branch_lane = branch_lane + 1) begin
      if (logical_active_mask_q[branch_lane]) begin
        if (pred_enable_q && (pred_negate_q ^ branch_pred_mask_q[warp_q][pred_reg_q][branch_lane])) begin
          taken_mask[branch_lane] = 1'b1;
        end else begin
          fallthrough_mask[branch_lane] = 1'b1;
        end
      end
    end
  end

  always_comb begin
    stack_push      = 1'b0;
    stack_push_warp = '0;
    stack_push_pc   = 16'd0;
    stack_push_mask = 32'd0;
    stack_pop       = 1'b0;
    stack_pop_warp  = '0;
    branch_taken_o  = 1'b0;
    branch_warp_o   = warp_q;
    branch_target_o = 16'd0;
    branch_mask_o   = logical_active_mask_q;
    simt_stack_fault_o = (|stack_overflow) || (|stack_underflow);

    if (valid_q && (beat_q == 2'd0)) begin
      unique case (aec_opcode_e'(opcode_q))
        AEC_OP_BRA: begin
          branch_taken_o  = 1'b1;
          branch_target_o = src3_imm_q[15:0];
          branch_mask_o   = logical_active_mask_q;
        end
        AEC_OP_BRX: begin
          if ((taken_mask != 32'd0) && (fallthrough_mask != 32'd0)) begin
            stack_push      = 1'b1;
            stack_push_warp[warp_q] = 1'b1;
            stack_push_pc   = pc_q + 16'd1;
            stack_push_mask = fallthrough_mask;
            branch_taken_o  = 1'b1;
            branch_target_o = src3_imm_q[15:0];
            branch_mask_o   = taken_mask;
          end else if (taken_mask != 32'd0) begin
            branch_taken_o  = 1'b1;
            branch_target_o = src3_imm_q[15:0];
            branch_mask_o   = taken_mask;
          end else begin
            branch_taken_o  = 1'b1;
            branch_target_o = pc_q + 16'd1;
            branch_mask_o   = fallthrough_mask;
          end
        end
        AEC_OP_SSY: begin
          stack_push      = 1'b1;
          stack_push_warp[warp_q] = 1'b1;
          stack_push_pc   = src3_imm_q[15:0];
          stack_push_mask = logical_active_mask_q;
        end
        AEC_OP_SYNC: begin
          if (!stack_empty[warp_q]) begin
            stack_pop       = 1'b1;
            stack_pop_warp[warp_q] = 1'b1;
            branch_taken_o  = 1'b1;
            branch_target_o = stack_pop_pc[warp_q];
            branch_mask_o   = stack_pop_mask[warp_q];
          end else begin
            simt_stack_fault_o = 1'b1;
          end
        end
        default: begin
        end
      endcase
    end
  end

  always_comb begin
    src2_data_mux = calc_src2_data_q;
    if ((aec_opcode_e'(calc_opcode_q) == AEC_OP_LD) || (aec_opcode_e'(calc_opcode_q) == AEC_OP_ST)) begin
      for (int src2_lane = 0; src2_lane < PHYSICAL_SIMD_LANES; src2_lane = src2_lane + 1) begin
        src2_data_mux[src2_lane] = calc_src2_imm_q;
      end
    end
  end

  always_comb begin
    result_mux = alu_result;
    if (aec_opcode_e'(calc_opcode_q) == AEC_OP_MOV) begin
      if (calc_src1_sel_q == AEC_SR_LANEID) begin
        for (int result_lane = 0; result_lane < PHYSICAL_SIMD_LANES; result_lane = result_lane + 1) begin
          result_mux[result_lane] = {27'd0, calc_beat_q, result_lane[2:0]};
        end
      end else if (calc_src1_sel_q == AEC_SR_WARPID) begin
        for (int result_lane = 0; result_lane < PHYSICAL_SIMD_LANES; result_lane = result_lane + 1) begin
          result_mux[result_lane] = calc_warpid_q;
        end
      end else if (calc_src1_sel_q == AEC_SR_CTAID_X) begin
        for (int result_lane = 0; result_lane < PHYSICAL_SIMD_LANES; result_lane = result_lane + 1) begin
          result_mux[result_lane] = calc_ctaid_x_q;
        end
      end else if (calc_src1_sel_q == AEC_SR_NCTAID_X) begin
        for (int result_lane = 0; result_lane < PHYSICAL_SIMD_LANES; result_lane = result_lane + 1) begin
          result_mux[result_lane] = calc_nctaid_x_q;
        end
      end else if (calc_src1_sel_q == AEC_SR_ACTIVEMASK) begin
        for (int result_lane = 0; result_lane < PHYSICAL_SIMD_LANES; result_lane = result_lane + 1) begin
          result_mux[result_lane] = calc_logical_active_mask_q;
        end
      end else if (calc_src1_sel_q == AEC_SRC_IMM) begin
        for (int result_lane = 0; result_lane < PHYSICAL_SIMD_LANES; result_lane = result_lane + 1) begin
          result_mux[result_lane] = calc_src2_imm_q;
        end
      end
    end
    if (is_control_op(calc_opcode_q) ||
        (aec_opcode_e'(calc_opcode_q) == AEC_OP_SETP) ||
        (aec_opcode_e'(calc_opcode_q) == AEC_OP_CMPP) ||
        (((aec_opcode_e'(calc_opcode_q) == AEC_OP_ADD) ||
          (aec_opcode_e'(calc_opcode_q) == AEC_OP_SUB) ||
          (aec_opcode_e'(calc_opcode_q) == AEC_OP_MUL) ||
          (aec_opcode_e'(calc_opcode_q) == AEC_OP_MAD) ||
          (aec_opcode_e'(calc_opcode_q) == AEC_OP_FMA)) && (calc_type_code_q == 4'h8)) ||
        (aec_opcode_e'(calc_opcode_q) == AEC_OP_SHFL) ||
        (aec_opcode_e'(calc_opcode_q) == AEC_OP_REDUCE) ||
        (aec_opcode_e'(calc_opcode_q) == AEC_OP_SFU)) begin
      result_mux = '0;
    end
  end

  always_comb begin
    ex_valid_o       = ex_valid_q;
    ex_warp_o        = ex_warp_q;
    ex_opcode_o      = ex_opcode_q;
    ex_type_code_o   = ex_type_code_q;
    ex_beat_o        = ex_beat_q;
    ex_active_mask_o = ex_active_mask_q;
    ex_dst_reg_o     = ex_dst_reg_q;
    ex_pc_o          = ex_pc_q;
    ex_result_o      = ex_result_q;
    ex_src1_data_o   = ex_src1_data_q;
    ex_src2_data_o   = ex_src2_data_q;
    ex_src3_data_o   = ex_src3_data_q;
    ex_src2_imm_o    = ex_src2_imm_q;

    prf_write_valid_o = valid_q &&
        ((aec_opcode_e'(opcode_q) == AEC_OP_SETP) || (aec_opcode_e'(opcode_q) == AEC_OP_CMPP));
    prf_write_beat_o  = beat_q;
    prf_write_pred_o  = dst_reg_q[2:0];
    prf_write_data_o  = pred_write_data;
    prf_write_mask_o  = prf_write_valid_o ? guarded_active_mask : 8'd0;
  end
endmodule

`default_nettype wire
