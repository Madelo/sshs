#!/bin/bash

# --------------------------------------------------------------------------------------------------
# sshs: SSH Select (git: https://github.com/Madelo/sshs)
#   Shell Function to search for a host in the ~/.ssh/config file and connect to it
# Usage:
#   - sshs: Shows  the list of hosts in the config file
#   - sshs [param]: Searches the config file for the corresponding hosts. (ignore case)
#   - sshs -r [param]: Searches using regex pattern (metacharacters interpreted)
# Variable:
#   - SSHS_MENU : string containing the list of characters available for selection in the menu,
#                 default value: '0123456789'. The length of the string determines the maximum
#                 size of the menu.
#   - SSHS_CONFIG : ssh configuration file used, default value: '~/.ssh/config'
#   - SSHS_REGEX : when set, enables regex mode (same as -r flag)
# Result:
#   - if 0 host found: Not found message
#   - if 1 host found: Immediate connection
#   - if <= (size SSHS_MENU) hosts found : Selection menu and connection to the chosen host
#   - if > (size SSHS_MENU) results: Show host list and exit
# Advice:
#   - set the menu choice, example: export SSHS_MENU='12345'
#   - Source this file in .bashrc
#   - In  the ~/.ssh/config file, add a comment '#' with a description on the line above the 'Host'
#     element. This line is used for the search and the list of results displayed by the function.
#   - If the comment line contains sshs-off, the host is ignored
# --------------------------------------------------------------------------------------------------
sshs_connect() {
    local host="$1" config="$2"
    echo -e "\e[32m>>> Connect to $host <<<\e[0m"
    ssh -F "${config}" "$host"
    local ret=$?
    if (( ret == 255 )); then
        echo -e "\e[31m>>> Connection to $host failed <<<\e[0m"
    else
        echo -e "\e[32m>>> Disconnected from $host (exit $ret) <<<\e[0m"
    fi
    return $ret
}
sshs_strindex() { local x="${1%%"$2"*}"; [[ "$x" = "$1" ]] && echo -1 || echo "${#x}"; }

sshs () {
    local tblCom=() tblHost=() i=0 line='' hSize=0 fields=() padding=''
    local regex=0
    [[ "$1" == "-r" ]] && { regex=1; shift; }
    local search="$*"; search=${search,,}
    if (( ! regex )) && [[ -z "${SSHS_REGEX:-}" ]]; then
        search=$(sed 's/[].[\*+?^${}()|\\]/\\&/g' <<< "$search")
    fi
    search="${search// /.*}"; search=${search:-'.*'}
    local menu="${SSHS_MENU:-"0123456789"}"
    local config="${SSHS_CONFIG:-"$HOME/.ssh/config"}"

    while IFS= read -r line; do
        if [[ "${line,,}" =~ ^host[[:space:]] ]]; then
            if [[ "${pline,,}" != *sshs-off* && "${line,,} ${pline,,}" =~ $search ]]; then
                read -ra fields <<< "$line"
                tblHost[i]="${fields[1]}"
                tblCom[i]="${pline}"
                (( ${#tblHost[$i]} > hSize )) && hSize=${#tblHost[$i]}
                (( i++ ))
            fi
        fi
        if [[ "${line:0:1}" == '#' ]]; then pline=${line}
        else pline=''; fi
    done < "${config}"

    padding=''; for ((i=0;i<hSize;i++)); do padding="${padding} "; done
    for ((i = 0 ; i < ${#tblHost[@]} ; i++)); do
        tblHost[i]="${tblHost[i]:0:$hSize}${padding:0:$((hSize-${#tblHost[i]}))}"
    done

    if (( ${#tblHost[@]} == 0 )); then
        echo -e "\e[31m${FUNCNAME[0]}: '$search' not found in ${config}\e[0m"
    elif (( ${#tblHost[@]} == 1 )); then
        sshs_connect "${tblHost[0]//[[:space:]]/}" "$config"
    elif (( ${#tblHost[@]} <= ${#menu} )); then
        for ((i = 0 ; i < ${#tblHost[@]} ; i++)); do
            [[ "${tblCom[i]}" != "" ]] && echo -e "\e[32m${menu:$i:1}\e[0m) ${tblHost[i]}\e[31m ${tblCom[i]}\e[0m" \
                                       || echo -e "\e[32m${menu:$i:1}\e[0m) ${tblHost[i]}"
        done
        echo -ne "Choose an option (other key to cancel): "; read -rn1 i; echo
        # Only connect if key is in menu — sshs_strindex returns -1 otherwise, guarded here
        [[ "$i" != "" && "$menu" == *"$i"* ]] && sshs_connect "${tblHost[$(sshs_strindex "$menu" "$i")]//[[:space:]]/}" "$config"
    else
        for ((i = 0 ; i < ${#tblHost[@]} ; i++)); do
            [[ "${tblCom[i]}" != "" ]] && echo -e "${tblHost[i]}\e[31m ${tblCom[i]}\e[0m" \
                                       || echo -e "${tblHost[i]}"
        done
    fi
}

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && sshs "$@"
