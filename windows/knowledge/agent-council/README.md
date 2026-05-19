# Agent Council

Purpose: make multiple agents behave like a small engineering room instead of isolated helpers.

The agents do not have direct peer-to-peer sockets. The lead agent routes messages, writes the shared record, and turns consensus into scripts, docs, GitHub comments, and Linear updates.

## Roles

| Role | Focus |
| --- | --- |
| Evidence Analyst | Read logs and identify the exact failure boundary |
| Windows Automation Engineer | Reduce manual work in scripts and GUI |
| RPi Boot Specialist | Protect boot/NFS protocol correctness |
| Knowledge Architect | Keep Obsidian/GBrain/Hermes memory useful |
| Harness Engineer | Improve verdicts and repeatable tests |
| Systems Evaluator | Score options and define escalation rules |

## Round Protocol

1. State: lead writes the current facts and active attempt.
2. Propose: each agent gives one concrete next action and one risk.
3. Critique: each agent names what another role might overlook.
4. Decide: lead converts the strongest proposal into the action queue.
5. Execute: lead edits files, runs tools, and records evidence.
6. Publish: lead commits, pushes, and comments on GitHub/Linear.

## Current Active Round

See `rounds/2026-05-19-1419-hanewin-minimal.md`.
