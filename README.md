# CRON

A small cron for REXX that runs on **Windows and Linux** (macOS should work too).
Two implementations with the same crontab format and the same commands:

| Folder | Interpreter | Status |
|---|---|---|
| [`regina/`](regina) | [Regina REXX](https://regina-rexx.sourceforge.io/) | 50 tests pass on Linux; `add`/`list` confirmed on Windows |
| [`crexx/`](crexx) | [CREXX](https://github.com/adesutherland/CREXX) Level B (1.0.0 beta 1) | selftest passes on Linux; Windows untested |

## What it does

- Standard 5-field cron expressions: `*`, lists, ranges, steps (`*/5`, `5-30/10`),
  `JAN`..`DEC`, `SUN`..`SAT` (0 and 7 = Sunday), `@hourly @daily @weekly @monthly @yearly`.
  If day-of-month and day-of-week are both restricted, either one matching fires (like Vixie cron).
- Crontab file: `m h dom mon dow  command`, `#` comments, `NAME=value` environment lines.
  The scheduler re-reads the file every minute, so edits take effect without a restart.
- Manage jobs by command (`add`, `list`, `remove`) or by editing the file.
- `run` (the scheduler loop), `stop` and `status` work through small files next to the crontab,
  so they behave the same on Windows and Linux.
- Like real cron, a scheduler started mid-minute waits for the next full minute.
  Jobs missed while it was not running are not caught up.

## Commands

| Command | Meaning |
|---|---|
| `run crontab [VERBOSE] [SYNC] [DRYRUN] [ONCE]` | scheduler loop (runs until stopped) |
| `stop crontab` | ask a running scheduler to exit (takes up to 5 s) |
| `status crontab` | `running since ...` / `not running` |
| `add crontab "m h dom mon dow" command` | append a job (expression is validated first) |
| `list crontab` | numbered jobs with next fire time |
| `remove crontab n` | delete job number n (numbers as shown by `list`) |
| `next "m h dom mon dow" [stamp]` | next fire time after stamp (default now) |
| `match "m h dom mon dow" [stamp]` | 1 if the expression fires at stamp |
| `valid "m h dom mon dow"` | 1 / 0 |
| `tick crontab [stamp]` | run the jobs due at stamp (for testing, or from an OS scheduler) |

`stamp` is `YYYY-MM-DD HH:MM`. The crontab file name always comes first.
Examples: `add jobs.crontab 0 10 * * * backup.cmd` (daily at 10:00),
`add jobs.crontab 0 10 * * MON-FRI backup.cmd` (weekdays).

## Regina

```
regina CRON.rexx add  jobs.crontab 0 10 * * * echo hello
regina CRON.rexx list jobs.crontab
regina CRON.rexx run  jobs.crontab VERBOSE
```

Also usable as a function from other Regina programs: `CRON('NEXT', '0 10 * * *')`,
`CRON('ADD', file, expr, command)`, ... (see the header of `CRON.rexx`).
For that, the file must be named `CRON.rexx` and its folder must be on `PATH` (or in `REGINA_MACROS`),
because Regina on Linux matches the case of the called function name.

Tests: `regina test_cron.rexx` (with the folder on `PATH`).

## CREXX

Compile once, then run with `rxvme`; program arguments follow `-a`:

```
crexx cron.rexx -noexec
rxvme cron -a add  jobs.crontab 0 10 * * * echo hello
rxvme cron -a run  jobs.crontab VERBOSE
rxvme cron -a selftest
```

Notes for CREXX beta 1: `ADDRESS` does not use a shell, so each job is written to a small script
(`<crontab>.job.sh` / `.job.cmd`) that is run and then deleted; a file name must not contain spaces.
`lineout(file, x)` silently writes nothing when `x` is a bare variable, so the code always writes `x || ''`.

## Both versions

- Jobs run in the background by default (`SYNC` waits for each one). On Windows a job starts with
  `start /b cmd /c`, on Linux with `( command ) &`.
- Environment variable `CRON_OS=WIN` or `UNIX` overrides OS detection (useful for testing).
- Times are the local clock of the machine.
