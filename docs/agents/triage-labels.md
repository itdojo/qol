# Triage labels

The skills speak in terms of five canonical triage roles. This file maps those roles to the label strings this repo's issue tracker uses. Each label string equals its role name unless the right-hand column says otherwise.

| Role                       | Label in our tracker | Meaning                                  |
| -------------------------- | -------------------- | ---------------------------------------- |
| `needs-triage`             | `needs-triage`       | Maintainer needs to evaluate this issue  |
| `needs-info`               | `needs-info`         | Waiting on reporter for more information |
| `ready-for-agent`          | `ready-for-agent`    | Fully specified, ready for an AFK agent  |
| `ready-for-human`          | `ready-for-human`    | Requires human implementation            |
| `wontfix`                  | `wontfix`            | Will not be actioned                     |

When a skill mentions a role (e.g. "apply the AFK-ready triage label"), use the corresponding label string from this table.

A new GitHub repo has `wontfix` by default and none of the other four. `gh issue edit --add-label` fails against a label that doesn't exist, so create a missing one first with `gh label create <name> --description "<meaning>"`. That is a `gh` write, so it follows the gh policy in `docs/agents/issue-tracker.md`. The `wayfinder:` labels work the same way.

Edit the right-hand column if this repo's tracker already uses other names.
