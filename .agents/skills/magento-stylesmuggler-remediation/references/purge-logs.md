# StyleSmuggler - Purging poisoned logs (`~/var/log`) - HUMAN OPERATOR RUNBOOK

## STOP - this is a destructive runbook FOR A HUMAN OPERATOR. The agent does not run it.

**What this document is:** a runbook that **an agent hands to a human operator**, one
command at a time. It is not a task list for the agent, and the commands in it are not the
agent's to execute. Every step below is an **operator action** — each heading says so, on
purpose, so the shape of the document cannot be misread.

Nineteen steps, most of them shell commands, several of which **truncate, compress or
delete files**. Read this before executing a single one of them.

**The agent produces the commands; the human operator runs them.** The agent's job is to
hand over one command at a time, state what it does and what output to expect, and
**interpret the output the operator pastes back**.

**The rule is absolute: the agent does not execute. Full stop.** Not "confirm and then
run" — the human operator is the only party authorized to run commands against the platform
or against production. No level of low risk promotes the agent to executor.

- **This includes read-only commands.** `ls`, `grep`, `df`, `readlink`, `zgrep` — none of
  them write, but running them **opens a session to a production node**, and the log
  contents they print can carry customer data. The authorization is about **who touches
  production**, not about write risk. "It is read-only, so it is safe for me to run" is the
  reasoning that caused a real unauthorized production session.
- **Never invoke the platform CLI.** `magento-cloud` and its equivalents on other hosting
  platforms, any command that opens a database session against a hosted environment, and any
  SSH session to a node — none of these are the agent's to run. This is called out by name
  because the failure mode observed in the field was an agent *inferring* the CLI from a
  mention of "platform CLI" elsewhere in this skill and running it unprompted.
  This runbook says "execute over SSH on one node" — that instruction is addressed to the
  **operator**, not to the agent.
- **The agent never executes anything that writes**: `truncate`, `gzip`, `mv`, `rm`. Those
  are the operator's, with **explicit approval for each step**, not one blanket approval up
  front.
- **No destructive step happens without a *verified* backup.** In this runbook that is
  concrete: the forensic copy of steps 2 to 10 exists, is compressed, was checked, and is
  sealed in `MD5SUMS` **before** any `truncate` in step 12. If the check of step 6 or the
  listing of step 10 was not seen, step 12 does not happen.
- **Hard stop rule: no verification output seen means the step is not done.** If the
  operator has not pasted the output of the check, do not proceed to the next step and do
  not record the step as complete. "Not verified" is a valid and useful state; "done"
  without evidence is not.
- **Interpret, never fabricate.** Every "expected output" line below exists to be compared
  against what the operator actually pastes. Do not assume a command produced the expected
  output because it usually does.

Every step's "Expected output" is a verification gate, not a description.

Operational containment runbook, portable to any Magento / Adobe Commerce project
affected by StyleSmuggler (CVE-2026-75650 / APSB26-146).

It covers a different problem from the database hunt (`hunt-db.sql`): the payload that
ended up written **inside the log files**.

This is **step 3** of the flow in `SKILL.md`. Step 2 (close the write source) comes
first, and the reason is in section 5 below.

---

## 1. Why the logs have to be purged

- **PHP executes the code it finds in any file, even when surrounded by text that is not
  code.** The extension does not matter, and neither does the file being a log: if there
  is a `<?php ...` line somewhere in the middle, that file is, for practical purposes, an
  executable file. An `include` of `system.log` executes whatever sits between `<?php`
  and `?>` and prints the rest as plain text.
- The concrete origin is `magento/module-store-graph-ql`, in
  `Controller/HttpRequestValidator/StoreValidator.php:48`,
  which writes the invalid store code **literally** into the log. From there it fans out
  to as many files as the project's logger has destinations: Magento core writes to
  `exception.log`, and every additional logger the project has registered adds its own
  file. **How many and which ones is determined by discovery** (section 3), not from a
  list.
