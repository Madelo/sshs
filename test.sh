#!/bin/bash
# Tests for sshs.sh
# Run from the repository root: ./test.sh

cd "$(dirname "$0")" || exit
# shellcheck disable=SC1091 # sshs.sh is checked with it: shellcheck sshs.sh test.sh
source sshs.sh

PASS=0 FAIL=0

# Strip ANSI escape codes (regex removal; ${var//} cannot do regex)
strip_ansi() {
    # shellcheck disable=SC2001
    printf '%s\n' "$1" | sed 's/\x1b\[[0-9;]*m//g'
}

check() {
    local desc="$1" expected="$2" cmd="$3"
    local out
    out=$(SSHS_CONFIG=ssh_config_test/config5 bash -c "source sshs.sh; $cmd" </dev/null 2>&1) || true
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

check "List all hosts"                          "dev_bastion"           'sshs'
check "Simple search"                            "dev_k3s_master"        'sshs master'
check "Multi-word search"                        "k3s_worker1"           'sshs k3s worker'
check "1 result → auto-connect"                  "Connect to dev_k3s_master" 'sshs k3s master'
check "sshs-off ignored (Host* absent)"          "dev_k3s_master"        'sshs k3s'
check "Custom menu (abcde)"                      "a) dev_bastion"        'SSHS_MENU=abcde sshs'
# shellcheck disable=SC2016 # single-quoted string is evaluated later by bash -c
check "SSHS_MENU preserved after call"           "OK"                    'SSHS_MENU="" sshs >/dev/null 2>&1; [[ "$SSHS_MENU" == "" ]] && echo OK'
check "Alternative config config30"              "pve.lab"               'SSHS_CONFIG=ssh_config_test/config30 sshs pve'
check "-r flag (regex)"                           "dev_k3s_master"        'sshs -r "dev_.*master"'
check "SSHS_REGEX variable"                      "dev_k3s_master"        'SSHS_REGEX=1 sshs "dev_.*master"'
check "Safe mode: [a-z] → no injection"          "not found"             'sshs "[a-z]"'
check "No result"                                "not found"             'sshs zzz_nonexistent_zzz'
check "Too many results → list without menu"     "dev_bastion"           'SSHS_MENU=ab sshs dev'
check "Prompt 'other key to cancel' visible"     "other key to cancel"   'sshs'
check "SSH connection failure → failed"          "failed"                'sshs dev_k3s_master'

echo ""
echo "--- ssh options ---"

# Verify -- separator: SSH opts are not treated as search terms
check "-- separator: SSH options ignored for search"              "Connect to dev_k3s_master" 'sshs dev master -- -v'
check "-- separator: menu with SSH options (not used in search)"  "dev_k3s_worker1" 'sshs k3s worker -- -p 2222'
check "-- separator: no search, all entries"                      "dev_bastion" 'sshs -- -v'
check "SSHS_SSH_OPTS does not interfere with search"              "Connect to dev_k3s_master" 'SSHS_SSH_OPTS=-v sshs master'

echo ""
echo "--- menu bounds ---"

# Helper: run sshs with simulated keypress input
run_with_key() {
    local key="$1" cmd="$2"
    SSHS_CONFIG=ssh_config_test/config5 bash -c "source sshs.sh; $cmd" <<<"$key" 2>&1 || true
}

# Test: within bounds — press "1" in 3-host menu (workers 1,2,3) → should connect to index 1 = worker2
out=$(run_with_key "1" "sshs worker")
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
out=$(run_with_key "5" "sshs worker")
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
    local desc="$1" expected="$2" cmd="$3"
    local out clean
    out=$(HOME="$PWD/ssh_config_test/fakehome" SSHS_CONFIG=ssh_config_test/include/main.conf \
        bash -c "source sshs.sh; $cmd" </dev/null 2>&1) || true
    clean=$(strip_ansi "$out")
    if echo "$clean" | grep -qF "$expected"; then
        echo "  ✓ $desc"; ((PASS++))
    else
        echo "  ✗ $desc"; echo "    expected: $expected"; echo "    got:      $out"; ((FAIL++))
    fi
}

check_inc "Include: glob + relative path (conf.d/*.conf)"  "inc_aaa"   'sshs'
check_inc "Include: ~ expansion (recursive down to inner.conf)" "inc_inner" 'sshs'
check_inc "Include: host after the Includes"               "inc_bottom" 'sshs'
check_inc "Include: search in included files"              "Connect to inc_inner" 'sshs inner'

# sshs-off in an included file must be ignored (inc_a_off hidden, inc_aaa shown)
out=$(HOME="$PWD/ssh_config_test/fakehome" SSHS_CONFIG=ssh_config_test/include/main.conf \
    bash -c "source sshs.sh; sshs" </dev/null 2>&1) || true
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
echo "--- indented Host ---"

# An indented Host line must be listed (ssh accepts leading whitespace)
out=$(SSHS_CONFIG=ssh_config_test/indented bash -c "source sshs.sh; sshs" </dev/null 2>&1) || true
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
out=$(SSHS_CONFIG=ssh_config_test/alias bash -c "source sshs.sh; sshs alias" </dev/null 2>&1) || true
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
echo "--- missing config ---"

# Missing config file → clean error, not a raw bash error
out=$(SSHS_CONFIG=/nonexistent_sshs_cfg bash -c "source sshs.sh; sshs" </dev/null 2>&1) || true
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
out=$(SSHS_CONFIG=ssh_config_test/indented_comment bash -c "source sshs.sh; sshs" </dev/null 2>&1) || true
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
out=$(SSHS_CONFIG=ssh_config_test/regex_space bash -c "source sshs.sh; sshs -r 'foo bar'" </dev/null 2>&1) || true
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
echo "--- CRLF line endings ---"

# A CRLF included file must not leak a carriage return into host names
crlf_dir=$(mktemp -d)
mkdir -p "$crlf_dir/.ssh/conf.d"
printf '# local\nHost local_one\n    HostName 192.0.2.1\n\nInclude conf.d/*\n' > "$crlf_dir/.ssh/config"
printf '# included CRLF\r\nHost inc_crlf\r\n    HostName 192.0.2.1\r\n' > "$crlf_dir/.ssh/conf.d/inc_crlf"

out=$(HOME="$crlf_dir" bash -c "source sshs.sh; sshs" </dev/null 2>&1) || true
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
    # $1 = sshs command (string), run against the versioned fixture
    HOME="$perf_home" SSHS_CONFIG="$perf_config" \
        bash -c "source sshs.sh; $1" </dev/null 2>&1 || true
}

# Timed listing
start=$(date +%s%N); perf_run 'sshs' >/dev/null; end=$(date +%s%N)
t_list=$(( (end - start) / 1000000 ))
# Timed search (50 hosts from file 07)
start=$(date +%s%N); perf_run 'sshs perf_07_' >/dev/null; end=$(date +%s%N)
t_search=$(( (end - start) / 1000000 ))

# Correctness: number of hosts listed / found
list_out=$(perf_run 'sshs')
list_clean=$(strip_ansi "$list_out")
list_count=$(printf '%s\n' "$list_clean" | grep -c '^perf_' || true)
srch_out=$(perf_run 'sshs perf_07_')
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
