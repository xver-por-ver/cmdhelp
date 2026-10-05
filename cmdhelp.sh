#!/usr/bin/env bash

# Keep strict options scoped to direct execution; the popup actions reuse this
# same standalone command without launching the interactive picker.
if [[ "${BASH_SOURCE[0]:-}" == "$0" ]]; then
  set -euo pipefail
fi

APP_NAME=cmdhelp
CMDHELP_SCRIPT_FILE=${BASH_SOURCE[0]:-$0}
DATA_DIR="${XDG_DATA_HOME:-${HOME}/.local/share}/cmdhelp"
DATA_FILE="${CMDHELP_DATA_FILE:-${DATA_DIR}/commands.tsv}"
DATA_LOCK_FILE="${DATA_FILE}.lock"
DATA_LOCK_HELD=0
COMMAND_COLUMN_WIDTH=28
EXAMPLE_COLUMN_WIDTH=56
CMDHELP_MAX_INPUT_CHARS=2048
if [[ -t 1 ]]; then
  COLOR_CURRENT=$'\033[1;36m'
  COLOR_SHORTCUT=$'\033[1;33m'
  COLOR_SUCCESS=$'\033[92m'
  COLOR_ERROR=$'\033[1;31m'
  COLOR_RESET=$'\033[0m'
else
  COLOR_CURRENT=''
  COLOR_SHORTCUT=''
  COLOR_SUCCESS=''
  COLOR_ERROR=''
  COLOR_RESET=''
fi
COMMAND=''
COMMAND_DESCRIPTION=''
EXAMPLES=()
EXAMPLE_DESCRIPTIONS=()

usage() {
  cat <<'USAGE'
Usage:
  cmdhelp             Browse, add, edit, or remove commands
  cmdhelp --help      Show this help
USAGE
}

require_fzf() { 
  command -v fzf >/dev/null 2>&1 || {
    printf '%s requires fzf. Install fzf, then try again.\n' "$APP_NAME" >&2
    return 1
  }; 
}

