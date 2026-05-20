# AGENTS.md

Project instructions for Codex and agent-style work in this repository.

This file is intentionally strong. It reconstructs the project operating rules
from the repository memory, Obsidian vault, Hermes log, Linear, GitHub, and
previous Codex GUI session traces.

## Read First

- Start every resumed session by reading `windows/docs/project-memory.md`.
- Then check `windows/knowledge/obsidian-vault/Current-State.md`, `windows/knowledge/obsidian-vault/Timeline.md`, `windows/knowledge/obsidian-vault/Tooling-Map.md`, and `windows/knowledge/agent-council/action-queue.md`.
- Treat newer GitHub PR comments, Linear comments, and Hermes events as superseding stale issue bodies or old summaries.
- Do not rely on chat history alone. Every resumed session must rebuild context from repo-backed memory.

## Active Workspace

- The active project is `C:\Users\test\Documents\workspace\rpi-pxe-manager`.
- The active implementation area is `windows/`.
- `C:\Users\test\Documents\workspace\rpi-netboot-windows` is a legacy workspace. Do not use it for new work unless the user explicitly asks for historical comparison.

## Current Hardware Truth

- Known-good RPi4 serial: `d80c0b88`.
- Known-good RPi4 MAC: `88:a2:9e:4f:a9:b1`.
- Known-good RPi4 IP: `10.73.0.155`.
- Golden bootfs: `D:\tftp\d80c0b88`.
- Golden rootfs: `D:\rootfs\d80c0b88`.
- Current server Ethernet is expected at `10.73.0.10/24`; router is `10.73.0.1`.

## Safety Rules

- Do not erase or re-image an SD card without explicit user confirmation for that exact device.
- Do not ask the user to power-cycle hardware until DHCP, TFTP, and NFS provider state has been captured.
- Keep Raspberry Pi Zero 2 W gadget work separate from RPi4 netboot work.
- Protect the golden client `d80c0b88`; do not overwrite its bootfs or rootfs.
- Target clone paths must remain under `D:\tftp` and `D:\rootfs`.

## Provider Policy

- haneWIN is proof-only. It may be used for diagnostics, but it must not become the production NFS provider.
- Production provider work remains open until WinNFSd minimal mode or a Linux NFS helper/appliance passes.
- Do not present provider experiments as final UX choices.

## Clone Workflow

- Use `windows/tools/clone-rpi4-client.ps1` as the automation core for registering, cloning, and verifying RPi4 clients.
- Current clone input requires the target RPi serial and MAC.
- Do not overwrite existing target client folders unless the user explicitly requests `-Force`.

## Evidence And Publishing

After every meaningful hardware attempt or verdict:

1. Save raw evidence under `D:\logs\netboot-harness` or `D:\logs`.
2. Update `windows/docs/project-memory.md`.
3. Update the Obsidian vault, especially Current State and Timeline.
4. Append the appropriate Hermes event.
5. Commit and push the change.
6. Comment on GitHub PR `#1`.
7. Comment on Linear issue `3D-5`.

## LLM Wiki Rule

Use the Obsidian vault as an LLM wiki, not as a prose notebook.

- Keep pages short and linked.
- Put facts first.
- Put evidence paths next.
- Put decisions last.
- Every important claim should point to a log, commit, PR, Linear issue, Hermes event, or source document when possible.
- Prefer updating an existing focused page over creating a long catch-all page.
- When a fact changes, update the page that future agents are most likely to read first.

## Agent Council

- Use `windows/knowledge/agent-council/README.md` and `action-queue.md` as the local operating model.
- Follow the round shape when useful: State, Propose, Critique, Decide, Execute, Publish.
- For non-trivial work, run the council mentally or explicitly before acting.
- If the user asks for agents, subagents, parallel work, or council mode, use the maximum useful number of independent agents allowed by the active runtime.
- Do not create duplicate agents. Each agent must have a distinct role, ownership boundary, and output.
- The default council roles are Evidence Analyst, Windows Automation Engineer, RPi Boot Specialist, Knowledge Architect, Harness Engineer, and Systems Evaluator.
- Agents do not need direct peer-to-peer sockets. The lead agent routes messages through shared artifacts, round notes, action queues, GitHub comments, Linear comments, and final integration.
- Agent conversation should be concrete: facts, proposal, risk, critique, decision, and evidence path.
- If the runtime does not allow spawning agents, simulate the same council locally and record the role perspectives in the relevant round or worklog.
- The lead agent owns final integration and must not blindly merge agent output.

## Research Rules

- Prefer primary sources for technical facts: official Raspberry Pi documentation, kernel/NFS documentation, Microsoft/Windows documentation, upstream project docs, and source code.
- For LLM or tooling behavior, check the local LLM wiki first, then official docs or current primary sources when needed.
- Separate facts from inference. Label inference when the evidence is indirect.
- Do not let web research override local hardware evidence unless the conflict is explained.
- Record useful research in the Obsidian LLM wiki with source links and the local decision it supports.

## Development Rules

- Prefer existing PowerShell scripts and local patterns over new abstractions.
- Keep changes scoped to the requested behavior.
- Preserve user edits and unrelated working-tree changes.
- Validate PowerShell parser correctness after editing `.ps1` or `.psm1` files.
- Rebuild or run focused checks after GUI, packaging, or service-provider changes.

## GUI And Packaging

- The active user-facing binary is `windows/RPI-Netboot-Manager.exe`.
- Avoid reintroducing old BAT/admin-launcher clutter into the UI.
- Keep the GUI focused on concrete workflows: status, service control, SD prep, client registration/clone, and evidence collection.
