#!/bin/bash
# Tests for sshs.sh
# Run: cd /home/mdo/code/sshs && ./test.sh

cd "$(dirname "$0")"
source sshs.sh

PASS=0 FAIL=0

check() {
    local desc="$1" expected="$2" cmd="$3"
    local out
    out=$(SSHS_CONFIG=ssh_config_test/config5 bash -c "source sshs.sh; $cmd" </dev/null 2>&1) || true
    # Strip ANSI escape codes before matching
    local clean; clean=$(echo "$out" | sed 's/\x1b\[[0-9;]*m//g')
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

check "Liste tous les hôtes"                  "dev_bastion"           'sshs'
check "Recherche simple"                       "dev_k3s_master"        'sshs master'
check "Recherche multi-mots"                   "k3s_worker1"           'sshs k3s worker'
check "1 résultat → auto-connexion"             "Connect to dev_k3s_master" 'sshs k3s master'
check "sshs-off ignoré (Host* absent)"         "dev_k3s_master"        'sshs k3s'
check "Menu personnalisé (abcde)"              "a) dev_bastion"        'SSHS_MENU=abcde sshs'
check "SSHS_MENU préservé après appel"         "OK"                    'SSHS_MENU="" sshs >/dev/null 2>&1; [[ "$SSHS_MENU" == "" ]] && echo OK'
check "Config alternatif config30"             "pve.lab"               'SSHS_CONFIG=ssh_config_test/config30 sshs pve'
check "Flag -r (regex)"                        "dev_k3s_master"        'sshs -r "dev_.*master"'
check "Variable SSHS_REGEX"                    "dev_k3s_master"        'SSHS_REGEX=1 sshs "dev_.*master"'
check "Safe mode: [a-z] → pas d'injection"     "not found"             'sshs "[a-z]"'
check "Aucun résultat"                         "not found"             'sshs zzz_nonexistent_zzz'
check "Trop de résultats → liste sans menu"    "dev_bastion"           'SSHS_MENU=ab sshs dev'
check "Prompt 'other key to cancel' visible"   "other key to cancel"   'sshs'
check "Échec connexion SSH → failed"           "failed"                'sshs dev_k3s_master'

echo ""
echo "=== $PASS PASS, $FAIL FAIL ==="
exit $FAIL
