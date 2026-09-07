#!/bin/bash

# --------------------------------------------------------------------------------------------------
# sshs: SSH Select (git: https://github.com/Madelo/sshs)
#   Shell script to search for a host in the ~/.ssh/config file and connect to it
#   Must be executed directly, not sourced: a sourced run would inherit the calling shell's
#   state (e.g. a custom IFS), which breaks the parsing. The script refuses to be sourced.
# Usage:
#   - sshs: Shows  the list of hosts in the config file
#   - sshs [param]: Searches the config file for the corresponding hosts. (ignore case)
#   - sshs -r [param]: Searches using regex pattern (metacharacters interpreted,
#     case-sensitive)
#   - sshs [params...] [-- ssh_options...]: Pass SSH options after '--' separator
#     Example: sshs dev master -- -A -p 2222
# Variable:
#   - SSHS_MENU : string containing the list of characters available for selection in the menu,
#                 default value: '0123456789'. The length of the string determines the maximum
#                 size of the menu.
#   - SSHS_CONFIG : ssh configuration file used, default value: '~/.ssh/config'
#   - SSHS_REGEX : when set, enables regex mode (same as -r flag)
#   - SSHS_SSH_OPTS : additional SSH options appended to every connection
#     Example: export SSHS_SSH_OPTS="-A -p 2222"
#   - 'Include' directives are followed: included files are read recursively, globs
#     and '~' are expanded, and relative paths are resolved against ~/.ssh
# Result:
#   - if 0 host found: Not found message
#   - if 1 host found: Immediate connection
#   - if <= (size SSHS_MENU) hosts found : Selection menu and connection to the chosen host
#   - if > (size SSHS_MENU) results: Show host list and exit
# Exit codes:
#   - 0: hosts found and handled (connection, list display, or menu cancel)
#   - 1: no host found (grep-like)
#   - 2: usage error (config file not found or not readable, invalid regex, sourced run)
#   - when a connection is made, the exit code of ssh itself is propagated
#     (255 = connection failure)
# Advice:
#   - set the menu choice, example: export SSHS_MENU='12345'
#   - make the script executable and run it directly (or copy it into your PATH,
#     e.g. ~/.local/bin/sshs); do NOT source it (see note at the top)
#   - In  the ~/.ssh/config file, add a comment '#' with a description on the line above the 'Host'
#     element. This line is used for the search and the list of results displayed by the script.
#   - If the comment line contains sshs-off, the host is ignored
#   - The catch-all 'Host *' entry is never listed (not a connectable target);
#     comma-separated patterns ('Host dev,prd') are listed as separate hosts
# --------------------------------------------------------------------------------------------------
sshs_connect() {
    local host="$1" config="$2"
    shift 2
    echo -e "\e[32m>>> Connect to $host <<<\e[0m"
    # shellcheck disable=SC2086 # SSHS_SSH_OPTS is intentionally word-split into options
    ssh -F "${config}" "$@" ${SSHS_SSH_OPTS:-} "$host"
    local ret=$?
    if (( ret == 255 )); then
        echo -e "\e[31m>>> Connection to $host failed <<<\e[0m"
    else
        echo -e "\e[32m>>> Disconnected from $host (exit $ret) <<<\e[0m"
    fi
    return $ret
}
sshs_strindex() { local -n out_ref="$1"; local x="${2%%"$3"*}"; [[ "$x" == "$2" ]] && out_ref=-1 || out_ref="${#x}"; }

