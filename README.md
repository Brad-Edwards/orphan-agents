# orphan-agents

Finds agent subprocess trees that outlived the agent that launched them.

When a coding agent dies without signalling its process group, the kernel
reparents its children to init and they keep running — holding CPU, memory and
a working directory, with no console, no supervisor and no timeout. They are
invisible until something else slows down. This reports them.

Detect only. It never kills anything.

## Rules

A process qualifies on `ppid == 1` plus an age floor plus one more signal,
because plenty of legitimate daemons are also reparented to init:

| Rule | Extra signal |
|---|---|
| `workload` | the command is a test/build workload an agent runs (`pytest`, `nox`, `unittest discover`, a sandbox helper) — those never legitimately outlive their launcher |
| `stranded` | the working directory has been deleted and the command is an agent CLI — a long-lived agent with `ppid 1` is often a deliberate detached session, so age alone would false-alarm |

Each process is reported once, keyed by pid plus kernel start time so a recycled
pid is never mistaken for one already seen.

## Install

```sh
install -Dm755 orphan-agent-check ~/.local/bin/orphan-agent-check
install -Dm644 orphan-agents.service ~/.config/systemd/user/orphan-agents.service
install -Dm644 orphan-agents.timer   ~/.config/systemd/user/orphan-agents.timer
systemctl --user daemon-reload
systemctl --user enable --now orphan-agents.timer
loginctl enable-linger "$USER"   # otherwise the timer stops when you log out
```

Runs every 10 minutes. Reports via `notify-send`, `tmux display-message` and
`logger`; each is optional and skipped when absent. On a headless host only the
journal receives it:

```sh
journalctl --user -t orphan-agents -n 50
```

The newest report is also at `~/.local/state/orphan-agents/latest.txt`.

## Configuration

| Variable | Default | Meaning |
|---|---|---|
| `ORPHAN_MIN_AGE_SECONDS` | `1800` | ignore anything younger, so a real run is not flagged mid-flight |
| `ORPHAN_QUIET` | unset | write the report but send no alerts |

## Uninstall

```sh
systemctl --user disable --now orphan-agents.timer
rm -f ~/.local/bin/orphan-agent-check ~/.config/systemd/user/orphan-agents.{service,timer}
```

## Tests

```sh
./test.sh
```

Spawns real orphaned processes and asserts each rule fires, that a healthy
detached agent is ignored, and that state dedupes and prunes.

## License

MIT
