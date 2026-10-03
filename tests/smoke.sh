#!/usr/bin/env bash

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT

export CMDHELP_DATA_FILE="$test_dir/commands.tsv"
# shellcheck source=../cmdhelp.sh
source "$script_dir/cmdhelp.sh"

command -v flock >/dev/null 2>&1
ensure_data_file
[[ -s "$CMDHELP_DATA_FILE" ]]

command_name='smoke command'
new_command_name='smoke command renamed'
command_description='Description with a semicolon; tabs stay encoded'
example="printf 'value;with symbols\tand quotes'"
example_description='Example description; also encoded'

EXAMPLES=("$example")
EXAMPLE_DESCRIPTIONS=("$example_description")
save_command_changes "$command_name" "$command_name" "$command_description"

load_command "$command_name"
[[ "$COMMAND_DESCRIPTION" == "$command_description" ]]
[[ "${EXAMPLES[0]}" == "$example" ]]
[[ "${EXAMPLE_DESCRIPTIONS[0]}" == "$example_description" ]]

save_command_changes "$command_name" "$new_command_name" 'Renamed description'
load_command "$new_command_name"
[[ "$COMMAND_DESCRIPTION" == 'Renamed description' ]]
[[ "${EXAMPLES[0]}" == "$example" ]]

remove_command_entry "$new_command_name" >/dev/null
! grep -Fq "$(b64_encode "$new_command_name")" "$CMDHELP_DATA_FILE"

printf 'cmdhelp smoke test passed\n'
