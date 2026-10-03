#!/usr/bin/env bash

# Keep strict options scoped to direct execution; the popup actions reuse this
# same standalone command without launching the interactive picker.
if [[ "${BASH_SOURCE[0]:-}" == "$0" ]]; then
  set -euo pipefail
fi

APP_NAME=cmdhelp
CMDHELP_SCRIPT_FILE=${BASH_SOURCE[0]:-$0}
CMDHELP_SCRIPT_DIR=$(cd -- "$(dirname -- "$CMDHELP_SCRIPT_FILE")" && pwd)
DATA_DIR="${XDG_DATA_HOME:-${HOME}/.local/share}/cmdhelp"
DATA_FILE="${CMDHELP_DATA_FILE:-${DATA_DIR}/commands.tsv}"
DATA_LOCK_FILE="${DATA_FILE}.lock"
DATA_LOCK_HELD=0
COMMAND_COLUMN_WIDTH=28
EXAMPLE_COLUMN_WIDTH=56
if [[ -t 1 ]]; then
  COLOR_CURRENT=$'\033[1;36m'
  COLOR_SHORTCUT=$'\033[1;33m'
  COLOR_RESET=$'\033[0m'
else
  COLOR_CURRENT=''
  COLOR_SHORTCUT=''
  COLOR_RESET=''
fi

usage() { cat <<'USAGE'
Usage:
  cmdhelp             Browse, add, edit, or remove commands
  cmdhelp --help      Show this help
USAGE
}

require_fzf() { command -v fzf >/dev/null 2>&1 || { printf '%s requires fzf. Install fzf, then try again.\n' "$APP_NAME" >&2; return 1; }; }
clean_field() { local value=$1; value=${value//$'\t'/ }; value=${value//$'\r'/ }; value=${value//$'\n'/ }; printf '%s' "$value"; }
trim_right_spaces() { local value=$1; printf '%s' "${value%${value##*[! ]}}"; }
prompt_suffix() { [[ "${CMDHELP_POPUP:-0}" == 1 ]] && printf '\n> ' || printf ' '; }
acquire_data_lock() {
  ((DATA_LOCK_HELD)) && return 0
  if ! command -v flock >/dev/null 2>&1; then
    printf '%s requires the flock command (usually provided by util-linux).\n' "$APP_NAME" >&2
    return 1
  fi
  mkdir -p -- "$(dirname -- "$DATA_FILE")"
  exec 9>"$DATA_LOCK_FILE" || return 1
  flock -x 9 || { exec 9>&-; return 1; }
  DATA_LOCK_HELD=1
}
release_data_lock() {
  ((DATA_LOCK_HELD)) || return 0
  flock -u 9 2>/dev/null || true
  exec 9>&-
  DATA_LOCK_HELD=0
}
with_data_lock() {
  acquire_data_lock || { printf 'Could not acquire the cmdhelp data lock.\n' >&2; return 1; }
  local status=0
  "$@" || status=$?
  release_data_lock
  return "$status"
}
array_indices() {
  local i
  for ((i=0; i<${#EXAMPLES[@]}; i++)); do
    printf '%s\n' "$i"
  done
}
read_character() {
  IFS= read -r -s -N 1 "$1"
}
read_character_timeout() {
  IFS= read -r -s -N 1 -t 0.05 "$1"
}
read_input() {
  local variable=$1 input='' character
  while read_character character; do
    case "$character" in
      $'\e')
        # Arrow and navigation keys begin with Escape followed by CSI/SS3.
        # Consume those sequences without treating them as cancel.
        if read_character_timeout character; then
          case "$character" in
            '['|'O')
              while read_character_timeout character; do
                [[ "$character" == [A-Za-z~] ]] && break
              done
              continue
              ;;
          esac
        fi
        printf '\r\033[2K'
        return 1
        ;;
      $'\n'|$'\r') printf '\r\033[2K'; printf -v "$variable" '%s' "$input"; return 0 ;;
      $'\177'|$'\b') if [[ -n "$input" ]]; then input=${input%?}; printf '\b \b'; fi ;;
      *) input+="$character"; printf '%s' "$character" ;;
    esac
  done
  return 1
}
read_yes_no() {
  local variable=$1 input='' character
  while read_character character; do
    case "$character" in
      y|Y|n|N)
        [[ -z "$input" ]] && { input=$character; printf '%s' "$character"; }
        ;;
      $'\n'|$'\r')
        printf '\r\033[2K'
        printf -v "$variable" '%s' "$input"
        return 0
        ;;
      $'\177'|$'\b')
        if [[ -n "$input" ]]; then input=''; printf '\b \b'; fi
        ;;
      $'\e')
        printf '\r\033[2K'
        return 1
        ;;
    esac
  done
  return 1
}
b64_encode() { printf '%s' "$1" | base64 | tr -d '\n'; }
if base64 --help 2>&1 | grep -q -- '--decode'; then
  BASE64_DECODE_OPTION=--decode
