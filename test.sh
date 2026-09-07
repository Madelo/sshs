#!/bin/bash
# Tests for sshs.sh
# Run from the repository root: ./test.sh

cd "$(dirname "$0")" || exit

# sshs.sh is a standalone script (it refuses to be sourced): tests execute it.
SCRIPT=./sshs.sh

PASS=0 FAIL=0

# Strip ANSI escape codes (regex removal; ${var//} cannot do regex)
strip_ansi() {
    # shellcheck disable=SC2001
    printf '%s\n' "$1" | sed 's/\x1b\[[0-9;]*m//g'
}

check() {
    local desc="$1" expected="$2"; shift 2
    local out
    out=$(SSHS_CONFIG="${SSHS_CFG:-ssh_config_test/config5}" "$SCRIPT" "$@" </dev/null 2>&1) || true
    # Strip ANSI escape codes before matching
    local clean; clean=$(strip_ansi "$out")
    if echo "$clean" | grep -qF "$expected"; then
        echo "  ✓ $desc"
        ((PASS++))
    else
        echo "  ✗ $desc"
        echo "    expected: $expected"
        echo "    got:      $out"
        ((FAIL++))
    fi
}

echo "=== sshs tests ==="
echo ""

check "List all hosts"                            "dev_bastion"
check "Simple search"                             "dev_k3s_master"        master
check "Multi-word search"                         "k3s_worker1"           k3s worker
check "1 result → auto-connect"                   "Connect to dev_k3s_master" k3s master
check "sshs-off ignored (Host* absent)"           "dev_k3s_master"        k3s
SSHS_MENU=abcde check "Custom menu (abcde)"       "a) dev_bastion"
SSHS_CFG=ssh_config_test/config30 check "Alternative config config30" "pve.lab" pve
check "-r flag (regex)"                           "dev_k3s_master"        -r "dev_.*master"
SSHS_REGEX=1 check "SSHS_REGEX variable"          "dev_k3s_master"        "dev_.*master"
check "Safe mode: [a-z] → no injection"           "not found"             "[a-z]"
check "No result"                                 "not found"             zzz_nonexistent_zzz
SSHS_MENU=ab check "Too many results → list without menu" "dev_bastion" dev
check "Prompt 'other key to cancel' visible"      "other key to cancel"
check "SSH connection failure → failed"           "failed"                dev_k3s_master

echo ""
echo "--- sourced mode rejected ---"

# Sourcing must fail cleanly: error message + source returns 1, and the sshs
# function must be unset in the calling shell (checked in a separate run)
out=$(bash -c "source $SCRIPT" 2>&1); src_rc=$?
clean=$(strip_ansi "$out")
fn_state=$(bash -c "source $SCRIPT 2>/dev/null; [[ \$(type -t sshs) == function ]] && echo FUNCTION_STILL_DEFINED || echo FUNCTION_REMOVED" 2>/dev/null)
if echo "$clean" | grep -qF "not sourced" && (( src_rc == 2 )) && [[ "$fn_state" == "FUNCTION_REMOVED" ]]; then
    echo "  ✓ Sourcing refused: error, function removed, source returns 2"
    ((PASS++))
else
    echo "  ✗ Sourcing refused"
    echo "    source exit: $src_rc (expected 2)"
    echo "    function:    $fn_state"
    echo "    got: $out"
    ((FAIL++))
fi

echo ""
echo "--- ssh options ---"

# Verify -- separator: SSH opts are not treated as search terms
check "-- separator: SSH options ignored for search"              "Connect to dev_k3s_master" dev master -- -v
check "-- separator: menu with SSH options (not used in search)"  "dev_k3s_worker1" k3s worker -- -p 2222
check "-- separator: no search, all entries"                      "dev_bastion" -- -v
SSHS_SSH_OPTS=-v check "SSHS_SSH_OPTS does not interfere with search" "Connect to dev_k3s_master" master

echo ""
echo "--- menu bounds ---"

