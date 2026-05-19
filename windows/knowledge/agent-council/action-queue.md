# Agent Council Action Queue

Updated: 2026-05-19 14:45 KST

## Active

| Priority | Action | Owner | Trigger |
| --- | --- | --- | --- |
| P0 | Finish haneWIN systemd-explicit attempt and classify verdict | Harness Engineer | User power-cycles RPi4 and sends screen text |
| P0 | If systemd reaches userspace, keep haneWIN minimal as diagnostic success and continue service/rootfs fixes | Systems Evaluator | Verdict is init/systemd progress |
| P0 | If systemd returns `error -14`, escalate to Linux NFS helper | Systems Evaluator | Same rootfs fails under restored systemd |
| P1 | Add safer `finish-attempt` UX for empty console text and active attempt display | Windows Automation Engineer | After current attempt is closed |
| P1 | Add Linux helper readiness checklist before asking for another power cycle | Harness Engineer | Before LinuxNFS `start-attempt` |
| P2 | Update Obsidian/GBrain/Hermes after every attempt | Knowledge Architect | Every verdict |

## Rules

- Do not ask the user to power-cycle until DHCP/TFTP/NFS provider state is captured.
- Do not mix Zero 2 W gadget work into RPi4 netboot attempts.
- haneWIN minimal profile is allowed only as a diagnostic path. It passed BusyBox init execution; do not treat it as the final production provider yet.
- Keep GitHub PR and Linear `3D-5` updated after every meaningful verdict.
