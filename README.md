# `cmdhelp`

`cmdhelp` is an interactive terminal reference for useful shell commands. Search the command list with `fzf`, open a command's examples, and copy an example to the clipboard.

## Requirements

- Bash
- [`fzf`](https://github.com/junegunn/fzf)
- `base64`
- `flock` (usually provided by `util-linux` on Linux) to initialize or edit the database
- `tmux` to use add, edit, and remove actions, which open tmux popups
- A clipboard utility (`wl-copy`, `xclip`, `xsel`, `pbcopy`, or `clip.exe`) to copy examples

## Install

Copy the script into a directory on your `PATH` and make it executable:

```bash
mkdir -p "$HOME/.local/bin"
cp cmdhelp.sh "$HOME/.local/bin/cmdhelp"
chmod +x "$HOME/.local/bin/cmdhelp"
```

Run `cmdhelp` as a standalone command; do not source `cmdhelp.sh` from a shell startup file. If `~/.local/bin` is not already on your `PATH`, add this to your shell startup file (for example, `~/.bashrc`):

```bash
export PATH="$HOME/.local/bin:$PATH"
```

## Use

```bash
cmdhelp       # open the command browser
cmdhelp --help
```

In the command list, Ctrl-I adds a command, Ctrl-E edits its name or description, and Ctrl-R removes it after confirmation. Press Enter on a command to open its examples. In the examples list, Ctrl-I adds an example, Ctrl-E edits the selected example and its description, and Ctrl-R removes it after confirmation. Press Enter on an example to copy it; Escape returns to the command list.

The eight action names handled internally by the interface (`add-command`, `edit-command`, `remove-command`, `add-example`, `edit-example`, `remove-example`, `list-examples`, and `list-commands`) are not supported direct command-line arguments.

## Data and locking

The data file is `${XDG_DATA_HOME:-$HOME/.local/share}/cmdhelp/commands.tsv`; set `CMDHELP_DATA_FILE=/path/to/commands.tsv` to use another location. On first run, cmdhelp creates the file with built-in examples and owner-only permissions (`0600`).

Each line has three tab-separated fields: base64-encoded command name, base64-encoded description, and a base64-encoded examples string. The decoded examples string contains one record per example, with the base64-encoded example and description separated by a tab; records are separated by semicolons. Base64 encoding keeps tabs and semicolons in user data from colliding with those separators.

Edits use the adjacent `.lock` file. Lock acquisition is nonblocking; if another session holds the lock, cmdhelp reports that the database is being edited and the requested operation fails.

## Runtime behavior

- `fzf` is required when starting cmdhelp, including for `--help`.
- If tmux is available and cmdhelp starts outside a tmux session, it opens a temporary tmux session. Inside tmux, it uses the current session. Without tmux, browsing still opens in the current terminal, but add, edit, and remove actions cannot open their popups.
- Browsing works without a clipboard utility, but selecting an example to copy reports an error if no supported clipboard tool is installed.
- `flock` is required to initialize the data file and to edit it. If it is missing or another session holds the lock, those operations fail with an error.
