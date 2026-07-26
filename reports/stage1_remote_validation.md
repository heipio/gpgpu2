# Stage 1 Remote Validation

Date: 2026-07-25
Remote user: contest5
Remote path: /home/contest5/gpgpu_stage1

## Uploaded Files

- aec_g_isa_v1.json
- tests/simulator.py
- tests/test_sim.py

## Remote Environment Evidence

```text
hostname: localhost.localdomain
user: contest5
kernel: Linux 3.10.0-1160.108.1.el7.x86_64
OS: CentOS Linux release 7.9.2009 (Core)
GLIBC: 2.17
Python: 3.6.8
XRT: 2.13.479 / branch 2022.1
XOCL/XCLMGMT: 2.13.479, 5e92a513c6950e79638b1a879ddb882da34fc683
```

## U280 Board Evidence

`xbutil examine` reports 8 devices present and ready, all with shell `xilinx_u280_gen3x16_xdma_base_1`:

```text
0000:b5:00.1 Ready Yes
0000:b4:00.1 Ready Yes
0000:b2:00.1 Ready Yes
0000:b1:00.1 Ready Yes
0000:41:00.1 Ready Yes
0000:40:00.1 Ready Yes
0000:3e:00.1 Ready Yes
0000:3d:00.1 Ready Yes
```

## Validation Commands

```bash
python3 - <<'PY'
import json
json.load(open('/home/contest5/gpgpu_stage1/aec_g_isa_v1.json'))
print('json ok')
PY

cd /home/contest5/gpgpu_stage1
python3 tests/test_sim.py
```

## Results

```text
json ok
AEC-G simulator numeric tests passed
```

## Notes

The simulator was revised to be Python 3.6 compatible for the CentOS 7.9 host by avoiding Python 3.7+ future annotations and standard-library dataclasses. Local U280 notes mention Vitis/Vivado 2023.1, while the contest contract requires final submission compatibility with Vivado/Vitis 2022.2; keep this as a documented toolchain mismatch risk for later stages.
