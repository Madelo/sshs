# Code Review — sshs

## 🔴 Severe

- [x] **L73: circular `Include` → infinite recursion (hang)** — No depth limit or cycle detection in `sshs_read_config`. An `Include` that references itself (directly or indirectly) loops forever. `ssh` guards against this with `MAX_INCLUDE_DEPTH=16`. Demonstrated: `timeout 3` → exit 124. Fix: pass a depth counter and stop (e.g. 16). **Done: depth counter (16), verified — circular include now exits 0.**

- [x] **L77: indented `Host` silently ignored** — `^host[[:space:]]` requires column 0, but `ssh` accepts indentation (and sshs's own `Include` handling, L73, tolerates `^[[:space:]]*`). A `  Host foo` is silently dropped. Demonstrated. Fix: `^[[:space:]]*host[[:space:]]`. **Done + fixture `ssh_config_test/indented` + test.**

- [x] **L79-80: `Host alias1 alias2` → only the first alias kept** — `tblHost[i]="${fields[1]}"` reads only the first field after `Host`. `ssh alias2` works but `sshs alias2` reports "not found". Demonstrated. Fix: iterate all aliases (`fields[1..]`) and create one entry per alias (same comment). **Done + fixture `ssh_config_test/alias` + test.**

## 🟡 Minor

- [x] **L88: missing config → raw bash error** — `done < "$file"` lets bash print `sshs.sh: line 69: /path: No such file or directory` before the "not found" message. Fix: test `[[ -f "$file" ]]` before reading and print a clean message. **Done: existence check in `sshs()` (clean message + return 1) + test.**

- [x] **L86: indented comment (`  # ...`) not tracked** — `[[ "${line:0:1}" == '#' ]]` only detects column 0; an indented comment is dropped AND resets `pline` (losing the previous comment). Fix: `^[[:space:]]*#`. **Done + fixture `ssh_config_test/indented_comment` + test.**

- [x] **L160: space → `.*` substitution also applies in regex mode** — `sshs -r 'foo bar'` becomes `foo.*bar`, so a literal space cannot be searched in `-r` mode. Fix: only do the space→`.*` substitution in safe mode, or document it clearly. **Done: substitution moved into safe-mode branch + test + README note.**

- [x] **Bash 4.3+ not documented** — `sshs_escape_regex`/`sshs_strindex` use namerefs (`local -n`, bash 4.3+) and `${var,,}` (4.0+). The README does not state the minimum version. Fix: add a line to the README. **Done: "Requirements" section added.**

- [x] **L131: relative `Include` path always resolved against `~/.ssh`** — `ssh` resolves against `/etc/ssh` for a system config. If `SSHS_CONFIG` points to a system config, relative includes are mis-resolved. Fix: resolve according to the config location (or document the limitation). **Done: limitation documented in README (option 1).**