# Helper: run sshs with simulated keypress input
run_with_key() {
    local key="$1"; shift
    SSHS_CONFIG=ssh_config_test/config5 "$SCRIPT" "$@" <<<"$key" 2>&1 || true
}

# Test: within bounds — press "1" in 3-host menu (workers 1,2,3) → should connect to index 1 = worker2
out=$(run_with_key "1" worker)
clean=$(strip_ansi "$out")
if echo "$clean" | grep -qF "Connect to dev_k3s_worker2"; then
    echo "  ✓ Menu: key in bounds → connection"
    ((PASS++))
else
    echo "  ✗ Menu: key in bounds → connection"
    echo "    expected: Connect to dev_k3s_worker2"
    echo "    got:      $out"
    ((FAIL++))
fi

# Test: out of bounds — press "5" in 3-host menu → should NOT attempt connection
out=$(run_with_key "5" worker)
clean=$(strip_ansi "$out")
if echo "$clean" | grep -qF "Connect to"; then
    echo "  ✗ Menu: key out of bounds → no connection"
    echo "    unexpected connection attempt in output"
    echo "    got: $out"
    ((FAIL++))
else
    echo "  ✓ Menu: key out of bounds → no connection"
    ((PASS++))
fi

echo ""
echo "--- include ---"

check_inc() {
    local desc="$1" expected="$2"; shift 2
    local out clean
    out=$(HOME="$PWD/ssh_config_test/fakehome" SSHS_CONFIG=ssh_config_test/include/main.conf \
        "$SCRIPT" "$@" </dev/null 2>&1) || true
    clean=$(strip_ansi "$out")
    if echo "$clean" | grep -qF "$expected"; then
        echo "  ✓ $desc"; ((PASS++))
    else
        echo "  ✗ $desc"; echo "    expected: $expected"; echo "    got:      $out"; ((FAIL++))
    fi
}

check_inc "Include: glob + relative path (conf.d/*.conf)"  "inc_aaa"
check_inc "Include: ~ expansion (recursive down to inner.conf)" "inc_inner"
check_inc "Include: host after the Includes"               "inc_bottom"
check_inc "Include: search in included files"              "Connect to inc_inner" inner

# sshs-off in an included file must be ignored (inc_a_off hidden, inc_aaa shown)
out=$(HOME="$PWD/ssh_config_test/fakehome" SSHS_CONFIG=ssh_config_test/include/main.conf \
    "$SCRIPT" </dev/null 2>&1) || true
clean=$(strip_ansi "$out")
if echo "$clean" | grep -qF "inc_aaa" && ! echo "$clean" | grep -qF "inc_a_off"; then
    echo "  ✓ Include: sshs-off respected in an included file"
    ((PASS++))
else
    echo "  ✗ Include: sshs-off respected in an included file"
    echo "    got: $out"
    ((FAIL++))
fi

# Glob that matches nothing is silently ignored (no error, listing still complete)
if echo "$clean" | grep -qF "inc_top" && echo "$clean" | grep -qF "inc_bottom" \
   && ! echo "$clean" | grep -qi "error"; then
    echo "  ✓ Include: non-matching glob ignored without error"
    ((PASS++))
else
    echo "  ✗ Include: non-matching glob ignored without error"
    echo "    got: $out"
    ((FAIL++))
fi

# Ordering: hosts appear in the order of their Include directives
pos() { echo "$clean" | grep -nF "$1" | head -1 | cut -d: -f1; }
p_top=$(pos inc_top); p_a=$(pos inc_aaa); p_b=$(pos inc_bbb)
p_nb=$(pos inc_nested_before); p_in=$(pos inc_inner); p_na=$(pos inc_nested_after)
p_bot=$(pos inc_bottom)
if (( p_top < p_a && p_a < p_b && p_b < p_nb && p_nb < p_in && p_in < p_na && p_na < p_bot )); then
    echo "  ✓ Include: host order respected (interleaved with Includes)"
    ((PASS++))
