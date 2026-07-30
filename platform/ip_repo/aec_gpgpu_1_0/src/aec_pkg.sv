`ifndef AEC_PKG_SV
`define AEC_PKG_SV
`timescale 1ns/1ps

package aec_pkg;
  parameter int LOGICAL_WARP_WIDTH = 32;
  parameter int PHYSICAL_SIMD_LANES = 8;
  parameter int ISSUE_BEATS        = 4;

  parameter int INSTR_WIDTH_BITS = 128;
  parameter int REG_INDEX_BITS   = 8;
  parameter int PRED_INDEX_BITS  = 3;

  parameter logic [15:0] AEC_CSR_CTRL_ADDR       = 16'h0000;
  parameter logic [15:0] AEC_CSR_PC_ADDR         = 16'h0004;
  parameter logic [15:0] AEC_CSR_STATUS_ADDR     = 16'h0008;
  parameter logic [15:0] AEC_CSR_FAULT_CODE_ADDR = 16'h000c;
  parameter logic [15:0] AEC_CSR_FAULT_PC_ADDR   = 16'h0010;
  parameter logic [15:0] AEC_CSR_FAULT_META_ADDR = 16'h0014;
  parameter logic [15:0] AEC_CSR_CAP_MAGIC_ADDR   = 16'h0020;
  parameter logic [15:0] AEC_CSR_CAP_VERSION_ADDR = 16'h0024;
  parameter logic [15:0] AEC_CSR_CAP_GEOMETRY_ADDR = 16'h0028;
  parameter logic [15:0] AEC_CSR_CAP_FEATURES_ADDR = 16'h002c;
  parameter logic [15:0] AEC_CSR_CAP_LIMITS_ADDR  = 16'h0030;
  parameter logic [15:0] AEC_CSR_CAP_MEMORY_ADDR  = 16'h0034;
  parameter logic [15:0] AEC_IMEM_BASE_ADDR      = 16'h1000;
  parameter logic [15:0] AEC_IMEM_LAST_ADDR      = 16'h1fff;

  typedef enum logic [15:0] {
    AEC_OP_ADD        = 16'h0001,
    AEC_OP_SUB        = 16'h0002,
    AEC_OP_MUL        = 16'h0003,
    AEC_OP_MAD        = 16'h0004,
    AEC_OP_FMA        = 16'h0005,
    AEC_OP_AND        = 16'h0010,
    AEC_OP_OR         = 16'h0011,
    AEC_OP_XOR        = 16'h0012,
    AEC_OP_NOT        = 16'h0013,
    AEC_OP_SHL        = 16'h0014,
    AEC_OP_SHR        = 16'h0015,
    AEC_OP_SAR        = 16'h0016,
    AEC_OP_SETP       = 16'h0020,
    AEC_OP_CMPP       = 16'h0021,
    AEC_OP_SEL        = 16'h0022,
    AEC_OP_LD         = 16'h0030,
    AEC_OP_ST         = 16'h0031,
    AEC_OP_ATOM       = 16'h0032,
    AEC_OP_PREFETCH   = 16'h0033,
    AEC_OP_FENCE      = 16'h0034,
    AEC_OP_BRA        = 16'h0040,
    AEC_OP_BRX        = 16'h0041,
    AEC_OP_SSY        = 16'h0042,
    AEC_OP_SYNC       = 16'h0043,
    AEC_OP_BAR_SYNC   = 16'h0044,
    AEC_OP_HALT       = 16'h0045,
    AEC_OP_CPY        = 16'h0054,
    AEC_OP_LOADI      = 16'h0055,
    AEC_OP_LOADI64    = 16'h0056,
    AEC_OP_CVT        = 16'h0057,
    AEC_OP_PACK       = 16'h0058,
    AEC_OP_UNPACK     = 16'h0059,
    AEC_OP_SHFL       = 16'h0060,
    AEC_OP_REDUCE     = 16'h0061,
    AEC_OP_MMA        = 16'h0070,
    AEC_OP_SFU        = 16'h0080,
    AEC_OP_NOP        = 16'h00f0
  } aec_opcode_e;

  localparam logic [15:0] AEC_OP_MOV        = AEC_OP_CPY;
  localparam logic [15:0] AEC_OP_IADD_U32   = AEC_OP_ADD;
  localparam logic [15:0] AEC_OP_IMUL_U32   = AEC_OP_MUL;
  localparam logic [15:0] AEC_OP_FADD_F32   = AEC_OP_ADD;
  localparam logic [15:0] AEC_OP_FMUL_F32   = AEC_OP_MUL;
  localparam logic [15:0] AEC_OP_MAD_F32    = AEC_OP_MAD;
  localparam logic [15:0] AEC_OP_FMA_F32    = AEC_OP_FMA;
  localparam logic [15:0] AEC_OP_SUB_U32    = AEC_OP_SUB;
  localparam logic [15:0] AEC_OP_AND_B32    = AEC_OP_AND;
  localparam logic [15:0] AEC_OP_OR_B32     = AEC_OP_OR;
  localparam logic [15:0] AEC_OP_XOR_B32    = AEC_OP_XOR;
  localparam logic [15:0] AEC_OP_SHL_B32    = AEC_OP_SHL;
  localparam logic [15:0] AEC_OP_SHR_B32    = AEC_OP_SHR;
  localparam logic [15:0] AEC_OP_REDUCE_ADD = AEC_OP_REDUCE;
  localparam logic [15:0] AEC_OP_MMA_E4M3   = AEC_OP_MMA;

  typedef enum logic [3:0] {
    AEC_FAULT_NONE                = 4'd0,
    AEC_FAULT_ILLEGAL_INSTRUCTION = 4'd1,
    AEC_FAULT_MISALIGNED_ACCESS   = 4'd2,
    AEC_FAULT_ADDRESS_ERROR       = 4'd3,
    AEC_FAULT_SIMT_STACK_FAULT    = 4'd4,
    AEC_FAULT_BARRIER_DEADLOCK    = 4'd5,
    AEC_FAULT_WATCHDOG_TIMEOUT    = 4'd6,
    AEC_FAULT_UNSUPPORTED_FEATURE = 4'd7
  } aec_fault_e;

endpackage

`endif
