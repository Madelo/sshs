# SSH Select - command sshs

Shell function to search for a host in ~/.ssh/config and connect to it

## Usage

- `sshs`: Shows the list of hosts in the config file
- `sshs [param]`: Searches the config file for the corresponding hosts (case insensitive)
- `sshs -r [param]`: Searches using regex pattern (regex metacharacters are interpreted)
- `sshs [params...] [-- ssh_options...]`: Pass SSH options after `--` separator

## Passing SSH options

Use `--` to separate search terms from SSH options. Everything after `--` is passed directly to the `ssh` command.

```sh
# Agent forwarding + custom port
sshs dev master -- -A -p 2222

# Verbose mode + ProxyJump
sshs k3s worker -- -v -J user@bastion

# Local port forwarding (no search = all hosts via menu)
sshs -- -L 8080:localhost:80

# With regex + identity file
sshs -r 'dev_.*worker' -- -i ~/.ssh/dev_key
```

### Persistent options via `SSHS_SSH_OPTS`

Set `SSHS_SSH_OPTS` to append options to every SSH connection. Command-line options from `--` are placed before `SSHS_SSH_OPTS` in the final `ssh` command.

```sh
export SSHS_SSH_OPTS="-A -p 2222"
sshs dev master          # Always uses agent forwarding on port 2222
sshs dev master -- -v    # Adds -v on top of SSHS_SSH_OPTS
```

## Config variables

- `SSHS_MENU`: String containing the list of characters available for selection in the menu,
              default value: `0123456789`. The length of the string determines the maximum
              size of the menu.
- `SSHS_CONFIG`: SSH configuration file used, default value: `~/.ssh/config`
- `SSHS_REGEX`: When set to any value, enables regex mode (metacharacters like `.`, `*`, `[` are interpreted).
              Can also be enabled per-call with the `-r` flag.
- `SSHS_SSH_OPTS`: Additional SSH options appended to every connection. Options passed via `--` on the
                command line take priority (placed before `SSHS_SSH_OPTS`).

## Regex mode

By default, regex metacharacters in search terms are escaped so they are treated as literal text.
This prevents accidental regex injection (e.g. `sshs [a-z]` searches for the literal string `[a-z]`).

To use regex patterns intentionally, either:
```sh
sshs -r 'dev_.*master'
```
or:
```sh
SSHS_REGEX=1 sshs 'dev_.*master'
```

## Result

- if 0 host found: Not found message
- if 1 host found: Immediate connection
- if <= (size SSHS_MENU) hosts found: Selection menu and connection to the chosen host
- if > (size SSHS_MENU) results: Show host list and exit

## Advice

- Source the file `sshs.sh` in `.bashrc`
- In the `~/.ssh/config` file, add a comment `#` with a description on the line above the `Host`
  element. This line is used for the search and the list of results displayed by the function.
- If the comment line contains `sshs-off`, the host is ignored

## Tests

Run the test suite:
```sh
./test.sh
```

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
Choose an option (other key to cancel):
```

### search k3s worker: three results, choice

```sh
$ sshs k3s worker
0) dev_k3s_worker1  # dev, k3s, kubernetes, worker
1) dev_k3s_worker2  # dev, k3s, kubernetes, worker
2) dev_k3s_worker3  # dev, k3s, kubernetes, worker
Choose an option (other key to cancel):
```

### search dev master: one result, autochoice

```txt
$ sshs dev master
>>> Connect to dev_k3s_master <<<
dev_k3s_master:~$ exit
>>> Disconnected from dev_k3s_master (exit 0) <<<
```

### search with regex (-r flag)

```sh
$ sshs -r 'dev_.*worker'
0) dev_k3s_worker1  # dev, k3s, kubernetes, worker
1) dev_k3s_worker2  # dev, k3s, kubernetes, worker
2) dev_k3s_worker3  # dev, k3s, kubernetes, worker
Choose an option (other key to cancel):
```

### Set menu

```sh
$ SSHS_MENU='abcde' sshs
a) dev_bastion      # dev, jumphost, bastion
b) dev_k3s_master   # dev, k3s, kubernetes, master
c) dev_k3s_worker1  # dev, k3s, kubernetes, worker
d) dev_k3s_worker2  # dev, k3s, kubernetes, worker
e) dev_k3s_worker3  # dev, k3s, kubernetes, worker
Choose an option (other key to cancel):
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
Choose an option (other key to cancel):
```