else
    echo "  ✗ Include: host order respected"
    echo "    positions: top=$p_top a=$p_a b=$p_b nb=$p_nb inner=$p_in na=$p_na bottom=$p_bot"
    echo "    got: $out"
    ((FAIL++))
fi

# 7 hosts listed (menu 0..6), no phantom 7th entry
if echo "$clean" | grep -qF "6) inc_bottom" && ! echo "$clean" | grep -qF "7) "; then
    echo "  ✓ Include: 7 hosts listed, no phantom host"
    ((PASS++))
else
    echo "  ✗ Include: 7 hosts listed, no phantom host"
    echo "    got: $out"
    ((FAIL++))
fi

echo ""
echo "--- quoted Include paths (spaces) ---"

# A quoted path with spaces must stay one token (quoted globs included).
# Two hosts so sshs shows a menu instead of auto-connecting to a dead IP.
qinc=$(mktemp -d)
mkdir -p "$qinc/.ssh/my dir"
printf 'Host quoted_inc\n    HostName 192.0.2.6\n' > "$qinc/.ssh/my dir/inc.conf"
printf 'Include "my dir/inc.conf"\nHost qinc_main\n    HostName 192.0.2.5\nHost qinc_second\n    HostName 192.0.2.4\n' > "$qinc/.ssh/config"
out=$(HOME="$qinc" "$SCRIPT" </dev/null 2>&1) || true
clean=$(strip_ansi "$out")
if echo "$clean" | grep -qF "quoted_inc" && echo "$clean" | grep -qF "qinc_main"; then
    echo "  ✓ Include: quoted path with spaces loaded"
    ((PASS++))
else
    echo "  ✗ Include: quoted path with spaces"
    echo "    got: $out"
    ((FAIL++))
fi
rm -rf "$qinc"

echo ""
echo "--- comment above Include must not leak ---"

# A comment directly above an 'Include' line must not be applied to hosts inside
# or after the included file (regression: pline used to survive the Include line)
stale_dir=$(mktemp -d)
mkdir -p "$stale_dir/.ssh/conf.d"
printf 'Host inner_host\n    HostName 192.0.2.8\n' > "$stale_dir/.ssh/conf.d/inc.conf"
printf '# prod, database\nInclude conf.d/inc.conf\nHost after_inc\n    HostName 192.0.2.7\n' \
    > "$stale_dir/.ssh/config"

out=$(HOME="$stale_dir" "$SCRIPT" </dev/null 2>&1) || true
clean=$(strip_ansi "$out")
srch=$(HOME="$stale_dir" "$SCRIPT" prod </dev/null 2>&1) || true
srch_clean=$(strip_ansi "$srch")

if echo "$clean" | grep -qF "after_inc" && ! echo "$clean" | grep -qF "prod, database" \
   && echo "$srch_clean" | grep -qF "not found"; then
    echo "  ✓ Include: comment above Include not applied to the following host"
    ((PASS++))
else
    echo "  ✗ Include: comment above Include leaked"
    echo "    listing: $out"
    echo "    search:  $srch"
    ((FAIL++))
fi
rm -rf "$stale_dir"

echo ""
echo "--- indented Host ---"

# An indented Host line must be listed (ssh accepts leading whitespace)
out=$(SSHS_CONFIG=ssh_config_test/indented "$SCRIPT" </dev/null 2>&1) || true
clean=$(strip_ansi "$out")
if echo "$clean" | grep -qF "indented_host" && echo "$clean" | grep -qF "plain_host"; then
    echo "  ✓ Indented Host: indented host listed"
    ((PASS++))
else
    echo "  ✗ Indented Host: indented host listed"
    echo "    got: $out"
    ((FAIL++))
fi

echo ""
echo "--- multi-alias Host ---"

# Host alias_one alias_two must yield two findable entries
out=$(SSHS_CONFIG=ssh_config_test/alias "$SCRIPT" alias </dev/null 2>&1) || true
clean=$(strip_ansi "$out")
if echo "$clean" | grep -qF "alias_one" && echo "$clean" | grep -qF "alias_two"; then
    echo "  ✓ Multi-alias Host: both aliases listed"
    ((PASS++))