clean_field() {
  local value=$1
  value=${value//$'\t'/ }
  value=${value//$'\r'/ }
  value=${value//$'\n'/ }
  printf '%s' "$value"
}

trim_spaces() {
  local value=$1
  value=${value#"${value%%[! ]*}"}
  value=${value%"${value##*[! ]}"}
  printf '%s' "$value"
}

prompt_suffix() { [[ "${CMDHELP_POPUP:-0}" == 1 ]] && printf '\n> ' || printf ' '; }

acquire_data_lock() {
  ((DATA_LOCK_HELD)) && return 0
  if ! command -v flock >/dev/null 2>&1; then
    printf '%s requires the flock command (usually provided by util-linux).\n' "$APP_NAME" >&2
    return 1
  fi
  mkdir -p -- "$(dirname -- "$DATA_FILE")"
  exec 9>"$DATA_LOCK_FILE" || return 1
  flock -xn 9 || {
    exec 9>&-
    printf 'A different session is currenly editing the Database. Please wait.\n' >&2
    popup_pause
    return 1
  }
  DATA_LOCK_HELD=1
}

release_data_lock() {
  ((DATA_LOCK_HELD)) || return 0
  flock -u 9 2>/dev/null || true
  exec 9>&-
  DATA_LOCK_HELD=0
}

with_data_lock() {
  acquire_data_lock || return 1
  local status=0
  "$@" || status=$?
  release_data_lock
  return "$status"
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
        '[' | 'O')
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
    $'\n' | $'\r')
      printf '\r\033[2K'
      printf -v "$variable" '%s' "$input"
      return 0
      ;;
    $'\177' | $'\b') if [[ -n "$input" ]]; then
      input=${input%?}
      printf '\b \b'
    fi ;;
    *)
      if ((${#input} >= CMDHELP_MAX_INPUT_CHARS)); then
        printf '\a'
        continue
      fi
      input+="$character"
      printf '%s' "$character"
      ;;
    esac
  done
  return 1
}

read_yes_no() {
  local variable=$1 input='' character
  while read_character character; do
    case "$character" in
      y | Y | n | N)
        [[ -z "$input" ]] && {
          input=$character
          printf '%s' "$character"
        }
        ;;
      $'\n' | $'\r')
        printf '\r\033[2K'
        printf -v "$variable" '%s' "$input"
        return 0
        ;;
      $'\177' | $'\b')
        if [[ -n "$input" ]]; then
          input=''
          printf '\b \b'
        fi
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
write_record() { printf '%s\t%s\t%s\n' "$(b64_encode "$1")" "$(b64_encode "$2")" "$(b64_encode "$3")"; }

ensure_data_file() {
  mkdir -p -- "$(dirname -- "$DATA_FILE")"
  [[ -e "$DATA_FILE" ]] && return
  local acquired_lock=0
  if ((! DATA_LOCK_HELD)); then
    acquire_data_lock || return 1
    acquired_lock=1
  fi
  if [[ ! -e "$DATA_FILE" ]]; then
    (
      umask 077
      {
        write_record cat "Display a file's contents in the terminal" "$(example_column_format "cat notes.txt" "Display notes.txt")"
        write_record cd 'Change the current directory' "$(example_column_format "cd ~/Downloads" "Move to Downloads")"
        write_record chmod 'Change file permissions' "$(example_column_format "chmod +x script.sh" "Make a script executable")"
        write_record cp 'Copy files or directories' "$(example_column_format "cp report.txt backup.txt" "Copy a file")"
        write_record df 'Show free disk space' "$(example_column_format "df -h" "Show human-readable disk usage")"
        write_record diff 'Compare two files' "$(example_column_format "diff -u old.txt new.txt" "Compare files with unified output")"
        write_record find 'Find files by name or type' "$(example_column_format "find . -name *.log'" "Find log files")"
        write_record git 'Interact with GIT distributed version control system' "$(example_column_format "git status --short" "Show a compact status")"
        write_record less 'Read a file one screen at a time' "$(example_column_format "less /var/log/system.log" "Read a log interactively")"
        write_record ls 'List files and directories' "$(example_column_format "ls -lah" "List all files with details")"
        write_record mkdir 'Create a directory' "$(example_column_format "mkdir reports" "Create one directory")"
        write_record mv 'Move or rename files' "$(example_column_format "mv draft.txt final.txt" "Rename a file")"
        write_record pwd 'Print the current directory' "$(example_column_format "pwd" "Print the working directory")"
        write_record rg 'Search file contents quickly' "$(example_column_format "rg 'TODO' ." "Search for TODO markers")"
        write_record ssh 'Connect to a remote machine' "$(example_column_format "ssh user@example.com" "Connect to a server")"
        write_record tar 'Create or extract a tar archive' "$(example_column_format "tar -czf archive.tar.gz folder/" "Create a compressed archive")"
        write_record which 'Show which executable will run' "$(example_column_format "command -v git" "Find the executable on PATH")"
      } >"$DATA_FILE"
    )
    chmod 600 -- "$DATA_FILE"
  fi
  ((acquired_lock)) && release_data_lock
}

command_rows() {
  local ec ed ee command_name description example_record example_name example_description preview_encoded i
  local -a command_names=() example_records=()
  local -A descriptions=() previews=()
  while IFS=$'\t' read -r ec ed ee; do
    [[ -n "$ec" ]] || continue
    command_name=$(b64_decode "$ec")
    if [[ -z "${descriptions[$command_name]+yes}" ]]; then
      command_names+=("$command_name")
      descriptions[$command_name]=$(b64_decode "$ed")
      previews[$command_name]="Description: ${descriptions[$command_name]}"$'\n\n''Examples:'$'\n'
    fi  
    if [[ -n "$ee" ]]; then
      example_records=()
      IFS=';' read -r -a example_records <<<"$(b64_decode "$ee")"
      for example_record in "${example_records[@]}"; do
        [[ -n "$example_record" ]] || continue
        IFS=$'\t' read -r example_name example_description <<<"$example_record"
        [[ -n "$example_name" ]] || continue
        example_name=$(b64_decode "$example_name")
        example_description=$(b64_decode "${example_description:-}")
        previews[$command_name]+=$(printf '%-*s\t│ %s' "$COMMAND_COLUMN_WIDTH" "$example_name" "$example_description")
        previews[$command_name]+=$'\n'
      done
    fi
  done <"$DATA_FILE"
  for command_name in "${command_names[@]}"; do
    preview_encoded=$(b64_encode "${previews[$command_name]}")
    printf '%-*s\t│ %s\t%s\n' "$COMMAND_COLUMN_WIDTH" "$command_name" "${descriptions[$command_name]}" "$preview_encoded"
  done
}

load_command() {
  local target=$1 ec ed ee example_record example_name example_description
  local -a example_records=()
  COMMAND=''
  COMMAND_DESCRIPTION=''
  EXAMPLES=()
  EXAMPLE_DESCRIPTIONS=()
  while IFS=$'\t' read -r ec ed ee; do
    [[ -n "$ec" && "$(b64_decode "$ec")" == "$target" ]] || continue
    COMMAND=$(b64_decode "$ec")
    COMMAND_DESCRIPTION=$(b64_decode "$ed")
    [[ -n "$ee" ]] || break
    example_records=()
    IFS=';' read -r -a example_records <<<"$(b64_decode "$ee")"
    for example_record in "${example_records[@]}"; do
      [[ -n "$example_record" ]] || continue
      IFS=$'\t' read -r example_name example_description <<<"$example_record"
      [[ -n "$example_name" ]] || continue
      EXAMPLES+=("$(b64_decode "$example_name")")
      EXAMPLE_DESCRIPTIONS+=("$(b64_decode "${example_description:-}")")
    done
    break
  done <"$DATA_FILE"
}

command_exists() {
  local candidate=$1
  load_command "$candidate"
  [[ "$COMMAND" == "$candidate" ]] && return 0
  return 1
}

example_rows() {
  local command=$1 i
  load_command "$1"
  for i in "${!EXAMPLES[@]}"; do 
    printf '%s\t%-*s\t│ %s\n' "$i" "$EXAMPLE_COLUMN_WIDTH" "${EXAMPLES[i]}" "${EXAMPLE_DESCRIPTIONS[i]}";
  done
}

example_exists() {
  local command=$1 candidate=$2 skip=${3:--1} i 
  load_command "$command"
  for i in "${!EXAMPLES[@]}"; do [[ "$i" != "$skip" && "${EXAMPLES[$i]}" == "$candidate" ]] && return 0; done
  return 1
}

add_command_example() {
  local target=$1 example example_description
  printf 'Example command:'
  prompt_suffix
  read_input example || return 1
  example=$(clean_field "$example")
  [[ -z "$example" ]] && return 0
  if example_exists "$target" "$example"; then
    printf '%s🞮 Command example "%s" exists.%s\n' "$COLOR_ERROR" "$example" "$COLOR_RESET" >&2
    if [[ "${CMDHELP_POPUP:-0}" == 1 ]]; then
      popup_pause
    fi
    return 0
  fi
  printf 'Example description (optional):'
  prompt_suffix
  read_input example_description || return 1
  EXAMPLES+=("$example")
  EXAMPLE_DESCRIPTIONS+=("$(clean_field "$example_description")")
  command_examples_save "$target"
  printf '%s☑ Added command example “%s” - "%s" to command "%s".%s\n' "$COLOR_SUCCESS" "$example" "$example_description" "$target" "$COLOR_RESET"
  if [[ "${CMDHELP_POPUP:-0}" == 1 ]]; then
    popup_pause
  fi
}

edit_command_example() {
  local target=$1 i=$2 replacement_name replacement_description
  load_command "$target"
  printf 'New text (current: %s%s%s; blank keeps it):' "$COLOR_CURRENT" "${EXAMPLES[$i]}" "$COLOR_RESET"
  prompt_suffix
  read_input replacement_name || return 1
  replacement_name=$(clean_field "$replacement_name")
  if [[ -n "$replacement_name" && "$replacement_name" != "${EXAMPLES[$i]}" ]]; then
    if example_exists "$target" "$replacement_name" "$i"; then
      printf '%s🞮 Command example "%s" exists.%s\n' "$COLOR_ERROR" "$replacement_name" "$COLOR_RESET" >&2
      if [[ "${CMDHELP_POPUP:-0}" == 1 ]]; then
        popup_pause
      fi
      return 0
    else
      EXAMPLES[i]=$replacement_name
    fi
  fi
  if [[ -n "${EXAMPLE_DESCRIPTIONS[$i]}" ]]; then
    printf 'New description (current: %s%s%s; blank keeps it):' "$COLOR_CURRENT" "${EXAMPLE_DESCRIPTIONS[$i]}" "$COLOR_RESET"
    prompt_suffix
  else
    printf 'New description (current: %snone%s; blank keeps it):' "$COLOR_CURRENT" "$COLOR_RESET"
    prompt_suffix
  fi
  read_input replacement_description || return 1
  replacement_description=$(clean_field "$replacement_description")
  [[ -n "$replacement_description" ]] && EXAMPLE_DESCRIPTIONS[i]=$replacement_description
  command_examples_save "$target"
  printf '%s☑ Modified command example “%s” - "%s" from command "%s".%s\n' "$COLOR_SUCCESS" "${EXAMPLES[$i]}" "${EXAMPLE_DESCRIPTIONS[$i]}" "$target" "$COLOR_RESET"
  if [[ "${CMDHELP_POPUP:-0}" == 1 ]]; then
    popup_pause
  fi
}

remove_command_example() {
  local target=$1 index=$2 answer req_rem_example
  load_command "$target"
  req_rem_example="${EXAMPLES[index]}"
  printf 'Delete example %s"%s"%s? [y/N]:' "$COLOR_CURRENT" "$req_rem_example" "$COLOR_RESET"
  prompt_suffix
  read_yes_no answer || return 1
  case "$answer" in
    y | Y)
      unset "EXAMPLES[$index]" "EXAMPLE_DESCRIPTIONS[$index]"
      EXAMPLES=("${EXAMPLES[@]}")
      EXAMPLE_DESCRIPTIONS=("${EXAMPLE_DESCRIPTIONS[@]}")
      command_examples_save "$target"
      printf '%s☑ Removed command example “%s” from command "%s".%s\n' "$COLOR_SUCCESS" "$req_rem_example" "$target" "$COLOR_RESET"
      if [[ "${CMDHELP_POPUP:-0}" == 1 ]]; then
        popup_pause
      fi
      ;;
    n | N | '')
      printf '%s☑ Kept command example "%s".%s\n' "$COLOR_SUCCESS" "$req_rem_example" "$COLOR_RESET"
      if [[ "${CMDHELP_POPUP:-0}" == 1 ]]; then
        popup_pause
      fi
      return 1
      ;;
  esac
}