else
  BASE64_DECODE_OPTION=-D
fi
b64_decode() { printf '%s' "$1" | base64 "$BASE64_DECODE_OPTION"; }
write_record() { printf '%s\t%s\t%s\t%s\n' "$(b64_encode "$1")" "$(b64_encode "$2")" "$(b64_encode "$3")" "$(b64_encode "$4")"; }

ensure_data_file() {
  mkdir -p -- "$(dirname -- "$DATA_FILE")"
  [[ -e "$DATA_FILE" ]] && return
  local acquired_lock=0
  if (( ! DATA_LOCK_HELD )); then
    acquire_data_lock || return 1
    acquired_lock=1
  fi
  if [[ ! -e "$DATA_FILE" ]]; then
    (
      umask 077
      {
    write_record cat "Display a file's contents in the terminal" 'cat notes.txt' 'Display notes.txt'
    write_record cat "Display a file's contents in the terminal" 'cat -n notes.txt' 'Display notes.txt with line numbers'
    write_record cd 'Change the current directory' 'cd ~/Downloads' 'Move to Downloads'
    write_record cd 'Change the current directory' 'cd -' 'Return to the previous directory'
    write_record chmod 'Change file permissions' 'chmod +x script.sh' 'Make a script executable'
    write_record cp 'Copy files or directories' 'cp report.txt backup.txt' 'Copy a file'
    write_record cp 'Copy files or directories' 'cp -r src/ src-backup/' 'Copy a directory recursively'
    write_record df 'Show free disk space' 'df -h' 'Show human-readable disk usage'
    write_record df 'Show free disk space' 'df -i' 'Show inode usage'
    write_record diff 'Compare two files' 'diff -u old.txt new.txt' 'Compare files with unified output'
    write_record find 'Find files by name or type' "find . -name '*.log'" 'Find log files'
    write_record find 'Find files by name or type' 'find . -type f -mtime -1' 'Find files changed in the last day'
    write_record 'git status' 'Show the state of the working tree' 'git status --short' 'Show a compact status'
    write_record 'git status' 'Show the state of the working tree' 'git status' 'Show the full status'
    write_record less 'Read a file one screen at a time' 'less /var/log/system.log' 'Read a log interactively'
    write_record ls 'List files and directories' 'ls -lah' 'List all files with details'
    write_record ls 'List files and directories' 'ls -lt' 'Sort by modification time'
    write_record mkdir 'Create a directory' 'mkdir reports' 'Create one directory'
    write_record mkdir 'Create a directory' 'mkdir -p project/src' 'Create parent directories as needed'
    write_record mv 'Move or rename files' 'mv draft.txt final.txt' 'Rename a file'
    write_record pwd 'Print the current directory' pwd 'Print the working directory'
    write_record rg 'Search file contents quickly' "rg 'TODO' ." 'Search for TODO markers'
    write_record ssh 'Connect to a remote machine' 'ssh user@example.com' 'Connect to a server'
    write_record tar 'Create or extract a tar archive' 'tar -czf archive.tar.gz folder/' 'Create a compressed archive'
    write_record which 'Show which executable will run' 'command -v git' 'Find the executable on PATH'
      } >"$DATA_FILE"
    )
    chmod 600 -- "$DATA_FILE"
  fi
  (( acquired_lock )) && release_data_lock
}

command_rows() {
  local with_preview=${1:-0} ec ed ee exd command_name description example example_description preview_encoded
  local -a command_names=()
  local -A descriptions=() previews=()
  while IFS=$'\t' read -r ec ed ee exd; do
    [[ -n "$ec" ]] || continue
    command_name=$(b64_decode "$ec")
    if [[ -z "${descriptions[$command_name]+yes}" ]]; then
      command_names+=("$command_name")
      descriptions[$command_name]=$(b64_decode "$ed")
      if [[ "$with_preview" == 1 ]]; then
        previews[$command_name]="Description: ${descriptions[$command_name]}"$'\n\n''Examples:'$'\n'
      fi
    fi
    if [[ "$with_preview" == 1 && -n "$ee" ]]; then
      example=$(b64_decode "$ee")
      example_description=$(b64_decode "$exd")
      previews[$command_name]+="$example"
      [[ -n "$example_description" ]] && previews[$command_name]+=" — $example_description"
      previews[$command_name]+=$'\n'
    fi
  done <"$DATA_FILE"
  for command_name in "${command_names[@]}"; do
    if [[ "$with_preview" == 1 ]]; then
      preview_encoded=$(b64_encode "${previews[$command_name]}")
      printf '%-*s\t│ %s\t%s\n' "$COMMAND_COLUMN_WIDTH" "$command_name" "${descriptions[$command_name]}" "$preview_encoded"
    else
      printf '%-*s\t│ %s\n' "$COMMAND_COLUMN_WIDTH" "$command_name" "${descriptions[$command_name]}"
    fi
  done
}