else
    echo "  ✗ Multi-alias Host: both aliases listed"
    echo "    got: $out"
    ((FAIL++))
fi

echo ""
echo "--- host patterns ---"

# Host * (catch-all) must never be listed; comma-separated patterns must be
# split into separate entries; legacy 'Host=alias' must be recognized
out=$(SSHS_CONFIG=ssh_config_test/patterns "$SCRIPT" </dev/null 2>&1) || true
clean=$(strip_ansi "$out")
n_entries=$(echo "$clean" | grep -cE "^[0-9]+\) ")
if (( n_entries == 4 )) \
   && echo "$clean" | grep -qF "real_host" && echo "$clean" | grep -qF "stg1" \
   && echo "$clean" | grep -qF "stg2" && echo "$clean" | grep -qF "legacy_one"; then
    echo "  ✓ Host patterns: '*' hidden, comma-split, Host= recognized (4 entries)"
    ((PASS++))
else
    echo "  ✗ Host patterns"
    echo "    expected 4 entries (real_host, stg1, stg2, legacy_one), got $n_entries"
    echo "    got: $out"
    ((FAIL++))
fi

echo ""
echo "--- missing config ---"

# Missing config file → clean error, not a raw bash error
out=$(SSHS_CONFIG=/nonexistent_sshs_cfg "$SCRIPT" </dev/null 2>&1) || true
clean=$(strip_ansi "$out")
if echo "$clean" | grep -qF "config file not found" && ! echo "$clean" | grep -qi "no such file"; then
    echo "  ✓ Missing config: clean error message"
    ((PASS++))
else
    echo "  ✗ Missing config: clean error message"
    echo "    got: $out"
    ((FAIL++))
fi

echo ""
echo "--- indented comment ---"

# An indented sshs-off comment must hide the host
out=$(SSHS_CONFIG=ssh_config_test/indented_comment "$SCRIPT" </dev/null 2>&1) || true
clean=$(strip_ansi "$out")
if echo "$clean" | grep -qF "visible_one" && echo "$clean" | grep -qF "visible_two" \
   && ! echo "$clean" | grep -qF "off_host"; then
    echo "  ✓ Indented comment: indented sshs-off hides the host"
    ((PASS++))
else
    echo "  ✗ Indented comment: indented sshs-off hides the host"
    echo "    got: $out"
    ((FAIL++))
fi

echo ""
echo "--- regex space ---"

# In regex mode, a literal space must not be converted to .*
out=$(SSHS_CONFIG=ssh_config_test/regex_space "$SCRIPT" -r 'foo bar' </dev/null 2>&1) || true
clean=$(strip_ansi "$out")
if echo "$clean" | grep -qF "not found"; then
    echo "  ✓ Regex mode: literal space not converted to .*"
    ((PASS++))
else
    echo "  ✗ Regex mode: literal space not converted to .*"
    echo "    got: $out"
    ((FAIL++))
fi

echo ""
echo "--- invalid regex ---"

# An invalid regex must be reported (exit 2 = usage error), not silently
# return "not found"
out=$(SSHS_CONFIG=ssh_config_test/config5 "$SCRIPT" -r "[" </dev/null 2>&1); code=$?
clean=$(strip_ansi "$out")
if echo "$clean" | grep -qF "invalid regex" && (( code == 2 )); then
    echo "  ✓ Regex mode: invalid pattern → error + exit 2"
    ((PASS++))
else
    echo "  ✗ Regex mode: invalid pattern"
    echo "    expected: 'invalid regex' + exit 2"
    echo "    got:      $out (exit $code)"
    ((FAIL++))
fi