example_column_format() {
  local example=$1 description=$2
  printf "%s\t%s;" "$(b64_encode "$example")" "$(b64_encode "$description")"
}

command_examples_save() {
  local command=$1 examples_new=''
  temp_file=$(mktemp "${DATA_FILE}.XXXXXX") 
  while IFS=$'\t' read -r ec ed ee; do
    if [[ "$(b64_decode "$ec")" != "$command" ]]; then 
      printf '%s\t%s\t%s\n' "$ec" "$ed" "$ee" >>"$temp_file"; 
    else
      for i in "${!EXAMPLES[@]}"; do
        examples_new+=$(example_column_format "${EXAMPLES[$i]}" "${EXAMPLE_DESCRIPTIONS[$i]}")
      done
      printf '%s\t%s\t%s\n' "$ec" "$ed" "$(b64_encode "$examples_new")" >>"$temp_file";
    fi
  done <"$DATA_FILE"
  mv -- "$temp_file" "$DATA_FILE"
}

add_command_save() {
  local command_name=$1 description=$2
  write_record "$command_name" "$description" '' >>"$DATA_FILE"; 
}

add_command() {
  local command_name description example example_description i
  printf 'Command:'
  prompt_suffix
  read_input command_name || return 1
  command_name=$(clean_field "$command_name")
  if [[ -z "$command_name" ]]; then
    printf '%s🞮 A command name is required.%s\n' "$COLOR_ERROR" "$COLOR_RESET" >&2
    if [[ "${CMDHELP_POPUP:-0}" == 1 ]]; then
      popup_pause
    fi
    return 1
  fi
  if command_exists "$command_name"; then
    printf '%s🞮 “%s” is already in the command list. Nothing was added.%s\n' "$COLOR_ERROR" "$command_name" "$COLOR_RESET" >&2
    if [[ "${CMDHELP_POPUP:-0}" == 1 ]]; then
      popup_pause
    fi
    return 1
  fi
  printf 'Brief description:'
  prompt_suffix
  read_input description || return 1
  description=$(clean_field "$description")
  if [[ -z "$description" ]]; then
    printf '%s🞮 A command description is required.%s\n' "$COLOR_ERROR" "$COLOR_RESET" >&2
    if [[ "${CMDHELP_POPUP:-0}" == 1 ]]; then
      popup_pause
    fi
    return 1
  fi
  add_command_save "$command_name" "$description"
  printf '%s☑ Added command “%s”.%s\n' "$COLOR_SUCCESS" "$command_name" "$COLOR_RESET"
  if [[ "${CMDHELP_POPUP:-0}" == 1 ]]; then
    popup_pause
  fi
}