# Escape regex metacharacters so the search is treated as literal text.
# Pure bash, no fork: writes into the nameref variable (no command substitution),
# which matters for parse performance on large config files.
sshs_escape_regex() {
    local -n out_ref="$1"
    local s="$2" c='' i
    out_ref=''
    for (( i = 0; i < ${#s}; i++ )); do
        c="${s:i:1}"
        case "$c" in
            ']'|'.'|'['|\\|'*'|'+'|'?'|'^'|'$'|'{'|'}'|'('|')'|'|') out_ref+="\\$c" ;;
            *) out_ref+="$c" ;;
        esac
    done
}

# Read an SSH config file, collecting hosts (recursively following 'Include').
# Appends to the caller's tblHost/tblCom/hSize/i via dynamic scoping, and reads
# $search from the caller. 'pline' is local to each file (comment scope).
# $2 = include depth, guarding against circular includes (ssh caps at 16).
sshs_read_config() {
    local file="$1" depth="${2:-0}" line='' pline='' fields=() j a='' rest='' hay=''
    (( depth > 16 )) && return 0
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"  # tolerate CRLF line endings
        # Legacy keyword=value syntax: 'Host=alias' behaves like 'Host alias'
        if [[ "$line" =~ ^[[:space:]]*[Hh]ost[[:space:]]*=[[:space:]]*(.*)$ ]]; then
            line="Host ${BASH_REMATCH[1]}"
        fi
        # Include directive: process included files in place
        if [[ "$line" =~ ^[[:space:]]*[Ii][Nn][Cc][Ll][Uu][Dd][Ee]([[:space:]]+(.*))?$ ]]; then
            sshs_include "${BASH_REMATCH[2]}" "$((depth + 1))"
            pline=''  # a comment above an 'Include' must not leak onto hosts after it
            continue
        fi
        if [[ "${line,,}" =~ ^[[:space:]]*host[[:space:]] ]]; then
            if [[ "${pline,,}" != *sshs-off* ]]; then
                # Safe mode is case-insensitive; regex mode is case-sensitive
                if (( regex )); then hay="$line $pline"; else hay="${line,,} ${pline,,}"; fi
                if [[ "$hay" =~ $search ]]; then
                    read -ra fields <<< "$line"
                    for (( j = 1; j < ${#fields[@]}; j++ )); do
                        # Comma-separated patterns: one entry per alias
                        rest="${fields[j]},"
                        while [[ -n "$rest" ]]; do
                            a="${rest%%,*}"
                            rest="${rest#*,}"
                            # skip empty aliases and the catch-all '*' (not connectable)
                            [[ -z "$a" || "$a" == "*" ]] && continue
                            tblHost[i]="$a"
                            tblCom[i]="${pline}"
                            (( ${#tblHost[$i]} > hSize )) && hSize=${#tblHost[$i]}
                            (( i++ ))
                        done
                    done
                fi
            fi
        fi
        if [[ "$line" =~ ^[[:space:]]*# ]]; then pline=${line}
        else pline=''; fi
    done < "$file"
}

# Expand the argument list of an 'Include' directive and read each matched file.
sshs_include() {
    local tmp="$1" depth="${2:-0}" buf='' c='' inq=0 pat='' g=''
    local -a toks=()
    # Tokenize on whitespace, honouring double quotes
    while [[ -n "$tmp" ]]; do
        c="${tmp:0:1}"; tmp="${tmp:1}"
        if [[ "$c" == '"' ]]; then
            (( inq ^= 1 ))
        elif [[ "$c" == ' ' || "$c" == $'\t' ]]; then
            if (( ! inq )); then
                [[ -n "$buf" ]] && { toks+=("$buf"); buf=''; }
            else
                buf+="$c"
            fi
        else
            buf+="$c"
        fi
    done
    [[ -n "$buf" ]] && toks+=("$buf")

    for pat in "${toks[@]}"; do
        [[ -z "$pat" ]] && continue
        # Expand leading ~ (and ~user) to the home directory
        if [[ "$pat" == "~" ]]; then
            pat="$HOME"
        elif [[ "$pat" =~ ^~([^/]*)(/.*)?$ ]]; then
            local un="${BASH_REMATCH[1]}" rest="${BASH_REMATCH[2]}"
            if [[ -z "$un" ]]; then
                pat="$HOME${rest}"
            else
                local uh; uh=$(getent passwd "$un" 2>/dev/null)
                if [[ -n "$uh" ]]; then
                    uh=${uh#*:}; uh=${uh#*:}; uh=${uh#*:}; uh=${uh#*:}; uh=${uh#*:}
                    uh=${uh%%:*}
                    pat="$uh${rest}"
                fi
            fi
        fi
        # Relative paths are resolved against ~/.ssh (user config)
        [[ "$pat" != /* ]] && pat="$HOME/.ssh/$pat"
        # Glob-expand the pattern in place (a quoted path stays a single token,
        # so paths with spaces work, quoted globs included). No '--': compgen -G
        # fails on patterns containing a literal space when '--' is given.
        # compgen also returns a literal existing path; no match is silently
        # ignored. sort restores the lexical order of a normal glob expansion
        # (compgen returns matches in readdir order).
        local -a matches=()
        while IFS= read -r g; do
            [[ -n "$g" ]] && matches+=("$g")
        done < <(compgen -G "$pat" 2>/dev/null | sort)
        for g in "${matches[@]}"; do
            [[ -f "$g" ]] && sshs_read_config "$g" "$depth"
        done
    done
}

sshs () {
    local tblCom=() tblHost=() i=0 hSize=0 padding=''
    local regex=0
    [[ "$1" == "-r" ]] && { regex=1; shift; }
    [[ -n "${SSHS_REGEX:-}" ]] && regex=1
    # Regex mode: match bytes in the C locale so character classes are
    # deterministic and case-sensitive ([A-Z] never matches lowercase letters;
    # under a dictionary-collated UTF-8 locale it would).
    (( regex )) && local LC_ALL=C
    # Split args on "--": before = search terms, after = ssh options
    local search_args=() ssh_opts=() found_sep=0
    for arg in "$@"; do
        if (( ! found_sep )) && [[ "$arg" == "--" ]]; then
            found_sep=1
            continue
        fi
        if (( found_sep )); then
            ssh_opts+=("$arg")
        else
            search_args+=("$arg")
        fi
    done
    local search="${search_args[*]}"
    local shown_search="${search:-'.*'}"
    if (( ! regex )); then
        search=${search,,}
        sshs_escape_regex search "$search"
        search="${search// /.*}"
    fi
    search=${search:-'.*'}
    # In regex mode, bash's =~ fails silently on an invalid pattern (it simply never
    # matches), so validate the regex explicitly before parsing.
    # grep exit codes: 0 = match, 1 = no match, 2 = invalid regex.
    if (( regex )); then
        local rc=0
        grep -Eq "$search" /dev/null 2>/dev/null || rc=$?
        if (( rc == 2 )); then
            echo -e "\e[31msshs: invalid regex: '$search'\e[0m" >&2
            return 2
        fi
    fi
    local menu="${SSHS_MENU:-"0123456789"}"
    local config="${SSHS_CONFIG:-"$HOME/.ssh/config"}"
    if [[ ! -f "$config" ]]; then
        echo -e "\e[31msshs: config file not found: ${config}\e[0m" >&2
        return 2
    fi
    if [[ ! -r "$config" ]]; then
        echo -e "\e[31msshs: config file not readable: ${config}\e[0m" >&2
        return 2
    fi

    sshs_read_config "$config"

    padding=''; for ((i=0;i<hSize;i++)); do padding="${padding} "; done
    for ((i = 0 ; i < ${#tblHost[@]} ; i++)); do
        tblHost[i]="${tblHost[i]:0:$hSize}${padding:0:$((hSize-${#tblHost[i]}))}"
    done

    if (( ${#tblHost[@]} == 0 )); then
        echo -e "\e[31m${FUNCNAME[0]}: '$shown_search' not found in ${config}\e[0m"
        return 1
    elif (( ${#tblHost[@]} == 1 )); then
        sshs_connect "${tblHost[0]//[[:space:]]/}" "$config" "${ssh_opts[@]}"
    elif (( ${#tblHost[@]} <= ${#menu} )); then
        for ((i = 0 ; i < ${#tblHost[@]} ; i++)); do
            [[ "${tblCom[i]}" != "" ]] && echo -e "\e[32m${menu:$i:1}\e[0m) ${tblHost[i]}\e[31m ${tblCom[i]}\e[0m" \
                                       || echo -e "\e[32m${menu:$i:1}\e[0m) ${tblHost[i]}"
        done
        echo -ne "Choose an option (other key to cancel): "; read -rn1 i; echo
        # Only connect if key is in menu AND within range of available hosts.
        # A cancel (other key / out of bounds) is a normal end: exit 0.
        local idx; sshs_strindex idx "$menu" "$i"
        if [[ "$i" != "" && "$idx" != "-1" && "$idx" -lt "${#tblHost[@]}" ]]; then
            sshs_connect "${tblHost[$idx]//[[:space:]]/}" "$config" "${ssh_opts[@]}"
            return
        fi
        return 0
    else
        for ((i = 0 ; i < ${#tblHost[@]} ; i++)); do
            [[ "${tblCom[i]}" != "" ]] && echo -e "${tblHost[i]}\e[31m ${tblCom[i]}\e[0m" \
                                       || echo -e "${tblHost[i]}"
        done
    fi
}

# Standalone script only: refuse to be sourced (the calling shell's state, e.g. a
# custom IFS, would corrupt the parsing). 'return' keeps the sourcing shell alive.
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    echo -e "\e[31msshs: this script must be executed directly, not sourced\e[0m" >&2
    unset -f sshs sshs_connect sshs_strindex sshs_escape_regex sshs_read_config sshs_include
    return 2
fi
sshs "$@"