# Same behavior via the SSHS_REGEX variable
out=$(SSHS_REGEX=1 SSHS_CONFIG=ssh_config_test/config5 "$SCRIPT" "[" </dev/null 2>&1); code=$?
clean=$(strip_ansi "$out")
if echo "$clean" | grep -qF "invalid regex" && (( code == 2 )); then
    echo "  ✓ Regex mode (SSHS_REGEX): invalid pattern → error + exit 2"
    ((PASS++))
else
    echo "  ✗ Regex mode (SSHS_REGEX): invalid pattern"
    echo "    got:      $out (exit $code)"
    ((FAIL++))
fi

echo ""
echo "--- exit codes ---"

# Scheme: 0 = found & handled (menu cancel is a normal end), 1 = not found
# (grep-like), 2 = usage error. The ssh exit code itself is propagated.

out=$(SSHS_CONFIG=ssh_config_test/config5 "$SCRIPT" zzz_nonexistent_zzz </dev/null 2>&1); code=$?
if (( code == 1 )); then
    echo "  ✓ Not found → exit 1"
    ((PASS++))
else
    echo "  ✗ Not found → exit 1"
    echo "    got: exit $code"
    ((FAIL++))
fi

out=$(SSHS_CONFIG=ssh_config_test/config5 "$SCRIPT" worker <<<"x" 2>&1); code=$?
if (( code == 0 )) && echo "$out" | grep -qF "Choose an option"; then
    echo "  ✓ Menu cancel → exit 0 (normal end)"
    ((PASS++))
else
    echo "  ✗ Menu cancel → exit 0"
    echo "    got: exit $code"
    ((FAIL++))
fi

out=$(SSHS_CONFIG=/nonexistent_sshs_cfg "$SCRIPT" </dev/null 2>&1); code=$?
if (( code == 2 )); then
    echo "  ✓ Missing config → exit 2"
    ((PASS++))
else
    echo "  ✗ Missing config → exit 2"
    echo "    got: exit $code"
    ((FAIL++))
fi

echo ""
echo "--- unreadable config ---"

# Config exists but is not readable → clean error + exit 2 (not a raw bash error)
unr=$(mktemp)
printf 'Host nope\n    HostName 127.0.0.1\n' > "$unr"
chmod 000 "$unr"
out=$(SSHS_CONFIG="$unr" "$SCRIPT" </dev/null 2>&1); code=$?
chmod 644 "$unr"; rm -f "$unr"
clean=$(strip_ansi "$out")
if echo "$clean" | grep -qF "not readable" && (( code == 2 )) && ! echo "$clean" | grep -qi "permission denied"; then
    echo "  ✓ Unreadable config: clean error + exit 2"
    ((PASS++))
else
    echo "  ✗ Unreadable config: clean error + exit 2"
    echo "    got: $out (exit $code)"
    ((FAIL++))
fi

echo ""
echo "--- regex case sensitivity ---"

# Regex mode is case-sensitive: 'DEV_' must not match lowercase 'dev_' hosts.
# (Note: the hay includes the literal 'Host' keyword, so a class like [A-Z]
# legitimately matches its 'H' — target host text, not the keyword.)
out=$(SSHS_CONFIG=ssh_config_test/config5 "$SCRIPT" -r "DEV_" </dev/null 2>&1) || true
clean=$(strip_ansi "$out")
if echo "$clean" | grep -qF "not found"; then
    echo "  ✓ Regex mode: case-sensitive ('DEV_' matches nothing)"
    ((PASS++))
else
    echo "  ✗ Regex mode: case-sensitive"
    echo "    got: $out"
    ((FAIL++))
fi

# ...and the same pattern lowercased matches
out=$(SSHS_CONFIG=ssh_config_test/config5 "$SCRIPT" -r "dev_k3s_worker" </dev/null 2>&1) || true
clean=$(strip_ansi "$out")
if echo "$clean" | grep -qF "dev_k3s_worker1"; then
    echo "  ✓ Regex mode: lowercase pattern matches"
    ((PASS++))
else
    echo "  ✗ Regex mode: lowercase pattern matches"
    echo "    got: $out"
    ((FAIL++))