edit_command_save() {
  local old_name=$1 new_name=$2 description=$3 temp_file ec ed ee
  temp_file=$(mktemp "${DATA_FILE}.XXXXXX")
  while IFS=$'\t' read -r ec ed ee; do
    [[ -n "$ec" ]] || continue
    if [[ "$(b64_decode "$ec")" != "$old_name" ]]; then 
      printf '%s\t%s\t%s\n' "$ec" "$ed" "$ee" >>"$temp_file"; 
    else
      write_record "$new_name" "$description" "$(b64_decode "$ee")" >>"$temp_file"; 
    fi
  done <"$DATA_FILE"
  mv -- "$temp_file" "$DATA_FILE"
}

edit_command() {
  local old_name=$1 new_name new_description
  printf 'New command name (current: %s%s%s; blank keeps it):' "$COLOR_CURRENT" "$old_name" "$COLOR_RESET"
  prompt_suffix
  if read_input new_name; then
    new_name=$(clean_field "$new_name")
    if [[ -z "$new_name" ]]; then
      new_name=$old_name
    else
      if command_exists "$new_name"; then
        printf '%s🞮 Command "%s" exists.%s\n' "$COLOR_ERROR" "$new_name" "$COLOR_RESET" >&2
        if [[ "${CMDHELP_POPUP:-0}" == 1 ]]; then
          popup_pause
        fi
        return 1
      fi
    fi
  fi
  load_command "$old_name"
  printf 'New description (current: %s%s%s; blank keeps it):' "$COLOR_CURRENT" "$COMMAND_DESCRIPTION" "$COLOR_RESET"
  prompt_suffix
  if read_input new_description; then
    new_description=$(clean_field "$new_description")
    [[ -z "$new_description" ]] && new_description=$COMMAND_DESCRIPTION
  fi
  edit_command_save "$old_name" "$new_name" "$new_description"
  printf '%s☑ Modified “%s”.%s\n' "$COLOR_SUCCESS" "$old_name" "$COLOR_RESET"
  if [[ "${CMDHELP_POPUP:-0}" == 1 ]]; then
    popup_pause
  fi
}

