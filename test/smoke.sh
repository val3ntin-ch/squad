#!/usr/bin/env bash
# Smoke test: runs squad against a stand-in for herdr and checks the commands
# it sends, the worktrees it creates and its error paths. Needs git and jq.
# This does not start real agents; it checks squad's own logic.
set -euo pipefail

here=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)
squad="$here/../bin/squad"
# resolved path: on macOS mktemp gives /var/..., which git reports as /private/var/...
tmp=$(cd -P "$(mktemp -d)" && pwd); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/home"

cat >"$tmp/bin/herdr" <<'EOF'
#!/usr/bin/env bash
echo "herdr $* sock=${HERDR_SOCKET_PATH:-}" >>"$MOCK_LOG"
nf="$(dirname "$MOCK_LOG")/n"; n=$(cat "$nf" 2>/dev/null || echo 1)
case "$1 $2" in
  "workspace create") echo '{"result":{"root_pane":{"pane_id":"w2:p1"}}}' ;;
  "pane split") n=$((n + 1)); echo "$n" >"$nf"; echo "{\"result\":{\"pane\":{\"pane_id\":\"w2:p$n\"}}}" ;;
  # JSON shaped like herdr 0.9.3; set MOCK_AGENTS / MOCK_WS / MOCK_PANES to override
  "agent list") if [ -n "${MOCK_AGENTS:-}" ]; then echo "$MOCK_AGENTS"; else echo '{"result":{"agents":[]}}'; fi ;;
  "workspace list") if [ -n "${MOCK_WS:-}" ]; then echo "$MOCK_WS"; else echo '{"result":{"workspaces":[]}}'; fi ;;
  "pane list") if [ -n "${MOCK_PANES:-}" ]; then echo "$MOCK_PANES"; else echo '{"result":{"panes":[]}}'; fi ;;
  "pane read") echo "${MOCK_PANE_TEXT:-}" ;;
  "agent start")
    if [ "$3" = "${MOCK_FAIL:-}" ]; then echo '{"error":"agent_not_ready"}' >&2; exit 1; fi
    # MOCK_BUSY=N: the first N starts answer like a shell that is still starting
    bf="$(dirname "$MOCK_LOG")/busy"; b=$(cat "$bf" 2>/dev/null || echo 0)
    if [ "$b" -lt "${MOCK_BUSY:-0}" ]; then echo $((b + 1)) >"$bf"
      echo '{"error":{"code":"agent_pane_busy","message":"agent target pane is not an available shell"}}'; exit 1; fi
    echo '{}' ;;
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
check "lead runs codex with the Sol model" log_has "agent start lead --kind codex --pane w2:p1 --timeout 90000 -- -m gpt-6.1-sol --add-dir $tmp/proj/.team --add-dir $tmp/proj/.git -s workspace-write"
check "claude seats get write access to .team" log_has "agent start dev-a --kind claude --pane w2:p2 --timeout 90000 -- --model claude-opus-5-5 --add-dir $tmp/proj/.team --add-dir $tmp/proj/.git"
check "dev-a runs in its own worktree" log_has "--cwd $tmp/proj-team/dev-a"
check "reviewers share the integration worktree" test "$(grep -c "pane split.*--cwd $tmp/proj-team/integration" "$MOCK_LOG")" = 2
check "every seat is briefed" test "$(grep -c '^herdr agent prompt' "$MOCK_LOG")" = 6
check "the lead is briefed last" sh -c "tail -1 '$MOCK_LOG' | grep -q 'agent prompt lead'"
check "worktrees were created" test "$(git worktree list | wc -l | tr -d ' ')" = 5
check "integration branch exists" git show-ref --verify --quiet refs/heads/team/integration
check "up works from inside a team worktree" sh -c "cd '$tmp/proj-team/dev-a' && '$squad' status"
other='{"result":{"agents":[{"name":"lead","pane_id":"w9:p1","workspace_id":"w9","agent":"codex"}]}}'
check "up refuses when a seat name runs in another workspace" refuses env MOCK_AGENTS="$other" "$squad" up

# resume: the team workspace exists; lead runs, rev-sol's agent runs unnamed
reset_log
ws='{"result":{"workspaces":[{"workspace_id":"w2","label":"proj team"}]}}'
panes='{"result":{"panes":[{"pane_id":"w2:p1","label":"lead"},{"pane_id":"w2:p2","label":"dev-a"},{"pane_id":"w2:p3","label":"dev-b"},{"pane_id":"w2:p4","label":"rev-sol"},{"pane_id":"w2:p5","label":"rev-claude"},{"pane_id":"w2:p6","label":"tester"}]}}'
agents='{"result":{"agents":[{"name":"lead","pane_id":"w2:p1","workspace_id":"w2","agent":"codex"},{"name":null,"pane_id":"w2:p4","workspace_id":"w2","agent":"codex"}]}}'
check "up resumes an existing team workspace" env MOCK_WS="$ws" MOCK_PANES="$panes" MOCK_AGENTS="$agents" "$squad" up
check "resume creates no new workspace" refuses log_has "workspace create"
check "resume keeps the running lead" refuses log_has "agent start lead"
check "resume adopts the unnamed agent in its seat's pane" log_has "agent rename w2:p4 rev-sol"
check "resume starts only the missing seats" test "$(grep -c '^herdr agent start' "$MOCK_LOG")" = 4
check "resume briefs only started and adopted seats" test "$(grep -c '^herdr agent prompt' "$MOCK_LOG")" = 5
check "resume does not re-brief the lead" refuses log_has "agent prompt lead"

