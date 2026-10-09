#!/usr/bin/env bash
# Smoke test: runs squad against a stand-in for herdr and checks the commands
# it sends, the worktrees it creates and its error paths. Needs git and jq.
# This does not start real agents; it checks squad's own logic.
set -euo pipefail

here=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)
squad="$here/../bin/squad"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/home"

cat >"$tmp/bin/herdr" <<'EOF'
#!/usr/bin/env bash
echo "herdr $*" >>"$MOCK_LOG"
nf="$(dirname "$MOCK_LOG")/n"; n=$(cat "$nf" 2>/dev/null || echo 1)
case "$1 $2" in
  "workspace create") echo '{"result":{"root_pane":{"pane_id":"w2:p1"}}}' ;;
  "pane split") n=$((n + 1)); echo "$n" >"$nf"; echo "{\"result\":{\"pane\":{\"pane_id\":\"w2:p$n\"}}}" ;;
  "agent list") echo "${MOCK_AGENTS:-}" ;;
  "agent start") if [ "$3" = "${MOCK_FAIL:-}" ]; then echo '{"error":"agent_not_ready"}' >&2; exit 1; fi; echo '{}' ;;
  *) echo '{}' ;;
esac
EOF
chmod +x "$tmp/bin/herdr"
for a in claude codex opencode; do printf '#!/bin/sh\n' >"$tmp/bin/$a"; chmod +x "$tmp/bin/$a"; done

export PATH="$tmp/bin:$PATH" HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/home/.config" MOCK_LOG="$tmp/log"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
unset HERDR_ENV

pass=0; fail=0
check() { # <description> <command...>
  local d=$1; shift
  if "$@" >/dev/null 2>&1; then pass=$((pass + 1)); echo "ok   $d"; else fail=$((fail + 1)); echo "FAIL $d"; fi
}
refuses() { ! "$@"; }
log_has() { grep -qF -- "$1" "$MOCK_LOG"; }
reset_log() { : >"$MOCK_LOG"; rm -f "$tmp/n"; }

cd "$tmp"
check "new creates a project with the default team" "$squad" new proj
cd proj
check "team files exist" test -f .team/team.conf -a -f .team/ROSTER.md -a -f .team/roles/lead.md
check "team files are excluded from git" test -z "$(git status --porcelain)"
check "up refuses to run outside herdr" refuses "$squad" up
export HERDR_ENV=1

reset_log
check "up starts the default team" "$squad" up
check "six agents started" test "$(grep -c '^herdr agent start' "$MOCK_LOG")" = 6
check "lead runs codex with the Sol model" log_has "agent start lead --kind codex --pane w2:p1 --timeout 90000 -- -m gpt-6.1-sol"
check "dev-a runs in its own worktree" log_has "--cwd $tmp/proj-team/dev-a"
check "reviewers share the integration worktree" test "$(grep -c "pane split.*--cwd $tmp/proj-team/integration" "$MOCK_LOG")" = 2
check "every seat is briefed" test "$(grep -c '^herdr agent prompt' "$MOCK_LOG")" = 6
check "the lead is briefed last" sh -c "tail -1 '$MOCK_LOG' | grep -q 'agent prompt lead'"
check "worktrees were created" test "$(git worktree list | wc -l)" = 5
check "integration branch exists" git show-ref --verify --quiet refs/heads/team/integration
check "up works from inside a team worktree" sh -c "cd '$tmp/proj-team/dev-a' && MOCK_AGENTS= '$squad' status"
check "up refuses when the team is already running" refuses env MOCK_AGENTS="lead idle" "$squad" up
check "a seat that fails to start stops before briefing" refuses env MOCK_FAIL=dev-b "$squad" up
check "brief alone works" "$squad" brief
check "status prints the task table" sh -c "'$squad' status | grep -q 'T-001'"
check "doctor passes" "$squad" doctor

echo "dirty" >"$tmp/proj-team/dev-a/scratch.txt"
check "clean keeps a worktree with uncommitted work" refuses "$squad" clean
check "the dirty worktree is still there" test -f "$tmp/proj-team/dev-a/scratch.txt"
check "clean removed the clean worktrees" test ! -d "$tmp/proj-team/dev-b"
rm "$tmp/proj-team/dev-a/scratch.txt"
check "clean removes it once it is clean" "$squad" clean

cd "$tmp"
check "new accepts the opencode preset" "$squad" new proj2 --preset opencode
cd proj2; reset_log
check "up starts the opencode team" "$squad" up
check "opencode seat starts with no extra arguments" grep -qE '^herdr agent start dev-c --kind opencode --pane [^ ]+ --timeout 90000$' "$MOCK_LOG"
check "roster pairs rev-claude with dev-b and dev-c" grep -qF 'dev-b,dev-c' .team/ROSTER.md
check "roster gives opencode its clear command" sh -c "grep 'dev-c' .team/ROSTER.md | grep -qF '/new'"

cd "$tmp"
check "config writes a personal default" "$squad" config --preset small
check "init uses the personal default" sh -c "'$squad' new proj3 && test \"\$(grep -c '^seat ' proj3/.team/team.conf)\" = 3"

cd "$tmp/proj3"
printf 'seat lead codex lead -\nseat lead2 codex lead -\n' >.team/team.conf
check "two leads are rejected" refuses "$squad" status
printf 'seat lead codex lead -\nseat rev claude reviewer dev-x\n' >.team/team.conf
check "a reviewer of an unknown dev is rejected" refuses "$squad" status
printf 'seat Lead codex lead -\n' >.team/team.conf
check "an invalid seat name is rejected" refuses "$squad" status
check "init keeps an existing team.conf" sh -c "'$squad' init 2>&1 | grep -q 'kept     .team/team.conf'"

echo
echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