fi

# Safe mode stays case-insensitive
out=$(SSHS_CONFIG=ssh_config_test/config5 "$SCRIPT" MASTER </dev/null 2>&1) || true
clean=$(strip_ansi "$out")
if echo "$clean" | grep -qF "Connect to dev_k3s_master"; then
    echo "  ✓ Safe mode: still case-insensitive (MASTER matches master)"
    ((PASS++))
else
    echo "  ✗ Safe mode: still case-insensitive"
    echo "    got: $out"
    ((FAIL++))
fi

echo ""
echo "--- CRLF line endings ---"

# A CRLF included file must not leak a carriage return into host names
crlf_dir=$(mktemp -d)
mkdir -p "$crlf_dir/.ssh/conf.d"
printf '# local\nHost local_one\n    HostName 192.0.2.1\n\nInclude conf.d/*\n' > "$crlf_dir/.ssh/config"
printf '# included CRLF\r\nHost inc_crlf\r\n    HostName 192.0.2.1\r\n' > "$crlf_dir/.ssh/conf.d/inc_crlf"

out=$(HOME="$crlf_dir" "$SCRIPT" </dev/null 2>&1) || true
clean=$(strip_ansi "$out")
if echo "$clean" | grep -qF "inc_crlf" && ! echo "$clean" | grep -q $'\r'; then
    echo "  ✓ CRLF included file: host name clean (no carriage return)"
    ((PASS++))
else
    echo "  ✗ CRLF included file: host name clean"
    echo "    got: $out"
    ((FAIL++))
fi
rm -rf "$crlf_dir"

echo ""
echo "--- performance (>500 hosts, >10 Include files) ---"

# Versioned fixture in ssh_config_test/perf/ (deterministic and verifiable):
# 12 included files × 50 hosts = 600, + 2 in the main file = 602.
perf_home="$PWD/ssh_config_test/perf"
perf_config="$perf_home/main.conf"
total=602

perf_run() {
    # $@ = sshs arguments, run against the versioned fixture
    HOME="$perf_home" SSHS_CONFIG="$perf_config" "$SCRIPT" "$@" </dev/null 2>&1 || true
}

# Timed listing
start=$(date +%s%N); perf_run >/dev/null; end=$(date +%s%N)
t_list=$(( (end - start) / 1000000 ))
# Timed search (50 hosts from file 07)
start=$(date +%s%N); perf_run perf_07_ >/dev/null; end=$(date +%s%N)
t_search=$(( (end - start) / 1000000 ))

# Correctness: number of hosts listed / found
list_out=$(perf_run)
list_clean=$(strip_ansi "$list_out")
list_count=$(printf '%s\n' "$list_clean" | grep -c '^perf_' || true)
srch_out=$(perf_run perf_07_)
srch_clean=$(strip_ansi "$srch_out")
srch_count=$(printf '%s\n' "$srch_clean" | grep -c '^perf_07_' || true)

echo "  listing $total hosts : ${t_list} ms"
echo "  search 50 hosts      : ${t_search} ms"

limit=${SSHS_PERF_LIMIT_MS:-2000}

if (( list_count == total )) && (( srch_count == 50 )); then
    echo "  ✓ Performance: correct count ($list_count listed, $srch_count found)"
    ((PASS++))
else
    echo "  ✗ Performance: incorrect count (expected $total/50, got $list_count/$srch_count)"
    ((FAIL++))
fi

# Safety net: a fork per line (sed/grep/awk in the parse loop) would blow this
# budget. Tunable via SSHS_PERF_LIMIT_MS.
if (( t_list < limit )) && (( t_search < limit )); then
    echo "  ✓ Performance: listing and search under ${limit} ms"
    ((PASS++))
else
    echo "  ✗ Performance: over ${limit} ms (listing=${t_list}ms, search=${t_search}ms)"
    ((FAIL++))
fi

echo ""
echo "=== $PASS PASS, $FAIL FAIL ==="
exit $FAIL
