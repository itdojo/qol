# CLAUDE.md

Shell scripts and helpers for setting up and maintaining Linux and macOS machines: cross-platform scripts at the repo root, `linux/` and `macos/` for the rest, `linux/base_functions.sh` as the shared helper library. This repo is **public** (fleet `notify`), so nothing machine-specific or secret is committed. `script-design.md` is the canonical structure and STDOUT standard for operator-facing shell scripts across every repo; follow it here first. Read `docs/working-notes.md` before proposing an approach.

## Knowledge hub

<!-- knowledge-hub:begin (public variant). create-project writes this block and refreshes it on a rerun. This repo is public, so the block names no private paths; the global contract's "Public repos" section resolves them. Repo-specific lines go after the end marker. -->
This repo is public. It holds code, the tracker config the dojo- skills read in `docs/agents/`, and `docs/working-notes.md`, which is session scratch. Durable knowledge lives in the Dojobrain vault, where this project's slug is `qol`. Your global contract's "Public repos" section says where the vault is and where this project's MOC sits in it.

Durable knowledge goes to the vault:

- A decision worth a full record becomes a `setup-decision` note, filed by what it governs as the vault's contract describes. A small implementation call stays in working notes under Decisions.
- A new term goes through the gloss skill, which files it in this project's glossary or, when other repos share the term, in the vault's shared glossary.
- A gotcha or ruled-out approach that would bite another repo goes into working notes tagged `(cross-project)` when it happens. dojo-retro proposes it for the vault at the end of the session, and Weekly catches what retro missed.
- A raw source, such as an article, a PDF or research findings, goes to the vault's inbox.

Before your first write in the vault, read the vault's `AGENTS.md`. It governs every file in the vault, including which writes wait for the user's yes, and this file governs the files in this repo. A Claude session with the vault added already has it loaded. Codex never loads it on its own. Git runs in this repo only, and the fleet checkpoint commits the vault.

Before substantive work, brief yourself. Spawn it even when a few greps look like enough: recall sweeps every repo's working notes, which a search from here doesn't reach. Spawn a read-only subagent told to read `~/.agents/skills/dojo-grilling/recall.md` and follow it, with the task as its topic, and work from the digest it returns. If that file is missing, give the subagent the vault's `vault-query` agent as its procedure instead, with the task and the slug `qol`. A planning dojo- skill that already ran recall covers this. A question about past work, an earlier choice, or which of two tools to use counts as substantive, however short. One-line fixes skip it.

Everything committed here is published, working notes included. Name another repo by its name and a repo-relative path, such as qol's `script-design.md`, and a vault note by its note name, never by a home-relative or absolute path. A line that has to keep one carries `public-path-ok`, and the `no-private-paths` pre-commit hook refuses any other.
<!-- knowledge-hub:end -->
