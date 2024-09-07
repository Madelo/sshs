# SSH Select - command sshs

Shell function to search for a host in ~/.ssh/config and connect to it

## Usage

- sshs: Shows  the list of hosts in the config file
- sshs [param]: Searches the config file for the corresponding hosts. (ignore case)

## Config variable

- SSHS_MENU : string containing the list of characters available for selection in the menu,
              default value: '0123456789'. The length of the string determines the maximum
              size of the menu.
- SSHS_CONFIG : ssh configuration file used, default value: '~/.ssh/config'

## Result

- if 0 host found : Not found message
- if 1 host found : Immediate connection
- if <= (size SSHS_MENU) hosts found : Selection menu and connection to the chosen host
- if > (size SSHS_MENU) results : Show host list and exit

## Advice

- Source the file sshs.sh in .bashrc
- In the ~/.ssh/config file, add a comment '#' with a description on the line above the 'Host'
  element. This line is used for the search and the list of results displayed by the function.
- If the comment line contains sshs-off, the host is ignored

## Example

### ~/.ssh/config

```sh
# dev, jumphost, bastion
Host dev_bastion
    HostName 192.168.10.2

# dev, k3s, kubernetes, master
Host dev_k3s_master
    HostName 192.168.10.3

# dev, k3s, kubernetes, worker
Host dev_k3s_worker1
    HostName 192.168.10.4

# dev, k3s, kubernetes, worker
Host dev_k3s_worker2
    HostName 192.168.10.5

# dev, k3s, kubernetes, worker
Host dev_k3s_worker3
    HostName 192.168.10.6

# Global (sshs-off)
Host *
    AddKeysToAgent yes
    IdentityFile "~\.ssh\id_ecdsa"
```

### Comment of **Host \*** contains sshs-off and is not displayed

```sh
$ sshs
0) dev_bastion      # dev, jumphost, bastion
1) dev_k3s_master   # dev, k3s, kubernetes, master
2) dev_k3s_worker1  # dev, k3s, kubernetes, worker
3) dev_k3s_worker2  # dev, k3s, kubernetes, worker
4) dev_k3s_worker3  # dev, k3s, kubernetes, worker
Choose an option:
```

### search k3s worker : three results, choice

```sh
$ sshs k3s worker
0) dev_k3s_worker1  # dev, k3s, kubernetes, worker
1) dev_k3s_worker2  # dev, k3s, kubernetes, worker
2) dev_k3s_worker3  # dev, k3s, kubernetes, worker
Choose an option:
```

### search dev master : one result, autochoice

```txt
$ sshs dev master
>>> Connect to dev_k3s_master <<<
dev_k3s_master:~$ exit
>>> Disconnected from dev_k3s_master <<<
```

### Set menu

```sh
$ SSHS_MENU='abcde' sshs
a) dev_bastion      # dev, jumphost, bastion
b) dev_k3s_master   # dev, k3s, kubernetes, master
c) dev_k3s_worker1  # dev, k3s, kubernetes, worker
d) dev_k3s_worker2  # dev, k3s, kubernetes, worker
e) dev_k3s_worker3  # dev, k3s, kubernetes, worker
Choose an option:
```

### Set ssh config file

```sh
$ export SSHS_CONFIG='other_config'
$ sshs
0) tst_bastion      # tst, jumphost, bastion
1) tst_k3s_master   # tst, k3s, kubernetes, master
2) tst_k3s_worker1  # tst, k3s, kubernetes, worker
3) tst_k3s_worker2  # tst, k3s, kubernetes, worker
4) tst_k3s_worker3  # tst, k3s, kubernetes, worker
Choose an option:
```
