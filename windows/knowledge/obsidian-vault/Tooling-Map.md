# Tooling Map

## Source of Truth

- Git branch: `agent/windows-netboot-manager`
- GitHub PR: `https://github.com/minoTrey/rpi-pxe-manager/pull/1`
- Linear issue: `3D-5`
- Local status: `windows/docs/current-test-status-ko.md`
- Current handoff: `windows/docs/project-memory.md`
- Daily worklog: `windows/docs/worklog/2026-05-20-gui-storage-eeprom.md`
- Active executable: `windows/RPI-Netboot-Manager.exe`
- EEPROM cache: `windows/cache/downloads`

## Workspace Rule

Use `C:\Users\test\Documents\workspace\rpi-pxe-manager\windows`.

Do not continue active work from `C:\Users\test\Documents\workspace\rpi-netboot-windows`; that folder is a legacy snapshot.

## Obsidian

Open `windows/knowledge/obsidian-vault` as a vault.

## GBrain

Use `windows/knowledge/gbrain/graph.json` as the relationship graph export.

## Hermes

Use `windows/knowledge/hermes/events.jsonl` as the append-only event stream.

## LLM Wiki Rule

Keep short linked pages:

- facts first
- evidence path next
- decision last
- every claim points to a log, commit, PR, or Linear issue when possible
