#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
LC_ALL=C
shopt -s nullglob

# --- helpers ---------------------------------------------------------------

ok()   { printf "[%s] ✅ %s\n" "$1" "$2"; }
fail() { printf "[%s] ❌ %s\n" "$1" "$2"; exit 1; }

need_dir()  { [[ -d "$1" ]] || fail "$2" "Missing directory: $1"; }
need_file() { [[ -f "$1" ]] || fail "$2" "Missing file: $1"; }

same_file() {
    # compare contents (binary-safe)
    cmp -s -- "$1" "$2"
}

tmpfile() { mktemp "${TMPDIR:-/tmp}/uq.XXXXXXXX"; }

# --- task checks -----------------------------------------------------------

check_1() {
    [[ -d my_stuff ]] || fail 1 "my_stuff directory not found"
    ok 1 "my_stuff exists"
}

check_2() {
    need_file "my_stuff/empty.txt" 2
    if [[ -s my_stuff/empty.txt ]]; then
    fail 2 "my_stuff/empty.txt is not empty"
    fi
    ok 2 "empty.txt exists and is empty"
}

check_3() {
    need_dir "my_stuff/output" 3
    ok 3 "output directory exists"
}

check_4() {
    need_dir "data/poems" 4
    need_dir "my_stuff/output" 4
    local all_ok=1
    for f in data/poems/*.txt; do
    local base=${f##*/}
    if [[ ! -f "my_stuff/output/$base" ]]; then
        echo "   missing copy: my_stuff/output/$base"
        all_ok=0
    elif ! same_file "$f" "my_stuff/output/$base"; then
        echo "   content differs for: $base"
        all_ok=0
    fi
    done
    [[ $all_ok -eq 1 ]] || fail 4 "Not all poems correctly copied"
    ok 4 "All poems copied correctly"
}

check_5() {
    need_dir "data/versions" 5
    need_dir "my_stuff/output" 5
    local all_ok=1
    for f in data/versions/*-v*[13579].txt; do
    local base=${f##*/}
    if [[ ! -f "my_stuff/output/$base" ]]; then
        echo "   missing copy: my_stuff/output/$base"
        all_ok=0
    elif ! same_file "$f" "my_stuff/output/$base"; then
        echo "   content differs for: $base"
        all_ok=0
    fi
    done
    [[ $all_ok -eq 1 ]] || fail 5 "Version files not correctly copied"
    ok 5 "Version files copied correctly"
}

check_6() {
    need_file "my_stuff/about.md" 6
    # expected exact content (3 lines, LF endings)
    read -r -d '' EXPECT <<'EOF' || true
# About This Quest
Made during Lecture 1.
Shell power!
EOF
    local tmp; tmp=$(tmpfile)
    printf "%s\n" "$EXPECT" > "$tmp"
    same_file "$tmp" "my_stuff/about.md" || { rm -f "$tmp"; fail 6 "about.md content mismatch"; }
    rm -f "$tmp"
    ok 6 "about.md content is correct"
}

check_7() {
    need_file "my_stuff/greeter.sh" 7
    [[ -x "my_stuff/greeter.sh" ]] || fail 7 "greeter.sh is not executable"
    local out; out=$(bash my_stuff/greeter.sh)
    [[ "$out" == "Hello, world" || "$out" == "Hello, world!" ]] || fail 7 "greeter.sh did not print 'Hello, world'"
    ok 7 "greeter.sh prints the expected greeting"
}

check_8() {
    need_file "my_stuff/output/error.txt" 8
    need_file "data/log.txt" 8
    local expected; expected=$(grep -i 'error' data/log.txt | wc -l | awk '{print $1}')
    local got; got=$(tr -d '[:space:]' < my_stuff/output/error.txt)
    [[ "$got" == "$expected" ]] || fail 8 "error.txt=$got but expected $expected"
    ok 8 "error count is correct ($expected)"
}

check_9() {
    need_file "my_stuff/whereami.sh" 9
    [[ -x "my_stuff/whereami.sh" ]] || fail 9 "whereami.sh is not executable"
    local here; here=$(pwd)
    local out; out=$(bash my_stuff/whereami.sh)
    [[ "$out" == "Your current directory is: $here" ]] || fail 9 "whereami.sh printed '$out' but expected 'Your current directory is: $here'"
    ok 9 "whereami.sh prints the correct path"
}

build_expected_anthology() {
    local tmp; tmp=$(tmpfile)
    : > "$tmp"
    cat "my_stuff/about.md" >> "$tmp"
    echo "" >> "$tmp"
    tail -n 1 -q data/poems/*.txt >> "$tmp"
    echo "" >> "$tmp"
    tail -n 1 -q data/versions/*-v?.txt >> "$tmp"
    echo "" >> "$tmp"
    echo "Thank you!" >> "$tmp"
    printf "%s\n" "$tmp"
}

check_10() {
    need_file "my_stuff/build_anthology.sh" 10
    [[ -x "my_stuff/build_anthology.sh" ]] || fail 10 "build_anthology.sh is not executable"

    local OUT="my_stuff/output/anthology.txt"
    local HAD_ORIG=0
    local BACKUP=""
    # If a file already exists, stash it safely
    if [[ -f "$OUT" ]]; then
        BACKUP=$(tmpfile)
        mv -f "$OUT" "$BACKUP"
        HAD_ORIG=1
    fi

    # Helper to restore original state before failing or finishing
    restore_original() {
    if [[ $HAD_ORIG -eq 1 ]]; then
        # Put back the student's original file
        rm -f "$OUT" || true
        mv -f "$BACKUP" "$OUT"
    else
        # There was no anthology originally; remove what we generated
        rm -f "$OUT" || true
    fi
    }

    # --- Run #1: generate fresh anthology and compare to expected
    bash my_stuff/build_anthology.sh
    need_file "$OUT" 10

    local exp1; exp1=$(build_expected_anthology)
    if ! same_file "$exp1" "$OUT"; then
        echo "---- diff (expected vs. got) ----"
        diff -u "$exp1" "$OUT" || true
        rm -f "$exp1"
        restore_original
        fail 10 "anthology.txt differs from expected on first run"
    fi
    rm -f "$exp1"

    # --- Run #2: idempotence check (catches scripts that only use >>)
    bash my_stuff/build_anthology.sh
    local exp2; exp2=$(build_expected_anthology)
    if ! same_file "$exp2" "$OUT"; then
        echo "---- diff after second run (expected vs. got) ----"
        diff -u "$exp2" "$OUT" || true
        rm -f "$exp2"
        echo
        echo "Hint: Your script likely APPENDS to \$OUT_FILE without truncating."
        echo 'Add near the top:'
        echo '  mkdir -p "$OUT_DIR"'
        echo '  : > "$OUT_FILE"    # truncate/create before appending'
        restore_original
        fail 10 "anthology.txt is not idempotent (second run changed output)"
    fi
    rm -f "$exp2"

    # All good — restore the student’s original state
    restore_original
    ok 10 "anthology.txt matches expected and the script is idempotent"
}

# --- entrypoint ------------------------------------------------------------

usage() { echo "Usage: $0 [1|2|...|10|all]"; }

if [[ $# -eq 0 ]]; then usage; exit 1; fi

case "${1:-}" in
    1)  check_1 ;;
    2)  check_2 ;;
    3)  check_3 ;;
    4)  check_4 ;;
    5)  check_5 ;;
    6)  check_6 ;;
    7)  check_7 ;;
    8)  check_8 ;;
    9)  check_9 ;;
    10) check_10 ;;
    all)
    for i in {1..10}; do "check_$i"; done
    ;;
  *) usage; exit 1 ;;
esac
