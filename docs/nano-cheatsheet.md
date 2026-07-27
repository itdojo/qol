# nano cheat sheet

`^` means Ctrl. `M-` means Alt on Linux, or Esc-then-key on macOS — press and
release Esc, then the key. Key names are not case sensitive: `^X` is Ctrl and x.

Lines marked **(qol)** exist because of `install_nano.sh`. On a stock nano they
will not work.

## Get out

| Key | Does |
|:--|:--|
| `^X` | Exit. Prompts to save if the file changed. |
| `^S` | Save, no prompt. **(qol)** |
| `^O` | Save As — prompts for the filename. Stock nano's save key. |
| `^C` | Show the cursor's line, column, and character count. Does **not** quit. |

If you are stuck at a prompt, `^C` cancels it.

## Move

| Key | Does |
|:--|:--|
| `^A` / `^E` | Start / end of line. |
| `^Y` / `^V` | Page up / page down. |
| `^/` then a number | Go to that line. (`^_` also works.) |
| `M-\` / `M-/` | Start / end of the file. |
| `M-]` | Jump to the matching bracket. |
| `M-7` / `M-8` | Previous / next block of text. |

## Edit

| Key | Does |
|:--|:--|
| `^K` | Cut the current line. Press repeatedly to cut several. |
| `^U` | Paste what was cut. |
| `M-6` | Copy the current line without cutting it. |
| `M-U` | Undo. |
| `M-E` | Redo. |
| `M-3` | Comment or uncomment the line, using the right character for the file type. |
| `Tab` / `Shift-Tab` | Indent / unindent. Works on a selection too. |
| `^T` | Run a command and read its output. |

`^Z` by itself does nothing but remind you of the real sequence: `^T` then `^Z`
suspends nano and drops you back to the shell. Type `fg` to return. Neither one
is undo — undo is `M-U`.

## Select and copy

| Key | Does |
|:--|:--|
| `^6` or `M-A` | Start selecting. Move the cursor to extend. |
| `^K` | Cut the selection. |
| `M-6` | Copy the selection. |
| `^6` again | Cancel the selection. |

Copying *out of* nano into another application is your terminal's job, not
nano's — use the terminal's own select-and-copy.

## Search and replace

| Key | Does |
|:--|:--|
| `^W` | Search forwards. |
| `M-W` | Repeat the last search. |
| `^\` | Search and replace. `A` at the prompt replaces all. |
| `M-R` | Toggle regular expressions in the search prompt. |
| `M-C` | Toggle case sensitivity. |

Search history is kept between sessions **(qol)** — press ↑ at the search prompt.

## Files and buffers

| Key | Does |
|:--|:--|
| `^R` | Read another file into a new buffer. **(qol** — stock nano inserts it into the current one.**)** |
| `M-,` / `M-.` | Previous / next buffer. |
| `^R` then `^T` | Open the file browser. |

## Help

| Key | Does |
|:--|:--|
| `^G` | Full help, inside nano. |
| `M-X` | Show or hide the two-line help bar at the bottom. |

## What the qol config changes

- Line numbers down the left margin, and a faint rule at column 80.
- Syntax highlighting for roughly 180 file types.
- Tab inserts four spaces rather than a tab character.
- Long lines wrap on screen at word boundaries without newlines being inserted.
- Reopening a file returns you to where you left off.
- `^S` saves.
- `^Q` is deliberately **not** bound to quit. On many terminals `^Q` is flow
  control and can make the terminal look frozen. Use `^X`.

## About `~/.nanorc`

`install_nano.sh` writes a block into `~/.nanorc` between a start and end
marker, and rewrites that whole block on every run. Put your own settings
**above** the block, not below it — anything below the end marker survives,
but gets moved back above the block the next time you run the installer.
