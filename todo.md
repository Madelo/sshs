# Code Review — sshs

## Round 1 (all fixed)

### 🔴 Severe

- [x] **L73: circular `Include` → infinite recursion (hang)** — No depth limit or cycle detection in `sshs_read_config`. An `Include` that references itself (directly or indirectly) loops forever. `ssh` guards against this with `MAX_INCLUDE_DEPTH=16`. Demonstrated: `timeout 3` → exit 124. Fix: pass a depth counter and stop (e.g. 16). **Done: depth counter (16), verified — circular include now exits 0.**

- [x] **L77: indented `Host` silently ignored** — `^host[[:space:]]` requires column 0, but `ssh` accepts indentation (and sshs's own `Include` handling, L73, tolerates `^[[:space:]]*`). A `  Host foo` is silently dropped. Demonstrated. Fix: `^[[:space:]]*host[[:space:]]`. **Done + fixture `ssh_config_test/indented` + test.**

- [x] **L79-80: `Host alias1 alias2` → only the first alias kept** — `tblHost[i]="${fields[1]}"` reads only the first field after `Host`. `ssh alias2` works but `sshs alias2` reports "not found". Demonstrated. Fix: iterate all aliases (`fields[1..]`) and create one entry per alias (same comment). **Done + fixture `ssh_config_test/alias` + test.**

### 🟡 Minor

- [x] **L88: missing config → raw bash error** — `done < "$file"` lets bash print `sshs.sh: line 69: /path: No such file or directory` before the "not found" message. Fix: test `[[ -f "$file" ]]` before reading and print a clean message. **Done: existence check in `sshs()` (clean message + return 1) + test.**

- [x] **L86: indented comment (`  # ...`) not tracked** — `[[ "${line:0:1}" == '#' ]]` only detects column 0; an indented comment is dropped AND resets `pline` (losing the previous comment). Fix: `^[[:space:]]*#`. **Done + fixture `ssh_config_test/indented_comment` + test.**

- [x] **L160: space → `.*` substitution also applies in regex mode** — `sshs -r 'foo bar'` becomes `foo.*bar`, so a literal space cannot be searched in `-r` mode. Fix: only do the space→`.*` substitution in safe mode, or document it clearly. **Done: substitution moved into safe-mode branch + test + README note.**

- [x] **Bash 4.3+ not documented** — `sshs_escape_regex`/`sshs_strindex` use namerefs (`local -n`, bash 4.3+) and `${var,,}` (4.0+). The README does not state the minimum version. Fix: add a line to the README. **Done: "Requirements" section added.**

- [x] **L131: relative `Include` path always resolved against `~/.ssh`** — `ssh` resolves against `/etc/ssh` for a system config. If `SSHS_CONFIG` points to a system config, relative includes are mis-resolved. Fix: resolve according to the config location (or document the limitation). **Done: limitation documented in README (option 1).**

## Round 2

### 🔴 Severe

- [x] **L91-92: comment above an `Include` leaks onto the next `Host`** — `pline` survives the `Include` line (the `continue` skips the pline reset), so the first comment-less host after the include inherits the wrong description, and a search on that comment matches an unrelated host. Demonstrated: `# prod, database` above an `Include` made `sshs prod` match the unrelated `after_inc`. Fix: reset `pline` after processing an `Include`. **Done + regression test.**

- [x] **L82/L161: caller's IFS breaks a sourced run** — `read -ra fields` uses the current IFS and `"${search_args[*]}"` joins with the first IFS char; sourced from a shell with a custom `IFS` (e.g. `IFS=';'` in .bashrc), the multi-word search and the full listing silently broke (`k3s;master not found`, `''.*'' not found`). Decision: remove sourced usage entirely — `sshs.sh` is now a standalone script that refuses to be sourced (error + functions unset). An executed run is immune: bash never imports `IFS` from the environment. **Done: guard at the bottom of the script, tests now execute the script, README updated.**

- [x] **L167: invalid regex in `-r` mode silently matches nothing (exit 0)** — bash `=~` never errors on a bad pattern; `sshs -r '['` printed `not found` with exit 0 (while `ssh` reports `Invalid regular expression`). Fix: validate the pattern with `grep -Eq` (exit 2 = invalid) before parsing; error `sshs: invalid regex: '...'` + exit 1. **Done + tests (flag and SSHS_REGEX variable).**

### Open

- [x] **Exit codes inconsistent** — "not found" → exit 0, menu cancel → exit 1 (a `set -e` script died on cancel but not on "not found"). Decision: interactive-first usage, but a coherent grep-like scheme. **Done: 0 = found & handled (menu cancel = normal end), 1 = not found, 2 = usage error (missing config, invalid regex, sourced run); ssh's own exit code propagated. Documented in header + README "Exit codes" + tests.**
- [x] **🟡 Minor items (batch)**:
  - **Config exists but unreadable** (`-f` check only) → raw bash "Permission denied" then bogus "not found". **Done: `-r` check, clean message + exit 2, test.**
  - **Quoted `Include` paths with spaces** — tokens kept their quotes and the unquoted glob loop re-split paths on spaces; `"my dir/inc.conf"` silently ignored. **Done: quote-stripping tokenizer + compgen -G glob expansion (builtin, paths with spaces and quoted globs preserved); test.**
  - **Regex mode lowercased the pattern** — `[A-Z]` silently became `[a-z]`. **Done: regex mode is case-sensitive (pattern and hay kept as-is), safe mode still lowercases; tests + README.**
  - **`Host *` listed without sshs-off** → phantom entry connecting to `*`. **Done: catch-all `*` never listed; fixture + test.**
  - **Comma-separated and legacy `Host=` patterns** — `Host dev,prd` kept as one dead entry; `Host=foo` (accepted by ssh) unrecognized. **Done: split on commas (one entry per pattern), `Host=alias` normalized to `Host alias`; fixture + test + README "Host patterns".**
