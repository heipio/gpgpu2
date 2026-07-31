# 180 MHz Routed Timing Closure

Date: 2026-07-31

## Build

- Remote project: `/home/contest5/gpgpu_contract_audit`
- Toolchain: Vitis/Vivado 2023.1, XRT/platform 2022.1
- Link command policy: `--kernel_frequency 180`
- Artifact: `bitstream/aec_gpgpu.hw.xclbin` (51 MiB)
- Routed report: `vitis_180mhz_sfu_multicycle_timing_summary_routed.rpt`

## Result

The final Vitis implementation meets all reported timing constraints.

| Metric | Value |
| --- | ---: |
| Global WNS | +0.016 ns |
| Global TNS | 0.000 ns |
| Global WHS | +0.006 ns |
| Global THS | 0.000 ns |
| Kernel clock | 180.000 MHz (5.556 ns) |

The kernel clock group itself reports +0.047 ns setup slack and +0.010 ns hold
slack. The SFU request registers are held stable for the existing eight-cycle
`sfu_core` operation; the matching setup/hold multicycle constraint is packaged
with the RTL. A simulation-only assertion verifies that the request/control
bundle remains stable while the SFU is busy.

## Board Validation Status

The remote host can enumerate eight Ready U280 cards, but `device.load_xclbin()`
currently fails before RTL execution with XRT error `Can't reach out to mgmt for
xclbin downloading` (`err = -110`). `xbutil` shows the selected device has an
all-zero loaded xclbin UUID. This is a remote XRT management-plane/service
condition, not a timing or RTL functional failure. Do not reset cards or restart
shared services while another user's Vitis link is active. The HALT lifecycle
test must be rerun after the administrator restores xclbin download service.

On 2026-07-31, the documented `xbutil reset -d 0000:b5:00.1` HOT Reset was
explicitly authorized and completed successfully. The post-reset platform shell
enumerated and reported `Power Warning: false`, but a further HALT smoke test
still failed at `device.load_xclbin()` with the same management-mailbox timeout.
The kernel had previously reported that this card required a PCI hot reset after
a critical power or thermal event. Administrator-level `xbmgmt` warm reboot or
PCI recovery is therefore still required before board evidence can be collected.