load_command() {
  local target=$1 ec ed ee exd
  EXAMPLES=(); EXAMPLE_DESCRIPTIONS=(); COMMAND_DESCRIPTION=''
  while IFS=$'\t' read -r ec ed ee exd; do
    [[ -n "$ec" && "$(b64_decode "$ec")" == "$target" ]] || continue
    COMMAND_DESCRIPTION=$(b64_decode "$ed")
    [[ -n "$ee" ]] || continue
    EXAMPLES+=("$(b64_decode "$ee")")
    EXAMPLE_DESCRIPTIONS+=("$(b64_decode "$exd")")
  done <"$DATA_FILE"
}

list_commands() { ensure_data_file; printf '%-*s │ %s\n' "$COMMAND_COLUMN_WIDTH" 'COMMAND' 'DESCRIPTION'; command_rows | LC_ALL=C sort -f -t $'\t' -k1,1 | awk -F '\t' '{ sub(/[[:space:]]+$/, "", $1); sub(/^│ /, "", $2); printf "%-28s │ %s\n", $1, $2 }'; }
example_exists() { local candidate=$1 skip=${2:--1} i; for i in $(array_indices); do [[ "$i" != "$skip" && "${EXAMPLES[$i]}" == "$candidate" ]] && return 0; done; return 1; }
print_examples() { local i; for i in $(array_indices); do printf '  %s' "${EXAMPLES[$i]}"; [[ -n "${EXAMPLE_DESCRIPTIONS[$i]}" ]] && printf ' — %s' "${EXAMPLE_DESCRIPTIONS[$i]}"; printf '\n'; done; }
add_example_prompt() {
  local example example_description
  printf 'Example command:'; prompt_suffix; read_input example || return 1
  example=$(clean_field "$example")
  [[ -z "$example" ]] && return 0
  if example_exists "$example"; then
    printf 'That example is already in this command.\n' >&2
    return 0
  fi
  printf 'Example description (optional):'; prompt_suffix; read_input example_description || return 1
  EXAMPLES+=("$example")
  EXAMPLE_DESCRIPTIONS+=("$(clean_field "$example_description")")
}
edit_example_prompt() {
  local i=$1 replacement
  printf 'New text (current: %s%s%s; blank keeps it):' "$COLOR_CURRENT" "${EXAMPLES[$i]}" "$COLOR_RESET"; prompt_suffix
  read_input replacement || return 1
  replacement=$(clean_field "$replacement")
  if [[ -n "$replacement" && "$replacement" != "${EXAMPLES[$i]}" ]]; then
    if example_exists "$replacement" "$i"; then
      printf 'That example already exists.\n' >&2
    else
      EXAMPLES[$i]=$replacement
    fi
  fi
  if [[ -n "${EXAMPLE_DESCRIPTIONS[$i]}" ]]; then
    printf 'New description (current: %s%s%s; blank keeps it):' "$COLOR_CURRENT" "${EXAMPLE_DESCRIPTIONS[$i]}" "$COLOR_RESET"; prompt_suffix
  else
    printf 'New description (current: %snone%s; blank keeps it):' "$COLOR_CURRENT" "$COLOR_RESET"; prompt_suffix
  fi
  read_input replacement || return 1
  replacement=$(clean_field "$replacement")
  [[ -n "$replacement" ]] && EXAMPLE_DESCRIPTIONS[$i]=$replacement
}
delete_example_prompt() {
  local i=$1 answer
  printf 'Delete this example? [y/N]:'; prompt_suffix
  read_yes_no answer || return 1
  case "$answer" in
    y|Y)
      unset "EXAMPLES[$i]" "EXAMPLE_DESCRIPTIONS[$i]"
      EXAMPLES=("${EXAMPLES[@]}")
      EXAMPLE_DESCRIPTIONS=("${EXAMPLE_DESCRIPTIONS[@]}")
      ;;
  esac
}
add_example_to_command_unlocked() {
  local target=$1
  load_command "$target"
  add_example_prompt || return 1
  save_command_changes "$target" "$target" "$COMMAND_DESCRIPTION"
}
edit_example_to_command_unlocked() {
  local target=$1 index=$2
  load_command "$target"
  edit_example_prompt "$index" || return 1
  save_command_changes "$target" "$target" "$COMMAND_DESCRIPTION"
}
remove_example_from_command_unlocked() {
  local target=$1 index=$2
  load_command "$target"
  delete_example_prompt "$index" || return 1
  save_command_changes "$target" "$target" "$COMMAND_DESCRIPTION"
}
add_example_to_command() { with_data_lock add_example_to_command_unlocked "$@"; }
edit_example_to_command() { with_data_lock edit_example_to_command_unlocked "$@"; }
remove_example_from_command() { with_data_lock remove_example_from_command_unlocked "$@"; }

