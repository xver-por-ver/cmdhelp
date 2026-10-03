#!/usr/bin/env bash

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT

data_file="$test_dir/commands.tsv"
run_worker() {
  local command_name=$1 example_value=$2
  CMDHELP_DATA_FILE="$data_file" bash -c '
    source "$1"
    ensure_data_file
    EXAMPLES=("printf '\''%s'\'' '\''$3'\''")
    EXAMPLE_DESCRIPTIONS=("concurrent write")
    save_command_changes "$2" "$2" "Concurrent test command"
  ' bash "$script_dir/cmdhelp.sh" "$command_name" "$example_value"
}

worker_pids=()
for i in $(seq 1 16); do
  run_worker "concurrent-$i" "$i" &
  worker_pids+=("$!")
done
for worker_pid in "${worker_pids[@]}"; do
  wait "$worker_pid"
done

[[ "$(stat -c '%a' "$data_file" 2>/dev/null || stat -f '%Lp' "$data_file")" == 600 ]]
awk -F '\t' 'NF != 4 { exit 1 }' "$data_file"
for i in $(seq 1 16); do
  encoded_name=$(CMDHELP_DATA_FILE="$data_file" bash -c 'source "$1"; b64_encode "$2"' bash "$script_dir/cmdhelp.sh" "concurrent-$i")
  grep -Fq "$encoded_name" "$data_file"
done

printf 'cmdhelp permission and concurrency test passed\n'
