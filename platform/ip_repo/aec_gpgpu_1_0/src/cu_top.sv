`timescale 1ns/1ps
`default_nettype none

module cu_top #(
  parameter int AXI_ADDR_WIDTH = 64,
  parameter int AXI_DATA_WIDTH = 512,
  parameter int NUM_WARPS = 4,
  parameter int NUM_BLOCKS = 1,
  parameter bit USE_EXTERNAL_INSTR = 1'b0,
  parameter bit TRACE_HALT_FINISH = 1'b1,
  parameter int WATCHDOG_LIMIT_CYCLES = 1000000
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

  localparam logic [31:0] WATCHDOG_LIMIT_U32 = WATCHDOG_LIMIT_CYCLES;
  localparam int WARP_BITS = (NUM_WARPS <= 1) ? 1 : $clog2(NUM_WARPS);
  localparam int BLOCK_BITS = (NUM_BLOCKS <= 1) ? 1 : $clog2(NUM_BLOCKS);
  localparam int WARPS_PER_BLOCK = (NUM_BLOCKS <= 1) ? NUM_WARPS : ((NUM_WARPS + NUM_BLOCKS - 1) / NUM_BLOCKS);

  logic dec_valid;
  logic dec_ready;
  logic instr_src_valid;
  logic [127:0] instr_src_data;
  logic [9:0] imem_addr;
  logic [9:0] if_imem_addr;
  logic [127:0] imem_data;
  logic if_valid;
  logic [127:0] if_instr;
  logic [15:0] if_pc;
  logic        sched_fetch_valid;
  logic [WARP_BITS-1:0] sched_fetch_warp;
  logic [15:0] sched_fetch_pc;
  logic [31:0] sched_fetch_mask;
  logic [NUM_WARPS-1:0] sched_live_warps;
  logic [NUM_WARPS-1:0] sched_stall_mask;
  logic        sched_all_done;
  logic        sched_halt_valid;
  logic [WARP_BITS-1:0] sched_halt_warp;
  logic [31:0] sched_halt_mask;
  logic [WARP_BITS-1:0] instr_src_warp;
  logic [31:0] instr_src_mask;
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
  logic [WARP_BITS-1:0] issue_warp_q;
  logic [31:0] issue_logical_active_mask_q;
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
  logic [WARP_BITS-1:0] ex_warp;
  logic [15:0] ex_opcode;
  logic [3:0]  ex_type_code;
  logic [1:0]  ex_beat;
  logic [7:0]  ex_active_mask;
  logic [7:0]  ex_dst_reg;
  logic [7:0][31:0] ex_result;
  logic [7:0][31:0] ex_src1_data;
  logic [7:0][31:0] ex_src2_data;
  logic [7:0][31:0] ex_src3_data;
  logic [31:0] ex_src2_imm;

  logic        lsu_busy;
  logic        lsu_outstanding;
  logic        lsu_load_valid;
  logic [WARP_BITS-1:0] lsu_load_warp;
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
  logic [WARP_BITS-1:0] branch_warp;
  logic [15:0] branch_target;
  logic [31:0] branch_mask;
  logic        simt_stack_fault;
  logic        pipeline_flush;
  logic [2:0]  issue_pred_reg_q;
  logic [15:0] issue_pred_ctrl_q;
  logic        issue_pred_negate_q;
  logic        issue_pred_enable_q;
  logic [3:0]  issue_pred_sel_q;
  logic        issue_imm_en_q;
  logic [2:0]  issue_subop_q;
  logic [3:0]  issue_type_code_q;
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
  logic [31:0] fault_meta;
  logic [31:0] watchdog_count_q;
  logic        watchdog_fault;
  logic        lsu_fault_valid;
  aec_fault_e lsu_fault_code;
  logic [15:0] lsu_fault_pc;
  logic        mma_start;
  logic        mma_busy;
  logic        mma_done;
  logic        mma_vrf_read_enable;
  logic [WARP_BITS-1:0] mma_warp_q;
  logic [1:0]  mma_vrf_read_beat;
  logic [7:0]  mma_vrf_read_reg1;
  logic [7:0]  mma_vrf_read_reg2;
  logic [7:0]  mma_vrf_read_reg3;
  logic        mma_vrf_write_valid;
  logic [1:0]  mma_vrf_write_beat;
  logic [7:0]  mma_vrf_write_reg;
  logic [7:0][31:0] mma_vrf_write_data;
  logic [7:0]  mma_vrf_write_mask;
  logic        mma_fault_valid;
  aec_fault_e mma_fault_code;
  logic [15:0] mma_fault_pc;
  logic        issue_is_mma;
  logic        issue_is_fpu;
  logic        issue_is_sfu;
  logic        issue_is_collective;
  logic        fpu_start;
  logic        fpu_busy;
  logic        fpu_vrf_write_valid;
  logic [WARP_BITS-1:0] fpu_vrf_write_warp;
  logic [1:0]  fpu_vrf_write_beat;
  logic [7:0]  fpu_vrf_write_reg;
  logic [7:0][31:0] fpu_vrf_write_data;
  logic [7:0]  fpu_vrf_write_mask;
  logic [7:0][31:0] fpu_src2_data;
  logic        sfu_start;
  logic        sfu_busy;
  logic        sfu_vrf_write_valid;
  logic [WARP_BITS-1:0] sfu_vrf_write_warp;
  logic [1:0]  sfu_vrf_write_beat;
  logic [7:0]  sfu_vrf_write_reg;
  logic [7:0][31:0] sfu_vrf_write_data;
  logic [7:0]  sfu_vrf_write_mask;
  logic        coll_start;
  logic        coll_busy;
  logic        coll_vrf_read_enable;
  logic [WARP_BITS-1:0] coll_vrf_read_warp;
  logic [1:0]  coll_vrf_read_beat;
  logic [7:0]  coll_vrf_read_reg1;
  logic [7:0]  coll_vrf_read_reg2;
  logic [7:0]  coll_vrf_read_reg3;
  logic        coll_vrf_write_valid;
  logic [WARP_BITS-1:0] coll_vrf_write_warp;
  logic [1:0]  coll_vrf_write_beat;
  logic [7:0]  coll_vrf_write_reg;
  logic [7:0][31:0] coll_vrf_write_data;
  logic [7:0]  coll_vrf_write_mask;
  logic        accel_vrf_read_enable;
  logic [WARP_BITS-1:0] accel_vrf_read_warp;
  logic [1:0]  accel_vrf_read_beat;
  logic [7:0]  accel_vrf_read_reg1;
  logic [7:0]  accel_vrf_read_reg2;
  logic [7:0]  accel_vrf_read_reg3;
  logic        accel_vrf_write_valid;
  logic [WARP_BITS-1:0] accel_vrf_write_warp;
  logic [1:0]  accel_vrf_write_beat;
  logic [7:0]  accel_vrf_write_reg;
  logic [7:0][31:0] accel_vrf_write_data;
  logic [7:0]  accel_vrf_write_mask;
  logic        trace_write_valid;
  logic [1:0]  trace_write_beat;
  logic [7:0]  trace_write_mask;
  logic [7:0]  trace_write_dst_reg;
  logic [7:0][31:0] trace_write_data;
  logic [WARP_BITS-1:0] wb_vrf_write_warp;
  logic        scoreboard_hazard;
  logic        scoreboard_mark_valid;
  logic [3:0]  scoreboard_mark_count;
  logic        scoreboard_clear_valid;
  logic [WARP_BITS-1:0] scoreboard_clear_warp;
  logic [7:0]  scoreboard_clear_reg;
  logic [3:0]  scoreboard_clear_count;
  logic        barrier_arrive_valid;
  logic [BLOCK_BITS-1:0] barrier_arrive_block;
  logic [2:0]  barrier_id;
  logic [15:0] barrier_expected_warps;
  logic        barrier_release_valid;
  logic [NUM_WARPS-1:0] barrier_release_warps;
  logic        barrier_deadlock_fault;
  logic [NUM_WARPS-1:0] barrier_stalled_q;
  logic        fence_arrive_valid;
  logic [NUM_WARPS-1:0] fence_stalled_q;

  function automatic logic [BLOCK_BITS-1:0] warp_to_block(input logic [WARP_BITS-1:0] warp_id);
    begin
      if (NUM_BLOCKS <= 1) begin
        warp_to_block = '0;
      end else begin
        warp_to_block = warp_id / WARPS_PER_BLOCK;
      end
    end
  endfunction

  function automatic logic opcode_writes_scoreboard(input logic [15:0] opcode, input logic [3:0] type_code);
    begin
      opcode_writes_scoreboard = 1'b0;
      unique case (aec_opcode_e'(opcode))
        AEC_OP_ADD,
        AEC_OP_SUB,
        AEC_OP_MUL,
        AEC_OP_MAD,
        AEC_OP_FMA,
        AEC_OP_AND,
        AEC_OP_OR,
        AEC_OP_XOR,
        AEC_OP_SHL,
        AEC_OP_SHR,
        AEC_OP_MOV,
        AEC_OP_LOADI,
        AEC_OP_LD,
        AEC_OP_SFU,
        AEC_OP_SHFL,
        AEC_OP_REDUCE,
        AEC_OP_MMA: opcode_writes_scoreboard = 1'b1;
        default:    opcode_writes_scoreboard = 1'b0;
      endcase
      if (type_code == 4'h0) begin
        opcode_writes_scoreboard = opcode_writes_scoreboard;
      end
    end
  endfunction

  assign gpu_done_pulse = USE_EXTERNAL_INSTR ?
      (ex_valid && (aec_opcode_e'(ex_opcode) == AEC_OP_HALT) && (ex_beat == 2'd0)) :
      (gpu_running_q && sched_all_done);
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
    .fault_meta_i(fault_meta),
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

  assign imem_addr = USE_EXTERNAL_INSTR ? if_imem_addr : sched_fetch_pc[9:0];

  if_stage u_if_stage (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .imem_addr_o(if_imem_addr),
    .imem_data_i(imem_data),
    .branch_taken_i(branch_taken),
    .branch_target_i(branch_target),
    .flush_i(pipeline_flush),
    .enable_i(if_enable && USE_EXTERNAL_INSTR),
    .start_i(csr_start_pulse && !USE_EXTERNAL_INSTR),
    .start_pc_i(csr_start_pc),
    .if_valid_o(if_valid),
    .if_ready_i(dec_ready && active_mask_ready_q),
    .instr_o(if_instr),
    .pc_o(if_pc)
  );

  warp_scheduler #(
    .NUM_WARPS(NUM_WARPS)
  ) u_warp_scheduler (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .start_i(csr_start_pulse && !USE_EXTERNAL_INSTR),
    .start_pc_i(csr_start_pc),
    .start_mask_i(warp_active_mask_i),
    .issue_ready_i(accept_dec && !USE_EXTERNAL_INSTR),
    .branch_valid_i(branch_taken && !USE_EXTERNAL_INSTR),
    .branch_warp_i(branch_warp),
    .branch_pc_i(branch_target),
    .branch_mask_i(branch_mask),
    .halt_valid_i(sched_halt_valid),
    .halt_warp_i(sched_halt_warp),
    .halt_mask_i(sched_halt_mask),
    .warp_stall_mask_i(sched_stall_mask),
    .fetch_valid_o(sched_fetch_valid),
    .fetch_warp_o(sched_fetch_warp),
    .fetch_pc_o(sched_fetch_pc),
    .fetch_active_mask_o(sched_fetch_mask),
    .live_warps_o(sched_live_warps),
    .all_warps_done_o(sched_all_done)
  );

  always_comb begin
    if (USE_EXTERNAL_INSTR) begin
      instr_src_valid = instr_valid_i;
      instr_src_data  = instr_i;
      instr_src_warp  = '0;
      instr_src_mask  = current_active_mask_q;
      pc_q            = 16'd0;
    end else begin
      instr_src_valid = sched_fetch_valid && gpu_running_q;
      instr_src_data  = imem_data;
      instr_src_warp  = sched_fetch_warp;
      instr_src_mask  = sched_fetch_mask;
      pc_q            = sched_fetch_pc;
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
    .dec_valid_i(dec_valid && !id_illegal_opcode && !scoreboard_hazard),
    .dec_ready_o(dec_ready),
    .logical_active_mask_i(instr_src_mask),
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
  assign issue_is_mma = (aec_opcode_e'(issue_opcode_q) == AEC_OP_MMA);
  assign issue_is_fpu =
      (((aec_opcode_e'(issue_opcode_q) == AEC_OP_ADD) ||
        (aec_opcode_e'(issue_opcode_q) == AEC_OP_SUB) ||
        (aec_opcode_e'(issue_opcode_q) == AEC_OP_MUL) ||
        (aec_opcode_e'(issue_opcode_q) == AEC_OP_MAD) ||
        (aec_opcode_e'(issue_opcode_q) == AEC_OP_FMA)) && (issue_type_code_q == 4'h8));
  assign issue_is_collective =
      (aec_opcode_e'(issue_opcode_q) == AEC_OP_SHFL) ||
      (aec_opcode_e'(issue_opcode_q) == AEC_OP_REDUCE);
  assign issue_is_sfu = (aec_opcode_e'(issue_opcode_q) == AEC_OP_SFU);
  assign mma_start = issue_fire && issue_is_mma && (issue_beat == 2'd0);
  assign fpu_start = issue_fire && issue_is_fpu;
  assign sfu_start = issue_fire && issue_is_sfu;
  assign coll_start = issue_fire && issue_is_collective && (issue_beat == 2'd0);
  assign issue_ready_eff = issue_ready_i && !lsu_busy && !ex_is_lsu_op &&
      !mma_busy && !fpu_busy && !sfu_busy && !coll_busy;
  assign issue_fire = issue_valid && issue_ready_eff;
  assign accept_dec = dec_valid && !id_illegal_opcode && !scoreboard_hazard &&
      dec_ready && active_mask_ready_q && !pipeline_flush;
  assign instr_ready_o = USE_EXTERNAL_INSTR ? (dec_ready && active_mask_ready_q) : 1'b0;
  assign issue_valid_o = issue_valid;
  assign issue_beat_o = issue_beat;
  assign physical_active_mask_o = issue_active_mask;

  assign decoded_opcode_o   = decoded_opcode;
  assign decoded_dst_reg_o  = dst_reg;
  assign decoded_src1_reg_o = src1_reg;
  assign decoded_src2_reg_o = src2_reg;
  assign decoded_src3_reg_o = src3_reg;

  assign scoreboard_mark_valid = accept_dec &&
      opcode_writes_scoreboard(decoded_opcode, pred_ctrl[6:3]);
  assign scoreboard_mark_count = (aec_opcode_e'(decoded_opcode) == AEC_OP_MMA) ? 4'd8 : 4'd1;

  always_comb begin
    scoreboard_clear_valid = 1'b0;
    scoreboard_clear_warp  = wb_vrf_write_warp;
    scoreboard_clear_reg   = wb_vrf_write_dst_reg;
    scoreboard_clear_count = 4'd1;
    if (lsu_load_valid) begin
      scoreboard_clear_valid = 1'b1;
      scoreboard_clear_warp  = lsu_load_warp;
      scoreboard_clear_reg   = lsu_load_dst_reg;
      scoreboard_clear_count = 4'd1;
    end else if (wb_vrf_write_valid && (wb_vrf_write_beat == 2'd3)) begin
      scoreboard_clear_valid = 1'b1;
      scoreboard_clear_warp  = wb_vrf_write_warp;
      scoreboard_clear_reg   = wb_vrf_write_dst_reg;
      scoreboard_clear_count = 4'd1;
    end
    if (accel_vrf_write_valid) begin
      scoreboard_clear_valid = 1'b1;
      scoreboard_clear_warp  = accel_vrf_write_warp;
      scoreboard_clear_reg   = accel_vrf_write_reg;
      scoreboard_clear_count = 4'd1;
    end
  end

  scoreboard #(
    .NUM_WARPS(NUM_WARPS)
  ) u_scoreboard (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .clear_i(csr_start_pulse || fault_valid || gpu_done_pulse),
    .check_valid_i(dec_valid && !id_illegal_opcode),
    .check_warp_i(instr_src_warp),
    .check_opcode_i(decoded_opcode),
    .check_type_code_i(pred_ctrl[6:3]),
    .check_imm_en_i(pred_ctrl[7]),
    .check_src1_reg_i(src1_reg),
    .check_src2_reg_i(src2_reg),
    .check_src3_reg_i(src3_reg),
    .check_dst_reg_i(dst_reg),
    .hazard_o(scoreboard_hazard),
    .mark_valid_i(scoreboard_mark_valid),
    .mark_warp_i(instr_src_warp),
    .mark_reg_i(dst_reg),
    .mark_count_i(scoreboard_mark_count),
    .clear_valid_i(scoreboard_clear_valid),
    .clear_warp_i(scoreboard_clear_warp),
    .clear_reg_i(scoreboard_clear_reg),
    .clear_count_i(scoreboard_clear_count)
  );

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      mma_warp_q <= '0;
    end else if (mma_start) begin
      mma_warp_q <= issue_warp_q;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      issue_opcode_q   <= AEC_OP_NOP;
      issue_dst_reg_q  <= 8'd0;
      issue_src1_reg_q <= 8'd0;
      issue_src2_reg_q <= 8'd0;
      issue_src3_reg_q <= 8'd0;
      issue_src1_sel_q <= 16'd0;
      issue_pred_reg_q <= 3'd0;
      issue_pred_ctrl_q <= 16'd0;
      issue_pred_negate_q <= 1'b0;
      issue_pred_enable_q <= 1'b0;
      issue_pred_sel_q <= 4'hf;
      issue_imm_en_q <= 1'b0;
      issue_subop_q <= 3'd0;
      issue_type_code_q <= 4'd0;
      issue_src2_imm_q <= 32'd0;
      issue_src3_imm_q <= 32'd0;
      issue_pc_q       <= 16'd0;
      issue_warp_q     <= '0;
      issue_logical_active_mask_q <= 32'd0;
    end else if (pipeline_flush) begin
      issue_opcode_q   <= AEC_OP_NOP;
      issue_dst_reg_q  <= 8'd0;
      issue_src1_reg_q <= 8'd0;
      issue_src2_reg_q <= 8'd0;
      issue_src3_reg_q <= 8'd0;
      issue_src1_sel_q <= 16'd0;
      issue_pred_reg_q <= 3'd0;
      issue_pred_ctrl_q <= 16'd0;
      issue_pred_negate_q <= 1'b0;
      issue_pred_enable_q <= 1'b0;
      issue_pred_sel_q <= 4'hf;
      issue_imm_en_q <= 1'b0;
      issue_subop_q <= 3'd0;
      issue_type_code_q <= 4'd0;
      issue_src2_imm_q <= 32'd0;
      issue_src3_imm_q <= 32'd0;
      issue_pc_q       <= 16'd0;
      issue_warp_q     <= '0;
      issue_logical_active_mask_q <= 32'd0;
    end else if (accept_dec) begin
      issue_opcode_q   <= decoded_opcode;
      issue_dst_reg_q  <= dst_reg;
      issue_src1_reg_q <= src1_reg;
      issue_src2_reg_q <= src2_reg;
      issue_src3_reg_q <= src3_reg;
      issue_src1_sel_q <= src1;
      issue_pred_reg_q <= pred_reg;
      issue_pred_ctrl_q <= pred_ctrl;
      issue_pred_negate_q <= pred_negate;
      issue_pred_enable_q <= pred_enable;
      issue_pred_sel_q <= pred_sel;
      issue_imm_en_q <= pred_ctrl[7];
      issue_subop_q <= pred_ctrl[10:8];
      issue_type_code_q <= pred_ctrl[6:3];
      issue_src2_imm_q <= src2;
      issue_src3_imm_q <= src3;
      issue_pc_q       <= pc_q;
      issue_warp_q     <= instr_src_warp;
      issue_logical_active_mask_q <= instr_src_mask;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      current_active_mask_q <= 32'd0;
      active_mask_ready_q   <= 1'b0;
    end else if (csr_start_pulse || !active_mask_ready_q) begin
      current_active_mask_q <= warp_active_mask_i;
      active_mask_ready_q   <= csr_start_pulse || USE_EXTERNAL_INSTR;
    end else if (USE_EXTERNAL_INSTR && branch_taken) begin
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

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      watchdog_count_q <= 32'd0;
    end else if (csr_start_pulse || gpu_done_pulse || fault_valid || !gpu_running_q) begin
      watchdog_count_q <= 32'd0;
    end else if (gpu_running_q && (watchdog_count_q < WATCHDOG_LIMIT_U32)) begin
      watchdog_count_q <= watchdog_count_q + 32'd1;
    end
  end

  assign watchdog_fault = gpu_running_q && (watchdog_count_q >= WATCHDOG_LIMIT_U32);

  prf_top #(
    .NUM_WARPS(NUM_WARPS)
  ) u_prf_top (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .read_warp_i(issue_warp_q),
    .read_beat_i(issue_beat),
    .read_pred1_i(issue_pred_sel_q),
    .read_pred2_i(4'hf),
    .read_pred3_i(4'hf),
    .read_mask1_o(issue_predicate_mask),
    .read_mask2_o(),
    .read_mask3_o(),
    .write_valid_i(prf_write_valid),
    .write_warp_i(ex_warp),
    .write_beat_i(prf_write_beat),
    .write_pred_i(prf_write_pred),
    .write_data_i(prf_write_data),
    .write_mask_i(prf_write_mask)
  );

  always_comb begin
    accel_vrf_read_enable = mma_vrf_read_enable;
    accel_vrf_read_warp   = mma_warp_q;
    accel_vrf_read_beat   = mma_vrf_read_beat;
    accel_vrf_read_reg1   = mma_vrf_read_reg1;
    accel_vrf_read_reg2   = mma_vrf_read_reg2;
    accel_vrf_read_reg3   = mma_vrf_read_reg3;
    if (coll_vrf_read_enable) begin
      accel_vrf_read_enable = 1'b1;
      accel_vrf_read_warp   = coll_vrf_read_warp;
      accel_vrf_read_beat   = coll_vrf_read_beat;
      accel_vrf_read_reg1   = coll_vrf_read_reg1;
      accel_vrf_read_reg2   = coll_vrf_read_reg2;
      accel_vrf_read_reg3   = coll_vrf_read_reg3;
    end

    accel_vrf_write_valid = mma_vrf_write_valid;
    accel_vrf_write_warp  = mma_warp_q;
    accel_vrf_write_beat  = mma_vrf_write_beat;
    accel_vrf_write_reg   = mma_vrf_write_reg;
    accel_vrf_write_data  = mma_vrf_write_data;
    accel_vrf_write_mask  = mma_vrf_write_mask;
    if (!mma_vrf_write_valid && fpu_vrf_write_valid) begin
      accel_vrf_write_valid = 1'b1;
      accel_vrf_write_warp  = fpu_vrf_write_warp;
      accel_vrf_write_beat  = fpu_vrf_write_beat;
      accel_vrf_write_reg   = fpu_vrf_write_reg;
      accel_vrf_write_data  = fpu_vrf_write_data;
      accel_vrf_write_mask  = fpu_vrf_write_mask;
    end else if (!mma_vrf_write_valid && !fpu_vrf_write_valid && sfu_vrf_write_valid) begin
      accel_vrf_write_valid = 1'b1;
      accel_vrf_write_warp  = sfu_vrf_write_warp;
      accel_vrf_write_beat  = sfu_vrf_write_beat;
      accel_vrf_write_reg   = sfu_vrf_write_reg;
      accel_vrf_write_data  = sfu_vrf_write_data;
      accel_vrf_write_mask  = sfu_vrf_write_mask;
    end else if (!mma_vrf_write_valid && !fpu_vrf_write_valid &&
        !sfu_vrf_write_valid && coll_vrf_write_valid) begin
      accel_vrf_write_valid = 1'b1;
      accel_vrf_write_warp  = coll_vrf_write_warp;
      accel_vrf_write_beat  = coll_vrf_write_beat;
      accel_vrf_write_reg   = coll_vrf_write_reg;
      accel_vrf_write_data  = coll_vrf_write_data;
      accel_vrf_write_mask  = coll_vrf_write_mask;
    end
  end

  always_comb begin
    fpu_src2_data = vrf_src2_data;
    if (issue_imm_en_q) begin
      for (int fpu_lane = 0; fpu_lane < PHYSICAL_SIMD_LANES; fpu_lane = fpu_lane + 1) begin
        fpu_src2_data[fpu_lane] = issue_src2_imm_q;
      end
    end
  end

  (* keep_hierarchy = "yes", dont_touch = "yes" *) vrf_top #(
    .NUM_WARPS(NUM_WARPS)
  ) u_vrf_top (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .issue_warp_i(issue_warp_q),
    .issue_beat_i(issue_beat),
    .src1_reg_i(issue_src1_reg_q),
    .src2_reg_i(issue_src2_reg_q),
    .src3_reg_i(issue_src3_reg_q),
    .src1_data_o(vrf_src1_data),
    .src2_data_o(vrf_src2_data),
    .src3_data_o(vrf_src3_data),
    .mma_read_enable_i(accel_vrf_read_enable),
    .mma_read_warp_i(accel_vrf_read_warp),
    .mma_read_beat_i(accel_vrf_read_beat),
    .mma_read_reg1_i(accel_vrf_read_reg1),
    .mma_read_reg2_i(accel_vrf_read_reg2),
    .mma_read_reg3_i(accel_vrf_read_reg3),
    .write_valid_i(wb_vrf_write_valid),
    .write_warp_i(wb_vrf_write_warp),
    .write_beat_i(wb_vrf_write_beat),
    .dst_reg_i(wb_vrf_write_dst_reg),
    .write_data_i(wb_vrf_write_data),
    .write_mask_i(wb_vrf_write_mask),
    .mma_write_valid_i(accel_vrf_write_valid),
    .mma_write_warp_i(accel_vrf_write_warp),
    .mma_write_beat_i(accel_vrf_write_beat),
    .mma_write_reg_i(accel_vrf_write_reg),
    .mma_write_data_i(accel_vrf_write_data),
    .mma_write_mask_i(accel_vrf_write_mask)
  );

  mma_core u_mma_core (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .start_i(mma_start),
    .pc_i(issue_pc_q),
    .pred_ctrl_i(issue_pred_ctrl_q),
    .logical_active_mask_i(issue_logical_active_mask_q),
    .pred_enable_i(issue_pred_enable_q),
    .d_base_i({8'd0, issue_dst_reg_q}),
    .a_base_i(issue_src1_sel_q),
    .b_base_i(issue_src2_imm_q),
    .c_base_i(issue_src3_imm_q),
    .busy_o(mma_busy),
    .done_o(mma_done),
    .vrf_read_enable_o(mma_vrf_read_enable),
    .vrf_read_beat_o(mma_vrf_read_beat),
    .vrf_read_reg1_o(mma_vrf_read_reg1),
    .vrf_read_reg2_o(mma_vrf_read_reg2),
    .vrf_read_reg3_o(mma_vrf_read_reg3),
    .vrf_read_data1_i(vrf_src1_data),
    .vrf_read_data2_i(vrf_src2_data),
    .vrf_read_data3_i(vrf_src3_data),
    .vrf_write_valid_o(mma_vrf_write_valid),
    .vrf_write_beat_o(mma_vrf_write_beat),
    .vrf_write_reg_o(mma_vrf_write_reg),
    .vrf_write_data_o(mma_vrf_write_data),
    .vrf_write_mask_o(mma_vrf_write_mask),
    .fault_valid_o(mma_fault_valid),
    .fault_code_o(mma_fault_code),
    .fault_pc_o(mma_fault_pc)
  );

  fpu_core #(
    .NUM_WARPS(NUM_WARPS)
  ) u_fpu_core (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .start_i(fpu_start),
    .warp_i(issue_warp_q),
    .opcode_i(issue_opcode_q),
    .type_code_i(issue_type_code_q),
    .beat_i(issue_beat),
    .active_mask_i(issue_active_mask & issue_predicate_mask),
    .dst_reg_i(issue_dst_reg_q),
    .src1_data_i(vrf_src1_data),
    .src2_data_i(fpu_src2_data),
    .src3_data_i(vrf_src3_data),
    .busy_o(fpu_busy),
    .write_valid_o(fpu_vrf_write_valid),
    .write_warp_o(fpu_vrf_write_warp),
    .write_beat_o(fpu_vrf_write_beat),
    .write_reg_o(fpu_vrf_write_reg),
    .write_data_o(fpu_vrf_write_data),
    .write_mask_o(fpu_vrf_write_mask)
  );

  sfu_core #(
    .NUM_WARPS(NUM_WARPS),
    .COMPUTE_LATENCY(8)
  ) u_sfu_core (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .start_i(sfu_start),
    .warp_i(issue_warp_q),
    .subop_i(issue_subop_q),
    .beat_i(issue_beat),
    .active_mask_i(issue_active_mask & issue_predicate_mask),
    .dst_reg_i(issue_dst_reg_q),
    .src_data_i(vrf_src1_data),
    .busy_o(sfu_busy),
    .write_valid_o(sfu_vrf_write_valid),
    .write_warp_o(sfu_vrf_write_warp),
    .write_beat_o(sfu_vrf_write_beat),
    .write_reg_o(sfu_vrf_write_reg),
    .write_data_o(sfu_vrf_write_data),
    .write_mask_o(sfu_vrf_write_mask)
  );

  warp_collective_core #(
    .NUM_WARPS(NUM_WARPS)
  ) u_warp_collective_core (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .start_i(coll_start),
    .warp_i(issue_warp_q),
    .opcode_i(issue_opcode_q),
    .subop_i(issue_subop_q),
    .type_code_i(issue_type_code_q),
    .imm_en_i(issue_imm_en_q),
    .logical_active_mask_i(issue_logical_active_mask_q),
    .dst_reg_i(issue_dst_reg_q),
    .src1_reg_i(issue_src1_reg_q),
    .src2_reg_i(issue_src2_reg_q),
    .src2_imm_i(issue_src2_imm_q),
    .busy_o(coll_busy),
    .vrf_read_enable_o(coll_vrf_read_enable),
    .vrf_read_warp_o(coll_vrf_read_warp),
    .vrf_read_beat_o(coll_vrf_read_beat),
    .vrf_read_reg1_o(coll_vrf_read_reg1),
    .vrf_read_reg2_o(coll_vrf_read_reg2),
    .vrf_read_reg3_o(coll_vrf_read_reg3),
    .vrf_read_data1_i(vrf_src1_data),
    .vrf_read_data2_i(vrf_src2_data),
    .vrf_write_valid_o(coll_vrf_write_valid),
    .vrf_write_warp_o(coll_vrf_write_warp),
    .vrf_write_beat_o(coll_vrf_write_beat),
    .vrf_write_reg_o(coll_vrf_write_reg),
    .vrf_write_data_o(coll_vrf_write_data),
    .vrf_write_mask_o(coll_vrf_write_mask)
  );

  ex_stage #(
    .NUM_WARPS(NUM_WARPS)
  ) u_ex_stage (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .issue_valid_i(issue_fire),
    .issue_warp_i(issue_warp_q),
    .issue_opcode_i(issue_opcode_q),
    .issue_beat_i(issue_beat),
    .physical_active_mask_i(issue_active_mask),
    .dst_reg_i(issue_dst_reg_q),
    .src1_sel_i(issue_src1_sel_q),
    .imm_en_i(issue_imm_en_q),
    .subop_i(issue_subop_q),
    .type_code_i(issue_type_code_q),
    .pred_reg_i(issue_pred_reg_q),
    .pred_negate_i(issue_pred_negate_q),
    .pred_enable_i(issue_pred_enable_q),
    .predicate_mask_i(issue_predicate_mask),
    .logical_active_mask_i(issue_logical_active_mask_q),
    .issue_pc_i(issue_pc_q),
    .src2_imm_i(issue_src2_imm_q),
    .src3_imm_i(issue_src3_imm_q),
    .src1_data_i(vrf_src1_data),
    .src2_data_i(vrf_src2_data),
    .src3_data_i(vrf_src3_data),
    .ex_valid_o(ex_valid),
    .ex_warp_o(ex_warp),
    .ex_opcode_o(ex_opcode),
    .ex_type_code_o(ex_type_code),
    .ex_beat_o(ex_beat),
    .ex_active_mask_o(ex_active_mask),
    .ex_dst_reg_o(ex_dst_reg),
    .ex_pc_o(ex_pc),
    .ex_result_o(ex_result),
    .ex_src1_data_o(ex_src1_data),
    .ex_src2_data_o(ex_src2_data),
    .ex_src3_data_o(ex_src3_data),
    .ex_src2_imm_o(ex_src2_imm),
    .prf_write_valid_o(prf_write_valid),
    .prf_write_beat_o(prf_write_beat),
    .prf_write_pred_o(prf_write_pred),
    .prf_write_data_o(prf_write_data),
    .prf_write_mask_o(prf_write_mask),
    .branch_taken_o(branch_taken),
    .branch_warp_o(branch_warp),
    .branch_target_o(branch_target),
    .branch_mask_o(branch_mask),
    .simt_stack_fault_o(simt_stack_fault)
  );

  assign barrier_arrive_valid = !USE_EXTERNAL_INSTR && ex_valid && (ex_beat == 2'd0) &&
      (aec_opcode_e'(ex_opcode) == AEC_OP_BAR_SYNC);
  assign barrier_arrive_block = warp_to_block(ex_warp);
  assign barrier_id = ex_dst_reg[2:0];
  assign barrier_expected_warps = ex_src2_imm[15:0];
  assign fence_arrive_valid = !USE_EXTERNAL_INSTR && ex_valid && (ex_beat == 2'd0) &&
      (aec_opcode_e'(ex_opcode) == AEC_OP_FENCE);
  assign sched_stall_mask = barrier_stalled_q | fence_stalled_q;

  barrier_unit #(
    .NUM_WARPS(NUM_WARPS),
    .NUM_BLOCKS(NUM_BLOCKS),
    .NUM_BARRIERS(8)
  ) u_barrier_unit (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .clear_i(csr_start_pulse || fault_valid || gpu_done_pulse),
    .arrive_valid_i(barrier_arrive_valid),
    .arrive_warp_i(ex_warp),
    .arrive_block_i(barrier_arrive_block),
    .barrier_id_i(barrier_id),
    .expected_warps_i(barrier_expected_warps),
    .live_warps_i(sched_live_warps),
    .release_valid_o(barrier_release_valid),
    .release_warps_o(barrier_release_warps),
    .deadlock_fault_o(barrier_deadlock_fault)
  );

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      barrier_stalled_q <= '0;
    end else if (csr_start_pulse || fault_valid || gpu_done_pulse) begin
      barrier_stalled_q <= '0;
    end else begin
      barrier_stalled_q <= (barrier_stalled_q |
          (barrier_arrive_valid ? ({{(NUM_WARPS-1){1'b0}}, 1'b1} << ex_warp) : '0)) &
          ~(barrier_release_valid ? barrier_release_warps : '0);
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      fence_stalled_q <= '0;
    end else if (csr_start_pulse || fault_valid || gpu_done_pulse) begin
      fence_stalled_q <= '0;
    end else begin
      fence_stalled_q <= fence_stalled_q & {NUM_WARPS{lsu_outstanding}};
      if (fence_arrive_valid && lsu_outstanding) begin
        fence_stalled_q[ex_warp] <= 1'b1;
      end
    end
  end

  lsu #(
    .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
    .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
    .NUM_WARPS(NUM_WARPS)
  ) u_lsu (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .ex_valid_i(ex_valid),
    .ex_warp_i(ex_warp),
    .ex_opcode_i(ex_opcode),
    .ex_beat_i(ex_beat),
    .ex_pc_i(ex_pc),
    .ex_active_mask_i(ex_active_mask),
    .ex_dst_reg_i(ex_dst_reg),
    .ex_src1_data_i(ex_src1_data),
    .ex_src2_data_i(ex_src2_data),
    .ex_src3_data_i(ex_src3_data),
    .busy_o(lsu_busy),
    .outstanding_o(lsu_outstanding),
    .load_valid_o(lsu_load_valid),
    .load_warp_o(lsu_load_warp),
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

  wb_stage #(
    .NUM_WARPS(NUM_WARPS)
  ) u_wb_stage (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .ex_valid_i(ex_valid),
    .ex_warp_i(ex_warp),
    .ex_opcode_i(ex_opcode),
    .ex_type_code_i(ex_type_code),
    .ex_beat_i(ex_beat),
    .ex_active_mask_i(ex_active_mask),
    .ex_dst_reg_i(ex_dst_reg),
    .ex_result_i(ex_result),
    .lsu_load_valid_i(lsu_load_valid),
    .lsu_load_warp_i(lsu_load_warp),
    .lsu_load_beat_i(lsu_load_beat),
    .lsu_load_dst_reg_i(lsu_load_dst_reg),
    .lsu_load_mask_i(lsu_load_mask),
    .lsu_load_data_i(lsu_load_data),
    .vrf_write_valid_o(wb_vrf_write_valid),
    .vrf_write_warp_o(wb_vrf_write_warp),
    .vrf_write_beat_o(wb_vrf_write_beat),
    .vrf_write_dst_reg_o(wb_vrf_write_dst_reg),
    .vrf_waddr_o(wb_vrf_waddr),
    .vrf_write_data_o(wb_vrf_write_data),
    .vrf_write_mask_o(wb_vrf_write_mask)
  );

  logic unused_wb_addr;
  assign unused_wb_addr = ^wb_vrf_waddr;

  always_comb begin
    sched_halt_valid = !USE_EXTERNAL_INSTR && ex_valid && (aec_opcode_e'(ex_opcode) == AEC_OP_HALT);
    sched_halt_warp  = ex_warp;
    sched_halt_mask  = 32'd0;
    sched_halt_mask[ex_beat * PHYSICAL_SIMD_LANES +: PHYSICAL_SIMD_LANES] = ex_active_mask;
  end

  always_comb begin
    trace_write_valid   = wb_vrf_write_valid;
    trace_write_beat    = wb_vrf_write_beat;
    trace_write_mask    = wb_vrf_write_mask;
    trace_write_dst_reg = wb_vrf_write_dst_reg;
    trace_write_data    = wb_vrf_write_data;
    if (accel_vrf_write_valid) begin
      trace_write_valid   = 1'b1;
      trace_write_beat    = accel_vrf_write_beat;
      trace_write_mask    = accel_vrf_write_mask;
      trace_write_dst_reg = accel_vrf_write_reg;
      trace_write_data    = accel_vrf_write_data;
    end
  end

  always_comb begin
    fault_valid = 1'b0;
    fault_code  = AEC_FAULT_NONE;
    fault_pc    = 16'd0;
    fault_meta  = 32'd0;
    if (id_illegal_opcode) begin
      fault_valid = 1'b1;
      fault_code  = AEC_FAULT_ILLEGAL_INSTRUCTION;
      fault_pc    = pc_q;
    end else if (mma_fault_valid) begin
      fault_valid = 1'b1;
      fault_code  = mma_fault_code;
      fault_pc    = mma_fault_pc;
    end else if (simt_stack_fault) begin
      fault_valid = 1'b1;
      fault_code  = AEC_FAULT_SIMT_STACK_FAULT;
      fault_pc    = ex_pc;
    end else if (barrier_deadlock_fault) begin
      fault_valid = 1'b1;
      fault_code  = AEC_FAULT_BARRIER_DEADLOCK;
      fault_pc    = ex_pc;
      fault_meta  = {29'd0, barrier_id};
    end else if (lsu_fault_valid) begin
      fault_valid = 1'b1;
      fault_code  = lsu_fault_code;
      fault_pc    = lsu_fault_pc;
    end else if (watchdog_fault) begin
      fault_valid = 1'b1;
      fault_code  = AEC_FAULT_WATCHDOG_TIMEOUT;
      fault_pc    = pc_q;
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
    .write_valid_i(trace_write_valid),
    .write_beat_i(trace_write_beat),
    .write_mask_i(trace_write_mask),
    .dst_reg_i(trace_write_dst_reg),
    .write_data_i(trace_write_data),
    .halt_seen_o(trace_halt_seen)
  );
`endif

endmodule

`default_nettype wire

