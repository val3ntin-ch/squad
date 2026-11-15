#!/usr/bin/env bash
# Demo board: builds a small team with the data of the approved mockup
# (docs/design/squad-deck-team.html: Iris on T-117, 2 of 11 rows, Vera's candidate 23)
# and runs `squad board --preview` on it, so the board can be compared with the
# mockup one to one. Nothing outside a temporary directory is written.
# Usage: test/demo-board.sh [--once]
set -euo pipefail
unset SQUAD_HEAVY_DIR   # the demo keeps its own lock and queue
squad=$(cd "$(dirname "$0")/.." && pwd)/bin/squad
d=$(cd -P "$(mktemp -d)" && pwd); trap 'rm -rf "$d"' EXIT
mkdir -p "$d/bin" "$d/cache/squad/heavy/queue" "$d/cache/squad/teams" "$d/tonus/.team"

agents='{"result":{"agents":[
 {"name":"lead","agent_status":"working","pane_id":"w1:p1","agent":"claude","terminal_title_stripped":"✳ reviewing T-129"},
 {"name":"dev-a","agent_status":"working","pane_id":"w1:p2","agent":"claude","terminal_title_stripped":"✳ Timeline state prop"},
 {"name":"dev-b","agent_status":"working","pane_id":"w1:p3","agent":"claude","terminal_title_stripped":"✳ Sheet, Dialog"},
 {"name":"dev-c","agent_status":"working","pane_id":"w1:p4","agent":"claude","terminal_title_stripped":"✳ writing play test for Toast dismiss"},
 {"name":"tester","agent_status":"working","pane_id":"w1:p5","agent":"claude","terminal_title_stripped":"✳ candidate 23"},
 {"name":"rev-gpt","agent_status":"idle","pane_id":"w1:p6","agent":"codex"},
 {"name":"observer","agent_status":"idle","pane_id":"w1:p7","agent":"claude"}]}}'
printf '%s\n' "$agents" | tr -d '\n' >"$d/agents.json"
cat >"$d/bin/herdr" <<EOF
#!/usr/bin/env bash
case "\$1 \$2" in "agent list") cat "$d/agents.json" ;; *) echo '{"result":{}}' ;; esac
EOF
chmod +x "$d/bin/herdr"

mtime_ago() { perl -e '$t = time - $ARGV[0] * 60; utime $t, $t, $ARGV[1]' "$1" "$2"; }   # <minutes> <file>: GNU and BSD alike
r="$d/hive"; mkdir -p "$r/.team/tasks" "$r/.team/reports" "$r/.team/observer/.act"
git -C "$r" init -q -b main; git -C "$r" -c user.email=d@d -c user.name=d commit -q --allow-empty -m init
git -C "$r" branch team/integration
cat >"$r/.team/team.conf" <<'EOF'
seat lead     claude lead     -
seat dev-a    claude dev      -
seat dev-b    claude dev      -
seat dev-c    claude dev      -
seat tester   claude tester   -
seat rev-gpt  codex  reviewer dev-a,dev-b,dev-c
seat observer claude observer -
step 2
name lead Atlas mauve
name dev-a Nova blue
name dev-b Rook teal
name dev-c Iris peach
name tester Vera green
name rev-gpt Sol yellow
name observer Owl pink
EOF
{
  echo '# Tasks'; echo; echo '| ID | Title | Owner | Status | After |'; echo '|---|---|---|---|---|'
  for k in $(seq 1 38); do printf '| T-%03d | done %s | dev-a | merged | - |\n' "$k" "$k"; done
  echo '| T-110 | Tabs | dev-b | merged | - |'
  echo '| T-113 | Sheet, Dialog | dev-b | dev | - |'
  echo '| T-117 | Feedback 1 · Alert, StatusBanner, Toast | dev-c | dev | - |'
  echo '| T-129 | Timeline state prop | dev-a | dev | - |'
  for k in $(seq 140 156); do printf '| T-%03d | later %s | - | todo | - |\n' "$k" "$k"; done
} >"$r/.team/TASKS.md"
cat >"$r/.team/tasks/T-117.md" <<'EOF'
# T-117: Feedback 1 · Alert, StatusBanner, Toast
## Acceptance
| # | Requirement | How |
|---|---|---|
| 1 | recipes, no literal colour | x |
| 2 | light/dark · Precision/Soft | x |
| 3 | Alert roles | x |
| 4 | StatusBanner tones | x |
| 5 | Toast stack order | x |
| 6 | focus ring | x |
| 7 | contrast 4.5:1 | x |
| 8 | 390 / 820 / 1440 | x |
| 9 | Toast dismiss by keyboard | x |
| 10 | reduced motion | x |
| 11 | parity rows | x |
EOF
printf '# CANDIDATE-23: the whole list, once\n\n- Branch: `team/candidate-23` = `task/T-129` + `task/T-113`\n' >"$r/.team/tasks/CANDIDATE-23.md"
printf 'STATUS: DONE\n## Acceptance\n| # | Result | Evidence |\n|---|---|---|\n| 1 | pass | ok |\n| 2 | pass | ok |\n' >"$r/.team/reports/T-117-dev.md"
mtime_ago 74 "$r/.team/tasks/T-117.md"
cat >"$r/.team/DECISIONS.md" <<'EOF'
# Decisions

