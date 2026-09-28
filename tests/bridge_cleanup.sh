#!/usr/bin/env bash

set -euo pipefail

repo_dir=$(cd "$(dirname "$0")/.." && pwd)
test_dir=$(mktemp -d "$repo_dir/.bridge-test.XXXXXX")
mkdir "$test_dir/home" "$test_dir/tmp"
bridge_pid=""
stubborn_pid=""
other_pid=""

cleanup() {
    [ -z "$bridge_pid" ] || kill "$bridge_pid" 2>/dev/null || true
    [ -z "$stubborn_pid" ] || kill -KILL "$stubborn_pid" 2>/dev/null || true
    [ -z "$other_pid" ] || kill "$other_pid" 2>/dev/null || true
    [ -z "$bridge_pid" ] || wait "$bridge_pid" 2>/dev/null || true
    [ -z "$stubborn_pid" ] || wait "$stubborn_pid" 2>/dev/null || true
    [ -z "$other_pid" ] || wait "$other_pid" 2>/dev/null || true
    for file in "$test_dir/home/.claude.json" "$test_dir/claude" "$test_dir/claude.c" "$test_dir/output" "$test_dir/stubborn-ready" "$test_dir/cccleaner-functions" "$test_dir/bin/security"; do
        [ ! -e "$file" ] || unlink "$file"
    done
    rmdir "$test_dir/bin" "$test_dir/home" "$test_dir/tmp" "$test_dir"
}
trap cleanup EXIT

sed '$d' "$repo_dir/cccleaner" > "$test_dir/cccleaner-functions"
bash -c 'source "$1"; is_ancestor_process "$$"; is_ancestor_process "$PPID"' _ "$test_dir/cccleaner-functions"

cat > "$test_dir/claude.c" <<'EOF'
#include <signal.h>
#include <stdio.h>
#include <unistd.h>
int main(int argc, char **argv) {
    if (argc > 1) signal(SIGTERM, SIG_IGN);
    if (argc > 2) {
        FILE *ready = fopen(argv[2], "w");
        if (!ready) return 1;
        fclose(ready);
    }
    sleep(30);
    return 0;
}
EOF
cc "$test_dir/claude.c" -o "$test_dir/claude"

"$test_dir/claude" &
bridge_pid=$!
"$test_dir/claude" stubborn "$test_dir/stubborn-ready" &
stubborn_pid=$!
/bin/sleep 30 &
other_pid=$!
for attempt in {1..100}; do
    [ -f "$test_dir/stubborn-ready" ] && break
    sleep 0.01
done
[ -f "$test_dir/stubborn-ready" ]

bridge_start=$(LC_ALL=C TZ=UTC ps -p "$bridge_pid" -o lstart= | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
stubborn_start=$(LC_ALL=C TZ=UTC ps -p "$stubborn_pid" -o lstart= | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
other_start=$(LC_ALL=C TZ=UTC ps -p "$other_pid" -o lstart= | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

jq -n \
    --argjson bridge_pid "$bridge_pid" --arg bridge_start "$bridge_start" \
    --argjson stubborn_pid "$stubborn_pid" --arg stubborn_start "$stubborn_start" \
    --argjson other_pid "$other_pid" --arg other_start "$other_start" \
    '{projects: {}, replBridgePlaceholders: {
        cse_matching: {pid: $bridge_pid, procStart: $bridge_start, createdAt: 1},
        cse_stubborn: {pid: $stubborn_pid, procStart: $stubborn_start, createdAt: 1},
        cse_wrong_start: {pid: $other_pid, procStart: "wrong start", createdAt: 1},
        cse_wrong_command: {pid: $other_pid, procStart: $other_start, createdAt: 1},
        cse_gone: {pid: 99999999, procStart: "old start", createdAt: 1}
    }}' > "$test_dir/home/.claude.json"

mkdir "$test_dir/bin"
cat > "$test_dir/bin/security" << 'EOF'
#!/bin/bash
exit 44
EOF
chmod +x "$test_dir/bin/security"

PATH="$test_dir/bin:$PATH" HOME="$test_dir/home" TMPDIR="$test_dir/tmp" "$repo_dir/cccleaner" --all --no-backup > "$test_dir/output"

wait "$bridge_pid" 2>/dev/null || true
bridge_pid=""
wait "$stubborn_pid" 2>/dev/null || true
stubborn_pid=""
if ! kill -0 "$other_pid" 2>/dev/null; then
    echo "Unrelated process was terminated" >&2
    exit 1
fi

jq -e '(.replBridgePlaceholders | keys | sort) == ["cse_wrong_command", "cse_wrong_start"]' "$test_dir/home/.claude.json" >/dev/null
HOME="$test_dir/home" TMPDIR="$test_dir/tmp" "$repo_dir/cccleaner" --cache --no-backup > "$test_dir/output"
jq -e '(.replBridgePlaceholders | keys | sort) == ["cse_wrong_command", "cse_wrong_start"]' "$test_dir/home/.claude.json" >/dev/null
echo "Bridge cleanup process checks passed"
