# Task: Write the README usage section for a CLI tool

Write the **usage documentation** (README body) for a small command-line
tool called **snap** — a utility that takes named snapshots of a
directory and can restore them. Your audience is a developer who just
installed `snap` and wants to use it.

Below is the source of truth: the tool's argument parser and behavior.
Document what a user needs; do not document the internals.

## Source of truth

```
snap — snapshot and restore a directory

USAGE:
    snap <COMMAND> [OPTIONS]

COMMANDS:
    save <name>        Save a snapshot of the current directory under <name>.
    restore <name>     Restore the directory to the named snapshot.
    list               List all snapshots (name, timestamp, size).
    delete <name>      Delete the named snapshot.

GLOBAL OPTIONS:
    -C, --dir <path>   Operate on <path> instead of the current directory.
    -q, --quiet        Suppress non-error output.
    -h, --help         Print help.
    --version          Print version.

`save` OPTIONS:
    -m, --message <text>   Attach a note to the snapshot.
    --exclude <glob>       Exclude paths matching <glob>; repeatable.
    -f, --force            Overwrite an existing snapshot with the same name.

`restore` OPTIONS:
    --dry-run              Show what would change without writing anything.
    --force                Restore even if the working directory has
                           uncommitted changes to tracked files.

BEHAVIOR NOTES:
    - Snapshots are stored under `.snap/` in the target directory.
    - `save` refuses to overwrite an existing name unless `--force`.
    - `restore` refuses to run if there are local modifications, unless
      `--force`; `--dry-run` is always safe.
    - Snapshot names must match [A-Za-z0-9._-]+ (1..64 chars).
    - Exit codes: 0 success; 1 user error (bad args, name conflict);
      2 not-found (restore/delete of a missing snapshot); 3 I/O error.
```

## Requirements

Produce a single Markdown document, `README.md` (the usage section), that
covers:

- A one- or two-sentence description of what `snap` is for.
- A **Quickstart** showing the most common flow (save, list, restore) as
  runnable commands.
- A **Commands** reference: each of `save`, `restore`, `list`, `delete`
  with its purpose, arguments, and notable options.
- **Global options** and the **exit codes**.
- At least two realistic, correct usage **examples** beyond the
  quickstart (e.g. saving with a message and an exclude; a dry-run
  restore).

## Constraints

- Document only the behavior in the source of truth. Do not invent
  commands, options, or flags; do not omit documented ones.
- Commands in examples must be **valid** per the documented syntax and
  naming rules.

## Deliverable

A single `README.md`.
