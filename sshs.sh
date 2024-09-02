#!/bin/bash

# --------------------------------------------------------------------------------------------------
# sshs: SSH Select (git: https://github.com/Madelo/sshs)
#   Shell Function to search for a host in the ~/.ssh/config file and connect to it
# Usage:
#   - sshs: Shows  the list of hosts in the config file
#   - sshs [param]: Searches the config file for the corresponding hosts. (ignore case)
# Variable:
#   - SSHS_MENU : string containing the list of characters available for selection in the menu,
#                 default value: '0123456789'. The length of the string determines the maximum
#                 size of the menu.
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
sshs () {
    local tblCom=() tblHost=() i=0 line='' hSize=0 fields=()
    local search="$*"; search=${search,,}; search="${search// /.*}"
    local menu="${SSHS_MENU:="0123456789"}"

    sshs_connect() {
        echo -e "\e[32m>>> Connect to $1 <<<\e[0m"
        ssh "$1"
        echo -e "\e[32m>>> Disconnected from $1 <<<\e[0m"
    }
    sshs_strindex() { local x="${1%%"$2"*}"; [[ "$x" = "$1" ]] && echo -1 || echo "${#x}"; }

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
    done < ~/.ssh/config

    line=''; for ((i=0;i<hSize;i++)); do line="${line} "; done
    for ((i = 0 ; i < ${#tblHost[@]} ; i++)); do
        tblHost[i]="${tblHost[i]:0:$hSize}${line:0:$((hSize-${#tblHost[i]}))}"
    done

    if (( ${#tblHost[@]} == 0 )); then
        echo -e "\e[31m${FUNCNAME[0]}: '$search' not found in ~/.ssh/config\e[0m"
    elif (( ${#tblHost[@]} == 1 )); then
        sshs_connect "${tblHost[0]//[[:space:]]/}"
    elif (( ${#tblHost[@]} <= ${#menu} )); then
        for ((i = 0 ; i < ${#tblHost[@]} ; i++)); do
            [[ "${tblCom[i]}" != "" ]] && echo -e "\e[32m${menu:$i:1}\e[0m) ${tblHost[i]}\e[31m ${tblCom[i]}\e[0m" \
                                       || echo -e "\e[32m${menu:$i:1}\e[0m) ${tblHost[i]}"
        done
        echo -ne "Choose an option: "; read -rn1 i; echo
        [[ "$menu" == *"$i"* ]] && sshs_connect "${tblHost[$(sshs_strindex "$menu" "$i")]//[[:space:]]/}"
    else
        for ((i = 0 ; i < ${#tblHost[@]} ; i++)); do
            [[ "${tblCom[i]}" != "" ]] && echo -e "${tblHost[i]}\e[31m ${tblCom[i]}\e[0m" \
                                       || echo -e "${tblHost[i]}"
        done
    fi
}

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && sshs "$@"