- **The APSB26-146 patch does not touch this.** The patch only protects `var/report/api`
  and `pub/errors`: it prefixes them with `<?php exit; ?>` and neutralizes `<?`.
  `var/log` is left as it was.
- This is the **WRITE primitive** of the chain. If the patch is in place, the `include`
  primitive is cut, but **the write is still active and growing**.

---

## 2. Platform preconditions (verify, do not assume)

The procedure in section 4 assumes certain properties of the infrastructure. **They are
not universal**: they hold on Adobe Commerce Cloud Pro, but Cloud Starter has a single
node and on-premise is another matter. Verify each one before executing.

| Precondition | Check command | What to do if it does NOT hold |
|---|---|---|
| `~/var/log` is the real log directory (not a symlink elsewhere) | `ls -ld ~/var/log; readlink -f ~/var/log` | Use whatever `readlink -f` returns in every command |
| `var/` is on storage **shared** between nodes | `df -hT ~/var/log` (look at the filesystem type: network/cluster vs local) | If it is local, **repeat the whole procedure node by node** |
| `var/` **survives redeploy** | `ls -la ~/var/log` after a known deploy | If it is wiped on every deploy, purging is unnecessary: waiting for the deploy is enough |
| The docroot does **not** include `var/` | `ls -d ~/pub 2>/dev/null; curl -sI https://<domain>/var/log/exception.log \| head -1` | If it returns 200, there is **direct web exposure** on top of the include: that is worse, escalate before continuing |
| **There is no root** (cannot configure `logrotate` or `systemd`) | `id; sudo -n true 2>&1` | With root, configuring rotation is the structural fix: do that instead of truncating by hand |
| How many nodes there are (the monitoring inflation factor) | Look up the environment topology in the platform console | See the units warning in section 3 |

If the storage is shared, **doing it on a single node covers all of them**. There is no
need to repeat the procedure node by node or to coordinate a parallel window. This is
what saves the most work, and it is the first thing to confirm.

---

## 3. Discovery: which files have to be treated

**Do not use a fixed file list.** And do not stop at `*.log`: **rotated files are missed by
that glob**, and truncating the live file does **not** touch them. `exception.log.1`,
`exception.log-20260909` and `exception.log.2.gz` keep their payloads.

First inventory the real rotation scheme, which varies per platform:

```sh
ls -la ~/var/log/
```

Then count in the live logs and the uncompressed rotated ones. `-a` keeps grep from
bailing out on a file it decides is binary:

```sh
grep -a -c '<?php' ~/var/log/*.log ~/var/log/*.log.* 2>/dev/null
```

And in the ones already compressed:

```sh
zgrep -c '<?php' ~/var/log/*.gz 2>/dev/null
```

Expected output: **one line per file**, with the name and the count. Files with a count
**greater than 0** are the targets. Files that return **0 are not touched**: truncating
them destroys useful logs without removing a single poisoned line.

**Classify the result into three categories, because the treatment differs:**

| Category | Treatment | Why |
|---|---|---|
| **Live log** (`exception.log`) | `truncate -s 0` — steps 11 and 12 | Preserves the inode and Monolog's open descriptor |
| **Rotated, NOT compressed** (`exception.log.1`, `exception.log-YYYYMMDD`) | **`gzip` the file** — step 18 | It is a live payload. Compressing preserves the evidence and removes the literal `<?php` bytes in one move. No process holds it open, so there is nothing to truncate, and compressing beats deleting |
| **Rotated, ALREADY compressed** (`exception.log.2.gz`) | Inventory it and get it off the node — step 19 | See the caveat in step 4: compression is strong mitigation, not proof of immunity |

### WARNING: `<?php` is not a complete census of payloads

> Grepping for `<?php` finds only payloads that carry that literal string. Payloads
> wrapped in base64 — a documented variant of this campaign — do not contain it, so a
> clean `<?php` result across the whole archive history does **not** prove the archives
> are clean. It proves only that no *literal-tag* payload is there.

This matters because everything above is built on a `<?php` count, and a clean count reads
as "done". It is not the same claim.

