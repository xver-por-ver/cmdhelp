#!/usr/bin/env bash

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT

install_dir="$test_dir/bin"
data_file="$test_dir/commands.tsv"
mkdir -p -- "$install_dir"
cp -- "$script_dir/cmdhelp.sh" "$install_dir/cmdhelp"
chmod +x -- "$install_dir/cmdhelp"

help_output=$("$install_dir/cmdhelp" --help)
grep -Fq 'cmdhelp --help' <<<"$help_output"

CMDHELP_DATA_FILE="$data_file" "$install_dir/cmdhelp" list-commands >/dev/null
[[ -s "$data_file" ]]

printf 'cmdhelp standalone test passed\n'
