#!/usr/bin/env bash
# tender-test-checkout.sh: the Tender test's checkout (site/runbooks/agent-model-tests.md 5.2), from the builder's
# account. No evidence, no findings, squashed history: no earlier conclusion can anchor the agent.
#   make-repo <agent>    one squashed commit of forge main, without the paths below, pushed as main and
#                        agents/<agent> to a NEW private forge repository seed/seed-lab-test-<date>-<agent> (never
#                        reused: it refuses if it exists); tender gets write on it
#   revoke | grant       tender's access to seed/seed-lab: removed for the test window, given back after (write)
#   swap <agent> [path]  as tender: the agent's checkout moved to <path>.real and the test repository cloned in its
#                        place (default /work/tender/<agent>/seed-lab: the same path, so prompts, settings and trust
#                        hold); prints the root commands that close the rest (the orchestrator runs them)
#   prove <agent> [path] what the working tree can and cannot reach, as tender (during the window); exits 1 on any
#                        violation
#   next-block <agent> <NN-block>  (the agent exited) the previous block's branch kept in seed/seed-lab as
#                        tender-test/<agent>-<NN>, the test branch reset to the squashed main, the agent's site-review
#                        log moved into the closed archive: no block reads an earlier block's conclusions
#   restore <agent>      the test branch kept in seed/seed-lab as tender-test/<agent>-<date>, the real checkout
#                        back, the test clone moved to ~/archive (never deleted); run `grant` first
# The agent must be exited (and its timer stopped) for swap and restore.
set -euo pipefail
cd "$(dirname "$0")/.."
DAY=${TENDER_TEST_DAY:-$(date -u +%Y%m%d)}; F=https://git.seed.example.com
repo() { echo "seed-lab-test-$DAY-$1"; }
LEAVE=(evidence findings.md diary briefs site/runbooks/agent-model-tests.md tools/tender-test-checkout.sh tools/tender-test-runner.sh tools/tender-test-runner.py
       tools/tender-test-archive.py tools/tender-test-archive-task.py tools/tender-test-grade.py nixos/modules/tender-test-cut.nix)   # the cut helper: the dependency blocks' design (20261004)
T() { ssh -o BatchMode=yes -o LogLevel=ERROR tender@localhost "$@"; }
. /tmp/forge.sh
case ${1:-} in
make-repo)
  a=${2:?agent}; TEST=$(repo $a)
  git fetch -q forge; base=$(git rev-parse forge/main); d=$(mktemp -d); trap 'rm -rf "$d"' EXIT
  git archive "$base" | tar -x -C "$d"
  for p in "${LEAVE[@]}"; do rm -rf "${d:?}/$p"; done
  for p in "${LEAVE[@]}"; do [ ! -e "$d/$p" ] || { echo "still there: $p" >&2; exit 1; }; done
  git -C "$d" init -q -b main; git -C "$d" add -A .; git -C "$d" -c user.name="seed builder" -c user.email=builder@seed.example.com \
    commit -q -m "The site's repository for the Tender test: main at ${base:0:7}, squashed (its history, evidence, findings, diary and briefs left out)"
  ! forge GET /repos/seed/$TEST | jq -e .id >/dev/null 2>&1 || { echo "seed/$TEST exists: a test repository is never reused (set TENDER_TEST_DAY)" >&2; exit 1; }
  forge POST /orgs/seed/repos "$(jq -nc --arg n $TEST '{name: $n, private: true, description: "The Tender test: a squashed copy of seed-lab (no history, no evidence)", default_branch: "main"}')" | jq -r '"made \(.full_name) private=\(.private)"'
  git -C "$d" push -q "$(git remote get-url forge | sed "s|seed/seed-lab\(\.git\)\{0,1\}$|seed/$TEST.git|")" main main:agents/$a
  forge PUT /repos/seed/$TEST/collaborators/tender '{"permission":"write"}' >/dev/null
  echo "$TEST: $(git -C "$d" rev-parse --short HEAD) (main at ${base:0:7}); tender: $(forge GET /repos/seed/$TEST/collaborators/tender/permission | jq -r .permission)"
  ;;
revoke)
  forge DELETE /repos/seed/seed-lab/collaborators/tender >/dev/null
  echo "seed/seed-lab, tender: $(forge GET /repos/seed/seed-lab/collaborators/tender/permission | jq -r '.permission // "none"')" ;;
grant)
  forge PUT /repos/seed/seed-lab/collaborators/tender '{"permission":"write"}' >/dev/null
  echo "seed/seed-lab, tender: $(forge GET /repos/seed/seed-lab/collaborators/tender/permission | jq -r .permission)" ;;
