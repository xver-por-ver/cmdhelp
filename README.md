# `cmdhelp`

A searchable terminal reference for useful shell commands. It opens a compact bordered overlay, sorts entries by command name, and filters as you type. Press Enter on a command to open its filterable examples list; use Ctrl-I, Ctrl-E, and Ctrl-R there to insert, edit, or remove examples, or press Enter on an example to copy that command line to the system clipboard and close the list.

## Requirements

- Bash
- [`fzf`](https://github.com/junegunn/fzf)
- `base64`
- `flock` (usually provided by `util-linux` on Linux)
- A clipboard utility: `wl-copy`, `xclip`, `xsel`, `pbcopy`, or `clip.exe`

## Install

Copy the script into a directory on your `PATH` and make it executable:

```bash
mkdir -p "$HOME/.local/bin"
cp cmdhelp.sh "$HOME/.local/bin/cmdhelp"
chmod +x "$HOME/.local/bin/cmdhelp"
```

Run `cmdhelp` as a standalone command; do not source `cmdhelp.sh` from a shell startup file. Popup actions are included in the installed command.

If `~/.local/bin` is not already on your `PATH`, add this to your shell startup file (for example, `~/.bashrc`):

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Run `cmdhelp`, choose a command, then filter and choose an example. The picker closes and copies the example to your clipboard so you can paste it into the shell. Escape cancels the picker.

## Use

```bash
cmdhelp       # browse, add, edit, or remove commands
```

The command listing provides Ctrl-I, Ctrl-E, and Ctrl-R shortcuts for inserting, editing, and removing commands. Ctrl-E opens the selected command's name and description editor directly. Enter opens the full edit menu, where you can choose the name, description, or example manager. Press Escape to save changes and return to the command list. The example manager lists only saved examples; press **Ctrl-I** to insert, **Ctrl-E** to edit, or **Ctrl-R** to delete the selected example. Enter opens the action menu, and Escape returns to the edit menu. Removal asks for confirmation before deleting the command and its examples.

When adding an entry, provide the command name, a short description, then one example per prompt. Each example can have an optional description. The examples collected so far are shown before each prompt; submit a blank example to finish and save the entry. Exact duplicate examples within a command are rejected when adding or editing. In edit mode, the examples manager keeps the current list visible while you choose an example to edit or delete, and lets you update both the command text and its description. Entries are stored in `${XDG_DATA_HOME:-~/.local/share}/cmdhelp/commands.tsv` as one base64-encoded record per example, with four tab-separated fields: command, command description, example, and example description. Base64 encoding keeps user-entered tabs, semicolons, quotes, and other shell syntax from conflicting with the file format.

When run outside tmux, cmdhelp opens a temporary tmux session so its centered edit popups are available. When run inside tmux, it always uses the existing session and never creates a nested tmux session.

The script checks for common clipboard utilities (`wl-copy`, `xclip`, `xsel`, `pbcopy`, and `clip.exe`) and reports an error if none is available.

The built-in list is created the first time the command runs. You can override its location with `CMDHELP_DATA_FILE=/path/to/commands.tsv`.

The data file is created with owner-only permissions (`0600`). Add, edit, and remove operations use an exclusive lock file next to the data file so concurrent processes serialize their writes.

## Runtime behavior

- If `fzf` is unavailable, `cmdhelp` stops with an installation error before opening the picker.
- If `tmux` is unavailable, or the command is already running inside tmux, `cmdhelp` uses the current terminal directly. Edit actions remain available, but tmux-centered popup windows are not used.
- If `flock` is unavailable, read-only browsing of an existing data file can still work, but first-use initialization and add, edit, and remove actions fail with a lock requirement error.
- If no supported clipboard utility is available, browsing and editing still work, but copying an example reports an error and does not copy the command.
