#!/usr/bin/env python3
"""pretooluse-redact.py: the builder's PreToolUse hook on Bash (20261003). It rewrites every command (updatedInput)
so its stdout and stderr pass through redact-stream.py before the builder sees them:
    exec {fd}> >(python3 redact-stream.py)
    ( <close every descriptor above 2>; eval "$the_command"; save pwd ) >&$fd 2>&1
    <wait for the redactor, at most 5 s; say if it failed>; cd <the saved pwd>; (exit $rc)
- The command runs by eval in a subshell: its syntax errors are filtered too, a trailing backslash or a comment-only
  command still works, and no inherited descriptor (the harness's saved stdout and stderr) reaches past the
  redactor. Its exit code is kept; its working directory carried back (cd persists); variables don't (they never
  did between calls). A background job that redirects its output holds nothing of the redactor; one that doesn't
  writes into it, and the call waits for it (as the harness would for its output). After the command this shell's
  stdout is /dev/null: the redactor alone writes to the caller. `exec` in the command skips the cwd save.
- Editing redact-stream.py: write a copy and rename it over (a command's own redactor reading a half-written file
  crashed, and that command's output was lost, 20261003).
- Against accidents, not evasion: a process of the same user could still reach the redactor's own descriptors.
- FAILS CLOSED: if the redactor or python is missing, or anything here fails, the command is refused (deny, and the
  settings line adds `|| exit 2`, since a hook that crashes otherwise lets the command run unfiltered).
Settings (~/.claude/settings.json, hooks.PreToolUse, matcher Bash):
    python3 /work/agent/seed-lab/tools/claude-hooks/pretooluse-redact.py || exit 2"""
import json, os, shutil, sys

HERE = os.path.dirname(os.path.abspath(__file__))
REDACTOR = os.path.join(HERE, 'redact-stream.py')

def deny(why):
    print(json.dumps({'hookSpecificOutput': {'hookEventName': 'PreToolUse', 'permissionDecision': 'deny',
                                             'permissionDecisionReason': f'redaction hook: {why}; the command was refused (it fails closed)'}}))
    sys.exit(0)

def main():
    ev = json.load(sys.stdin)
    if ev.get('tool_name') != 'Bash': sys.exit(0)
    ti = dict(ev.get('tool_input') or {}); cmd = ti.get('command')
    if not isinstance(cmd, str) or not cmd.strip(): deny('no command')
    py = shutil.which('python3') or sys.executable
    if not (os.path.isfile(REDACTOR) and os.access(REDACTOR, os.R_OK)): deny(f'{REDACTOR} missing')
    if not (py and os.access(py, os.X_OK)): deny('python3 missing')
    q = lambda s: "'" + s.replace("'", "'\\''") + "'"
    # the command runs by eval in a subshell whose every descriptor above 2 is closed (the harness keeps the original
    # stdout and stderr on high descriptors: writing there would pass the redactor), its stdout and stderr into the
    # redactor; syntax errors are the subshell's stderr, so filtered too. The working directory comes back out.
    ti['command'] = (
        f'__seed_cmd={q(cmd)}; __seed_cwd=$(mktemp); exec {{__seed_fd}}> >({q(py)} {q(REDACTOR)}); __seed_pid=$!\n'
        f'if ! kill -0 $__seed_pid 2>/dev/null; then echo "redaction hook: the redactor did not start; the command was not run"; (exit 126)\n'
        # from here this shell's own stdout and stderr are the redactor too, and its other descriptors (the harness's
        # saved stdout and stderr) are closed: /proc/$$/fd/N reaches nothing unfiltered
        # the list is taken first and closed with no redirection active: a `2>/dev/null` on the loop made bash save
        # stderr on a high descriptor, which the loop then closed, so stderr stayed /dev/null (20261003)
        f'else exec >&$__seed_fd 2>&1; __seed_l=$(ls /proc/$$/fd); for __seed_n in $__seed_l; do case $__seed_n in 0|1|2|$__seed_fd) ;; *) eval "exec $__seed_n>&-" ;; esac; done\n'
        f'( exec {{__seed_fd}}>&-; trap \'pwd -P > "$__seed_cwd" 2>/dev/null\' EXIT; eval "$__seed_cmd" )\n'
        f'__seed_rc=$?; exec {{__seed_fd}}>&- >/dev/null 2>&1\n'
        f'for __seed_i in $(seq 1 50); do kill -0 $__seed_pid 2>/dev/null || break; sleep 0.1; done\n'
        f'[ -s "$__seed_cwd" ] && cd "$(cat "$__seed_cwd")"; rm -f "$__seed_cwd"; (exit $__seed_rc); fi')
    print(json.dumps({'hookSpecificOutput': {'hookEventName': 'PreToolUse', 'permissionDecision': 'allow',
                                             'permissionDecisionReason': 'output passes the redactor', 'updatedInput': ti}}))

if __name__ == '__main__':
    try: main()
    except SystemExit: raise
    except BaseException as e: deny(f'internal error {type(e).__name__}')