swap)
  a=${2:?agent}; p=${3:-/work/tender/$a/seed-lab}
  T "set -e; export PATH=\$HOME/.local/bin:\$PATH; ! herdr agent list | jq -e '.result.agents[] | select(.name == \"$a\")' >/dev/null || { echo '$a is running: exit it first'; exit 1; }
     [ ! -e $p.real ] || { echo '$p.real exists'; exit 1; }
     n=\$(git -C $p config user.name); e=\$(git -C $p config user.email); mv $p $p.real
     git clone -q --branch agents/$a $F/seed/$(repo $a).git $p; git -C $p config user.name \"\$n\"; git -C $p config user.email \"\$e\"
     # Hermes loads AGENTS.override.md from its working directory: the deployed rulebook's link, as tender-config sets it
     # in the real checkout (Codex, 20261006: a fresh clone had none, so a Hermes test session loaded no rulebook)
     if [ $a = hermes ]; then ln -sfn /etc/site-agents/RULEBOOK.md $p/AGENTS.override.md; grep -qx AGENTS.override.md $p/.git/info/exclude || echo AGENTS.override.md >> $p/.git/info/exclude; fi
     echo \"$p: \$(git -C $p log --oneline | wc -l) commit(s), branch \$(git -C $p branch --show-current); the real one at $p.real\"
     # the pane's shell followed the renamed directory: put it in the new checkout, or the agent starts in .real (20261003)
     pane=\$(herdr agent list >/dev/null 2>&1; herdr pane list 2>/dev/null | jq -r '.result.panes[]? | select(.cwd? // \"\" | startswith(\"$p\")) | .pane_id' | head -1)
     [ -n \"\$pane\" ] && herdr pane send-text \"\$pane\" 'cd $p' >/dev/null && herdr pane send-keys \"\$pane\" enter >/dev/null && echo \"pane \$pane: cd $p\" || echo 'NOTE: put the pane shell in $p by hand (herdr pane send-text <pane> \"cd $p\")'"
  o=$([ "$a" = claude ] && echo hermes || echo claude)
  cat <<EOF
For the orchestrator (root on the agent box), to close the rest for the window (all given back after the test):
  chown -R root:root $p.real /work/tender/$o/seed-lab /home/tender/archive && chmod 700 $p.real /work/tender/$o/seed-lab /home/tender/archive
  chown root:root /home/tender/.local/state/site-review/*.log && chmod 600 /home/tender/.local/state/site-review/*.log
$( [ "$a" = claude ] && echo "  sudo -u tender XDG_RUNTIME_DIR=/run/user/\$(id -u tender) systemctl --user stop tender-hermes; chown -R root:root /home/tender/.hermes && chmod 700 /home/tender/.hermes   # Hermes is paused by decision" || echo "  chown -R root:root /home/tender/.claude/projects && chmod 700 /home/tender/.claude/projects" )
  # the clean-slate archive (runbook 5.3): mkdir -p /home/tender/archive/clean-slate/tender-test-$DAY-$a, opened
  # (chown tender) for each save or restore and closed (chown root, 0700) again after it
EOF
  ;;
prove)
  a=${2:?agent}; p=${3:-/work/tender/$a/seed-lab}
  T "cd $p; bad=0; v() { echo \"VIOLATION: \$*\"; bad=1; }
     n=\$(git log --all --oneline | wc -l); echo \"commits reachable: \$n\"; [ \$n -le 50 ] && [ \$(git rev-list --max-parents=0 --all | wc -l) = 1 ] || v 'more than the squashed history'
     echo \"remote: \$(git remote get-url origin)\"; git remote get-url origin | grep -q '/seed/$(repo $a).git' || v 'the remote is not the test repository'
     [ -z \"\$(git remote | grep -vx origin)\" ] || v 'another remote'
     for x in evidence findings.md diary briefs site/runbooks/agent-model-tests.md tools/tender-test-checkout.sh; do [ -e \$x ] && v \"present: \$x\" || echo \"absent: \$x\"; done
     k=\$(grep -rlE 'f[0-9]+-(alert|container|dns|router|unit|dataset|probe|reboot)|lying probe|probe endpoint mismatch|silent faults?|faults? f[0-9]|\\(f[0-9]+\\)|test.s f[0-9]|tender-test-cut' . --exclude-dir=.git | wc -l); echo \"files naming the faults: \$k\"; [ \$k = 0 ] || v 'files name the faults'
     printf 'the real repository by git: '; git ls-remote $F/seed/seed-lab.git >/dev/null 2>&1 && v REACHABLE || echo refused
     printf 'the real repository by the forge API: '; c=\$(printf 'header = \"Authorization: token %s\"\n' \"\$(cat /run/secrets/tender_forge_token)\" | curl -s -K - -o /dev/null -w '%{http_code}' $F/api/v1/repos/seed/seed-lab); echo \$c; [ \$c = 404 ] || v 'the forge API answers'
     printf 'its own branch pushes to: '; git push --dry-run origin HEAD:agents/$a >/dev/null 2>&1 && echo 'the test repository (dry run ok)' || v 'cannot push its branch'
     o=\$([ $a = claude ] && echo hermes || echo claude)
     for d in /work/agent $p.real /work/tender/\$o/seed-lab \$HOME/archive \$HOME/.hermes; do [ $a = hermes ] && [ \$d = \$HOME/.hermes ] && continue; [ -e \$d ] || [ \$d = $p.real ] || continue; printf '%s: ' \$d; ls \$d >/dev/null 2>&1 && v \"readable: \$d\" || echo closed; done
     for f in \$HOME/.local/state/site-review/*.log \$HOME/.local/state/site-review/*.closed-*; do [ -e \"\$f\" ] || continue; [ \"\$f\" = \$HOME/.local/state/site-review/$a.log ] && { echo \"\$f: its own, this block's (fresh)\"; continue; }; cat \"\$f\" >/dev/null 2>&1 && v \"readable: \$f\" || echo \"\$f: closed\"; done
     [ \$bad = 0 ] && echo 'PROVEN: no violation' || { echo 'NOT PROVEN'; exit 1; }" ;;
next-block)
  a=${2:?agent}; b=${3:?NN-block}; p=/work/tender/$a/seed-lab; TEST=$(repo $a)
  T "set -e; export PATH=\$HOME/.local/bin:\$PATH; ! herdr agent list | jq -e '.result.agents[] | select(.name == \"$a\")' >/dev/null || { echo '$a is running: exit it first'; exit 1; }"
  d=$(mktemp -d); git clone -q --bare "$(git remote get-url forge | sed "s|seed/seed-lab\(\.git\)\{0,1\}$|seed/$TEST.git|")" "$d/t.git"
  git -C "$d/t.git" push -q "$(git remote get-url forge)" "agents/$a:refs/heads/tender-test/$a-$b" && echo "the previous block's branch kept: tender-test/$a-$b in seed/seed-lab"
  git -C "$d/t.git" push -q --force origin main:agents/$a && echo "$TEST agents/$a reset to the squashed main"; rm -rf "$d"
  T "set -e; cd $p; git fetch -q origin; git checkout -q -B agents/$a origin/agents/$a; echo \"$p: \$(git log --oneline | wc -l) commit(s)\""
  echo "root: move /home/tender/.local/state/site-review/$a.log into the closed clean-slate archive (runbook 5.3)" ;;
restore)
  a=${2:?agent}; p=${3:-/work/tender/$a/seed-lab}; day=$(date -u +%Y%m%dT%H%MZ)   # with the time: two tests in one day (20261006)
  T "set -e; export PATH=\$HOME/.local/bin:\$PATH; ! herdr agent list | jq -e '.result.agents[] | select(.name == \"$a\")' >/dev/null || { echo '$a is running: exit it first'; exit 1; }
     export PATH=\$HOME/.local/bin:\$PATH
     [ -d $p.real ] && [ -r $p.real ] || { echo '$p.real missing or still closed (root: give it back first)'; exit 1; }
     git -C $p push -q $F/seed/seed-lab.git agents/$a:refs/heads/tender-test/$a-$day-last
     # the test clone beside it (~/archive stays closed until the test's end), the real one back in place
     mv $p $p.test-$day; mv $p.real $p
     # the pane's shell followed the rename (into .test-*): put it back in the real checkout
     pane=\$(herdr pane list 2>/dev/null | jq -r '.result.panes[]? | select(.cwd? // \"\" | startswith(\"$p\")) | .pane_id' | head -1)
     [ -n \"\$pane\" ] && herdr pane send-text \"\$pane\" 'cd $p' >/dev/null && herdr pane send-keys \"\$pane\" enter >/dev/null && echo \"pane \$pane: cd $p\" || echo 'NOTE: put the pane shell in $p by hand'
     echo \"$p: the real checkout back (\$(git -C $p log --oneline | wc -l) commits); the test clone at $p.test-$day; the test branch kept as tender-test/$a-$day-last\"" ;;
*) sed -n '2,15p' "$0"; exit 64 ;;
esac
