#!/usr/bin/env bash

set -euo pipefail

repo_dir=$(cd "$(dirname "$0")/.." && pwd)
test_dir=$(mktemp -d "$repo_dir/.device-key-test.XXXXXX")
mkdir -p "$test_dir/home/.claude" "$test_dir/bin" "$test_dir/store"

cleanup() {
    rm -rf "$test_dir"
}
trap cleanup EXIT

cat > "$test_dir/bin/security" << 'EOF'
#!/bin/bash
set -euo pipefail

store=${SECURITY_STORE:?}
mkdir -p "$store"

next_id() {
    local n=1
    while [ -d "$store/$n" ]; do
        n=$((n + 1))
    done
    printf '%s\n' "$n"
}

each_item() {
    local d
    for d in "$store"/*; do
        [ -d "$d" ] || continue
        printf '%s\n' "$d"
    done
}

cmd=${1:-}
shift || true

account=""
service=""
secret=""
print_secret=0

case "$cmd" in
    list-keychains)
        printf '    "%s"\n' "$SECURITY_KEYCHAIN"
        exit 0
        ;;
    dump-keychain)
        while IFS= read -r d; do
            printf 'keychain: "%s"\n' "$SECURITY_KEYCHAIN"
            printf 'class: "genp"\n'
            printf '    "acct"<blob>="%s"\n' "$(cat "$d/account")"
            printf '    "svce"<blob>="%s"\n' "$(cat "$d/service")"
        done < <(each_item)
        exit 0
        ;;
    delete-generic-password|find-generic-password|add-generic-password)
        ;;
    *)
        echo "unexpected security command: $cmd" >&2
        exit 99
        ;;
esac

while [ $# -gt 0 ]; do
    case "$1" in
        -a)
            account=$2
            shift 2
            ;;
        -s)
            service=$2
            shift 2
            ;;
        -U)
            shift
            ;;
        -w)
            if [ "$cmd" = "add-generic-password" ]; then
                secret=$2
                shift 2
            else
                print_secret=1
                shift
            fi
            ;;
        *)
            echo "unexpected security argument: $1" >&2
            exit 99
            ;;
    esac
done

match_service() {
    local d
    while IFS= read -r d; do
        if [ "$(cat "$d/service")" = "$service" ]; then
            printf '%s\n' "$d"
            return 0
        fi
    done < <(each_item)
    return 1
}

match_account_service() {
    local d
    while IFS= read -r d; do
        if [ "$(cat "$d/account")" = "$account" ] && [ "$(cat "$d/service")" = "$service" ]; then
            printf '%s\n' "$d"
            return 0
        fi
    done < <(each_item)
    return 1
}

case "$cmd" in
    delete-generic-password)
        d=$(match_service) || exit 44
        rm -rf "$d"
        exit 0
        ;;
    find-generic-password)
        d=$(match_account_service) || exit 44
        if [ "$print_secret" -eq 1 ]; then
            cat "$d/secret"
            printf '\n'
        fi
        exit 0
        ;;
    add-generic-password)
        if d=$(match_account_service); then
            printf '%s' "$secret" > "$d/secret"
            exit 0
        fi
        d="$store/$(next_id)"
        mkdir "$d"
        printf '%s' "$account" > "$d/account"
        printf '%s' "$service" > "$d/service"
        printf '%s' "$secret" > "$d/secret"
        exit 0
        ;;
esac
EOF
chmod +x "$test_dir/bin/security"

seed_store() {
    rm -rf "$test_dir/store"
    mkdir -p \
        "$test_dir/store/1" \
        "$test_dir/store/2" \
        "$test_dir/store/3" \
        "$test_dir/store/4" \
        "$test_dir/home/.claude/.device-keys/lock"
    printf '%s' "geminiwen" > "$test_dir/store/1/account"
    printf '%s' "Claude Code-device-keys" > "$test_dir/store/1/service"
    printf '%s' '{"keys":{"abc":{"privateKeyPkcs8B64":"device-private"}}}' > "$test_dir/store/1/secret"
    printf '%s' "other" > "$test_dir/store/2/account"
    printf '%s' "Claude Code-device-keys" > "$test_dir/store/2/service"
    printf '%s' '{"keys":{"def":{"privateKeyPkcs8B64":"other-private"}}}' > "$test_dir/store/2/secret"
    printf '%s' "geminiwen" > "$test_dir/store/3/account"
    printf '%s' "Claude Code-credentials" > "$test_dir/store/3/service"
    printf '%s' '{"claudeAiOauth":{"accessToken":"keep-me"},"coworkRemoteDevice":{"abc":{"privateKeyPkcs8B64":"legacy-private"}}}' > "$test_dir/store/3/secret"
    printf '%s' "geminiwen" > "$test_dir/store/4/account"
    printf '%s' "Claude Code-credentials-5d5cbd52" > "$test_dir/store/4/service"
    printf '%s' '{"mcpOAuth":{"clientId":"leave-me"}}' > "$test_dir/store/4/secret"
    cp "$test_dir/store/4/secret" "$test_dir/credentials-suffix-before"
    printf '%s\n' '{"keys":{"abc":{"privateKeyPkcs8B64":"file-private"}}}' > "$test_dir/home/.claude/.device-keys.json"
    printf '%s\n' 'corrupt' > "$test_dir/home/.claude/.device-keys.json.corrupt-1-2-aa"
    printf '%s\n' '{"projects":{}}' > "$test_dir/home/.claude.json"
}

run_cleaner() {
    PATH="$test_dir/bin:$PATH" \
        SECURITY_STORE="$test_dir/store" \
        SECURITY_KEYCHAIN="$test_dir/test.keychain" \
        HOME="$test_dir/home" \
        TMPDIR="$test_dir" \
        "$repo_dir/cccleaner" "$@"
}

assert_removed() {
    local output=$1
    [ ! -e "$test_dir/home/.claude/.device-keys.json" ]
    [ ! -e "$test_dir/home/.claude/.device-keys.json.corrupt-1-2-aa" ]
    [ ! -e "$test_dir/home/.claude/.device-keys" ]
    [ ! -d "$test_dir/store/1" ]
    [ ! -d "$test_dir/store/2" ]
    jq -e '.claudeAiOauth.accessToken == "keep-me" and (has("coworkRemoteDevice") | not)' "$test_dir/store/3/secret" >/dev/null
    cmp -s "$test_dir/store/4/secret" "$test_dir/credentials-suffix-before"
    grep -q "Claude Code-device-keys" "$output"
    grep -q "coworkRemoteDevice" "$output"
    if grep -q "keep-me\|legacy-private\|device-private\|file-private" "$output"; then
        echo "device credential material leaked into output" >&2
        exit 1
    fi
}

seed_store
run_cleaner --device-keys --no-backup > "$test_dir/output"
assert_removed "$test_dir/output"

run_cleaner --device-keys --no-backup > "$test_dir/output"
grep -q "No Cowork device credentials found" "$test_dir/output"

seed_store
run_cleaner --all --no-backup > "$test_dir/output"
assert_removed "$test_dir/output"

echo "Device credential cleanup checks passed"
