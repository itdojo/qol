# Domain docs

How the dojo- skills consume this repo's domain documentation. The layout is single-context, and it lives in the Dojobrain vault rather than in this repo, so that every project and course can find the same vocabulary and the same decisions. This repo is public, so this file names the vault's notes without their paths; the "Public repos" section of your global contract resolves them for the slug `qol`.

| Skill expects     | Read instead |
| ----------------- | ------------ |
| `GLOSSARY.md`     | This project's glossary in the vault when it exists, then the vault's shared glossary |
| `docs/adr/`       | `type: setup-decision` notes. This project's sit beside its MOC, a cluster's conventions are in that cluster, and the vault's and the shared machinery's are in the vault's setup-decisions folder |
| `CONTEXT.md`, `GLOSSARY-MAP.md` | Not applicable. Single-context. |

## Before exploring, read these

- **This project's MOC in the vault**, which indexes its notes, decisions and open threads.
- **The two glossaries** in the table above.
- **The setup-decision notes that touch the area you are about to work in.** Find them by type, not by folder: search the project's vault folder and the vault's references for `^type: setup-decision`.

The glossary and the decision log for this repo are the vault's. This repo has no `GLOSSARY.md`, `CONTEXT.md`, `GLOSSARY-MAP.md` or `docs/adr/`, by design.

## When a skill would write

Read the vault's `AGENTS.md` before the first vault write. It sets the frontmatter, the confirmation rules and the `_log.md` line each write needs.

- **A new term** goes through the gloss skill, which places it in the project glossary or the shared one.
- **A decision worth a full record** becomes a `type: setup-decision` note in the folder its scope picks from the table above, linked from that folder's MOC. Propose it first, and write it as a draft only after the user says yes.
- **An implementation call** goes in this repo's `docs/working-notes.md` under Decisions.

Whatever lands in this repo is published. Name a vault note by its note name, never by its path.

## Use the glossary's vocabulary

When your output names a domain concept, such as an issue title, a refactor proposal, a hypothesis or a test name, use the term as the glossary defines it. Don't drift to synonyms the glossary explicitly avoids.

If the concept isn't in either glossary yet, that's a signal. Either you're inventing language the project doesn't use, so reconsider, or there's a real gap, so queue it with gloss.

## Flag decision conflicts

If your output contradicts an existing setup-decision note, surface it explicitly rather than silently overriding:

> _Contradicts `<note-name>`, but worth reopening because…_
