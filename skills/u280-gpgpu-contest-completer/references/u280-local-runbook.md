# U280 Local Runbook

Use this reference only for local remote access and board bring-up. It complements the contest contract; it does not override the official locked submission environment in `contest.md`.

## Security Rules

- Do not store usernames, passwords, SSH private keys, FRP `auth.token`, `secretKey`, or host fingerprints in this skill, repository, logs, scripts, documentation, or submission archive.
- If the user provides credentials in the conversation, use them only for the current task and redact them from commands, logs, notes, and final reports.
- Prefer SSH key authentication. If password login is unavoidable, do not echo the password into shell commands or files.
- Do not commit `frpc-visitor.toml` or any tunnel config containing secrets.

## Remote Access Summary

Preferred path:

```bash
cd ~/frp-visitor
./frpc -c ./frpc-visitor.toml
ssh -p 2222 <user>@127.0.0.1
scp -P 2222 <local-file> <user>@127.0.0.1:<remote-path>
```

Fallback path when P2P fails:

```bash
ssh -p 6000 <user>@117.72.69.71
scp -P 6000 <local-file> <user>@117.72.69.71:<remote-path>
```

Troubleshooting:

- P2P success logs often include `xtcp proxy started successfully` and `nat hole connection make success`.
- If P2P fails, verify the inner machine FRP client, public FRP server, token/key match, and STUN reachability; then switch to TCP fallback if needed.
- For long compile or board runs, use `tmux` or `nohup` on the remote machine.

## Local Board Environment

Known local machine notes may include:

- Server: Inspur NF5468M5, 64 CPU cores, about 754-768 GB RAM.
- Cards: up to 8 Alveo U280 cards.
- Runtime: XRT 2022.1 / 2.13.479 under `/opt/xilinx/xrt`.
- Platform: `xilinx_u280_gen3x16_xdma_1_202211_1`.
- Shell: `xilinx_u280_gen3x16_xdma_base_1`.
- Local build tools may be Vitis/Vivado 2023.1 under `/apps/Xilinx2023/...`.
- Host compiler should use devtoolset, commonly `source /opt/rh/devtoolset-9/enable`, because the default GCC 4.8.5 is too old for XRT C++14 host code.

Important:

- The contest submission environment is still CentOS 7.9, GLIBC 2.17, Vivado/Vitis 2022.2, XRT 2.13.479. Treat local Vitis/Vivado 2023.1 as a development convenience and document any mismatch.
- Compile host code conservatively with C++14 unless the official environment confirms otherwise.

Typical setup:

```bash
source ~/setup_u280.sh

# Equivalent expanded setup when the helper is unavailable:
source /apps/Xilinx2023/Vitis/2023.1/settings64.sh
source /opt/xilinx/xrt/setup.sh
source /opt/rh/devtoolset-9/enable
export PLATFORM=xilinx_u280_gen3x16_xdma_1_202211_1
```

Verify:

```bash
v++ --version
echo $XILINX_XRT
xbutil examine
```

## Build And Emulation

Kernel compile:

```bash
v++ -c -t hw --platform $PLATFORM -k <kernel_name> -o <kernel>.xo <kernel_source>
```

Link xclbin:

```bash
v++ -l -t hw --platform $PLATFORM --config connectivity.cfg -o <kernel>.xclbin <kernel>.xo
```

Host compile:

```bash
g++ -std=c++14 -O2 -Wall \
  -I$XILINX_XRT/include \
  -L$XILINX_XRT/lib \
  -o host src/host.cpp \
  -lxrt_coreutil -lpthread -lrt -ldl
```

Emulation:

```bash
emconfigutil --platform $PLATFORM
export XCL_EMULATION_MODE=sw_emu
export XILINX_VITIS=~/vitis_xrt221_overlay
./host <kernel>.xclbin
```

Before real board runs:

```bash
unset XCL_EMULATION_MODE
```

## U280 Connectivity

For Vitis kernels, explicitly map ports to HBM channels in `connectivity.cfg`:

```ini
[connectivity]
nk=<kernel_name>:1:<kernel_name>_1
sp=<kernel_name>_1.in0:HBM[0]
sp=<kernel_name>_1.in1:HBM[1]
sp=<kernel_name>_1.out:HBM[2]
slr=<kernel_name>_1:SLR0
```

Guidance:

- Do not leave ports on ambiguous default banks.
- Avoid mapping all high-traffic ports to one HBM channel.
- Record HBM channel mapping in reports and `design.json`.
- U280 platform notes may show PL DDR bank0/bank1 as unavailable for Vitis kernels; use HBM mappings for these kernels unless the project explicitly proves a valid DDR path.

## Board Commands

Inspect:

```bash
xbutil examine
xbutil examine -d <BDF> -r platform
xbutil examine -d <BDF> -r memory
xbutil examine -d <BDF> -r thermal
xbutil examine -d <BDF> -r electrical
```

Validate:

```bash
xbutil validate -d <BDF>
xbutil validate -d <BDF> -r bandwidth
```

Program/reset:

```bash
xbutil program -d <BDF> -u <file>.xclbin
xbutil reset -d <BDF>
```

Monitor:

```bash
xbutil top -d <BDF>
```

Multi-card:

```bash
export XRT_VISIBLE_DEVICES=0
```

Use the BDF shown by `xbutil examine`; do not assume a fixed card index on shared machines.

## Timing And Evidence

- Inspect `.link_summary`, `_logs/`, utilization, timing, and power reports after link.
- WNS must be >= 0 for all scoring clocks in the submitted bitstream.
- Capture `xbutil examine`, shell/platform, BDF, XRT version, tool versions, frequency, HBM mapping, thermal, electrical, and 30-minute stability evidence.
- If local tools produce version warnings, record them and verify the final submission build on the official or faithfully mirrored toolchain.

## Common Failures

- `xbutil: command not found`: source `/opt/xilinx/xrt/setup.sh`.
- Host compile fails on modern C++/XRT headers: enable devtoolset and keep `-std=c++14`.
- `xclbin not compatible with the shell`: rebuild for `xilinx_u280_gen3x16_xdma_1_202211_1` and use a real `hw` xclbin, not emulation.
- Bank mapping errors: explicitly map ports to `HBM[n]` in `connectivity.cfg`.
- Board hang or no response: collect logs, then try `xbutil reset -d <BDF>`; if reset fails, ask for administrator intervention rather than hiding the fault.