remove_command_save() {
  local target=$1 ec ed ee temp_file
  temp_file=$(mktemp "${DATA_FILE}.XXXXXX")
  while IFS=$'\t' read -r ec ed ee; do 
    [[ -n "$ec" && "$(b64_decode "$ec")" == "$target" ]] || printf '%s\t%s\t%s\n' "$ec" "$ed" "$ee" >>"$temp_file"; 
  done <"$DATA_FILE"
  mv -- "$temp_file" "$DATA_FILE"
}

remove_command() {
  local target=$1 answer
  printf 'Remove %s“%s”%s and all its examples? [y/N]:' "$COLOR_CURRENT" "$target" "$COLOR_RESET"
  prompt_suffix
  read_yes_no answer || return 1
  case "$answer" in 
    y | Y) 
      remove_command_save "$target" 
      printf '%s☑ Removed “%s” and its examples.%s\n' "$COLOR_SUCCESS" "$target" "$COLOR_RESET"
      if [[ "${CMDHELP_POPUP:-0}" == 1 ]]; then
        popup_pause
      fi
      ;;
    n | N | '')
      printf '%s☑ Kept "%s".%s\n' "$COLOR_SUCCESS" "$target" "$COLOR_RESET"
      if [[ "${CMDHELP_POPUP:-0}" == 1 ]]; then
        popup_pause
      fi
      return 1
      ;;
  esac
}

