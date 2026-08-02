`timescale 1ns/1ps
`default_nettype none

module mma_core #(
  parameter int FMA_LATENCY = 8
) (
  input  wire logic        clk_i,
  input  wire logic        rst_ni,

  input  wire logic        start_i,
  input  wire logic [15:0] pc_i,
  input  wire logic [15:0] pred_ctrl_i,
  input  wire logic [31:0] logical_active_mask_i,
  input  wire logic        pred_enable_i,
  input  wire logic [15:0] d_base_i,
  input  wire logic [15:0] a_base_i,
  input  wire logic [31:0] b_base_i,
  input  wire logic [31:0] c_base_i,

  output logic        busy_o,
  output logic        done_o,

  output logic        vrf_read_enable_o,
  output logic [1:0]  vrf_read_beat_o,
  output logic [7:0]  vrf_read_reg1_o,
  output logic [7:0]  vrf_read_reg2_o,
  output logic [7:0]  vrf_read_reg3_o,
  input  wire logic [7:0][31:0] vrf_read_data1_i,
  input  wire logic [7:0][31:0] vrf_read_data2_i,
  input  wire logic [7:0][31:0] vrf_read_data3_i,

  output logic        vrf_write_valid_o,
  output logic [1:0]  vrf_write_beat_o,
  output logic [7:0]  vrf_write_reg_o,
  output logic [7:0][31:0] vrf_write_data_o,
  output logic [7:0]  vrf_write_mask_o,

  output logic        fault_valid_o,
  output aec_pkg::aec_fault_e fault_code_o,
  output logic [15:0] fault_pc_o
);
  import aec_pkg::*;

  typedef enum logic [3:0] {
    MMA_IDLE,
    MMA_READ_SETUP,
    MMA_READ_CAPTURE,
    MMA_COMPUTE_PREP,
    MMA_COMPUTE_ISSUE,
    MMA_COMPUTE_WAIT,
    MMA_WRITE,
    MMA_DONE,
    MMA_FAULT
  } mma_state_e;

  localparam logic [31:0] FULL_WARP_MASK = 32'hffff_ffff;
  localparam logic [31:0] CANONICAL_NAN  = 32'h7fc0_0000;

  mma_state_e state_q;
  logic [15:0] pc_q;
  logic [7:0] d_base_q;
  logic [7:0] a_base_q;
  logic [7:0] b_base_q;
  logic [7:0] c_base_q;
  logic [1:0] read_beat_q;
  logic [2:0] read_slot_q;
  logic [5:0] out_lane_q;
  logic [2:0] out_elem_q;
  logic [4:0] k_q;
  logic [2:0] write_elem_q;
  logic [1:0] write_beat_q;
  logic [31:0] acc_q;

  logic [31:0] a_pack_q [0:31][0:1];
  logic [31:0] b_pack_q [0:31][0:1];
  logic [31:0] c_frag_q [0:31][0:7];
  logic [31:0] d_frag_q [0:31][0:7];

  logic        fma_valid;
  logic [31:0] fma_a;
  logic [31:0] fma_b;
  logic [31:0] fma_c;
  logic [31:0] fma_a_q;
  logic [31:0] fma_b_q;
  logic [31:0] fma_c_q;
  logic        fma_result_valid;
  logic [31:0] fma_result;

  function automatic logic [31:0] fp8_to_f32(input logic [7:0] fp8);
    logic sign;
    logic [3:0] exp;
    logic [2:0] frac;
    logic [2:0] norm_frac;
    logic [7:0] out_exp;
    integer shift_count;
    begin
      sign = fp8[7];
      exp = fp8[6:3];
      frac = fp8[2:0];
      norm_frac = frac;
      out_exp = 8'd0;
      shift_count = 0;

      if ((exp == 4'hf) && (frac == 3'h7)) begin
        fp8_to_f32 = CANONICAL_NAN;
      end else if (exp == 4'd0) begin
        if (frac == 3'd0) begin
          fp8_to_f32 = {sign, 31'd0};
        end else begin
          for (int bit_idx = 2; bit_idx >= 0; bit_idx = bit_idx - 1) begin
            if ((norm_frac[2] == 1'b0) && (norm_frac != 3'd0)) begin
              norm_frac = norm_frac << 1;
              shift_count = shift_count + 1;
            end
          end
          out_exp = 127 - 7 - shift_count;
          fp8_to_f32 = {sign, out_exp, norm_frac[1:0], 21'd0};
        end
      end else begin
        out_exp = (exp == 4'hf) ? 8'd135 : (exp + 120);
        fp8_to_f32 = {sign, out_exp, frac, 20'd0};
      end
    end
  endfunction

  function automatic logic [7:0] pick_fp8_byte(input logic [31:0] word, input logic [1:0] byte_idx);
    begin
      pick_fp8_byte = word[byte_idx * 8 +: 8];
    end
  endfunction

  function automatic logic [7:0] a_fp8_for(
    input logic [5:0] out_lane,
    input logic [4:0] k_idx
  );
    logic [4:0] row;
    logic half;
    logic [5:0] owner_lane;
    logic reg_sel;
    logic [1:0] byte_sel;
    begin
      row = out_lane[5:1];
      half = k_idx[3];
      owner_lane = {row, half};
      reg_sel = k_idx[2];
      byte_sel = k_idx[1:0];
      a_fp8_for = pick_fp8_byte(a_pack_q[owner_lane][reg_sel], byte_sel);
    end
  endfunction

  function automatic logic [7:0] b_fp8_for(
    input logic [5:0] out_lane,
    input logic [2:0] out_elem,
    input logic [4:0] k_idx
  );
    logic [3:0] col;
    logic half;
    logic [5:0] owner_lane;
    logic reg_sel;
    logic [1:0] byte_sel;
    begin
      col = {out_lane[0], out_elem};
      half = k_idx[3];
      owner_lane = {col, half};
      reg_sel = k_idx[2];
      byte_sel = k_idx[1:0];
      b_fp8_for = pick_fp8_byte(b_pack_q[owner_lane][reg_sel], byte_sel);
    end
  endfunction

  function automatic logic start_is_legal;
    logic [3:0] type_code;
    logic [2:0] subop;
    begin
      type_code = pred_ctrl_i[6:3];
      subop = pred_ctrl_i[10:8];
      start_is_legal =
          (type_code == 4'hb) &&
          (subop == 3'd0) &&
          !pred_enable_i &&
          (logical_active_mask_i == FULL_WARP_MASK) &&
          (d_base_i[15:8] == 8'd0) &&
          (a_base_i[15:8] == 8'd0) &&
          (b_base_i[31:16] == 16'd0) &&
          (c_base_i[31:16] == 16'd0) &&
          (d_base_i[2:0] == 3'd0) &&
          (c_base_i[2:0] == 3'd0) &&
          (a_base_i[0] == 1'b0) &&
          (b_base_i[0] == 1'b0) &&
          (d_base_i[7:0] <= 8'd248) &&
          (c_base_i[7:0] <= 8'd248) &&
          (a_base_i[7:0] <= 8'd254) &&
          (b_base_i[7:0] <= 8'd254);
    end
  endfunction

  fp32_fma_ip_wrap #(
    .BEHAVIORAL_LATENCY(FMA_LATENCY)
  ) u_fp32_fma (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .valid_i(fma_valid),
    .a_i(fma_a),
    .b_i(fma_b),
    .c_i(fma_c),
    .result_valid_o(fma_result_valid),
    .result_o(fma_result)
  );

  always_comb begin
    busy_o = (state_q != MMA_IDLE);
    done_o = (state_q == MMA_DONE);
    fault_valid_o = (state_q == MMA_FAULT);
    fault_code_o = AEC_FAULT_ILLEGAL_INSTRUCTION;
    fault_pc_o = pc_q;

    vrf_read_enable_o = (state_q == MMA_READ_SETUP) || (state_q == MMA_READ_CAPTURE);
    vrf_read_beat_o = read_beat_q;
    vrf_read_reg1_o = a_base_q + ((read_slot_q == 3'd1) ? 8'd1 : 8'd0);
    vrf_read_reg2_o = b_base_q + ((read_slot_q == 3'd1) ? 8'd1 : 8'd0);
    vrf_read_reg3_o = c_base_q + {5'd0, read_slot_q};

    fma_valid = (state_q == MMA_COMPUTE_ISSUE);
    fma_a = fma_a_q;
    fma_b = fma_b_q;
    fma_c = fma_c_q;

    vrf_write_valid_o = (state_q == MMA_WRITE);
    vrf_write_beat_o = write_beat_q;
    vrf_write_reg_o = d_base_q + {5'd0, write_elem_q};
    vrf_write_mask_o = 8'hff;
    vrf_write_data_o = '0;
    for (int wlane = 0; wlane < PHYSICAL_SIMD_LANES; wlane = wlane + 1) begin
      vrf_write_data_o[wlane] = d_frag_q[{write_beat_q, wlane[2:0]}][write_elem_q];
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= MMA_IDLE;
      pc_q <= 16'd0;
      d_base_q <= 8'd0;
      a_base_q <= 8'd0;
      b_base_q <= 8'd0;
      c_base_q <= 8'd0;
      read_beat_q <= 2'd0;
      read_slot_q <= 3'd0;
      out_lane_q <= 6'd0;
      out_elem_q <= 3'd0;
      k_q <= 5'd0;
      write_elem_q <= 3'd0;
      write_beat_q <= 2'd0;
      acc_q <= 32'd0;
      fma_a_q <= 32'd0;
      fma_b_q <= 32'd0;
      fma_c_q <= 32'd0;
    end else begin
      unique case (state_q)
        MMA_IDLE: begin
          if (start_i) begin
            pc_q <= pc_i;
            if (!start_is_legal()) begin
              state_q <= MMA_FAULT;
            end else begin
              d_base_q <= d_base_i[7:0];
              a_base_q <= a_base_i[7:0];
              b_base_q <= b_base_i[7:0];
              c_base_q <= c_base_i[7:0];
              read_beat_q <= 2'd0;
              read_slot_q <= 3'd0;
              state_q <= MMA_READ_SETUP;
            end
          end
        end

        MMA_READ_SETUP: begin
          state_q <= MMA_READ_CAPTURE;
        end

        MMA_READ_CAPTURE: begin
          for (int cap_lane = 0; cap_lane < PHYSICAL_SIMD_LANES; cap_lane = cap_lane + 1) begin
            if (read_slot_q == 3'd0) begin
              a_pack_q[{read_beat_q, cap_lane[2:0]}][0] <= vrf_read_data1_i[cap_lane];
              b_pack_q[{read_beat_q, cap_lane[2:0]}][0] <= vrf_read_data2_i[cap_lane];
              c_frag_q[{read_beat_q, cap_lane[2:0]}][0] <= vrf_read_data3_i[cap_lane];
            end else if (read_slot_q == 3'd1) begin
              a_pack_q[{read_beat_q, cap_lane[2:0]}][1] <= vrf_read_data1_i[cap_lane];
              b_pack_q[{read_beat_q, cap_lane[2:0]}][1] <= vrf_read_data2_i[cap_lane];
              c_frag_q[{read_beat_q, cap_lane[2:0]}][1] <= vrf_read_data3_i[cap_lane];
            end else begin
              c_frag_q[{read_beat_q, cap_lane[2:0]}][read_slot_q] <= vrf_read_data3_i[cap_lane];
            end
          end
          if ((read_slot_q == 3'd7) && (read_beat_q == 2'd3)) begin
            out_lane_q <= 6'd0;
            out_elem_q <= 3'd0;
            k_q <= 5'd0;
            acc_q <= 32'd0;
            state_q <= MMA_COMPUTE_PREP;
          end else begin
            if (read_slot_q == 3'd7) begin
              read_slot_q <= 3'd0;
              read_beat_q <= read_beat_q + 2'd1;
            end else begin
              read_slot_q <= read_slot_q + 3'd1;
            end
            state_q <= MMA_READ_SETUP;
          end
        end

        MMA_COMPUTE_PREP: begin
          fma_a_q <= fp8_to_f32(a_fp8_for(out_lane_q, k_q));
          fma_b_q <= fp8_to_f32(b_fp8_for(out_lane_q, out_elem_q, k_q));
          fma_c_q <= (k_q == 5'd0) ? c_frag_q[out_lane_q][out_elem_q] : acc_q;
          state_q <= MMA_COMPUTE_ISSUE;
        end

        MMA_COMPUTE_ISSUE: begin
          state_q <= MMA_COMPUTE_WAIT;
        end

        MMA_COMPUTE_WAIT: begin
          if (fma_result_valid) begin
            acc_q <= fma_result;
            if (k_q == 5'd15) begin
              d_frag_q[out_lane_q][out_elem_q] <= fma_result;
              k_q <= 5'd0;
              acc_q <= 32'd0;
              if ((out_lane_q == 6'd31) && (out_elem_q == 3'd7)) begin
                write_elem_q <= 3'd0;
                write_beat_q <= 2'd0;
                state_q <= MMA_WRITE;
              end else begin
                if (out_elem_q == 3'd7) begin
                  out_elem_q <= 3'd0;
                  out_lane_q <= out_lane_q + 6'd1;
                end else begin
                  out_elem_q <= out_elem_q + 3'd1;
                end
                state_q <= MMA_COMPUTE_PREP;
              end
            end else begin
              k_q <= k_q + 5'd1;
              state_q <= MMA_COMPUTE_PREP;
            end
          end
        end

        MMA_WRITE: begin
          if ((write_elem_q == 3'd7) && (write_beat_q == 2'd3)) begin
            state_q <= MMA_DONE;
          end else begin
            if (write_beat_q == 2'd3) begin
              write_beat_q <= 2'd0;
              write_elem_q <= write_elem_q + 3'd1;
            end else begin
              write_beat_q <= write_beat_q + 2'd1;
            end
          end
        end

        MMA_DONE: begin
          state_q <= MMA_IDLE;
        end

        MMA_FAULT: begin
          state_q <= MMA_IDLE;
        end

        default: begin
          state_q <= MMA_IDLE;
        end
      endcase
    end
  end
endmodule

`default_nettype wire