Complementary sweep to run before declaring the archives clean:

```sh
zgrep -l -E 'shell_exec|X_TRACE|eval\(' ~/var/log/*.gz 2>/dev/null
```

If the specific incident had an identified base64 blob, sweep for **its prefix** as well:
the prefix stays stable across encoded variants of the same dropper, so it matches the
variants a keyword list misses.

**Why the glob is more correct than a fixed list, and how we know:** in a real case the
runbook listed 4 files as targets. Running the glob on the node, 2 of those 4 were at 0 —
the logger fan-out did not carry store-code payloads to them. The list was an
**assumption**; the glob is a **fact**. On top of that, the names of the additional
loggers are project-specific: a list written for one project does not transfer to
another, and the glob does.

Write down the full output before continuing: it is the baseline the post-truncate check
is compared against, and the record of which files were touched.

### WATCH THE UNITS: the monitoring count comes inflated

**If the platform has N nodes reading the same file over shared storage, the counts
reported by the observability platform are multiplied by N.** Each node reports the same
file, so every line that exists **only once on disk** is counted N times. In a real case
with 3 nodes, 144 lines on disk showed up as ~468 in the observability platform:
144 x 3 = 432, the same order of magnitude.

**Confirm the multiplier for your own topology instead of assuming it.** In one real case
the on-disk count for a single day was 60 lines while the observability platform reported
180 for that same day — exactly 3x, with three nodes on shared storage. Use that kind of
cross-check before trusting either number: pick one rotated archive covering one full day,
count on disk, and compare against what the platform reports for that day.

Portable rule:

- **The on-disk count is AUTHORITATIVE for remediation.** It is the one that says how
  many lines there are and which files they are in.
- **The monitoring count is good for the TREND.** It is not distorted, because the
  inflation factor is constant: if it rises day over day, the write is still active.
- **Never compare a monitoring number against an on-disk number.** They are in different
  units and the difference reads as a finding that does not exist.

---

## 4. Procedure

**Addressed to the human operator.** Execute over SSH on **one** node. If the
shared-storage precondition was verified, one node covers all of them; if not, repeat
everything on each node. The agent's part here is to hand over one command at a time and
read the output back.

**Environment restriction: the operator CANNOT upload or execute `.sh` scripts on the
node.** That is why the procedure is written as **standalone commands**: each one is
self-contained, uses **literal absolute paths**, and **does not depend on shell variables
or on the state of any previous command**. There is no `$TS`, no `$DEST`, no `for` loops.
They are copied and pasted **one at a time**, in order, checking the output before moving
to the next. If the SSH session drops, resume at the command you were on.

**Two substitutions to make by hand before starting:**

1. **`YYYYMMDD` -> the date of the day it is executed**, written literally (for example
   `20260910`) in **every** command. The forensic directory stays fixed for the whole run.
2. **`exception.log`** is the example file because it is Magento core's and always shows
   up. **For each additional file the discovery in section 3 returned with a count greater
   than 0, repeat steps 2, 4, 6, 8, 11, 12, 14 and 15 substituting `exception.log` with
   that file's name, written literally.** Never with a variable and never with a glob: a
   glob in a destructive command is how the wrong file gets truncated.

The forensic directory is `~/var/forensics/stylesmuggler-YYYYMMDD`. It sits under
`~/var/`, that is **outside the docroot**: it is not exposed over the web.

### Step 1 (operator action) - Create the forensic directory

```sh
mkdir -p ~/var/forensics/stylesmuggler-YYYYMMDD
```

Expected output: **none**. `mkdir -p` says nothing if the directory already existed.

### Step 2 (operator action) - Copy the log

```sh
cp -p ~/var/log/exception.log ~/var/forensics/stylesmuggler-YYYYMMDD/
```

Expected output: **none**. `-p` preserves mtime and permissions, which is what makes the
copy usable as evidence.

### Step 3 (operator action) - (repeat step 2 for each additional file from discovery)