add_command_unlocked() {
  ensure_data_file; local command_name description example example_description i; local -a EXAMPLES=() EXAMPLE_DESCRIPTIONS=()
  printf 'Command:'; prompt_suffix; read_input command_name || return 1; command_name=$(clean_field "$command_name")
  command_rows | awk -F '\t' -v key="$command_name" '$1 == key { found=1 } END { exit !found }' && { printf '“%s” is already in the command list. Nothing was added.\n' "$command_name" >&2; return 1; }
  [[ -n "$command_name" ]] || { printf 'A command name is required.\n' >&2; return 1; }
  printf 'Brief description:'; prompt_suffix; read_input description || return 1; description=$(clean_field "$description"); [[ -n "$description" ]] || { printf 'A description is required.\n' >&2; return 1; }
  printf '\nExamples so far:\n'
  printf '  (none yet)\n'
  while true; do
    printf 'Example command (leave blank when done):'; prompt_suffix; read_input example || return 1; example=$(clean_field "$example"); [[ -z "$example" ]] && break
    if example_exists "$example"; then printf 'That example is already in this command.\n' >&2; continue; fi
    printf 'Example description (optional):'; prompt_suffix; read_input example_description || return 1
    example_description=$(clean_field "$example_description")
    EXAMPLES+=("$example"); EXAMPLE_DESCRIPTIONS+=("$example_description")
    printf '  %s' "$example"
    [[ -n "$example_description" ]] && printf ' — %s' "$example_description"
    printf '\n'
  done
  if ((${#EXAMPLES[@]} == 0)); then write_record "$command_name" "$description" '' '' >>"$DATA_FILE"; else for i in $(array_indices); do write_record "$command_name" "$description" "${EXAMPLES[$i]}" "${EXAMPLE_DESCRIPTIONS[$i]}" >>"$DATA_FILE"; done; fi
  printf 'Added “%s”.\n' "$command_name"
}
add_command() { with_data_lock add_command_unlocked; }

manage_examples() {
  local selected kind i label action example replacement answer example_description
  while true; do
    selected=$(for i in $(array_indices); do printf 'I\t%s\t%-*s\t│\t%s\n' "$i" "$EXAMPLE_COLUMN_WIDTH" "${EXAMPLES[$i]}" "${EXAMPLE_DESCRIPTIONS[$i]}"; done | fzf --height='65%' --layout=reverse --border=rounded --padding=1 --pointer='▌' --cycle --ansi --delimiter=$'\t' --with-nth=3,4,5 --prompt='Examples> ' --header="$(printf '%-*s\t│ %s' "$EXAMPLE_COLUMN_WIDTH" EXAMPLE DESCRIPTION)" --footer="$(printf '%sCtrl-I%s: insert · %sCtrl-E%s: edit · %sCtrl-R%s: delete · %sEsc%s: edit menu' "$COLOR_SHORTCUT" "$COLOR_RESET" "$COLOR_SHORTCUT" "$COLOR_RESET" "$COLOR_SHORTCUT" "$COLOR_RESET" "$COLOR_SHORTCUT" "$COLOR_RESET")" --bind='ctrl-i:become(printf "__cmdhelp_add_example__\\n")' --bind='ctrl-e:become(printf "__cmdhelp_edit_example__\\t%s\\n" {1})' --bind='ctrl-r:become(printf "__cmdhelp_delete_example__\\t%s\\n" {1})' --no-multi) || return 0
    IFS=$'\t' read -r kind i label <<<"$selected"
    case "$kind" in
      __cmdhelp_add_example__) add_example_prompt || continue ;;
      __cmdhelp_edit_example__) edit_example_prompt "$i" || continue ;;
      __cmdhelp_delete_example__) delete_example_prompt "$i" || continue ;;
      I) action=$(printf '%s\n' 'Edit example' 'Delete example' 'Back' | fzf --height='40%' --layout=reverse --border=rounded --padding=1 --pointer='▌' --cycle --ansi --prompt='Example> ' --header="${EXAMPLES[$i]}" --footer="$(printf '%sEnter%s: choose · %sEsc%s: examples' "$COLOR_SHORTCUT" "$COLOR_RESET" "$COLOR_SHORTCUT" "$COLOR_RESET")" --no-multi) || continue; case "$action" in
        'Edit example') edit_example_prompt "$i" || continue ;;
        'Delete example') delete_example_prompt "$i" || continue ;;
      esac ;;
    esac
  done
}

