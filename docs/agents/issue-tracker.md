# Issue tracker: GitHub

Issues and specs for this repo live as GitHub issues on `itdojo/qol`. Use the `gh` CLI for every operation. Run it from this repo's root, where `gh` infers the repo from `git remote -v`. From any other directory, the vault included, pass `-R itdojo/qol`, or the call lands on the repo that directory belongs to.

## gh policy

Confirm-first. Reads (`view`, `list`, `api` GET) run freely. Every write is proposed with its full text and runs only after the user says yes: creating, commenting, labelling, closing, reopening, sub-issue links, dependency edges and label creation. A subagent can't pause for a yes, so it hands the write back to the main session.

This section is this repo's own policy. To grant standing permission, replace the paragraph above with what may run without asking and the date the owner decided it, for example "Skills may create, label, comment on and close issues without asking (owner decision, 2026-10-09)."

Push, PR creation and repo-settings changes always ask, whatever this file says. The default for local commits comes from the dojo- skills and hard rule 10 of the Dojobrain vault's `AGENTS.md`. Write a stricter commit rule here if this repo needs one.

## Conventions

- **Create an issue**: `gh issue create --title "..." --body-file <file>`. Write a multi-line body to a scratch file first, because a heredoc inside `$(...)` leaves stray backslash escapes in the rendered body. `gh issue edit` and `gh issue comment` take `--body-file` the same way.
- **Read an issue**: `gh issue view <number> --json number,title,body,labels,comments`.
- **List issues**: `gh issue list --state open --json number,title,body,labels,comments --jq '[.[] | {number, title, body, labels: [.labels[].name], comments: [.comments[].body]}]'` with appropriate `--label` and `--state` filters.
- **Make an issue a sub-issue of a parent**: `gh issue create --parent <parent> ...`, or `gh issue edit <parent> --add-sub-issue <child>` afterwards (`gh` 2.94+). Older `gh`: `gh api --method POST repos/itdojo/qol/issues/<parent>/sub_issues -F sub_issue_id=<child-db-id>` (database id, as in **Blocking** below). Without sub-issues, put `Part of #<parent>` at the top of the child body.
- **Comment on an issue**: `gh issue comment <number> --body-file <file>`.
- **Apply / remove labels**: `gh issue edit <number> --add-label "..."` / `--remove-label "..."`. The label must exist first; see `docs/agents/triage-labels.md`.
- **Close**: `gh issue close <number> --comment "..."`.

Every write above follows the gh policy.

## Pull requests as a triage surface

**PRs as a request surface: no.** _(Set to `yes` if this repo treats external PRs as feature requests; triage reads this flag.)_

When set to `yes`, PRs run through the same labels and states as issues, using the `gh pr` equivalents:

- **Read a PR**: `gh pr view <number> --comments` and `gh pr diff <number>` for the diff.
- **List external PRs for triage**: `gh api --paginate 'repos/itdojo/qol/pulls?state=open' --jq '.[] | select(.author_association | IN("OWNER","MEMBER","COLLABORATOR") | not) | {number, title, author: .user.login, author_association, labels: [.labels[].name]}'`.
- **Comment / label / close**: `gh pr comment`, `gh pr edit --add-label`/`--remove-label`, `gh pr close`.

GitHub shares one number space across issues and PRs, so a bare `#42` may be either. Resolve it with `gh pr view 42` and fall back to `gh issue view 42`.

## When a skill says "publish to the issue tracker"

Create a GitHub issue under the gh policy.

## When a skill says "fetch the relevant ticket"

Read it as in **Read an issue** above.

## Wayfinding operations

Used by wayfinder. The **map** is a single issue with **child** issues as tickets. Every write here follows the gh policy.

- **Map**: a single issue labelled `wayfinder:map`, holding the Notes / Decisions-so-far / Fog body. `gh issue create --label wayfinder:map`.
- **Child ticket**: an issue linked to the map as a GitHub sub-issue (see **Make an issue a sub-issue of a parent**). Where sub-issues aren't enabled, add the child to a task list in the map body and put `Part of #<map>` at the top of the child body. Labels: `wayfinder:<type>` (`research`/`prototype`/`grilling`/`task`). Once claimed, the ticket is assigned to the driving dev.
- **Blocking**: GitHub's **native issue dependencies**, the canonical, UI-visible representation. Add an edge with `gh api --method POST repos/itdojo/qol/issues/<child>/dependencies/blocked_by -F issue_id=<blocker-db-id>`, where `<blocker-db-id>` is the blocker's numeric **database id** (`gh api repos/itdojo/qol/issues/<n> --jq .id`, _not_ the `#number` or `node_id`). GitHub reports `issue_dependencies_summary.blocked_by` (open blockers only, the live gate). Where dependencies aren't available, fall back to a `Blocked by: #<n>, #<n>` line at the top of the child body. A ticket is unblocked when every blocker is closed.
- **Frontier query**: list the map's open children (`gh issue list --state open`, scoped to the map's sub-issues / task list), drop any with an open blocker (`issue_dependencies_summary.blocked_by > 0`, or an open issue in the `Blocked by` line) or an assignee; first in map order wins.
- **Claim**: `gh issue edit <n> --add-assignee @me`, the session's first write.
- **Resolve**: `gh issue comment <n> --body "<answer>"`, then `gh issue close <n>`, then append a context pointer (gist + link) to the map's Decisions-so-far.
