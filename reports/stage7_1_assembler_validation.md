# Stage 7.1 AEC Assembler Validation

Date: 2026-07-26

## Implemented

- Added `compiler/aec_assembler.py`.
- Added `tests/vector_add.asm`.
- Added `tests/test_assembler.py`.
- Generated:
  - `tests/vector_add.hex`
  - `tests/vector_add.aecbin`

## Encoding Contract

The assembler emits the fixed AEC-G 128-bit instruction layout:

```text
[127:112] Opcode
[111:96]  Pred/Ctrl
[95:80]   Dest
[79:64]   Src1
[63:32]   Src2 / Imm32
[31:0]    Src3 / ImmExt
```

Text `.hex` output is one 128-bit big-endian hex word per line, matching the SystemVerilog `128'h...` convention and the Stage 6 `tb_system.sv` loader split:

```text
w0 = bits[31:0]
w1 = bits[63:32]
w2 = bits[95:64]
w3 = bits[127:96]
```

Binary `.aecbin` output is headerless `w0,w1,w2,w3` little-endian 32-bit words per instruction.

## Pred/Ctrl Layout Used

```text
bits[2:0]   predicate index
bit[3]      predicate negate
bits[7:4]   type
bit[8]      immediate-enable
bits[11:9]  address space
bits[14:12] control/subop reserved
bit[15]     predicate-enable
```

This preserves the predicate bits already consumed by `fetch_decode.sv` while making type, immediate, and space explicit for later RTL decoding.

## Supported Stage 7.1 Assembly Subset

- Arithmetic/logical: `ADD`, `SUB`, `MUL`, `AND`, `OR`, `XOR`, `SHL`, `SHR`.
- Memory: `LD`, `ST` with `.gmem`, `.pmem`, `.smem`, `.lmem`, `.cmem` aliases.
- Control: `BR`, `BRA`, `BRX`, `SSY`, `SYNC`, `BAR`, `HALT`.
- Move/immediate: `CPY`, `MOV`, `LOADI`.
- Register aliases: `R0..R255`, `%tid.x`, `%laneid`, `%warpid`, `%ctaid.x`, `%nctaid.x`, `%activemask`.
- Types: `.u8/.u16/.u32/.u64/.s*`, `.b*`, `.f16`, `.f32`.
- Diagnostics: rejects out-of-range GPR/predicate indices and odd `.u64/.b64` LD/ST registers.

## Local Validation

Commands:

```text
python compiler/aec_assembler.py tests/vector_add.asm -o tests/vector_add.hex
python compiler/aec_assembler.py tests/vector_add.asm -o tests/vector_add.aecbin --format aecbin
```

Direct assertion checks passed:

```text
test_vector_add_exact_hex PASS
test_labels_and_predicate_encode PASS
test_b64_alignment_rejected PASS
assembler tests PASS
```

## Contest-Contract Notes

- `MOV/CPY/LOADI` currently encode to opcode `0x0001` to remain compatible with the Stage 3-6 RTL `AEC_OP_MOV` execution path.
- `ADD/MUL/LD/ST/BR/BRX/HALT` align with the current Stage 1 JSON and RTL opcode values.
- `SUB/AND/OR/XOR/SHL/SHR` are assembled as reserved scalar-extension opcodes `0x000a..0x000f`. RTL execution and ISA JSON should be updated before these opcodes are used in scoreable kernels; reserved or unsupported opcodes must fault rather than silently act as NOP.