rewrite_command() {
  local old_name=$1 new_name=$2 description=$3 temp_file=$4 ec ed ee exd i
  while IFS=$'\t' read -r ec ed ee exd; do
    [[ -n "$ec" ]] || continue
    if [[ "$(b64_decode "$ec")" != "$old_name" ]]; then printf '%s\t%s\t%s\t%s\n' "$ec" "$ed" "$ee" "$exd" >>"$temp_file"; fi
  done <"$DATA_FILE"
  if ((${#EXAMPLES[@]} == 0)); then write_record "$new_name" "$description" '' '' >>"$temp_file"; else for i in $(array_indices); do write_record "$new_name" "$description" "${EXAMPLES[$i]}" "${EXAMPLE_DESCRIPTIONS[$i]}" >>"$temp_file"; done; fi
}
save_command_changes_unlocked() {
  local old_name=$1 new_name=$2 description=$3 temp_file
  temp_file=$(mktemp "${DATA_FILE}.XXXXXX")
  rewrite_command "$old_name" "$new_name" "$description" "$temp_file"
  mv -- "$temp_file" "$DATA_FILE"
}
save_command_changes() { with_data_lock save_command_changes_unlocked "$@"; }
edit_command_details() {
  local old_name=$1 command_name description replacement
  load_command "$old_name"
  command_name=$old_name
  description=$COMMAND_DESCRIPTION
  printf 'New command name (current: %s%s%s; blank keeps it):' "$COLOR_CURRENT" "$command_name" "$COLOR_RESET"; prompt_suffix
  if read_input replacement; then
    replacement=$(clean_field "$replacement")
    [[ -n "$replacement" ]] && command_name=$replacement
  else
    save_command_changes "$old_name" "$command_name" "$description"
    return 0
  fi
  printf 'New description (current: %s%s%s; blank keeps it):' "$COLOR_CURRENT" "$description" "$COLOR_RESET"; prompt_suffix
  if read_input replacement; then
    replacement=$(clean_field "$replacement")
    [[ -n "$replacement" ]] && description=$replacement
  fi
  save_command_changes "$old_name" "$command_name" "$description"
}

edit_command_unlocked() {
  ensure_data_file; require_fzf; local target=${1:-} row command_name old_name description action replacement temp_file shortcut_mode=0
  [[ -n "$target" ]] && shortcut_mode=1
  while true; do
    if ((shortcut_mode)); then
      command_name=$target
    else
      row=$(command_rows 1 | LC_ALL=C sort -f -t $'\t' -k1,1 | fzf --height='80%' --layout=reverse --border=rounded --padding=1 --pointer='▌' --cycle --ansi --delimiter=$'\t' --with-nth=1,2 --prompt='Edit command> ' --header="$(printf '%-*s\t│ %s' "$COMMAND_COLUMN_WIDTH" COMMAND DESCRIPTION)" --footer="$(printf '%sEnter%s: edit command · %sEsc%s: close' "$COLOR_SHORTCUT" "$COLOR_RESET" "$COLOR_SHORTCUT" "$COLOR_RESET")" --preview='base64 -d <<< {3}' --preview-window='right:50%:wrap' --no-multi) || return 0
      IFS=$'\t' read -r command_name description _ <<<"$row"
      command_name=$(trim_right_spaces "$command_name")
    fi
    old_name=$command_name
    load_command "$command_name"
    description=$COMMAND_DESCRIPTION
    while true; do
      action=$(printf '%s\n' 'Name' 'Description' 'Examples' | fzf --height='45%' --layout=reverse --border=rounded --padding=1 --pointer='▌' --cycle --ansi --prompt="Edit ${command_name}> " --footer="$(printf '%sEnter%s: choose · %sEsc%s: back' "$COLOR_SHORTCUT" "$COLOR_RESET" "$COLOR_SHORTCUT" "$COLOR_RESET")" --no-multi) || {
        save_command_changes "$old_name" "$command_name" "$description" || return 1
        ((shortcut_mode)) && return 0 || break
      }
      case "$action" in
        Name) printf 'New command name (current: %s%s%s; blank keeps it):' "$COLOR_CURRENT" "$command_name" "$COLOR_RESET"; prompt_suffix; read_input replacement || continue; replacement=$(clean_field "$replacement"); [[ -n "$replacement" ]] && command_name=$replacement ;;
        Description) printf 'New description (current: %s%s%s; blank keeps it):' "$COLOR_CURRENT" "$description" "$COLOR_RESET"; prompt_suffix; read_input replacement || continue; replacement=$(clean_field "$replacement"); [[ -n "$replacement" ]] && description=$replacement ;;
        Examples) manage_examples ;;
      esac
    done
  done
}
edit_command() { with_data_lock edit_command_unlocked "$@"; }

