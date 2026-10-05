#!/usr/bin/env bash

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT

export CMDHELP_DATA_FILE="$test_dir/commands.tsv"
source "$script_dir/cmdhelp.sh"

command -v flock >/dev/null 2>&1
ensure_data_file
require_fzf
[[ -s "$CMDHELP_DATA_FILE" ]]

command_name='smoke command'
new_command_name='smoke command renamed'
command_description=$'Description with a tab\tinside'
new_command_description='Renamed description'
example="printf 'value;with symbols\tand quotes'"
new_example='printf replacement'
example_description='Example description; also encoded'
new_example_description='Updated example description'

# Add a command and persist its first example using the command row format.
add_command_save "$command_name" "$command_description"
load_command "$command_name"
[[ "$COMMAND_DESCRIPTION" == "$command_description" ]]
EXAMPLES=("$example")
EXAMPLE_DESCRIPTIONS=("$example_description")
command_examples_save "$command_name"
load_command "$command_name"
[[ ${#EXAMPLES[@]} == 1 ]]
[[ "${EXAMPLES[0]}" == "$example" ]]
[[ "${EXAMPLE_DESCRIPTIONS[0]}" == "$example_description" ]]

# Add a second example and check that semicolon-delimited records are decoded.
EXAMPLES+=("$new_example")
EXAMPLE_DESCRIPTIONS+=("$new_example_description")
command_examples_save "$command_name"
load_command "$command_name"
[[ ${#EXAMPLES[@]} == 2 ]]
[[ "${EXAMPLES[1]}" == "$new_example" ]]
[[ "${EXAMPLE_DESCRIPTIONS[1]}" == "$new_example_description" ]]
encoded_preview=$(command_rows | awk -F '\t' -v target="$command_name" 'substr($1, 1, length(target)) == target { print $NF; exit }')
preview=$(b64_decode "$encoded_preview")
[[ "$preview" == *"$example"* ]]
[[ "$preview" == *"$new_example_description"* ]]

# Rename the command and preserve its examples.
edit_command_save "$command_name" "$new_command_name" "$new_command_description"
load_command "$new_command_name"
[[ "$COMMAND_DESCRIPTION" == "$new_command_description" ]]
[[ ${#EXAMPLES[@]} == 2 ]]
[[ "${EXAMPLES[0]}" == "$example" ]]
[[ "${EXAMPLES[1]}" == "$new_example" ]]

# Edit and remove examples, then remove the command.
EXAMPLES[0]=$new_example
EXAMPLE_DESCRIPTIONS[0]=$new_example_description
unset 'EXAMPLES[1]' 'EXAMPLE_DESCRIPTIONS[1]'
EXAMPLES=("${EXAMPLES[@]}")
EXAMPLE_DESCRIPTIONS=("${EXAMPLE_DESCRIPTIONS[@]}")
command_examples_save "$new_command_name"
load_command "$new_command_name"
[[ ${#EXAMPLES[@]} == 1 ]]
[[ "${EXAMPLES[0]}" == "$new_example" ]]
[[ "${EXAMPLE_DESCRIPTIONS[0]}" == "$new_example_description" ]]

remove_command_save "$new_command_name"
load_command "$new_command_name"
[[ -z "$COMMAND" ]]
[[ ${#EXAMPLES[@]} == 0 ]]

printf 'cmdhelp smoke test passed\n'