## D-075 · Toast motion for T-117
- Time: t
- Question: T-117 motion
- Options: o
- Claude: c
- GPT: g
- Sources: s
- Decision: d
- Why: w
- Status: final

## D-076 · Toast states for T-117
- Time: t
- Question: T-117 look
- Options: o
- Claude: c
- GPT: g
- Sources: s
- Decision: d
- Why: w
- Status: to test by V!
- See: feedback-toast--states
EOF
ago() { perl -MPOSIX -e 'print strftime("%Y-%m-%d %H:%M:%S", localtime(time - $ARGV[0] * 60))' "$1"; }
{
  echo "$(ago 300) dev-b T-110 DISPATCH round=1"; echo "$(ago 250) rev-gpt T-110 APPROVE"; echo "$(ago 240) lead T-110 MERGE"
  echo "$(ago 56) tester T-117 CONTRACT report=x"; echo "$(ago 55) dev-c T-117 DISPATCH round=1"
  echo "$(ago 28) dev-c T-117 HEAVY_END rc=0"; echo "$(ago 27) dev-c T-117 HEAVY_END rc=0"
  echo "$(ago 40) dev-a T-129 DISPATCH round=1"; echo "$(ago 20) dev-a T-129 DISPATCH round=2"
  echo "$(ago 30) dev-b T-113 DISPATCH round=1"
  echo "$(ago 11) tester CANDIDATE-23 DISPATCH round=1"
} | sort >"$r/.team/events.log"
printf '01:10 pass 21: candidate 23 running\n' >"$r/.team/observer/passes.log"
printf '# Now\nLargest loss: 19 min on the lock\n1. **one**\n2. **two**\n' >"$r/.team/observer/NOW.md"
now=$(date +%s); for k in $(seq 0 14); do v=$(( (k * 7 + 3) % 10 )); printf '%s %s\n' $((now - (14 - k) * 120)) "0.$v" ; done >"$r/.team/observer/.act/dev-c"

# Iris's worktree: 22 changed files, the last commit 31 min ago
wt="$r-team"; mkdir -p "$wt"
git -C "$r" worktree add -q "$wt/integration" team/integration
git -C "$r" branch task/T-117 team/integration
git -C "$r" worktree add -q "$wt/dev-c" task/T-117
GIT_COMMITTER_DATE="$(( $(date +%s) - 31 * 60 )) +0000" git -C "$wt/dev-c" -c user.email=d@d -c user.name=d commit -q --allow-empty -m wip
for f in alert toast banner; do for k in $(seq 1 7); do echo x >"$wt/dev-c/$f-$k.tsx"; done; done; echo x >"$wt/dev-c/toast.css"
for s in dev-a dev-b; do git -C "$r" worktree add -q --detach "$wt/$s" team/integration; done

# the machine's lock: Vera runs, Rook and Nova wait; tonus is idle
ln -s "tester@hive:1:$now" "$d/cache/squad/heavy/lock"
: >"$d/cache/squad/heavy/queue/000000000001-1-dev-b@hive"; : >"$d/cache/squad/heavy/queue/000000000002-1-dev-a@hive"
printf '%s\n' "$d/tonus/.team" >"$d/cache/squad/teams/tonus"; : >"$d/tonus/.team/events.log"; mtime_ago 600 "$d/tonus/.team/events.log"
printf '{"p5":36,"r5":0,"p7":20,"r7":0}\n' >"$d/cache/squad/claude-usage.json"

cd "$r"
case " $* " in *" --seat="*|*" --view="*) ;; *) set -- --seat=dev-c "$@" ;; esac   # Iris, as in the mockup
PATH="$d/bin:$PATH" XDG_CACHE_HOME="$d/cache" "$squad" board --preview "$@"
