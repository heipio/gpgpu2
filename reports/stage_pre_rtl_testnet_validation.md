# Pre-RTL Test Network Validation

Date: 2026-07-26
Remote path: /home/contest5/gpgpu_stage1

## Added / Updated Files

- tests/test_compiler.py
- tests/test_sim_ctrl.py
- tests/test_differential.py
- tests/simulator.py
- compiler/compiler.py

## Coverage Added

### Compiler Tests

- `.b128` load/store lowering is checked to emit legal 32-bit AEC `LD/ST` sequences and no base-ISA b128 extension.
- `.b64` reuse of an odd preallocated GPR is rejected before `.aecbin` emission.
- MMA fragment reuse of a misaligned preallocated GPR is rejected before `.aecbin` emission.

### SIMT Control Tests

- `BRX` splits active masks into taken/fallthrough masks and pushes a reconvergence token.
- `SYNC` restores reconvergence PC and active mask.
- `SYNC` underflow records `SIMT_STACK_FAULT`.

### Differential Test

- A minimal vector-add PTX program is compiled with `compiler.py` into headerless 128-bit `.aecbin`.
- The generated machine code is decoded and executed by `AECGSimulator`.
- Simulator memory output is compared against Python native integer addition.

## Simulator / Compiler Support Added

- `AECGSimulator.execute_aecbin()` for a minimal scalar/memory/control execution subset.
- `decode_aec_instruction_words()` for fixed-width AEC machine-code decode.
- Byte-addressed `load_u32` / `store_u32` memory helpers.
- SIMT reconvergence helpers: `brx`, `ssy`, `sync`, `push_reconvergence`.
- Compiler compile report now includes `register_map` and `predicate_map` for differential tests.
- Compiler now rejects existing misaligned GPR reuse for `.b64` and MMA fragment operands.
- Arithmetic register-vs-immediate RHS is encoded with a small internal src3 flag for simulator/compiler differential testing.

## Local Validation

```text
python E:\gpgpu\tests\test_sim.py: PASS
python E:\gpgpu\tests\test_compiler.py: PASS
python E:\gpgpu\tests\test_sim_ctrl.py: PASS
python E:\gpgpu\tests\test_differential.py: PASS
```

## Remote Validation

CentOS 7.9 / Python 3.6:

```text
python3 tests/test_sim.py: PASS
python3 tests/test_compiler.py: PASS
python3 tests/test_sim_ctrl.py: PASS
python3 tests/test_differential.py: PASS
```

## RTL Readiness Notes

These tests should become the seed for RTL trace comparison: PTX intent -> compiler report/register map -> `.aecbin` -> golden simulator trace -> RTL trace. The next step is to emit per-instruction traces from `AECGSimulator` so RTL simulation can diff PC, active mask, GPR writes, memory writes, and faults cycle-by-cycle or instruction-by-instruction.
