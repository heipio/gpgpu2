# Contract Audit After Stage 7.3

Date: 2026-07-26

## Scope

Audited the machine-readable ISA, assembler, PTX compiler, golden simulator,
RTL opcode package, EX/WB data path, runtime command protocol, and current E2E
tests for magic-number or encoding drift before MMA/SFU RTL work.

## Findings Fixed

1. PTX compiler opcode table lagged Stage 7 RTL/assembler.
   - Added `CMPP`, `SUB`, `AND`, `OR`, `XOR`, `SHL`, `SHR`, `SSY`, and `SYNC`
     encodings to `compiler/compiler.py`.
   - Added PTX lowering for `sub`, `and`, `or`, `xor`, `shl`, and `shr`.

2. PTX compiler memory-space IDs did not match assembler/RTL.
   - Fixed `compiler/compiler.py` to match the active contract:
     `global/gmem=0`, `param/pmem=1`, `shared/smem=2`,
     `local/lmem=3`, `const/cmem=4`.

3. Golden simulator lagged Stage 7 ALU and `%laneid`.
   - Added opcode names and execution semantics for `SUB/AND/OR/XOR/SHL/SHR`.
   - Added `MOV src1=0x0100` handling for `%laneid`.
   - Updated pred/control decoding so assembler type bits are not mistaken for
     a live predicate. `pred_ctrl[15]` now controls predicate enable, while
     legacy `0xffff` remains PT-compatible for the PTX compiler path.

4. MOV/LOADI immediate contract was inconsistent.
   - `compiler/compiler.py` already emitted immediate MOV as `src1=0xffff`.
   - `compiler/aec_assembler.py` now emits `LOADI` with `src1=0xffff`.
   - `rtl/ex_stage.sv` now recognizes `src1=0xffff` and writes `src2_imm`.

5. Root-level compatibility copies had drifted.
   - Synced root `compiler.py`, `simulator.py`, `test_compiler.py`, and
     `test_contract_audit.py` with the directory implementations so legacy
     direct-entry scripts keep the same contract.

## New Guardrails

- Added `tests/test_contract_audit.py`.
  - Compares opcode constants across `aec_g_isa_v1.json`,
    `compiler/aec_assembler.py`, `compiler/compiler.py`, `tests/simulator.py`,
    and `rtl/aec_pkg.sv`.
  - Compares special register encodings, including `%laneid = 0x0100`.
  - Compares memory-space encodings across assembler and PTX compiler.
- Extended `tests/test_compiler.py` for Stage 7 integer/logical lowering and
  memory-space control words.
- Extended `tests/test_sim.py` for `%laneid`, `LOADI`, and Stage 7 ALU
  semantics.

## Validation

Local:

```text
python tests/test_contract_audit.py
python tests/test_compiler.py
python tests/test_sim.py
python tests/test_differential.py
python tests/test_assembler.py
python tests/run_vector_add_e2e.py --skip-xsim
python tests/run_alu_simt_e2e.py --skip-xsim
python -m json.tool aec_g_isa_v1.json
python skills/u280-gpgpu-contest-completer/scripts/audit_submission.py .
```

Remote Vivado/XSim 2023.1:

```text
contract audit tests passed
ALU_SIMT_E2E PASS out=['0x6539832', '0x7a0b0c6b', '0x244c4b32', '0x705f7c0', '0xbb384aff', '0x8cc9c34e', '0x58b92abc', '0x4ffb7291']
VECTOR_ADD_E2E PASS a=1390851128 b=647892279 out=2038743407
```

## Residual Risks

- Predicate execution is only partially wired in RTL. Current branch tests use
  predicate state for `BRX`, but general predicated ALU/LD/ST write masking
  still needs a dedicated RTL pass before hidden predication tests.
- `imem.sv` is currently XPM write-only from AXI-Lite and returns zero on the
  AXI-Lite readback path. This is acceptable for current load/launch tests but
  should be resolved if host-side IMEM readback is part of the final debug ABI.
- The root-level duplicate files are compatibility mirrors. Long term, the repo
  should keep one canonical implementation and thin wrappers to avoid drift.
- Remote validation uses the user-provided Vivado/Vitis 2023.1 environment.
