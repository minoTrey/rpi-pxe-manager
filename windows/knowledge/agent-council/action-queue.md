# Agent Council Action Queue

Updated: 2026-05-19 15:15 KST

## Active

| Priority | Action | Owner | Trigger |
| --- | --- | --- | --- |
| P0 | Retest no-expiry WinNFSd minimal profile with the known-good bootfs/rootfs | Harness Engineer | Pi can be powered down or switched safely |
| P0 | Design production Linux NFS appliance path for ext4 rootfs storage | Systems Evaluator | haneWIN is proof-only |
| P0 | Wrap `clone-rpi4-client.ps1` in the GUI as a new RPi4 clone wizard | Windows Automation Engineer | Script core is ready |
| P1 | Add safer `finish-attempt` UX for explicit user-success evidence | Harness Engineer | After clone flow is stable |
| P1 | Add Linux helper readiness checklist before asking for another power cycle | Harness Engineer | Before LinuxNFS `start-attempt` |
| P2 | Update Obsidian/GBrain/Hermes after every attempt | Knowledge Architect | Every verdict |

## Rules

- Do not ask the user to power-cycle until DHCP/TFTP/NFS provider state is captured.
- Do not mix Zero 2 W gadget work into RPi4 netboot attempts.
- haneWIN minimal profile is allowed only as a proof/diagnostic path. It reached userspace, but it must not become the production provider.
- Keep GitHub PR and Linear `3D-5` updated after every meaningful verdict.