remove_command_entry() { local target=$1 ec ed ee exd temp_file; temp_file=$(mktemp "${DATA_FILE}.XXXXXX"); while IFS=$'\t' read -r ec ed ee exd; do [[ -n "$ec" && "$(b64_decode "$ec")" == "$target" ]] || printf '%s\t%s\t%s\t%s\n' "$ec" "$ed" "$ee" "$exd" >>"$temp_file"; done <"$DATA_FILE"; mv -- "$temp_file" "$DATA_FILE"; printf 'Removed “%s” and its examples.\n' "$target"; }
confirm_and_remove() { local target=$1 answer; printf 'Remove “%s” and all its examples? [y/N]:' "$target"; prompt_suffix; read_yes_no answer || return 1; case "$answer" in y|Y) remove_command_entry "$target";; n|N|'') printf 'Kept “%s”.\n' "$target"; return 1;; esac; }
remove_command_unlocked() { ensure_data_file; require_fzf; local target=${1:-} row command_name; if [[ -n "$target" ]]; then confirm_and_remove "$target" || true; return 0; fi; row=$(command_rows | LC_ALL=C sort -f -t $'\t' -k1,1 | fzf --height='80%' --layout=reverse --border=rounded --padding=1 --pointer='▌' --cycle --delimiter=$'\t' --with-nth=1,2 --prompt='Remove command> ' --header="$(printf '%-*s\t│ %s' "$COMMAND_COLUMN_WIDTH" COMMAND DESCRIPTION)" --no-multi) || return 0; IFS=$'\t' read -r command_name _ <<<"$row"; command_name=$(trim_right_spaces "$command_name"); confirm_and_remove "$command_name" || true; }
remove_command() { with_data_lock remove_command_unlocked "$@"; }
show_overlay() {
  ensure_data_file; require_fzf
  local row command_name description examples selected key selected_row i command example_description preview_encoded popup_add_command popup_edit_command popup_remove_command command_reload bind_add bind_edit bind_remove example_popup_add example_popup_edit example_popup_remove example_reload example_bind_add example_bind_edit example_bind_remove example_index_base
  bind_add='ctrl-i:become(printf "__cmdhelp_add__\\n")'
  bind_edit='ctrl-e:become(printf "__cmdhelp_edit__\\t%s\\n" {1})'
  bind_remove='ctrl-r:become(printf "__cmdhelp_remove__\\t%s\\n" {1})'
  if [[ -n "${TMUX:-}" ]] && command -v tmux >/dev/null 2>&1; then
    printf -v popup_add_command 'tmux display-popup -E -e CMDHELP_POPUP=1 -xC -yC -w 72 -h 20 -T %q -- bash %q add-command' 'Add command' "$CMDHELP_SCRIPT_FILE"
    printf -v popup_edit_command 'tmux display-popup -E -e CMDHELP_POPUP=1 -xC -yC -w 72 -h 12 -T %q -- bash %q edit-command' 'Edit command' "$CMDHELP_SCRIPT_FILE"
    printf -v popup_remove_command 'tmux display-popup -E -e CMDHELP_POPUP=1 -xC -yC -w 60 -h 8 -T %q -- bash %q remove-command' 'Remove command' "$CMDHELP_SCRIPT_FILE"
    printf -v command_reload 'bash %q list-commands' "$CMDHELP_SCRIPT_FILE"
    bind_add="ctrl-i:execute-silent($popup_add_command)+reload($command_reload)"
    bind_edit="ctrl-e:execute-silent($popup_edit_command {1})+reload($command_reload)"
    bind_remove="ctrl-r:execute-silent($popup_remove_command {1})+reload($command_reload)"
  fi
  while true; do
    row=$(
      command_rows 1 | LC_ALL=C sort -f -t $'\t' -k1,1 |
        fzf --height='80%' --layout=reverse --border=rounded --padding=1 --pointer='▌' --cycle \
          --delimiter=$'\t' --with-nth=1,2 --prompt='Commands> ' --ansi \
          --header="$(printf '%-*s\t│ %s' "$COMMAND_COLUMN_WIDTH" COMMAND DESCRIPTION)" \
          --footer="$(printf '%sCtrl-I%s: insert · %sCtrl-E%s: edit · %sCtrl-R%s: remove · %sEnter%s: examples · %sEsc%s: close' "$COLOR_SHORTCUT" "$COLOR_RESET" "$COLOR_SHORTCUT" "$COLOR_RESET" "$COLOR_SHORTCUT" "$COLOR_RESET" "$COLOR_SHORTCUT" "$COLOR_RESET" "$COLOR_SHORTCUT" "$COLOR_RESET")" \
          --bind="$bind_add" \
          --bind="$bind_edit" \
          --bind="$bind_remove" \
          --preview='base64 -d <<< {3}' --preview-window='right:50%:wrap' --no-multi
    ) || return 0
    IFS=$'\t' read -r command_name description preview_encoded <<<"$row"
    command_name=$(trim_right_spaces "$command_name")
    case "$command_name" in
      __cmdhelp_add__) add_command || true; continue ;;
      __cmdhelp_edit__) command_name=$(trim_right_spaces "$description"); with_data_lock edit_command_details "$command_name"; continue ;;
      __cmdhelp_remove__) command_name=$(trim_right_spaces "$description"); remove_command "$command_name"; continue ;;
    esac
    load_command "$command_name"
    if ((${#EXAMPLES[@]} == 0)); then
      printf 'No examples saved for %s.\n' "$command_name" >&2
      continue
    fi
    while true; do
      examples=$(for i in $(array_indices); do printf '%s\t%-*s\t│\t%s\n' "$i" "$EXAMPLE_COLUMN_WIDTH" "${EXAMPLES[$i]}" "${EXAMPLE_DESCRIPTIONS[$i]}"; done)
      example_bind_add='ctrl-i:become(printf "__cmdhelp_add_example__\\n")'
      example_bind_edit='ctrl-e:become(printf "__cmdhelp_edit_example__\\t%s\\n" {1})'
      example_bind_remove='ctrl-r:become(printf "__cmdhelp_delete_example__\\t%s\\n" {1})'
      if [[ -n "${TMUX:-}" ]] && command -v tmux >/dev/null 2>&1; then
        example_index_base=0
        printf -v example_popup_add 'tmux display-popup -E -e CMDHELP_POPUP=1 -xC -yC -w 72 -h 16 -T %q -- bash %q add-example %q' 'Add example' "$CMDHELP_SCRIPT_FILE" "$command_name"
        printf -v example_popup_edit 'tmux display-popup -E -e CMDHELP_POPUP=1 -xC -yC -w 72 -h 14 -T %q -- bash %q edit-example %q %q' 'Edit example' "$CMDHELP_SCRIPT_FILE" "$command_name" "$example_index_base"
        printf -v example_popup_remove 'tmux display-popup -E -e CMDHELP_POPUP=1 -xC -yC -w 60 -h 8 -T %q -- bash %q remove-example %q %q' 'Remove example' "$CMDHELP_SCRIPT_FILE" "$command_name" "$example_index_base"
        printf -v example_reload 'CMDHELP_ARRAY_BASE=%q EXAMPLE_COLUMN_WIDTH=%q bash %q list-examples %q' "$example_index_base" "$EXAMPLE_COLUMN_WIDTH" "$CMDHELP_SCRIPT_FILE" "$command_name"
        example_bind_add="ctrl-i:execute-silent($example_popup_add)"
        example_bind_edit="ctrl-e:execute-silent($example_popup_edit {1})+reload($example_reload)"
        example_bind_remove="ctrl-r:execute-silent($example_popup_remove {1})+reload($example_reload)"
        example_bind_add="ctrl-i:execute-silent($example_popup_add)+reload($example_reload)"
      fi
      selected=$(printf '%s\n' "$examples" | fzf --height='60%' --layout=reverse --border=rounded --padding=1 --pointer='▌' --cycle --ansi --delimiter=$'\t' --with-nth=2,3,4 --prompt='Examples> ' --header="$(printf '%-*s\t│ %s' "$EXAMPLE_COLUMN_WIDTH" EXAMPLE DESCRIPTION)" --footer="$(printf '%sCtrl-I%s: insert · %sCtrl-E%s: edit · %sCtrl-R%s: remove · %sEnter%s: copy & close · %sEsc%s: back' "$COLOR_SHORTCUT" "$COLOR_RESET" "$COLOR_SHORTCUT" "$COLOR_RESET" "$COLOR_SHORTCUT" "$COLOR_RESET" "$COLOR_SHORTCUT" "$COLOR_RESET" "$COLOR_SHORTCUT" "$COLOR_RESET")" --bind="$example_bind_add" --bind="$example_bind_edit" --bind="$example_bind_remove" --no-multi) || break
      IFS=$'\t' read -r key i command _ example_description <<<"$selected"
      if [[ "$key" != __cmdhelp_add_example__ && "$key" != __cmdhelp_edit_example__ && "$key" != __cmdhelp_delete_example__ ]]; then
        command=$i
        i=$key
      fi
      case "$key" in
        __cmdhelp_add_example__)
          add_example_to_command "$command_name" || true
          continue
          ;;
        __cmdhelp_edit_example__)
          edit_example_to_command "$command_name" "$i" || true
          continue
          ;;
        __cmdhelp_delete_example__)
          remove_example_from_command "$command_name" "$i" || true
          continue
          ;;
      esac
      command=$(trim_right_spaces "$command")
      if copy_to_clipboard "$command"; then
        printf 'Copied to clipboard: %s\n' "$command" >&2
        return 0
      else
        printf 'Could not copy the example: install a clipboard utility.\n' >&2
        return 1
      fi
    done
  done
}
copy_to_clipboard() { local value=$1; if command -v wl-copy >/dev/null 2>&1; then printf '%s' "$value" | wl-copy; elif command -v xclip >/dev/null 2>&1; then printf '%s' "$value" | xclip -selection clipboard; elif command -v xsel >/dev/null 2>&1; then printf '%s' "$value" | xsel --clipboard --input; elif command -v pbcopy >/dev/null 2>&1; then printf '%s' "$value" | pbcopy; elif command -v clip.exe >/dev/null 2>&1; then printf '%s' "$value" | clip.exe; else return 1; fi; }
run_in_temporary_tmux() {
  [[ -z "${TMUX:-}" ]] || return 1
  [[ "${CMDHELP_NO_TMUX:-0}" != 1 ]] || return 1
  [[ -t 1 ]] || return 1
  command -v tmux >/dev/null 2>&1 || return 1

  local session_name="cmdhelp-$$-${RANDOM:-0}" shell_path script_path child_command attach_status
  shell_path=${SHELL:-/bin/bash}
  script_path="$CMDHELP_SCRIPT_FILE"
  printf -v script_path '%q' "$script_path"
  child_command="cleanup_cmdhelp_tmux() { tmux kill-session -t '$session_name' 2>/dev/null || true; }; trap cleanup_cmdhelp_tmux EXIT; trap 'exit 143' INT TERM; CMDHELP_NO_TMUX=1; bash $script_path"

  tmux new-session -d -s "$session_name" "$shell_path" -lc "$child_command" || return 1
  tmux attach-session -t "$session_name"
  attach_status=$?
  tmux kill-session -t "$session_name" 2>/dev/null || true
  return "$attach_status"
}
popup_pause() {
  printf '\n%s\nPress Enter to close. ' "$1"
  IFS= read -r || true
}
run_popup_action() {
  local popup_action=${1:-} popup_command popup_array_base popup_index popup_index_base popup_row_index
  case "$popup_action" in
    add-command)
      add_command
      ;;
    edit-command)
      with_data_lock edit_command_details "$(trim_right_spaces "${2:-}")"
      ;;
    remove-command)
      with_data_lock confirm_and_remove "$(trim_right_spaces "${2:-}")"
      ;;
    add-example)
      popup_command=$(trim_right_spaces "${2:-}")
      add_example_to_command "$popup_command"
      ;;
    edit-example)
      popup_command=$(trim_right_spaces "${2:-}")
      popup_array_base=${3:-0}
      popup_index=${4:-0}
      [[ "$popup_array_base" == 1 ]] && popup_index=$((popup_index - 1))
      load_command "$popup_command"
      [[ -n "${EXAMPLES[$popup_index]+present}" ]] || { popup_pause 'The selected example could not be found.'; return 1; }
      edit_example_to_command "$popup_command" "$popup_index"
      ;;
    remove-example)
      popup_command=$(trim_right_spaces "${2:-}")
      popup_array_base=${3:-0}
      popup_index=${4:-0}
      [[ "$popup_array_base" == 1 ]] && popup_index=$((popup_index - 1))
      load_command "$popup_command"
      [[ -n "${EXAMPLES[$popup_index]+present}" ]] || { popup_pause 'The selected example could not be found.'; return 1; }
      remove_example_from_command "$popup_command" "$popup_index"
      ;;
    list-examples)
      popup_command=$(trim_right_spaces "${2:-}")
      load_command "$popup_command"
      popup_index_base=${CMDHELP_ARRAY_BASE:-0}
      for popup_index in "${!EXAMPLES[@]}"; do
        popup_row_index=$((popup_index + popup_index_base))
        printf '%s\t%-*s\t│\t%s\n' "$popup_row_index" "${EXAMPLE_COLUMN_WIDTH:-56}" "${EXAMPLES[$popup_index]}" "${EXAMPLE_DESCRIPTIONS[$popup_index]}"
      done
      ;;
    list-commands)
      ensure_data_file
      command_rows 1 | LC_ALL=C sort -f -t $'\t' -k1,1
      ;;
    *)
      return 2
      ;;
  esac
}
main() {
  case "${1:-}" in
    '')
      if run_in_temporary_tmux; then
        return 0
      fi
      show_overlay
      ;;
    add-command|edit-command|remove-command|add-example|edit-example|remove-example|list-examples|list-commands)
      run_popup_action "$@"
      ;;
    -h|--help|help) usage;;
    *) usage >&2; return 2;;
  esac
}

if [[ "${BASH_SOURCE[0]:-}" == "$0" ]]; then
  main "$@"
fi
