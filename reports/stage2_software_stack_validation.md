# Stage 2 Software Stack Validation

Date: 2026-07-26
Remote path: /home/contest5/gpgpu_stage1

## Files

- compiler/compiler.py
- runtime/aec_runtime.h
- runtime/aec_runtime.cpp
- pytorch/aec_torch.py

## Implemented Scope

### Compiler

- Restricted PTX parser for `.entry`, `.param`, `.shared`, labels, predicates, and a first scalar/memory/SFU/MMA subset.
- Lowering for `mov`, integer add/mul, FP32 add/mul/MAD/FMA, LD/ST, SETP, BRA/BRX, BAR.SYNC, RCP/EXP2, and MMA.m16n16k16.e4m3.f32.
- Register allocation with even register-pair handling for `.b64` and alignment checks for MMA fragments.
- `.b128` memory operations are lowered into legal b64/b32 LD/ST sequences; base ISA does not emit b128.
- Strict headerless 128-bit `.aecbin` emission plus JSON compile report.

### Runtime

- Fixed C API surface: context, malloc/free, H2D/D2H, module load/unload, kernel launch, synchronize, last error, counters, state reset, and address translation.
- 64-bit opaque device pointer to 32-bit AEC address-window mapping.
- HBM/DDR placement policy using explicit placement plus hot/cold/KV/weight flags.
- Module validation checks `.aecbin` size is a nonzero multiple of 16 bytes and rejects manifest text requiring b128.
- Launch validation checks block warp alignment, dynamic shared-memory limit, and device-pointer arguments.
- TODO markers remain for XDMA command queue, completion queue, cache flush/invalidate, and RTL command ABI.

### PyTorch

- `AECTorch` wrapper for P0 FP8 GEMM, add, mul, and ReLU.
- Scoreable CPU fallback is blocked by default.
- Debug fallback is explicit and logs required audit fields: fallback, reason, CPU time, input bytes, output bytes, call count, operator/model, and scoreable-main-compute flag.
- Request-state reset hook logs boundary events and leaves TODO for runtime KV/output/activation clearing.

## Validation

Local:

```text
python -m py_compile stage2/compiler/compiler.py stage2/pytorch/aec_torch.py
compiler smoke generated 80-byte .aecbin, aligned to 16 bytes
```

Remote CentOS 7.9 / Python 3.6 / devtoolset C++14:

```text
python3 -m py_compile compiler/compiler.py pytorch/aec_torch.py: PASS
python3 compiler/compiler.py compiler/tiny.ptx -o compiler/tiny.aecbin --report compiler/tiny_report.json: PASS
compiler/tiny.aecbin size: 80 bytes
runtime C++14 compile: PASS
```

## Known Risks / Next TODO

- PTX support is intentionally a restricted subset; next step is CFG/type checking and parameter ABI lowering.
- Runtime is a host-shadow skeleton until XDMA driver and RTL command queue ABI exist.
- PyTorch scoreable FP8 GEMM path is blocked until the first compiled AEC kernel module exists; debug CPU reference is available only with `allow_debug_fallback=True`.
