# CLAUDE.md

Shell scripts and helpers for setting up and maintaining Linux and macOS machines: cross-platform scripts at the repo root, `linux/` and `macos/` for the rest, `linux/base_functions.sh` as the shared helper library. This repo is **public** (fleet `notify`), so nothing machine-specific or secret is committed. `script-design.md` is the canonical structure and STDOUT standard for operator-facing shell scripts across every repo; follow it here first. Read `docs/working-notes.md` before proposing an approach.

## Knowledge hub

Durable notes, decisions, and synthesis for this project live in Dojobrain, not here:
`~/vaults/dojobrain/10-projects/qol/qol-moc.md`.
This repo carries only source + spec; harvest in-repo material into the vault
deliberately via Ingest — never bulk-move (see pre-existing-repo-notes-as-ingest-candidates).

Before substantive work, brief yourself from the vault: run a read-only subagent that searches Dojobrain for lessons, gotchas and decisions bearing on the task, starting from this project's MOC, and cites the notes it used. In a session launched from Dojobrain that subagent is `vault-query`; elsewhere, give a general-purpose subagent `~/vaults/dojobrain/.claude/agents/vault-query.md` as its procedure, with the task and the slug `qol`. Quick lookups and one-line fixes skip it.