show_overlay() {
  local row command_name description selected i example example_description preview_encoded popup_add_command popup_edit_command popup_remove_command command_reload bind_add bind_edit bind_remove popup_add_example popup_edit_example popup_remove_example example_reload example_bind_add example_bind_edit example_bind_remove
  printf -v popup_add_command 'tmux display-popup -E -e CMDHELP_POPUP=1 -xC -yC -w 72 -h 20 -T %q -- env CMDHELP_INTERNAL=1 bash %q add-command' 'Add command' "$CMDHELP_SCRIPT_FILE"
  printf -v popup_edit_command 'tmux display-popup -E -e CMDHELP_POPUP=1 -xC -yC -w 72 -h 12 -T %q -- env CMDHELP_INTERNAL=1 bash %q edit-command' 'Edit command' "$CMDHELP_SCRIPT_FILE"
  printf -v popup_remove_command 'tmux display-popup -E -e CMDHELP_POPUP=1 -xC -yC -w 60 -h 8 -T %q -- env CMDHELP_INTERNAL=1 bash %q remove-command' 'Remove command' "$CMDHELP_SCRIPT_FILE"
  printf -v command_reload 'CMDHELP_INTERNAL=1 bash %q list-commands' "$CMDHELP_SCRIPT_FILE"
  bind_add="ctrl-i:execute-silent($popup_add_command)+reload($command_reload)"
  bind_edit="ctrl-e:execute-silent($popup_edit_command {1})+reload($command_reload)"
  bind_remove="ctrl-r:execute-silent($popup_remove_command {1})+reload($command_reload)"
  while true; do
    row=$(
      command_rows | LC_ALL=C sort -f -t $'\t' -k1,1 |
        fzf --layout=reverse --border=rounded --pointer='▌' --cycle \
          --delimiter=$'\t' --with-nth=1,2 --input-border --prompt='Commands> ' --ansi \
          --header="$(printf '%sCtrl-I%s: insert · %sCtrl-E%s: edit · %sCtrl-R%s: remove · %sEnter%s: examples · %sEsc%s: close\n\n%-*s\t│ %s' "$COLOR_SHORTCUT" "$COLOR_RESET" "$COLOR_SHORTCUT" "$COLOR_RESET" "$COLOR_SHORTCUT" "$COLOR_RESET" "$COLOR_SHORTCUT" "$COLOR_RESET" "$COLOR_SHORTCUT" "$COLOR_RESET" "$COMMAND_COLUMN_WIDTH" COMMAND DESCRIPTION)" \
          --bind="$bind_add" \
          --bind="$bind_edit" \
          --bind="$bind_remove" \
          --preview='base64 -d <<< {3}' --preview-window='right:50%:wrap' --no-multi
    ) || return 0
    IFS=$'\t' read -r command_name description preview_encoded <<<"$row"
    command_name=$(trim_spaces "$command_name")
    while true; do
      printf -v popup_add_example 'tmux display-popup -E -e CMDHELP_POPUP=1 -xC -yC -w 72 -h 16 -T %q -- env CMDHELP_INTERNAL=1 bash %q add-example %q' 'Add example' "$CMDHELP_SCRIPT_FILE" "$command_name"
      printf -v popup_edit_example 'tmux display-popup -E -e CMDHELP_POPUP=1 -xC -yC -w 72 -h 14 -T %q -- env CMDHELP_INTERNAL=1 bash %q edit-example %q %q' 'Edit example' "$CMDHELP_SCRIPT_FILE" "$command_name" 0
      printf -v popup_remove_example 'tmux display-popup -E -e CMDHELP_POPUP=1 -xC -yC -w 60 -h 8 -T %q -- env CMDHELP_INTERNAL=1 bash %q remove-example %q %q' 'Remove example' "$CMDHELP_SCRIPT_FILE" "$command_name" 0
      printf -v example_reload 'CMDHELP_INTERNAL=1 CMDHELP_ARRAY_BASE=%q EXAMPLE_COLUMN_WIDTH=%q bash %q list-examples %q' 0 "$EXAMPLE_COLUMN_WIDTH" "$CMDHELP_SCRIPT_FILE" "$command_name"
      example_bind_add="ctrl-i:execute-silent($popup_add_example)+reload($example_reload)"
      example_bind_edit="ctrl-e:execute-silent($popup_edit_example {1})+reload($example_reload)"
      example_bind_remove="ctrl-r:execute-silent($popup_remove_example {1})+reload($example_reload)"
      selected=$(
        example_rows "$command_name" | LC_ALL=C sort -f -t $'\t' -k1,1 |
        fzf --layout=reverse --border=rounded --pointer='▌' --cycle \
          --delimiter=$'\t' --with-nth=2,3,4 --input-border --prompt='Examples> ' --ansi  \
          --header="$(printf '%sCtrl-I%s: insert · %sCtrl-E%s: edit · %sCtrl-R%s: remove · %sEnter%s: copy & close · %sEsc%s: back\n\n%-*s\t│ %s' "$COLOR_SHORTCUT" "$COLOR_RESET" "$COLOR_SHORTCUT" "$COLOR_RESET" "$COLOR_SHORTCUT" "$COLOR_RESET" "$COLOR_SHORTCUT" "$COLOR_RESET" "$COLOR_SHORTCUT" "$COLOR_RESET" "$EXAMPLE_COLUMN_WIDTH" EXAMPLE DESCRIPTION)" \
          --bind="$example_bind_add" \
          --bind="$example_bind_edit" \
          --bind="$example_bind_remove" \
          --no-multi) || break
      IFS=$'\t' read -r i example example_description <<<"$selected"
      example=$(trim_spaces "$example")
      if copy_to_clipboard "$example"; then
        printf 'Copied to clipboard: %s\n' "$example" >&2
        return 0
      else
        printf 'Could not copy the example: install a clipboard utility.\n' >&2
        return 1
      fi
    done
  done
}
copy_to_clipboard() {
  local value=$1
  if command -v wl-copy >/dev/null 2>&1; then printf '%s' "$value" | wl-copy; elif command -v xclip >/dev/null 2>&1; then printf '%s' "$value" | xclip -selection clipboard; elif command -v xsel >/dev/null 2>&1; then printf '%s' "$value" | xsel --clipboard --input; elif command -v pbcopy >/dev/null 2>&1; then printf '%s' "$value" | pbcopy; elif command -v clip.exe >/dev/null 2>&1; then printf '%s' "$value" | clip.exe; else return 1; fi
}
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
  if [[ -n "${1:-}" ]]; then
    printf '\n%s\n' "$1"
  else
    printf '\n'
  fi
  printf 'Press Enter to close. '
  IFS= read -r || true
}

