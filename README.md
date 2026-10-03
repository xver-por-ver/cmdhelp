# `cmdhelp`

A searchable terminal reference for useful shell commands. It opens a compact bordered overlay, sorts entries by command name, and filters as you type. Press Enter on a command to open its filterable examples list; press Enter on an example to copy that command line to the system clipboard.

## Requirements

- Bash
- [`fzf`](https://github.com/junegunn/fzf)
- A clipboard utility: `wl-copy`, `xclip`, `xsel`, `pbcopy`, or `clip.exe`

## Install

Copy the script into a directory on your `PATH` and make it executable:

```bash
mkdir -p "$HOME/.local/bin"
cp cmdhelp "$HOME/.local/bin/cmdhelp"
chmod +x "$HOME/.local/bin/cmdhelp"
```

If `~/.local/bin` is not already on your `PATH`, add this to your shell startup file (for example, `~/.bashrc`):

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Run `cmdhelp`, choose a command, then filter and choose an example. The picker closes and copies the example to your clipboard so you can paste it into the shell. Escape cancels the picker.

## Use

```bash
cmdhelp       # open the filterable overlay
cmdhelp add   # add an entry through guided prompts
cmdhelp edit  # rename a command, change its description, and manage examples
cmdhelp remove  # choose and remove a command
cmdhelp list  # print the alphabetized command list
```

In edit mode, choose a command, then select its name, description, example manager, or **Delete command**. The example manager lets you add examples, select an example to edit, or select one to delete. Choose **Done** to save your changes. The `remove` subcommand offers a direct removal flow. Both removal flows ask for confirmation before deleting the command and its examples.

When adding an entry, provide the command name, a short description, then one example per prompt. The examples collected so far are shown before each prompt; submit a blank example to finish and save the entry. Exact duplicate examples within a command are rejected when adding or editing. In edit mode, the examples manager keeps the current list visible while you choose an example to edit or delete, and shows the list again before editing text. Entries are stored in `${XDG_DATA_HOME:-~/.local/share}/cmdhelp/commands.tsv`.

The script checks for common clipboard utilities (`wl-copy`, `xclip`, `xsel`, `pbcopy`, and `clip.exe`) and reports an error if none is available.

The built-in list is created the first time the command runs. You can override its location with `CMDHELP_DATA_FILE=/path/to/commands.tsv`.