One `cp -p` per file, with the name written literally.

### Step 4 (operator action) - Compress the copy

```sh
gzip ~/var/forensics/stylesmuggler-YYYYMMDD/exception.log
```

Expected output: **none**. It leaves `exception.log.gz` and **deletes** the uncompressed
`.log`, which is exactly what we want.

**Why compress, and why this step is not optional:** the copy from step 2 is a second
file with `<?php` in literal bytes inside `var/`. That is, we duplicated the problem
instead of containing it. Compressing removes the **literal-bytes path**: the `<?php`
sequence stops existing as literal bytes and lives inside the deflate stream. That is
exactly the path the observed gadget used — an `include` of a plain path, which only
executes if it finds a literal `<?php` — so compressing cuts the known route and raises
the bar substantially. The content is still recoverable with `zcat` / `zgrep` for analysis.

**Caveat: compression is strong mitigation, not proof of immunity.** If an attacker can
prefix a PHP stream wrapper — something of the form `compress.zlib://path/to/file.gz` —
the `include` decompresses on the fly and the payload is executable again. The documented
gadget passes a plain path, not a wrapper, so the known route is closed; but immunity
cannot be claimed. The practical consequence: **for archive files the definitive answer is
getting them off the node**, not leaving them compressed in place. See the recommended
follow-up at the end of this section.

### Step 5 (operator action) - (repeat step 4 for each additional file)

### Step 6 (operator action) - Check that the `.gz` came out neutralized

```sh
grep -a -c '<?php' ~/var/forensics/stylesmuggler-YYYYMMDD/exception.log.gz
```

Expected output: **`0`**. If it returns anything else, the `.gz` still contains the
sequence in literal bytes: **do not continue**, investigate before truncating anything.

### Step 7 (operator action) - (repeat step 6 for each additional file)

### Step 8 (operator action) - Seal the copies with md5

```sh
md5sum ~/var/forensics/stylesmuggler-YYYYMMDD/*.gz > ~/var/forensics/stylesmuggler-YYYYMMDD/MD5SUMS
```

Expected output: **none** (the output goes into the `MD5SUMS` file). This is the only
command in the runbook with a glob, and it is safe: it is a **read**, and the `.gz` is
already neutralized.

### Step 9 (operator action) - Read the generated md5 values

```sh
cat ~/var/forensics/stylesmuggler-YYYYMMDD/MD5SUMS
```

Expected output: **one line per `.gz`**, a hash and a path each. `MD5SUMS` is what lets
you prove later that the `.gz` downloaded off the node is the same one generated here.
Without it, the copy is not usable as evidence.

### Step 10 (operator action) - List the forensic directory

```sh
ls -l ~/var/forensics/stylesmuggler-YYYYMMDD/
```

Expected output: **one `.gz` per treated file, plus `MD5SUMS`**. If any uncompressed
`.log` shows up, step 4 or 5 is missing for that file: **do not continue**.

### Step 11 (operator action) - Record the log size BEFORE truncating

```sh
ls -l ~/var/log/exception.log
```

Expected output: **one line** with the current size, different from 0. **Write the number
down**: it is the reference step 15 is compared against.

### Step 12 (operator action) - Truncate the log IN PLACE. Never `rm`.

```sh
truncate -s 0 ~/var/log/exception.log
```

Expected output: **none**.

**Why truncate and not delete:** Monolog and PHP-FPM keep the **file descriptor open**
for the whole lifetime of the worker. With `rm` the name disappears from the directory
but the inode stays alive as long as a descriptor points at it: the workers **keep writing
to a deleted inode**, nobody ever sees that content, and **logs are lost silently** until
the pool recycles its workers. `truncate -s 0` preserves the inode, the open descriptor
stays valid, the offset is adjusted and the next write lands in the correct, visible file.

Do not use `rm`, or `mv`, or a shell redirection over the file. We use `truncate -s 0`
rather than an empty redirection because it is **unambiguous**: it literally says "set the
size to 0" and **cannot be mistyped into a destructive redirection** over the wrong file.

