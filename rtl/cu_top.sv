`timescale 1ns/1ps
`default_nettype none

module cu_top #(
  parameter int AXI_ADDR_WIDTH = 64,
  parameter int AXI_DATA_WIDTH = 512,
  parameter bit USE_EXTERNAL_INSTR = 1'b0,
  parameter bit TRACE_HALT_FINISH = 1'b1
) (
  input  wire logic                       clk_i,
  input  wire logic                       rst_ni,

  input  wire logic [AXI_ADDR_WIDTH-1:0]  s_axil_awaddr,
  input  wire logic                       s_axil_awvalid,
  output logic                       s_axil_awready,
  input  wire logic [31:0]                s_axil_wdata,
  input  wire logic [3:0]                 s_axil_wstrb,
  input  wire logic                       s_axil_wvalid,
  output logic                       s_axil_wready,
  output logic [1:0]                 s_axil_bresp,
  output logic                       s_axil_bvalid,
  input  wire logic                       s_axil_bready,
  input  wire logic [AXI_ADDR_WIDTH-1:0]  s_axil_araddr,
  input  wire logic                       s_axil_arvalid,
  output logic                       s_axil_arready,
  output logic [31:0]                s_axil_rdata,
  output logic [1:0]                 s_axil_rresp,
  output logic                       s_axil_rvalid,
  input  wire logic                       s_axil_rready,

  output logic [AXI_ADDR_WIDTH-1:0]  m_axi_awaddr,
  output logic [7:0]                 m_axi_awlen,
  output logic [2:0]                 m_axi_awsize,
  output logic [1:0]                 m_axi_awburst,
  output logic                       m_axi_awvalid,
  input  wire logic                       m_axi_awready,
  output logic [AXI_DATA_WIDTH-1:0]  m_axi_wdata,
  output logic [AXI_DATA_WIDTH/8-1:0] m_axi_wstrb,
  output logic                       m_axi_wlast,
  output logic                       m_axi_wvalid,
  input  wire logic                       m_axi_wready,
  input  wire logic [1:0]                 m_axi_bresp,
  input  wire logic                       m_axi_bvalid,
  output logic                       m_axi_bready,
  output logic [AXI_ADDR_WIDTH-1:0]  m_axi_araddr,
  output logic [7:0]                 m_axi_arlen,
  output logic [2:0]                 m_axi_arsize,
  output logic [1:0]                 m_axi_arburst,
  output logic                       m_axi_arvalid,
  input  wire logic                       m_axi_arready,
  input  wire logic [AXI_DATA_WIDTH-1:0]  m_axi_rdata,
  input  wire logic [1:0]                 m_axi_rresp,
  input  wire logic                       m_axi_rlast,
  input  wire logic                       m_axi_rvalid,
  output logic                       m_axi_rready,

  input  wire logic                       instr_valid_i,
  output logic                       instr_ready_o,
  input  wire logic [127:0]               instr_i,
  input  wire logic [31:0]                warp_active_mask_i,

  output logic                       issue_valid_o,
  input  wire logic                       issue_ready_i,
  output logic [1:0]                 issue_beat_o,
  output logic [7:0]                 physical_active_mask_o,
  output logic [15:0]                decoded_opcode_o,
  output logic [7:0]                 decoded_dst_reg_o,
  output logic [7:0]                 decoded_src1_reg_o,
  output logic [7:0]                 decoded_src2_reg_o,
  output logic [7:0]                 decoded_src3_reg_o
);
  import aec_pkg::*;

  logic dec_valid;
  logic dec_ready;
  logic instr_src_valid;
  logic [127:0] instr_src_data;
  logic [9:0] imem_addr;
  logic [127:0] imem_data;
  logic if_valid;
  logic [127:0] if_instr;
  logic [15:0] if_pc;
  logic issue_busy;
  aec_opcode_e decoded_opcode;
  logic [15:0] pred_ctrl;
  logic [15:0] dst;
  logic [15:0] src1;
  logic [31:0] src2;
  logic [31:0] src3;
  logic [7:0]  dst_reg;
  logic [7:0]  src1_reg;
  logic [7:0]  src2_reg;
  logic [7:0]  src3_reg;
  logic [2:0]  pred_reg;
  logic        pred_negate;
  logic        pred_enable;
  logic [3:0]  pred_sel;
  logic        id_illegal_opcode;
  logic        accept_dec;

  logic        issue_valid;
  logic        issue_ready_eff;
  logic        issue_fire;
  logic [1:0]  issue_beat;
  logic [7:0]  issue_active_mask;
  logic [15:0] issue_opcode_q;
  logic [7:0]  issue_dst_reg_q;
  logic [7:0]  issue_src1_reg_q;
  logic [7:0]  issue_src2_reg_q;
  logic [7:0]  issue_src3_reg_q;
  logic [15:0] issue_src1_sel_q;

  logic [7:0][31:0] vrf_src1_data;
  logic [7:0][31:0] vrf_src2_data;
  logic [7:0][31:0] vrf_src3_data;

  logic        ex_valid;
  logic [15:0] ex_opcode;
  logic [1:0]  ex_beat;
  logic [7:0]  ex_active_mask;
  logic [7:0]  ex_dst_reg;
  logic [7:0][31:0] ex_result;
  logic [7:0][31:0] ex_src1_data;
  logic [7:0][31:0] ex_src2_data;
  logic [7:0][31:0] ex_src3_data;

  logic        lsu_busy;
  logic        lsu_load_valid;
  logic [1:0]  lsu_load_beat;
  logic [7:0]  lsu_load_dst_reg;
  logic [7:0]  lsu_load_mask;
  logic [7:0][31:0] lsu_load_data;

  logic        wb_vrf_write_valid;
  logic [1:0]  wb_vrf_write_beat;
  logic [7:0]  wb_vrf_write_dst_reg;
  logic [9:0]  wb_vrf_waddr;
  logic [7:0][31:0] wb_vrf_write_data;
  logic [7:0]  wb_vrf_write_mask;
  logic [15:0] pc_q;
  logic        ex_is_lsu_op;
  logic        trace_halt_seen;
  logic [31:0] current_active_mask_q;
  logic        active_mask_ready_q;
  logic        branch_taken;
  logic [15:0] branch_target;
  logic [31:0] branch_mask;
  logic        simt_stack_fault;
  logic        pipeline_flush;
  logic [2:0]  issue_pred_reg_q;
  logic        issue_pred_negate_q;
  logic        issue_pred_enable_q;
  logic [3:0]  issue_pred_sel_q;
  logic        issue_imm_en_q;
  logic [2:0]  issue_subop_q;
  logic [7:0]  issue_predicate_mask;
  logic [31:0] issue_src2_imm_q;
  logic [31:0] issue_src3_imm_q;
  logic [15:0] issue_pc_q;
  logic [15:0] ex_pc;
  logic        prf_write_valid;
  logic [1:0]  prf_write_beat;
  logic [2:0]  prf_write_pred;
  logic [7:0]  prf_write_data;
  logic [7:0]  prf_write_mask;
  logic        csr_start_pulse;
  logic [15:0] csr_start_pc;
  logic        imem_axil_we;
  logic [9:0]  imem_axil_word_addr;
  logic [31:0] imem_axil_wdata;
  logic [3:0]  imem_axil_wstrb;
  logic [9:0]  imem_axil_read_word_addr;
  logic [31:0] imem_axil_rdata;
  logic        gpu_running_q;
  logic        gpu_done_pulse;
  logic        if_enable;
  logic        fault_valid;
  aec_fault_e fault_code;
  logic [15:0] fault_pc;
  logic        lsu_fault_valid;
  aec_fault_e lsu_fault_code;
  logic [15:0] lsu_fault_pc;

  assign gpu_done_pulse = ex_valid && (aec_opcode_e'(ex_opcode) == AEC_OP_HALT) && (ex_beat == 2'd0);
  assign if_enable = USE_EXTERNAL_INSTR ? 1'b1 : gpu_running_q;

  csr_regfile #(
    .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH)
  ) u_csr_regfile (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .s_axil_awaddr(s_axil_awaddr),
    .s_axil_awvalid(s_axil_awvalid),
    .s_axil_awready(s_axil_awready),
    .s_axil_wdata(s_axil_wdata),
    .s_axil_wstrb(s_axil_wstrb),
    .s_axil_wvalid(s_axil_wvalid),
    .s_axil_wready(s_axil_wready),
    .s_axil_bresp(s_axil_bresp),
    .s_axil_bvalid(s_axil_bvalid),
    .s_axil_bready(s_axil_bready),
    .s_axil_araddr(s_axil_araddr),
    .s_axil_arvalid(s_axil_arvalid),
    .s_axil_arready(s_axil_arready),
    .s_axil_rdata(s_axil_rdata),
    .s_axil_rresp(s_axil_rresp),
    .s_axil_rvalid(s_axil_rvalid),
    .s_axil_rready(s_axil_rready),
    .gpu_done_i(gpu_done_pulse),
    .gpu_running_i(gpu_running_q),
    .fault_valid_i(fault_valid),
    .fault_code_i(fault_code),
    .fault_pc_i(fault_pc),
    .start_pulse_o(csr_start_pulse),
    .start_pc_o(csr_start_pc),
    .imem_we_o(imem_axil_we),
    .imem_word_addr_o(imem_axil_word_addr),
    .imem_wdata_o(imem_axil_wdata),
    .imem_wstrb_o(imem_axil_wstrb),
    .imem_read_word_addr_o(imem_axil_read_word_addr),
    .imem_rdata_i(imem_axil_rdata)
  );

  (* keep_hierarchy = "yes", dont_touch = "yes" *) imem u_imem (
    .clk_i(clk_i),
    .axil_we_i(imem_axil_we),
    .axil_word_addr_i(imem_axil_word_addr),
    .axil_wdata_i(imem_axil_wdata),
    .axil_wstrb_i(imem_axil_wstrb),
    .axil_read_word_addr_i(imem_axil_read_word_addr),
    .axil_rdata_o(imem_axil_rdata),
    .if_addr_i(imem_addr),
    .if_data_o(imem_data)
  );

  if_stage u_if_stage (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .imem_addr_o(imem_addr),
    .imem_data_i(imem_data),
    .branch_taken_i(branch_taken),
    .branch_target_i(branch_target),
    .flush_i(pipeline_flush),
    .enable_i(if_enable),
    .start_i(csr_start_pulse && !USE_EXTERNAL_INSTR),
    .start_pc_i(csr_start_pc),
    .if_valid_o(if_valid),
    .if_ready_i(dec_ready && active_mask_ready_q),
    .instr_o(if_instr),
    .pc_o(if_pc)
  );

  always_comb begin
    if (USE_EXTERNAL_INSTR) begin
      instr_src_valid = instr_valid_i;
      instr_src_data  = instr_i;
      pc_q            = 16'd0;
    end else begin
      instr_src_valid = if_valid && gpu_running_q;
      instr_src_data  = if_instr;
      pc_q            = if_pc;
    end
  end

  assign pipeline_flush = branch_taken;

  id_stage u_id_stage (
    .instr_valid_i(instr_src_valid && dec_ready && active_mask_ready_q && !pipeline_flush),
    .instr_i(instr_src_data),
    .dec_valid_o(dec_valid),
    .opcode_o(decoded_opcode),
    .pred_ctrl_o(pred_ctrl),
    .dst_o(dst),
    .src1_o(src1),
    .src2_o(src2),
    .src3_o(src3),
    .dst_reg_o(dst_reg),
    .src1_reg_o(src1_reg),
    .src2_reg_o(src2_reg),
    .src3_reg_o(src3_reg),
    .pred_reg_o(pred_reg),
    .pred_negate_o(pred_negate),
    .pred_enable_o(pred_enable),
    .pred_sel_o(pred_sel),
    .illegal_opcode_o(id_illegal_opcode)
  );

  issue_stage u_issue_stage (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .dec_valid_i(dec_valid && !id_illegal_opcode),
    .dec_ready_o(dec_ready),
    .logical_active_mask_i(current_active_mask_q),
    .issue_valid_o(issue_valid),
    .issue_ready_i(issue_ready_eff),
    .issue_beat_o(issue_beat),
    .physical_active_mask_o(issue_active_mask),
    .issue_first_o(),
    .issue_last_o(),
    .busy_o(issue_busy)
  );

  assign ex_is_lsu_op = ex_valid &&
      (|ex_active_mask) &&
      ((aec_opcode_e'(ex_opcode) == AEC_OP_LD) || (aec_opcode_e'(ex_opcode) == AEC_OP_ST));
  assign issue_ready_eff = issue_ready_i && !lsu_busy && !ex_is_lsu_op;
  assign issue_fire = issue_valid && issue_ready_eff;
  assign accept_dec = dec_valid && !id_illegal_opcode && dec_ready && active_mask_ready_q && !pipeline_flush;
  assign instr_ready_o = USE_EXTERNAL_INSTR ? (dec_ready && active_mask_ready_q) : 1'b0;
  assign issue_valid_o = issue_valid;
  assign issue_beat_o = issue_beat;
  assign physical_active_mask_o = issue_active_mask;

  assign decoded_opcode_o   = decoded_opcode;
  assign decoded_dst_reg_o  = dst_reg;
  assign decoded_src1_reg_o = src1_reg;
  assign decoded_src2_reg_o = src2_reg;
  assign decoded_src3_reg_o = src3_reg;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      issue_opcode_q   <= AEC_OP_NOP;
      issue_dst_reg_q  <= 8'd0;
      issue_src1_reg_q <= 8'd0;
      issue_src2_reg_q <= 8'd0;
      issue_src3_reg_q <= 8'd0;
      issue_src1_sel_q <= 16'd0;
      issue_pred_reg_q <= 3'd0;
      issue_pred_negate_q <= 1'b0;
      issue_pred_enable_q <= 1'b0;
      issue_pred_sel_q <= 4'hf;
      issue_imm_en_q <= 1'b0;
      issue_subop_q <= 3'd0;
      issue_src2_imm_q <= 32'd0;
      issue_src3_imm_q <= 32'd0;
      issue_pc_q       <= 16'd0;
    end else if (accept_dec) begin
      issue_opcode_q   <= decoded_opcode;
      issue_dst_reg_q  <= dst_reg;
      issue_src1_reg_q <= src1_reg;
      issue_src2_reg_q <= src2_reg;
      issue_src3_reg_q <= src3_reg;
      issue_src1_sel_q <= src1;
      issue_pred_reg_q <= pred_reg;
      issue_pred_negate_q <= pred_negate;
      issue_pred_enable_q <= pred_enable;
      issue_pred_sel_q <= pred_sel;
      issue_imm_en_q <= pred_ctrl[7];
      issue_subop_q <= pred_ctrl[10:8];
      issue_src2_imm_q <= src2;
      issue_src3_imm_q <= src3;
      issue_pc_q       <= pc_q;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      current_active_mask_q <= 32'd0;
      active_mask_ready_q   <= 1'b0;
    end else if (csr_start_pulse || !active_mask_ready_q) begin
      current_active_mask_q <= warp_active_mask_i;
      active_mask_ready_q   <= csr_start_pulse || USE_EXTERNAL_INSTR;
    end else if (branch_taken) begin
      current_active_mask_q <= branch_mask;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      gpu_running_q <= USE_EXTERNAL_INSTR;
    end else if (USE_EXTERNAL_INSTR) begin
      gpu_running_q <= 1'b1;
    end else if (csr_start_pulse) begin
      gpu_running_q <= 1'b1;
    end else if (gpu_done_pulse || fault_valid) begin
      gpu_running_q <= 1'b0;
    end
  end

  prf_top u_prf_top (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .read_beat_i(issue_beat),
    .read_pred1_i(issue_pred_sel_q),
    .read_pred2_i(4'hf),
    .read_pred3_i(4'hf),
    .read_mask1_o(issue_predicate_mask),
    .read_mask2_o(),
    .read_mask3_o(),
    .write_valid_i(prf_write_valid),
    .write_beat_i(prf_write_beat),
    .write_pred_i(prf_write_pred),
    .write_data_i(prf_write_data),
    .write_mask_i(prf_write_mask)
  );

  (* keep_hierarchy = "yes", dont_touch = "yes" *) vrf_top u_vrf_top (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .issue_beat_i(issue_beat),
    .src1_reg_i(issue_src1_reg_q),
    .src2_reg_i(issue_src2_reg_q),
    .src3_reg_i(issue_src3_reg_q),
    .src1_data_o(vrf_src1_data),
    .src2_data_o(vrf_src2_data),
    .src3_data_o(vrf_src3_data),
    .write_valid_i(wb_vrf_write_valid),
    .write_beat_i(wb_vrf_write_beat),
    .dst_reg_i(wb_vrf_write_dst_reg),
    .write_data_i(wb_vrf_write_data),
    .write_mask_i(wb_vrf_write_mask)
  );

  ex_stage u_ex_stage (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .issue_valid_i(issue_fire),
    .issue_opcode_i(issue_opcode_q),
    .issue_beat_i(issue_beat),
    .physical_active_mask_i(issue_active_mask),
    .dst_reg_i(issue_dst_reg_q),
    .src1_sel_i(issue_src1_sel_q),
    .imm_en_i(issue_imm_en_q),
    .subop_i(issue_subop_q),
    .pred_reg_i(issue_pred_reg_q),
    .pred_negate_i(issue_pred_negate_q),
    .pred_enable_i(issue_pred_enable_q),
    .predicate_mask_i(issue_predicate_mask),
    .logical_active_mask_i(current_active_mask_q),
    .issue_pc_i(issue_pc_q),
    .src2_imm_i(issue_src2_imm_q),
    .src3_imm_i(issue_src3_imm_q),
    .src1_data_i(vrf_src1_data),
    .src2_data_i(vrf_src2_data),
    .src3_data_i(vrf_src3_data),
    .ex_valid_o(ex_valid),
    .ex_opcode_o(ex_opcode),
    .ex_beat_o(ex_beat),
    .ex_active_mask_o(ex_active_mask),
    .ex_dst_reg_o(ex_dst_reg),
    .ex_pc_o(ex_pc),
    .ex_result_o(ex_result),
    .ex_src1_data_o(ex_src1_data),
    .ex_src2_data_o(ex_src2_data),
    .ex_src3_data_o(ex_src3_data),
    .prf_write_valid_o(prf_write_valid),
    .prf_write_beat_o(prf_write_beat),
    .prf_write_pred_o(prf_write_pred),
    .prf_write_data_o(prf_write_data),
    .prf_write_mask_o(prf_write_mask),
    .branch_taken_o(branch_taken),
    .branch_target_o(branch_target),
    .branch_mask_o(branch_mask),
    .simt_stack_fault_o(simt_stack_fault)
  );

  lsu #(
    .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
    .AXI_DATA_WIDTH(AXI_DATA_WIDTH)
  ) u_lsu (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .ex_valid_i(ex_valid),
    .ex_opcode_i(ex_opcode),
    .ex_beat_i(ex_beat),
    .ex_pc_i(ex_pc),
    .ex_active_mask_i(ex_active_mask),
    .ex_dst_reg_i(ex_dst_reg),
    .ex_src1_data_i(ex_src1_data),
    .ex_src2_data_i(ex_src2_data),
    .ex_src3_data_i(ex_src3_data),
    .busy_o(lsu_busy),
    .load_valid_o(lsu_load_valid),
    .load_beat_o(lsu_load_beat),
    .load_dst_reg_o(lsu_load_dst_reg),
    .load_mask_o(lsu_load_mask),
    .load_data_o(lsu_load_data),
    .fault_valid_o(lsu_fault_valid),
    .fault_code_o(lsu_fault_code),
    .fault_pc_o(lsu_fault_pc),
    .m_axi_awaddr(m_axi_awaddr),
    .m_axi_awlen(m_axi_awlen),
    .m_axi_awsize(m_axi_awsize),
    .m_axi_awburst(m_axi_awburst),
    .m_axi_awvalid(m_axi_awvalid),
    .m_axi_awready(m_axi_awready),
    .m_axi_wdata(m_axi_wdata),
    .m_axi_wstrb(m_axi_wstrb),
    .m_axi_wlast(m_axi_wlast),
    .m_axi_wvalid(m_axi_wvalid),
    .m_axi_wready(m_axi_wready),
    .m_axi_bresp(m_axi_bresp),
    .m_axi_bvalid(m_axi_bvalid),
    .m_axi_bready(m_axi_bready),
    .m_axi_araddr(m_axi_araddr),
    .m_axi_arlen(m_axi_arlen),
    .m_axi_arsize(m_axi_arsize),
    .m_axi_arburst(m_axi_arburst),
    .m_axi_arvalid(m_axi_arvalid),
    .m_axi_arready(m_axi_arready),
    .m_axi_rdata(m_axi_rdata),
    .m_axi_rresp(m_axi_rresp),
    .m_axi_rlast(m_axi_rlast),
    .m_axi_rvalid(m_axi_rvalid),
    .m_axi_rready(m_axi_rready)
  );

  wb_stage u_wb_stage (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .ex_valid_i(ex_valid),
    .ex_opcode_i(ex_opcode),
    .ex_beat_i(ex_beat),
    .ex_active_mask_i(ex_active_mask),
    .ex_dst_reg_i(ex_dst_reg),
    .ex_result_i(ex_result),
    .lsu_load_valid_i(lsu_load_valid),
    .lsu_load_beat_i(lsu_load_beat),
    .lsu_load_dst_reg_i(lsu_load_dst_reg),
    .lsu_load_mask_i(lsu_load_mask),
    .lsu_load_data_i(lsu_load_data),
    .vrf_write_valid_o(wb_vrf_write_valid),
    .vrf_write_beat_o(wb_vrf_write_beat),
    .vrf_write_dst_reg_o(wb_vrf_write_dst_reg),
    .vrf_waddr_o(wb_vrf_waddr),
    .vrf_write_data_o(wb_vrf_write_data),
    .vrf_write_mask_o(wb_vrf_write_mask)
  );

  logic unused_wb_addr;
  assign unused_wb_addr = ^wb_vrf_waddr;

  always_comb begin
    fault_valid = 1'b0;
    fault_code  = AEC_FAULT_NONE;
    fault_pc    = 16'd0;
    if (id_illegal_opcode) begin
      fault_valid = 1'b1;
      fault_code  = AEC_FAULT_ILLEGAL_INSTRUCTION;
      fault_pc    = pc_q;
    end else if (simt_stack_fault) begin
      fault_valid = 1'b1;
      fault_code  = AEC_FAULT_SIMT_STACK_FAULT;
      fault_pc    = ex_pc;
    end else if (lsu_fault_valid) begin
      fault_valid = 1'b1;
      fault_code  = lsu_fault_code;
      fault_pc    = lsu_fault_pc;
    end
  end

`ifndef SYNTHESIS
  trace_logger #(
    .HALT_FINISH(TRACE_HALT_FINISH)
  ) u_trace_logger (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .pc_q(pc_q),
    .opcode_i(issue_opcode_q),
    .write_valid_i(wb_vrf_write_valid),
    .write_beat_i(wb_vrf_write_beat),
    .write_mask_i(wb_vrf_write_mask),
    .dst_reg_i(wb_vrf_write_dst_reg),
    .write_data_i(wb_vrf_write_data),
    .halt_seen_o(trace_halt_seen)
  );
`endif

endmodule

`default_nettype wire