# a seat that runs but was never briefed (its first run stopped early) gets briefed
reset_log; rm -f .team/.briefed/dev-a
agents2='{"result":{"agents":[{"name":"lead","pane_id":"w2:p1","workspace_id":"w2","agent":"codex"},{"name":"dev-a","pane_id":"w2:p2","workspace_id":"w2","agent":"claude"}]}}'
check "up on a running team succeeds" env MOCK_WS="$ws" MOCK_PANES="$panes" MOCK_AGENTS="$agents2" "$squad" up
check "a running seat that was never briefed gets briefed" log_has "agent prompt dev-a"
check "a running seat that was briefed is left alone" refuses log_has "agent prompt lead"

# agents get literal values, not environment variables (Codex runs commands
# through a daemon whose environment can belong to another pane)
check "role files get the absolute team directory" grep -qF "$tmp/proj/.team/TASKS.md" .team/roles/lead.md
check "role files have no unexpanded \$TEAM_DIR" refuses grep -qF '$TEAM_DIR' .team/roles/lead.md .team/roles/dev.md .team/PROTOCOL.md
squad_abs=$(cd -P "$(dirname "$squad")" && pwd)/squad
check "the lead calls herdr through 'squad herdr'" grep -qF "$squad_abs herdr agent prompt" .team/roles/lead.md
check "up remembers the session's socket" sh -c "HERDR_SOCKET_PATH=/s/x.sock '$squad' brief >/dev/null; grep -qxF /s/x.sock .team/herdr.sock"
check "squad herdr uses the team's socket, not the caller's" sh -c "HERDR_SOCKET_PATH=/other.sock '$squad' herdr agent list >/dev/null; tail -1 '$MOCK_LOG' | grep -q 'sock=/s/x.sock'"
check "squad herdr works from a team worktree" sh -c "cd '$tmp/proj-team/dev-a' && '$squad' herdr agent list >/dev/null"
codex_home="$tmp/codexhome"
check "permissions adds one Codex rule" env CODEX_HOME="$codex_home" "$squad" permissions
check "the rule allows squad herdr" grep -qF "\"$squad_abs\", \"herdr\"" "$codex_home/rules/default.rules"
check "permissions is idempotent" sh -c "CODEX_HOME='$codex_home' '$squad' permissions >/dev/null; test \$(grep -c herdr '$codex_home/rules/default.rules') = 1"

check "a seat that fails to start stops before briefing" refuses env MOCK_FAIL=dev-b "$squad" up
check "a stuck seat's trust dialog is named" sh -c "MOCK_FAIL=dev-b MOCK_PANE_TEXT='Trust this folder?' '$squad' up | grep -q 'trust this folder'"
check "a stuck seat's update prompt is named" sh -c "MOCK_FAIL=dev-b MOCK_PANE_TEXT='Update available' '$squad' up | grep -q 'check_for_update_on_startup'"
reset_log; rm -f "$tmp/busy"
check "a seat on a still-starting shell is retried, not failed" env MOCK_BUSY=3 "$squad" up
check "the busy seat was retried until it started" test "$(grep -c '^herdr agent start lead ' "$MOCK_LOG")" = 4
check "brief alone works" "$squad" brief
check "status prints the task table" sh -c "'$squad' status | grep -q 'T-001'"
check "status shows each seat's agent state" sh -c "MOCK_AGENTS='{\"result\":{\"agents\":[{\"name\":\"dev-a\",\"agent_status\":\"working\"}]}}' '$squad' status | grep -qE 'dev-a +working'"
check "status marks seats without an agent" sh -c "'$squad' status | grep -qE 'tester +not running'"
reset_log
check "down refuses nothing when no team is open" "$squad" down
check "down closes the team workspace" sh -c "MOCK_WS='{\"result\":{\"workspaces\":[{\"workspace_id\":\"w7\",\"label\":\"proj team\"}]}}' '$squad' down >/dev/null; grep -q 'workspace close w7' '$MOCK_LOG'"
check "down forgets who was briefed" sh -c "ls .team/.briefed 2>/dev/null | grep -q . && exit 1 || exit 0"
check "doctor passes" "$squad" doctor

echo "dirty" >"$tmp/proj-team/dev-a/scratch.txt"
check "clean keeps a worktree with uncommitted work" refuses "$squad" clean
check "the dirty worktree is still there" test -f "$tmp/proj-team/dev-a/scratch.txt"
check "clean removed the clean worktrees" test ! -d "$tmp/proj-team/dev-b"
rm "$tmp/proj-team/dev-a/scratch.txt"
check "clean removes it once it is clean" "$squad" clean

cd "$tmp"
mkdir -p "$tmp/pnpmrepo" && (cd "$tmp/pnpmrepo" && git init -q && touch pnpm-lock.yaml && git add -A && git commit -qm i)
check "init detects the install command from the lockfile" sh -c "cd '$tmp/pnpmrepo' && '$squad' init | grep -q 'pnpm install --frozen-lockfile'"
check "the detected command lands in team.conf" grep -qx 'setup pnpm install --frozen-lockfile' "$tmp/pnpmrepo/.team/team.conf"
check "init keeps a team.conf it did not create" sh -c "cd '$tmp/pnpmrepo' && '$squad' init | grep -q 'kept'"

check "new accepts the opencode preset" "$squad" new proj2 --preset opencode
cd proj2; reset_log
check "up starts the opencode team" "$squad" up
check "opencode seat starts with no extra arguments" grep -qE '^herdr agent start dev-c --kind opencode --pane [^ ]+ --timeout 90000 sock=[^ ]*$' "$MOCK_LOG"
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