**About the `.gz` left in `var/`:** it does not block anything here. Step 6 confirmed the
literal `<?php` bytes are gone, so it is not one more poisoned file in the sense the
gadget needs. But per the step 4 caveat that is mitigation, not immunity, so getting it
off the node is a **recommended follow-up**, not merely optional. It is not a blocker for
truncating: do not wait for it here.

### Step 13 (operator action) - (repeat steps 11 and 12 for each additional file)

### Step 14 (operator action) - Verify the `<?php` count is at 0

```sh
grep -a -c '<?php' ~/var/log/*.log ~/var/log/*.log.* 2>/dev/null
```

Expected output: **`0` in the treated files**, live and rotated-uncompressed alike. If a
live log comes back non-zero, those are lines written **after** the truncate, which means
the source is still active (see section 5). If a rotated file comes back non-zero, it was
not treated: go to step 18.

### Step 15 (operator action) - Verify the size after truncating

```sh
ls -l ~/var/log/exception.log
```

Expected output: **size 0**, or a few bytes (whatever was written between the truncate and
this check). Compare against the number recorded in step 11.

### Step 16 (operator action) - Check `~/var/report/`

```sh
ls -la ~/var/report/ 2>/dev/null | tail -5
```

Expected output: the **last 5 entries** of the directory, to see whether there are recent
reports. If the directory does not exist, it returns nothing and that is fine.

### Step 17 (operator action) - Look for `<?php` inside `~/var/report/`

```sh
grep -rl '<?php' ~/var/report/ 2>/dev/null | head
```

Expected output: **no lines**. `var/report/api` is already protected by the APSB26-146
patch. The rest of `var/report/` is not, so if this returns paths, treat them with the
same criteria as steps 2 to 12: copy, `gzip`, verify, truncate with `truncate -s 0`.

### Step 18 (operator action) - Compress the rotated, uncompressed logs

For every file the discovery in section 3 classified as **rotated, not compressed** and
with a count greater than 0. One command per file, with the name written literally:

```sh
gzip ~/var/log/exception.log.1
```

Expected output: **none**. It leaves `exception.log.1.gz` and removes the uncompressed
file.

**Why `gzip` and not `truncate -s 0` here:** no process holds a rotated file open, so
there is no descriptor to preserve — the reason for truncating the live log does not apply.
And unlike the live log, the rotated file is pure history: compressing keeps the evidence
while removing the literal `<?php` bytes, in a single move. Deleting it would remove the
payload and the evidence together.

Then re-check that file:

```sh
grep -a -c '<?php' ~/var/log/exception.log.1.gz
```

Expected output: **`0`**. Same check as step 6, same reading: if it is not 0, the literal
bytes are still there — investigate before moving on.

### Step 19 (operator action) - Inventory the compressed archives and resolve their destination

```sh
zgrep -c '<?php' ~/var/log/*.gz 2>/dev/null
```

Expected output: **one line per `.gz`** with its count. These carry the payload inside the
deflate stream. Per the step 4 caveat, that is mitigation and not immunity, so each of
these files needs a **resolved destination**: either transferred off the node (the
recommended follow-up below), or **explicitly accepted as residual risk** and written down
as such. Leaving them unlisted is the one option that is not acceptable — an
uninventoried archive is an unowned one.

### Accepting the archives as residual risk - a legitimate exit, if it is auditable

Getting the archives off the node is the definitive answer, but it is **not the only
defensible one**. With compression having closed the known route and the root-cause patch
in place, accepting the residual is a reasonable decision. What separates a decision from
an oversight is that the decision is **auditable**.

To accept it, record all four of these:

1. **The exact list of files, with the payload line count for each** — the output of step
   19, written down, not recalled.
2. **That compression is mitigation, not immunity** — the step 4 caveat, referenced
   explicitly so the next reader does not have to rediscover it.
3. **Whether the extended IOC sweep of section 3 was run or not.** If it was not, say so:
   the census is then **declaredly incomplete**, and "clean" means "no literal-tag payload
   found", nothing more.
