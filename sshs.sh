#!/bin/bash
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && echo -en "\e[31mSource this file, don't run it\e[0m\n"

# --------------------------------------------------------------------------------------------------
# sshs: SSH Select (git: https://github.com/Madelo/sshs)
#   Shell Function to search for a host in the ~/.ssh/config file and connect to it
# Usage:
#   - sshs: Shows  the list of hosts in the config file
#   - sshs [param]: Searches the config file for the corresponding hosts. (ignore case)
# Result:
#   - if 0 host found: Not found message
#   - if 1 host found: Immediate connection
#   - if < 10 hosts found : Selection menu and connection to the chosen host
#   - if >= 10 results: Show host list and exit
# Advice: 
#   - Source this file in .bashrc
#   - In  the ~/.ssh/config file, add a comment '#' with a description on the line above the 'Host' 
#     element. This line is used for the search and the list of results displayed by the function.
#   - If the comment line contains sshs-off, the host is ignored
# --------------------------------------------------------------------------------------------------
sshs () {
    local tblCom=() tblHost=() i=0 line='' hSize=0 
    local search="$*"; search=${search,,}; search="${search// /.*}"

    sshs_connect() {
        echo -e "\e[32m>>> Connect to $1 <<<\e[0m"
        ssh "$1"
        echo -e "\e[32m>>> Disconnected from $1 <<<\e[0m"
    }
    get_column() { local fields; read -ra fields <<< "$2"; echo "${fields[$1]}"; }

    while IFS= read -r line; do
        if [[ "${line,,}" =~ ^host[[:space:]] ]]; then
            if [[ "${pline,,}" != *sshs-off* && "${line,,} ${pline,,}" =~ $search ]]; then
                tblHost[i]=$(get_column 1 "$line")
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
    elif (( ${#tblHost[@]} < 10 )); then
        for ((i = 0 ; i < ${#tblHost[@]} ; i++)); do
            [[ "${tblCom[i]}" != "" ]] && echo -e "\e[32m$i\e[0m) ${tblHost[i]}\e[31m ${tblCom[i]}\e[0m" \
                                       || echo -e "\e[32m$i\e[0m) ${tblHost[i]}"
        done
        echo -ne "Choose an option: "; read -rn1 i; echo
        [[ "$i" =~ ^[0-9]+$ ]] && (( i < ${#tblHost[@]} )) && sshs_connect "${tblHost[i]//[[:space:]]/}"
    else
        for ((i = 0 ; i < ${#tblHost[@]} ; i++)); do
            [[ "${tblCom[i]}" != "" ]] && echo -e "${tblHost[i]}\e[31m ${tblCom[i]}\e[0m" \
                                       || echo -e "${tblHost[i]}"
        done    
    fi    
}