run_popup_action() {
  local popup_action=${1:-} popup_command popup_array_base popup_index popup_index_base popup_row_index
  case "$popup_action" in
  add-command)
    with_data_lock add_command
    ;;
  edit-command)
    with_data_lock edit_command "$(trim_spaces "${2:-}")"
    ;;
  remove-command)
    with_data_lock remove_command "$(trim_spaces "${2:-}")"
    ;;
  add-example)
    popup_command=$(trim_spaces "${2:-}")
    with_data_lock add_command_example "$popup_command"
    ;;
  edit-example)
    popup_command=$(trim_spaces "${2:-}")
    popup_array_base=${3:-0}
    popup_index=${4:-0}
    [[ "$popup_array_base" == 1 ]] && popup_index=$((popup_index - 1))
    load_command "$popup_command"
    [[ -n "${EXAMPLES[$popup_index]+present}" ]] || {
      popup_pause 'The selected example could not be found.'
      return 1
    }
    with_data_lock edit_command_example "$popup_command" "$popup_index"
    ;;
  remove-example)
    popup_command=$(trim_spaces "${2:-}")
    popup_array_base=${3:-0}
    popup_index=${4:-0}
    [[ "$popup_array_base" == 1 ]] && popup_index=$((popup_index - 1))
    load_command "$popup_command"
    [[ -n "${EXAMPLES[$popup_index]+present}" ]] || {
      popup_pause 'The selected example could not be found.'
      return 1
    }
    with_data_lock remove_command_example "$popup_command" "$popup_index"
    ;;
  list-examples)
    popup_command=$(trim_spaces "${2:-}")
    load_command "$popup_command"
    popup_index_base=${CMDHELP_ARRAY_BASE:-0}
    for popup_index in "${!EXAMPLES[@]}"; do
      popup_row_index=$((popup_index + popup_index_base))
      printf '%s\t%-*s\t│ %s\n' "$popup_row_index" "${EXAMPLE_COLUMN_WIDTH}" "${EXAMPLES[$popup_index]}" "${EXAMPLE_DESCRIPTIONS[$popup_index]}"
    done
    ;;
  list-commands)
    command_rows | LC_ALL=C sort -f -t $'\t' -k1,1
    ;;
  *)
    return 2
    ;;
  esac
}

main() {
  require_fzf
  ensure_data_file
  case "${1:-}" in
  '')
    if run_in_temporary_tmux; then
      return 0
    fi
    show_overlay
    ;;
  add-command | edit-command | remove-command | add-example | edit-example | remove-example | list-examples | list-commands)
    if [[ "${CMDHELP_INTERNAL:-0}" != 1 ]]; then
      printf 'These actions are internal to cmdhelp and cannot be called directly.\n' >&2
      usage >&2
      return 2
    fi
    run_popup_action "$@"
    ;;
  -h | --help | help) usage ;;
  *)
    usage >&2
    return 2
    ;;
  esac
}

if [[ "${BASH_SOURCE[0]:-}" == "$0" ]]; then
  main "$@"
fi