4. **The condition that reopens the decision:** any **new file read or file inclusion
   primitive** (another LFI, another gadget) promotes these files from residual to urgent,
   and they come off the node before anything else. The acceptance is conditional on the
   threat model that justified it, and it expires with it.

**The residual GROWS while the source is open.** Every rotation cycle produces **one more
poisoned compressed archive**, so an accepted residual of N files becomes N+1 next cycle,
and keeps going. This is the strongest argument for closing the write source (step 2)
before purging: closing it is not only about not having to re-truncate the live log, it is
**what stops the accepted residual from multiplying**. Accepting residual risk over a set
that grows on its own is not a decision, it is a deferral.

### Recommended follow-up (operator action) - get the archives off the node

This does not block the truncate and it is not a prerequisite for calling the live-log
containment done. But when the acceptance above is not registered, this is the path:
per the step 4 caveat, compression closes the known route and does not prove immunity, and
**for archive files getting them off the node is the definitive answer**. A `.gz` sitting
in `var/` is a mitigated file, not a solved one.

Transfer the `~/var/forensics/stylesmuggler-YYYYMMDD` directory (the `.gz` files and
`MD5SUMS`) plus the rotated archives from step 18 and step 19 from the node to storage
outside the platform, using the team's usual transfer mechanism (`scp` / `rsync` over the
environment's SSH connection). Then verify the md5 at the destination against `MD5SUMS`.

Only once the copy is **verified off the node**, and if space in `var/` needs to be
reclaimed:

```sh
rm -rf ~/var/forensics/stylesmuggler-YYYYMMDD
```

Order matters: download and verify first, delete afterwards. If it is deleted first, the
evidence for the incident is gone and there is no way to reconstruct it.

---

## 5. WARNING: this is containment, not a fix

**Purging the logs fixes nothing.** It is containment. The source that writes the payload
is still unsanitized, so the file **fills up again** at the same rate it had before. If
this runbook is executed and nothing else is done, within a few days the state is the same
as before starting.

That is why the purge goes **after** closing the write source, not before. In the right
order it is a one-off task; in the reverse order it is a recurring one.

And it is not only the live log that keeps coming back: with the source open, **every
rotation cycle mints a new poisoned compressed archive**. Whatever was accepted as residual
risk grows by one file per cycle. Closing the source is what caps that set.

It has to be chained with **at least one** of these two, both specified in full in
**step 2 of `SKILL.md`**:

1. **Sanitizing the store-code logging** at the origin
   (`magento/module-store-graph-ql`, `Controller/HttpRequestValidator/StoreValidator.php`):
   stop writing the received value literally into the log. This is the durable fix, and it
   drags the fan-out to every log file at once. `SKILL.md` step 2b has the concrete
   `sanitizeForLog()` code and the two implementation paths (patch to `vendor/` vs. an
   `around` plugin in a project-owned module).
2. **A CDN/WAF rule** on the `Store` header. It is the **fastest** stopgap, needs no code
   change or deploy, and cuts the write at the edge. `SKILL.md` step 2a has the VCL
   snippet.

**The rule must be an allowlist of what a store code legally is, not a denylist of
`<?php`.** A denylist is evaded with `<?`, `<?=`, whitespace or encodings. The allowlist
matches the legal charset instead, and rejects everything else. Do not write a rule that
just looks for `<?php`.

Also note the CDN rule **does not cover the body vector**: the payload also travels in the
`paypal_payload` field of the `handlePayflowProResponse` mutation, which goes in the body
of the GraphQL POST, and CDNs do not practically inspect bodies. The rule closes the header
vector, not the body one.

While the source stays open: **re-run the step 14 command every day** and record the count:

```sh
grep -a -c '<?php' ~/var/log/*.log ~/var/log/*.log.* 2>/dev/null
```

It is the indicator of whether the write is still active and at what rate. When it returns
0 for several days in a row **without having truncated**, the source is effectively closed.
