# Stage 7.2 Runtime/TB Validation

Date: 2026-07-26

## Implemented

- Added `host_cmds.txt` and `docs/host_cmds.txt` protocol documentation.
- Added `runtime/aec_runtime_sim.py`.
  - Implements `aecMalloc`, `aecMemcpyH2D`, `aecModuleLoad`, `aecKernelLaunch`,
    `aecSynchronize`, and `aecMemcpyD2H` for command-file simulation.
  - Emits `.aecbin` into `IMEM_WINDOW` as 32-bit little-endian AXI-Lite writes.
  - Keeps GPU math in RTL simulation; Python only orchestrates commands and
    validates dumps.
- Refactored `rtl/tb_system.sv`.
  - Parses `WRITE_AXI`, `WRITE_AXIL`, `POLL_AXIL`, and `DUMP_AXI`.
  - Uses AXI4-Lite master tasks to program CSR/IMEM.
  - Uses a byte-addressed AXI main-memory model for LSU traffic.
- Added `tests/run_vector_add_e2e.py`.
  - Assembles `tests/vector_add.asm` to headerless `.aecbin`.
  - Generates host commands through `AECSimulatorRuntime`.
  - Runs XSim and checks dumped output against CPU `A + B`.

## Validation

Local:

- `python tests/test_assembler.py` passed.
- `python tests/run_vector_add_e2e.py --skip-xsim` generated
  `rtl/host_cmds.txt`.

Remote:

- Host: `contest5@127.0.0.1:2222`
- Tool: XSim 2023.1
- Command: `python3 tests/run_vector_add_e2e.py`
- Result:

```text
[SYSTEM TEST] PASS host_cmds complete
VECTOR_ADD_E2E PASS a=1390851128 b=647892279 out=2038743407
```

## Notes And Risks

- Remote validation uses Vivado/Vitis 2023.1, while the contest contract
  targets Vivado/Vitis 2022.2. This is acceptable for bring-up evidence but must
  be repeated in the official 2022.2 environment before submission.
- The current vector-add kernel is a one-word scalar bring-up case. The command
  protocol and runtime can emit multiple memory writes/dumps, but true
  multi-element vector kernels still need `%tid.x`/launch geometry ABI support
  or a looped kernel convention.
