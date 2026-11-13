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
  "workspace create") echo '{"result":{"root_pane":{"pane_id":"w2:p1"},"workspace":{"workspace_id":"w2"},"tab":{"tab_id":"w2:t1"}}}' ;;
  "pane layout") echo "{\"result\":{\"layout\":{\"area\":{\"width\":${MOCK_WIDTH:-160},\"height\":${MOCK_HEIGHT:-40}}}}}" ;;
  "tab create") n=$((n + 1)); echo "$n" >"$nf"; echo "{\"result\":{\"root_pane\":{\"pane_id\":\"w2:p$n\"}}}" ;;
  "pane split") n=$((n + 1)); echo "$n" >"$nf"; echo "{\"result\":{\"pane\":{\"pane_id\":\"w2:p$n\"}}}" ;;
  # JSON shaped like herdr 0.9.3; set MOCK_AGENTS / MOCK_WS / MOCK_PANES to override
  # MOCK_DYNAMIC=1: dev-a answers prompts like a real seat (a clear or /model leaves it
  # idle, a task makes it work; MOCK_NEVER_WORK=1: it never starts)
  "agent list") if [ "${MOCK_DYNAMIC:-}" = 1 ]; then st=$(cat "$(dirname "$MOCK_LOG")/state" 2>/dev/null || echo idle)
                  echo "{\"result\":{\"agents\":[{\"name\":\"dev-a\",\"agent_status\":\"$st\"},{\"name\":\"observer\",\"agent_status\":\"idle\"},{\"name\":\"lead\",\"agent_status\":\"working\"}]}}"
                elif [ -n "${MOCK_AGENTS:-}" ]; then echo "$MOCK_AGENTS"; else echo '{"result":{"agents":[]}}'; fi ;;
  "agent prompt") if [ "${MOCK_DYNAMIC:-}" = 1 ] && [ "$3" = dev-a ]; then
                    case "$4" in /*) echo idle ;; *) if [ "${MOCK_NEVER_WORK:-}" = 1 ]; then echo idle; else echo working; fi ;; esac >"$(dirname "$MOCK_LOG")/state"; fi
                  echo '{}' ;;
  "agent read") echo "${MOCK_PANE_TEXT:-}" ;;
  "session list") echo "${MOCK_SESSIONS:-{\}}" ;;
  "workspace list") if [ -n "${MOCK_WS:-}" ]; then echo "$MOCK_WS"; else echo '{"result":{"workspaces":[]}}'; fi ;;
  "pane list") if [ -n "${MOCK_PANES:-}" ]; then echo "$MOCK_PANES"; else echo '{"result":{"panes":[]}}'; fi ;;
  "pane read") echo "${MOCK_PANE_TEXT:-}" ;;
  "agent start")
    if [ "$3" = "${MOCK_FAIL:-}" ]; then echo '{"error":"agent_not_ready"}' >&2; exit 1; fi
    if [ "$3" = "${MOCK_TAKEN:-}" ]; then echo "{\"error\":{\"code\":\"agent_name_taken\",\"message\":\"agent name $3 is already used\"}}" >&2; exit 1; fi
    # MOCK_FAIL_RESUME=1: the agent refuses an old conversation
    if [ "${MOCK_FAIL_RESUME:-}" = 1 ] && case " $* " in *" --resume "*|*" -- resume "*) true ;; *) false ;; esac; then echo '{"error":"agent_not_ready"}' >&2; exit 1; fi
    # MOCK_BUSY=N: the first N starts answer like a shell that is still starting
    bf="$(dirname "$MOCK_LOG")/busy"; b=$(cat "$bf" 2>/dev/null || echo 0)
    if [ "$b" -lt "${MOCK_BUSY:-0}" ]; then echo $((b + 1)) >"$bf"
      echo '{"error":{"code":"agent_pane_busy","message":"agent target pane is not an available shell"}}'; exit 1; fi
    echo '{}' ;;
  *) echo '{}' ;;
esac
EOF
chmod +x "$tmp/bin/herdr"
for a in claude codex opencode lazygit; do printf '#!/bin/sh\n' >"$tmp/bin/$a"; chmod +x "$tmp/bin/$a"; done

export PATH="$tmp/bin:$PATH" HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/home/.config" MOCK_LOG="$tmp/log"
# never touch the real caches/configs: shells often export these explicitly
export XDG_CACHE_HOME="$tmp/home/.cache" CODEX_HOME="$tmp/home/.codex"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
# The engine tests run on mixed teams (several agent kinds, reviewer seats):
# they live in test/fixtures/presets. The shipped presets are tested at the end.
export SQUAD_PRESETS="$here/fixtures/presets"
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
export HERDR_ENV=1

reset_log
check "up starts the default team" "$squad" up
check "six agents started" test "$(grep -c '^herdr agent start' "$MOCK_LOG")" = 6
check "lead runs codex with the Sol model" log_has "agent start lead --kind codex --pane w2:p1 --timeout 90000 -- -m gpt-6.1-sol --add-dir $tmp/proj/.team --add-dir $tmp/proj/.git -c developer_instructions="
check "codex seats get their role as developer_instructions" grep -qE '^herdr agent start lead .* -c developer_instructions="# You are seat `lead`' "$MOCK_LOG"
check "codex seats run in workspace-write" grep -qE '^herdr agent start lead .* -s workspace-write sock=' "$MOCK_LOG"
check "claude seats get write access to .team" log_has "agent start dev-a --kind claude --pane w2:p3 --timeout 90000 -- --model claude-opus-5-5 --add-dir $tmp/proj/.team --add-dir $tmp/proj/.git --append-system-prompt-file $tmp/proj/.team/seats/dev-a.md"
check "dev-a runs in its own worktree" log_has "--cwd $tmp/proj-team/dev-a"
check "reviewers share the integration worktree" test "$(grep -c "pane split.*--cwd $tmp/proj-team/integration" "$MOCK_LOG")" = 2
check "no typed briefing for seats that load their role" test "$(grep -c '^herdr agent prompt' "$MOCK_LOG")" = 1
check "only the lead gets a start line" log_has "agent prompt lead Start: read GOAL.md (ask me for the goal only if it is empty), write the spec, then run the team until everything is green."
check "every seat is marked briefed" sh -c "for s in lead dev-a dev-b rev-sol rev-claude tester; do test -f .team/.briefed/\$s || exit 1; done"
check "a seat file holds its name, protocol and role" sh -c "grep -q 'You are seat .dev-a. (role: dev)' .team/seats/dev-a.md && grep -q 'Team protocol' .team/seats/dev-a.md && grep -q 'Role: dev' .team/seats/dev-a.md"
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
check "resume types nothing to seats that load their role" test "$(grep -c '^herdr agent prompt' "$MOCK_LOG")" = 0
check "resume does not re-brief the lead" refuses log_has "agent prompt lead"

# a seat that runs but was never briefed (its first run stopped early) gets briefed
reset_log; rm -f .team/.briefed/dev-a
agents2='{"result":{"agents":[{"name":"lead","pane_id":"w2:p1","workspace_id":"w2","agent":"codex"},{"name":"dev-a","pane_id":"w2:p2","workspace_id":"w2","agent":"claude"}]}}'
check "up on a running team succeeds" env MOCK_WS="$ws" MOCK_PANES="$panes" MOCK_AGENTS="$agents2" "$squad" up
check "a running seat that was never briefed gets marked briefed" test -f .team/.briefed/dev-a
check "a running seat that was briefed is left alone" refuses log_has "agent prompt lead"

# agents get literal values, not environment variables (Codex runs commands
# through a daemon whose environment can belong to another pane)
check "role files get the absolute team directory" grep -qF "$tmp/proj/.team/TASKS.md" .team/roles/lead.md
check "role files have no unexpanded \$TEAM_DIR" refuses grep -qF '$TEAM_DIR' .team/roles/lead.md .team/roles/dev.md .team/PROTOCOL.md
squad_abs=$(cd -P "$(dirname "$squad")" && pwd)/squad
check "the lead reads panes through 'squad herdr'" grep -qF "$squad_abs herdr agent read" .team/roles/lead.md
check "the lead dispatches through squad dispatch" grep -qF "$squad_abs dispatch dev-a T-001" .team/roles/lead.md
check "up remembers the session's socket" sh -c "HERDR_SOCKET_PATH=/s/x.sock '$squad' brief >/dev/null; grep -qxF /s/x.sock .team/herdr.sock"
check "squad herdr uses the team's socket, not the caller's" sh -c "HERDR_SOCKET_PATH=/other.sock '$squad' herdr agent list >/dev/null; tail -1 '$MOCK_LOG' | grep -q 'sock=/s/x.sock'"
check "squad herdr works from a team worktree" sh -c "cd '$tmp/proj-team/dev-a' && '$squad' herdr agent list >/dev/null"
check "role files send git writes through squad git" grep -qF "$squad_abs git switch -c task/" .team/roles/dev.md
check "the lead merges through squad merge" grep -qF "$squad_abs merge <ID>" .team/roles/lead.md
check "squad git runs an allowed write" sh -c "cd '$tmp/proj-team/dev-a' && '$squad' git switch -c t-probe >/dev/null 2>&1 && git branch --show-current | grep -qx t-probe"
check "squad git refuses push" refuses sh -c "cd '$tmp/proj-team/dev-a' && '$squad' git push"
check "squad git refuses force" refuses sh -c "cd '$tmp/proj-team/dev-a' && '$squad' git switch -f t-probe"
check "squad git refuses deleting branches" refuses sh -c "cd '$tmp/proj-team/dev-a' && '$squad' git branch -D t-probe"
check "squad git refuses read commands (plain git is fine)" refuses sh -c "cd '$tmp/proj-team/dev-a' && '$squad' git log"
check "squad git refuses outside a team" refuses sh -c "cd '$tmp' && '$squad' git switch -c nope"
git -C "$tmp/proj-team/dev-a" switch -q --detach team/integration
codex_home="$tmp/codexhome"
check "permissions adds one Codex rule" env CODEX_HOME="$codex_home" "$squad" permissions
check "the rule allows squad herdr" grep -qF "\"$squad_abs\", \"herdr\"" "$codex_home/rules/default.rules"
check "permissions is idempotent" sh -c "CODEX_HOME='$codex_home' '$squad' permissions >/dev/null; test \$(grep -c herdr '$codex_home/rules/default.rules') = 1"
layout_up() { # <width> -> fresh team workspace laid out at that width
  reset_log; rm -f .team/.briefed/*
  MOCK_WIDTH=$1 "$squad" up >/dev/null 2>&1
}
layout_up 160
talk_out=$(MOCK_WIDTH=160 "$squad" up 2>/dev/null || true)
check "talk layout at 160 columns" grep -qF "layout: talk" <<<"$talk_out"
check "talk: the strip runs squad watch" grep -qF "$squad_abs watch" "$MOCK_LOG"
check "talk: reviewers and tester get a review tab" grep -q 'tab create --workspace w2 --label review' "$MOCK_LOG"
check "talk: lazygit gets a changes tab" grep -q 'tab create --workspace w2 --label changes' "$MOCK_LOG"
layout_up 240
check "mission layout at 240 columns: no extra tabs but changes" sh -c "! grep -q 'label review' '$MOCK_LOG' && ! grep -q 'label devs' '$MOCK_LOG'"
layout_up 100
check "focus layout at 100 columns: devs get their own tab" grep -q 'tab create --workspace w2 --label devs' "$MOCK_LOG"
reset_log; rm -f .team/.briefed/*
MOCK_FAIL=lead MOCK_PANE_TEXT='Trust this folder?' MOCK_WIDTH=160 "$squad" up >/dev/null 2>&1 || true  # exits 1: seats held
check "held seats' panes are named too (so resume finds them)" sh -c "for s in dev-b rev-sol; do grep -q \"pane rename w2:p[0-9]* \$s\" '$MOCK_LOG' || exit 1; done"
check "SQUAD_LAYOUT overrides the width" sh -c "SQUAD_LAYOUT=mission MOCK_WIDTH=100 '$squad' up | grep -q 'layout: mission'"

# squad done: a worker tells the lead, even while it is busy
reset_log
echo "STATUS: DONE" >.team/reports/T-009-dev.md
check "squad done tells the lead" sh -c "'$squad' done dev-a T-009 DONE >/dev/null && grep -q 'agent prompt lead \[squad\] dev-a finished T-009: DONE' '$MOCK_LOG'"
check "squad done names the report" grep -qF "report: $tmp/proj/.team/reports/T-009-dev.md" "$MOCK_LOG"
check "squad done records the event" grep -q 'dev-a T-009 DONE' .team/events.log
check "squad done refuses an unknown seat" refuses "$squad" "done" nobody T-009 DONE
check "role files tell workers to run squad done" grep -qF "$squad_abs done <your seat name>" .team/roles/dev.md
check "the lead no longer blocks on agent wait" refuses grep -q 'agent wait' .team/roles/lead.md

# usage: Codex from its session files, Claude from the status line
cx="$tmp/codex"; mkdir -p "$cx/sessions/2026/01/01"
printf '%s\n' '{"type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":42.0,"window_minutes":300,"resets_at":4102444800},"secondary":{"used_percent":7.0,"window_minutes":10080,"resets_at":4102444800}}}}' >"$cx/sessions/2026/01/01/rollout-x.jsonl"
check "usage reads Codex's rate limits" sh -c "CODEX_HOME='$cx' '$squad' usage | grep -qE 'Codex 5h [▓░]+ +42%'"
check "statusline saves Claude's usage" sh -c "echo '{\"model\":{\"display_name\":\"Opus\"},\"rate_limits\":{\"five_hour\":{\"used_percentage\":61,\"resets_at\":4102444800},\"seven_day\":{\"used_percentage\":20,\"resets_at\":4102444800}}}' | '$squad' statusline | grep -q '61%'"
check "usage shows Claude after the status line ran" sh -c "'$squad' usage | grep -qE 'Claude 5h [▓░]+ +61%'"
check "a window past its reset shows 0%" sh -c "echo '{\"rate_limits\":{\"five_hour\":{\"used_percentage\":90,\"resets_at\":1}}}' | '$squad' statusline >/dev/null; '$squad' usage | grep -qE 'Claude 5h ░+ +0%'"
check "watch --once shows usage, tasks and seats" sh -c "'$squad' watch --once | grep -q 'T-001' && '$squad' watch --once | grep -q 'lead'"
check "permissions sets Claude's status line when none is set" sh -c "CODEX_HOME='$codex_home' CLAUDE_CONFIG_DIR='$tmp/cl1' '$squad' permissions >/dev/null; jq -e '.statusLine.command | contains(\"squad statusline\")' '$tmp/cl1/settings.json'"
mkdir -p "$tmp/cl2" && echo '{"statusLine":{"type":"command","command":"mine"},"model":"opus"}' >"$tmp/cl2/settings.json"
check "permissions keeps an existing Claude status line" sh -c "CODEX_HOME='$codex_home' CLAUDE_CONFIG_DIR='$tmp/cl2' '$squad' permissions >/dev/null; jq -e '.statusLine.command == \"mine\" and .model == \"opus\"' '$tmp/cl2/settings.json'"
check "squad done tells the lead to finish its current step first" grep -q 'first finish what you were doing' "$MOCK_LOG"
check "permissions also allows squad git" grep -qF "\"$squad_abs\", \"git\"" "$codex_home/rules/default.rules"

check "a seat that fails to start stops before briefing" refuses env MOCK_FAIL=dev-b "$squad" up
check "a stuck seat's trust dialog is named" sh -c "MOCK_FAIL=dev-b MOCK_PANE_TEXT='Trust this folder?' '$squad' up | grep -q 'trust this folder'"
reset_log
check "a trust dialog holds that agent's other seats" sh -c "MOCK_FAIL=lead MOCK_PANE_TEXT='Trust this folder?' '$squad' up | grep -q 'dev-b waits'"
check "held seats are not started" refuses grep -qE '^herdr agent start (dev-b|rev-sol) ' "$MOCK_LOG"
check "other agents' seats still start" grep -qE '^herdr agent start dev-a ' "$MOCK_LOG"
check "a stuck seat's update prompt is named" sh -c "MOCK_FAIL=dev-b MOCK_PANE_TEXT='Update available' '$squad' up | grep -q 'check_for_update_on_startup'"
reset_log; rm -f "$tmp/busy"
check "a seat on a still-starting shell is retried, not failed" env MOCK_BUSY=3 "$squad" up
check "the busy seat was retried until it started" test "$(grep -c '^herdr agent start lead ' "$MOCK_LOG")" = 4
check "brief alone works" "$squad" brief
reset_log; cp .team/SPEC.md "$tmp/spec.bak"; sed -i.x 's/^Status:.*/Status: APPROVED/' .team/SPEC.md
check "a lead with an approved spec resumes instead of starting over" sh -c "'$squad' brief >/dev/null && grep -q 'agent prompt lead Resume after a restart' '$MOCK_LOG' && ! grep -q 'ask me what we are building' '$MOCK_LOG'"
cp "$tmp/spec.bak" .team/SPEC.md; rm -f .team/SPEC.md.x
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
# capture first: 'squad … | grep -q' would kill squad mid-write once grep matches
check "init detects the install command from the lockfile" sh -c "cd '$tmp/pnpmrepo' && out=\$('$squad' init) && echo \"\$out\" | grep -q 'pnpm install --frozen-lockfile'"
check "init finishes writing every team file" test -f "$tmp/pnpmrepo/.team/TASKS.md" -a -f "$tmp/pnpmrepo/.team/PROTOCOL.md" -a -f "$tmp/pnpmrepo/.team/ROSTER.md"
check "watch works on a fresh team with no events yet" sh -c "cd '$tmp/pnpmrepo' && '$squad' watch --once | grep -q 'Claude'"
check "the detected command lands in team.conf" grep -qx 'setup pnpm install --frozen-lockfile' "$tmp/pnpmrepo/.team/team.conf"
check "init keeps a team.conf it did not create" sh -c "cd '$tmp/pnpmrepo' && '$squad' init | grep -q 'kept'"

check "new accepts the opencode preset" "$squad" new proj2 --preset opencode
cd proj2; reset_log
check "up starts the opencode team" "$squad" up
check "opencode seat starts with no extra arguments" grep -qE '^herdr agent start dev-c --kind opencode --pane [^ ]+ --timeout 90000 sock=[^ ]*$' "$MOCK_LOG"
check "opencode (no system-prompt flag) still gets a typed briefing" grep -q "^herdr agent prompt dev-c You are 'dev-c' on an agent team" "$MOCK_LOG"
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

# ---- the shipped presets: one Claude lead that plans and reviews, Claude devs, a cheap tester
unset SQUAD_PRESETS
rm -f "$XDG_CONFIG_HOME/squad/team.conf"
shipped="$here/../presets"
check "the shipped default has a GPT Sol reviewer at medium effort" grep -qE '^seat +rev-gpt +codex +reviewer +dev-a,dev-b,dev-c +-m gpt-6.1-sol -c model_reasoning_effort=medium$' "$shipped/default.conf"
check "the shipped default has an observer on Sonnet" grep -qE '^seat +observer +claude +observer +- +--model claude-sonnet-5-5' "$shipped/default.conf"
check "every shipped preset has one lead and a tester" sh -c "for f in '$shipped'/*.conf; do test \"\$(grep -cE '^seat .* lead ' \$f)\" = 1 && grep -qE '^seat .* tester ' \$f || exit 1; done"
check "every shipped preset turns the verify hook off and consults GPT Sol" sh -c "for f in '$shipped'/*.conf; do grep -qx 'verify_hook off' \$f && grep -q '^consult codex --search exec -m gpt-6.1-sol' \$f || exit 1; done"
cd "$tmp"
check "new creates a project with the shipped default team" "$squad" new proj4
cd proj4; reset_log
check "init creates the goal, the decisions log and the task template" test -f .team/GOAL.md -a -f .team/DECISIONS.md -a -f .team/tasks/_TEMPLATE.md
check "up starts the shipped team" "$squad" up
check "the lead runs the strongest model and may read the devs' worktrees" grep -qE "^herdr agent start lead --kind claude .* -- --model claude-fable-5-2 --add-dir $tmp/proj4/.team --add-dir [^ ]+ --add-dir $tmp/proj4-team " "$MOCK_LOG"
check "devs run at medium effort" grep -qE '^herdr agent start dev-a --kind claude .* -- --model claude-opus-5-5 --effort medium ' "$MOCK_LOG"
check "devs get no access to other worktrees" refuses grep -qE "^herdr agent start dev-a .* --add-dir $tmp/proj4-team " "$MOCK_LOG"
check "the tester is the cheap seat" grep -qE '^herdr agent start tester --kind claude .* -- --model claude-sonnet-5-5 --effort low ' "$MOCK_LOG"
check "seven seats start, the reviewer on Codex" sh -c "test \"\$(grep -c '^herdr agent start' '$MOCK_LOG')\" = 7 && grep -qE '^herdr agent start rev-gpt --kind codex .* -- -m gpt-6.1-sol -c model_reasoning_effort=medium ' '$MOCK_LOG'"
check "the protocol states the review rounds" grep -qF 'Review rounds before a task goes to the human: 5.' .team/PROTOCOL.md
check "READY.md links the lessons" grep -qF "the link to \`$tmp/proj4/.team/LESSONS.md\`" .team/roles/lead.md
check "the lead role has every task reviewed and decides each finding" grep -qF 'Every task is reviewed by a fresh pair of eyes and decided by you' .team/roles/lead.md
check "the task template holds the acceptance table" grep -qF '| # | Requirement | How to check it |' .team/tasks/_TEMPLATE.md
sed -i.bak 's/^rounds .*/rounds 3/' .team/team.conf && rm -f .team/team.conf.bak
check "rounds in team.conf reaches the role files" sh -c "'$squad' init >/dev/null && grep -qF 'After round 3 without approval' .team/roles/lead.md"
sed -i.bak 's/^rounds .*/rounds many/' .team/team.conf && rm -f .team/team.conf.bak
check "an invalid rounds value is rejected" refuses "$squad" status
sed -i.bak 's/^rounds .*/rounds 5/' .team/team.conf && rm -f .team/team.conf.bak
cat >.team/TASKS.md <<'TASKS'
| ID | Title | Owner | Status | Depends on |
|---|---|---|---|---|
| T-001 | a | dev-a | merged | - |
| T-002 | b | dev-b | review-2 | - |
| T-003 | c | dev-c | dev | T-001 |
| T-004 | d | dev-a | todo | T-002 |
TASKS
board=$("$squad" watch --once)
check "the board shows the progress of the goal" sh -c "printf '%s' \"\$1\" | grep -qF '1/4 merged · review 1 · dev 1 · todo 1'" _ "$board"
check "the board shows each task with its state and owner" sh -c "printf '%s' \"\$1\" | grep -qF '◆ T-002 review-2 dev-b' && printf '%s' \"\$1\" | grep -qF '● T-003 dev dev-c' && printf '%s' \"\$1\" | grep -qF '✔ T-001'" _ "$board"
check "the board is plain text when it is not a terminal" sh -c "! printf '%s' \"\$1\" | grep -q '\[3[0-9]m'" _ "$board"
check "usage shows no other vendor without data" sh -c "! '$squad' usage | grep -q Codex"

# ---- v2 (tickets 001-006), on the shipped default team in proj4 ----------------
ev() { grep -qE "$1" .team/events.log; }

# 001 · squad heavy: one at a time, first come first served, an owner, a time limit
export SQUAD_HEAVY_POLL=1 SQUAD_HEAVY_DIR="$tmp/heavy"; HV="$tmp/heavy"
rm -f "$tmp/order"
"$squad" heavy dev-a T-1 -- sh -c "sleep 2; echo A >>'$tmp/order'" >/dev/null 2>&1 &
sleep 0.5
"$squad" heavy dev-b T-2 -- sh -c "echo B >>'$tmp/order'" >/dev/null 2>&1
wait
check "heavy runs one command at a time, in arrival order" test "$(tr -d '\n' <"$tmp/order")" = AB
check "heavy logs start and end with the seat and the task" sh -c "grep -qE ' dev-a T-1 HEAVY_START ' .team/events.log && grep -qE ' dev-a T-1 HEAVY_END rc=0 ' .team/events.log"
check "the lock names its owner while it runs" sh -c "'$squad' heavy tester T-3 -- sh -c 'readlink $HV/lock; cat $HV/lock.cmd' | tr '\n' ' ' | grep -qE '^tester@proj4:[0-9]+:[0-9]+:[0-9]+ @[0-9a-f]+ \\(20 min\\): sh -c'"
check "the lock is free after a run" test ! -L "$HV"/lock
ln -s "dev-c:999999:$(date +%s)" "$HV"/lock
check "a lock whose owner process is gone is cleared" "$squad" heavy dev-a T-4 -- true
check "the cleared lock is in the events" ev 'dev-c - HEAVY_STALE'
check "a run over the time limit is stopped (exit 124) and frees the lock" sh -c "SQUAD_HEAVY_LIMIT_SECONDS=1 '$squad' heavy dev-a T-5 -- sleep 20; test \$? = 124 && test ! -L $HV/lock"
# a stopped wrapper frees the lock only after its command is gone
"$squad" heavy dev-a T-6 -- sh -c "sleep 31.4159" >/dev/null 2>&1 & hp=$!
sleep 1.5; kill -TERM "$hp"; wait "$hp" 2>/dev/null || true
check "a stopped heavy run leaves no command behind and frees the lock" sh -c "! pgrep -f 'sleep 31[.]4159' >/dev/null && test ! -L $HV/lock"
# callers in the same second keep their arrival order while the lock is held
sleep 60 & holder=$!
ln -s "tester:$holder:$(date +%s)" "$HV"/lock; rm -f "$tmp/order"
"$squad" heavy dev-a T-7 -- sh -c "echo A >>'$tmp/order'" >/dev/null 2>&1 & a=$!
sleep 0.3
"$squad" heavy dev-b T-8 -- sh -c "echo B >>'$tmp/order'" >/dev/null 2>&1 & b=$!
sleep 1.5; kill "$holder"; wait "$holder" 2>/dev/null || true; wait "$a" "$b"
sleep 60 & holder=$!; ln -s "tester:$holder:$(date +%s)" "$HV"/lock
"$squad" heavy dev-a T-77 -- true >"$tmp/orphan.out" 2>&1 & w=$!
sleep 1.5; rm -f "$HV"/queue/*-dev-a@*; sleep 1.5
check "a waiter whose queue entry is removed stops and says so" sh -c "! kill -0 $w 2>/dev/null && grep -q 'place in the heavy queue was removed' '$tmp/orphan.out'"
kill "$holder"; wait "$holder" "$w" 2>/dev/null || true; rm -f "$HV"/lock
check "the queue keeps arrival order within one second" test "$(tr -d '\n' <"$tmp/order")" = AB
check "heavy refuses a task id with a slash or markup" refuses "$squad" heavy dev-a '../x' -- true
check "heavy refuses an unknown seat" refuses "$squad" heavy nobody -- true

# 007 · a dev's run proves a commit; a dev's run has its own, shorter limit
echo wip >"$tmp/proj4-team/dev-c/wip.txt"
check "heavy refuses a dev worktree with an untracked file" sh -c "'$squad' heavy dev-c T-9 -- true 2>&1 | grep -q 'commit first'"
git -C "$tmp/proj4-team/dev-c" add wip.txt
check "heavy refuses a dev worktree with a staged change" refuses "$squad" heavy dev-c T-9 -- true
check "a refused run takes no lock and leaves no queue entry" sh -c "test ! -L $HV/lock && test -z \"\$(ls $HV/queue)\""
git -C "$tmp/proj4-team/dev-c" reset -q wip.txt; rm "$tmp/proj4-team/dev-c/wip.txt"
check "heavy runs a clean dev worktree" "$squad" heavy dev-c T-9 -- true
check "the run names the commit and the dev limit" grep -qE " dev-c T-9 HEAVY_START sha=[0-9a-f]{7,} limit=10m in=.runs/dev-c true" .team/events.log
echo shot >"$tmp/proj4-team/tester/artefact.png"
check "the tester's run is not held to the commit rule" "$squad" heavy tester T-9 -- true
check "the tester keeps the longer limit" grep -qE " tester T-9 HEAVY_START sha=[0-9a-f]{7,} limit=20m true" .team/events.log
rm "$tmp/proj4-team/tester/artefact.png"
check "the dev role says commit before squad heavy" grep -qF 'after a commit (it refuses uncommitted changes)' .team/roles/dev.md
check "heavy --status says the lock is free" sh -c "'$squad' heavy --status | grep -q 'lock: free'"

# 001 · squad dispatch: clear, wait for idle, send, confirm the start, log it
reset_log; rm -f "$tmp/state"; printf 'x\n' >.team/reports/T-100-contract.md
check "dispatch gives dev-a its task once it is idle again" env MOCK_DYNAMIC=1 SQUAD_DISPATCH_WAIT=5 "$squad" dispatch dev-a T-100
check "dispatch sends the clear first, then the task line" sh -c "grep -n 'agent prompt dev-a' '$MOCK_LOG' | head -1 | grep -q '/clear' && grep -q 'agent prompt dev-a Task T-100 is yours. Read $tmp/proj4/.team/tasks/T-100.md' '$MOCK_LOG'"
check "dispatch logs the event with the round" ev ' dev-a T-100 DISPATCH round=1'
check "dispatch fails when the seat never starts, and logs it" sh -c "! MOCK_DYNAMIC=1 MOCK_NEVER_WORK=1 SQUAD_DISPATCH_WAIT=2 '$squad' dispatch dev-a T-100 2>/dev/null && grep -q ' dev-a T-100 DISPATCH_FAILED' .team/events.log"
check "dispatch refuses a dev task with no contract from the tester" refuses env MOCK_DYNAMIC=1 SQUAD_DISPATCH_WAIT=2 "$squad" dispatch dev-a T-101
printf '19:09:44 dev-a T-150 DONE\n' >>.team/events.log; reset_log; rm -f "$tmp/state"
check "a task already under way (an older squad) goes on without a contract" env MOCK_DYNAMIC=1 SQUAD_DISPATCH_WAIT=5 "$squad" dispatch dev-a T-150
check "dispatch --contract goes to the tester only" refuses env MOCK_DYNAMIC=1 SQUAD_DISPATCH_WAIT=2 "$squad" dispatch dev-a T-101 --contract
reset_log; rm -f "$tmp/state"
printf 'RESULT: FAIL\n' >.team/reports/T-100-test.md; reset_log; rm -f "$tmp/state"
check "a dev sent back after a tester FAIL gets the correction line" sh -c "MOCK_DYNAMIC=1 SQUAD_DISPATCH_WAIT=5 '$squad' dispatch dev-a T-100 >/dev/null && grep -q 'agent prompt dev-a T-100 needs changes' '$MOCK_LOG'"
rm -f .team/reports/T-100-test.md; reset_log; rm -f "$tmp/state"
check "dispatch refuses a task id with markup" refuses env MOCK_DYNAMIC=1 "$squad" dispatch dev-a '<img>'
check "dispatch --escalate runs the fix on the stronger model" sh -c "MOCK_DYNAMIC=1 SQUAD_DISPATCH_WAIT=5 '$squad' dispatch dev-a T-100 --escalate >/dev/null && grep -q 'agent prompt dev-a /model claude-fable-5-2' '$MOCK_LOG'"
reset_log; rm -f "$tmp/state"
check "the next dispatch puts the seat back on its own model" sh -c "MOCK_DYNAMIC=1 SQUAD_DISPATCH_WAIT=5 '$squad' dispatch dev-a T-100 >/dev/null && grep -q 'agent prompt dev-a /model claude-opus-5-5' '$MOCK_LOG'"

# 001 · squad merge and the ledger
( cd "$tmp/proj4-team/dev-a" && git switch -q -c task/T-100 team/integration && echo x >t100.txt && git add t100.txt && git commit -qm "T-100" )
check "merge merges an approved task into the integration branch" "$squad" merge T-100
check "the merge is in git and in the events" sh -c "git -C '$tmp/proj4-team/integration' log -1 --format=%s | grep -q 'Merge T-100' && grep -qE ' lead T-100 MERGE [0-9a-f]+' .team/events.log"
check "event lines carry the date and the time" grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2} ' .team/events.log

# 001 · the verify switch
check "verify_hook off marks every team worktree" sh -c "for w in integration dev-a dev-b dev-c tester; do test -f '$tmp/proj4-team/'\$w/.agents-verify-off || exit 1; done"
check "the marker stays out of commits" grep -qxF '.agents-verify-off' "$tmp/proj4/.git/info/exclude"
check "a team without verify_hook off leaves the worktrees unmarked" test ! -e "$tmp/proj-team/integration/.agents-verify-off"

# 001 · squad notify: a rule change reaches the seats at work
reset_log; printf '%s dev-b T-200 DISPATCH round=1\n' "$(date '+%Y-%m-%d %H:%M:%S')" >>.team/events.log
check "notify tells each seat with an open task" sh -c "'$squad' notify 'SPEC Checks' 'run vitest related first' >/dev/null && grep -q 'agent prompt dev-b \[squad\] Rule changed' '$MOCK_LOG' && grep -q ' RULE SPEC Checks' .team/events.log"

# 002 · the gate in squad done
mkdir -p .team/tasks
cat >.team/tasks/T-300.md <<'BRIEF'
# T-300: probe
## Acceptance
| # | Requirement | How to check it |
|---|---|---|
| 1 | a | `true` |
| 2 | b | `true` |
## Dev check
`test -f ok.txt`
## Check command
`true`
BRIEF
printf 'STATUS: DONE\nAcceptance:\n| # | Result | Evidence |\n|---|---|---|\n| 1 | pass | exit 0 |\n' >.team/reports/T-300-dev.md
check "done refuses DONE when a row of the brief is missing" refuses "$squad" "done" dev-a T-300 DONE
printf '| 2 | fail | 16 px, expected 18 |\n' >>.team/reports/T-300-dev.md
check "done refuses DONE when a row failed" refuses "$squad" "done" dev-a T-300 DONE
sed -i.bak 's/| 2 | fail .*/| 2 | pending | dark mode: tester |/' .team/reports/T-300-dev.md && rm -f .team/reports/T-300-dev.md.bak
check "done refuses DONE when the dev check fails" refuses "$squad" "done" dev-a T-300 DONE
touch "$tmp/proj4-team/dev-a/ok.txt"; reset_log
check "done accepts DONE with every row and a passing dev check" "$squad" "done" dev-a T-300 DONE
check "the lead hears which rows are not verified" grep -q 'not verified: rows 2(pending)' "$MOCK_LOG"
check "BLOCKED always goes through" "$squad" "done" dev-a T-301 BLOCKED
printf 'RESULT: PASS\nAcceptance:\n| # | Result | Value |\n|---|---|---|\n| 1 | pass | x |\n| 2 | FAIL | y |\n' >.team/reports/T-300-test.md
check "done refuses the tester's PASS with a failed row" refuses "$squad" "done" tester T-300 PASS
printf 'RESULT: PASS\nAcceptance:\n| # | Result | Value |\n|---|---|---|\n| 1 | pass | Acceptance test exited 0 |\n| 2 | **fail** | y |\n' >.team/reports/T-300-test.md
check "a bold fail is still a fail" refuses "$squad" "done" tester T-300 PASS
printf 'RESULT: PASS\nAcceptance:\n| # | Result | Value |\n|---|---|---|\n| 1 | pass | Acceptance test exited 0 |\n| 2 | looks fine | y |\n' >.team/reports/T-300-test.md
check "a result that is none of the five words is refused" sh -c "! '$squad' done tester T-300 PASS 2>&1 | grep -q 'has no valid result' && exit 1 || exit 0"
printf 'RESULT: PASS\nAcceptance:\n| # | Result | Value |\n|---|---|---|\n| 1 | pass | Acceptance test exited 0 |\n| 2 | `pass` | y |\n' >.team/reports/T-300-test.md
check "evidence that says Acceptance keeps its row, and code-formatted pass counts" "$squad" "done" tester T-300 PASS
check "done refuses a task id with markup" refuses "$squad" "done" dev-a '<script>' DONE
reset_log
check "a reviewer's done with no review file yet still reaches the lead" sh -c "'$squad' done rev-gpt T-302 CHANGES >/dev/null 2>&1; grep -q 'agent prompt lead \[squad\] rev-gpt finished T-302: CHANGES' '$MOCK_LOG' && grep -q ' rev-gpt T-302 CHANGES' .team/events.log"
check "the tester's contract is logged" sh -c "printf 'CONTRACT\n' >.team/reports/T-300-contract.md && '$squad' done tester T-300 CONTRACT >/dev/null && grep -q ' tester T-300 CONTRACT report=T-300-contract.md' .team/events.log"
check "the task template has dev check, consumers, outside breaks and red run" sh -c "for h in 'Dev check' 'Consumers to run' 'If a check outside your files breaks' 'Red run'; do grep -q \"## \$h\" .team/tasks/_TEMPLATE.md || exit 1; done"
check "the protocol defines the five results" grep -qF '`inconclusive`' .team/PROTOCOL.md
check "the tester writes the contract before the dev starts" grep -qF 'The contract (before the dev starts)' .team/roles/tester.md

# 003 · the observer and report tabs
layout_up 160
check "the observer gets its own tab" grep -q 'tab create --workspace w2 --label observer' "$MOCK_LOG"
check "the observer tab runs the watcher that starts its passes" grep -qF "$squad_abs watch --observe" "$MOCK_LOG"
check "the report gets its own tab, live" sh -c "grep -q 'tab create --workspace w2 --label report' '$MOCK_LOG' && grep -qF '$squad_abs report --live' '$MOCK_LOG'"
check "the tabs come in order: review, changes, observer, report" sh -c "grep -o 'label [a-z]*' '$MOCK_LOG' | tr '\n' ' ' | grep -q 'label review label changes label observer label report'"
check "the observer is not a reviewer pane" refuses grep -qE 'pane split .* --cwd [^ ]+ .*observer' "$MOCK_LOG"
check "the observer reads the devs' worktrees" grep -qE "^herdr agent start observer --kind claude .* --add-dir $tmp/proj4-team " "$MOCK_LOG"

# 003 · trouble: stalled, login; the observer's passes
reset_log; rm -rf .team/observer/.seen .team/observer/.alerted "$tmp/state"
printf '%s dev-a T-400 DISPATCH round=1\n' "$(date '+%Y-%m-%d %H:%M:%S')" >>.team/events.log
mkdir -p .team/observer/.seen && echo $(( $(date +%s) - 3600 )) >.team/observer/.seen/dev-a
check "a seat with an open task and no work is stalled" sh -c "MOCK_DYNAMIC=1 '$squad' watch --once | grep -q 'dev-a ○ stalled'"
check "the stall is logged once and the lead is told" sh -c "grep -q ' dev-a T-400 STALLED' .team/events.log && grep -q 'agent prompt lead \[squad\] dev-a is stalled on T-400' '$MOCK_LOG'"
MOCK_DYNAMIC=1 "$squad" watch --once >/dev/null
check "the lead is told only once" test "$(grep -c 'dev-a is stalled' "$MOCK_LOG")" = 1
reset_log; rm -rf .team/observer/.alerted
check "a sign-in error is named" sh -c "MOCK_DYNAMIC=1 MOCK_PANE_TEXT='API Error: 403 · Please run /login' '$squad' watch --once | grep -q 'dev-a ○ login'"
reset_log; rm -rf .team/observer/.alerted
login_out=$(MOCK_DYNAMIC=1 MOCK_PANE_TEXT='Added the /login route' "$squad" watch --once)
check "a pane that only mentions /login is not a sign-in error" refuses grep -qF 'dev-a ○ login' <<<"$login_out"
check "the watcher records each running seat's conversation from herdr" sh -c "MOCK_AGENTS='{\"result\":{\"agents\":[{\"name\":\"rev-gpt\",\"agent_status\":\"idle\",\"agent_session\":{\"value\":\"cdx-0001\"}}]}}' '$squad' watch --once >/dev/null && grep -qx cdx-0001 .team/seats/rev-gpt.session"
reset_log; rm -f .team/observer/.last-pass .team/observer/.pass
check "the watcher starts the observer's first pass" sh -c "MOCK_DYNAMIC=1 '$squad' watch --once --observe >/dev/null && grep -q 'agent prompt observer Observer pass 1 (first pass)' '$MOCK_LOG' && grep -q ' observer - OBSERVE pass=1' .team/events.log"
reset_log
check "no second pass while nothing happened" sh -c "MOCK_DYNAMIC=1 '$squad' watch --once --observe >/dev/null; ! grep -q 'Observer pass 2' '$MOCK_LOG'"
printf '%s lead T-401 MERGE abc\n' "$(date '+%Y-%m-%d %H:%M:%S')" >>.team/events.log
check "a merge starts the next pass" sh -c "MOCK_DYNAMIC=1 '$squad' watch --once --observe >/dev/null; grep -q 'Observer pass 2 (new events)' '$MOCK_LOG'"
printf '# Now — pass 2\nLargest loss: 45 min\n' >.team/observer/NOW.md; echo 0 >.team/observer/.last-pass; reset_log
check "a loss over 30 min gets a deep pass on the stronger model" sh -c "MOCK_DYNAMIC=1 '$squad' watch --once --observe >/dev/null; grep -q 'agent prompt observer /model claude-opus-5-5' '$MOCK_LOG' && grep -q 'deep pass' '$MOCK_LOG'"
echo 0 >.team/observer/.last-pass; reset_log
check "the pass after a deep pass is back on the observer's own model" sh -c "MOCK_DYNAMIC=1 '$squad' watch --once --observe >/dev/null; grep -q 'agent prompt observer /model claude-sonnet-5-5' '$MOCK_LOG'"
printf '# Now\nLargest loss: 5 min (T-012, at 14:30)\n' >.team/observer/NOW.md; echo 0 >.team/observer/.last-pass; rm -f .team/observer/.deep-for; reset_log
check "a small loss next to other numbers gets no deep pass" sh -c "MOCK_DYNAMIC=1 '$squad' watch --once --observe >/dev/null; ! grep -q 'agent prompt observer /model claude-opus' '$MOCK_LOG'"

# 004 · consult and decisions
cat >"$tmp/bin/codex" <<'CODEX'
#!/usr/bin/env bash
echo "codex $*" >>"$MOCK_LOG"
while [ $# -gt 0 ]; do [ "$1" = -o ] && { printf '### Options\n1. A\n### Recommendation\nA, per https://www.w3.org/WAI/WCAG22/\n' >"$2"; }; shift; done
CODEX
chmod +x "$tmp/bin/codex"; reset_log
check "consult runs GPT Sol read-only with web search and writes the file" sh -c "'$squad' consult --wait 'Which contrast rule applies?' src/a.css >/dev/null && test -s .team/consult/1.md"
check "consult passes the model, the effort and read-only" grep -qE '^codex --search exec -m gpt-6.1-sol -c model_reasoning_effort=medium -s read-only --skip-git-repo-check -o [^ ]+/consult/1.md.tmp You are a senior engineer' "$MOCK_LOG"
check "the consult prompt carries the question, the files and the source order" sh -c "grep -q '^Which contrast rule applies?' '$MOCK_LOG' && grep -q '^- src/a.css' '$MOCK_LOG' && grep -q 'W3C and WCAG' '$MOCK_LOG'"
check "the consult file names the question and the answer" sh -c "grep -q 'Question: Which contrast rule applies?' .team/consult/1.md && grep -q 'w3.org' .team/consult/1.md"
"$squad" consult 'first question' >/dev/null; "$squad" consult 'second question' >/dev/null; sleep 2
check "two consults started together get their own numbers" sh -c "grep -q 'Question: first question' .team/consult/2.md && grep -q 'Question: second question' .team/consult/3.md"
check "consult is in the events" sh -c "grep -q ' CONSULT n=1 Which contrast' .team/events.log && grep -q ' CONSULT_READY n=1' .team/events.log"
cat >>.team/DECISIONS.md <<'DEC'

## D-001 · Contrast of the muted text
- Time: 2026-11-13 16:00
- Question: Which ratio applies to the muted label?
- Options: 1. 4.5:1 2. 3:1
- Claude: 4.5:1, it is text
- GPT: consult/1.md — 4.5:1
- Sources: https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum (WCAG 2.2, read 2026-11-13)
- Decision: 4.5:1
- Why: SC 1.4.3 covers text
- Status: provisional — open decision for V!
DEC
check "decisions --check passes a full block" "$squad" decisions --check
check "decisions --check writes each decision into the ledger once" sh -c "'$squad' decisions --check >/dev/null; test \$(grep -c ' - DECISION D-001 provisional' .team/events.log) = 1"
check "the template's example block is not a decision" sh -c "test \"\$('$squad' decisions | wc -l | tr -d ' ')\" = 1"
printf '\n## D-002 · Half done\n- Time: 2026-11-13\n- Question: q\n- Options: o\n- Claude: c\n- GPT: none: not a real issue\n- Sources: s\n- Decision: d\n- Why:\n- Status: final\n' >>.team/DECISIONS.md
check "decisions --check fails a block with an empty field" refuses "$squad" decisions --check
cp .team/team.conf "$tmp/conf.keep"; printf 'consult claude -p\n' >>.team/team.conf
check "consult refuses an agent other than Codex" refuses "$squad" consult --wait 'x'
cp "$tmp/conf.keep" .team/team.conf

# 003/004/005 · the report page
cat >.team/events.log <<'EVENTS'
2026-11-13 10:00:00 dev-a T-500 DISPATCH round=1 u=10/5 c=20/3
2026-11-13 10:20:00 dev-a T-500 DONE report=T-500-dev.md u=14/5 c=23/3
2026-11-13 10:25:00 tester T-500 DISPATCH round=1
2026-11-13 10:40:00 tester T-500 FAIL report=T-500-test.md
2026-11-13 10:45:00 dev-a T-500 DISPATCH round=1 u=15/5
2026-11-13 10:55:00 dev-a T-500 DONE report=T-500-dev.md u=17/5
2026-11-13 11:00:00 tester T-500 DISPATCH round=1
2026-11-13 11:10:00 tester T-500 PASS report=T-500-test.md
2026-11-13 11:12:00 rev-gpt T-500 DISPATCH round=1
2026-11-13 11:20:00 rev-gpt T-500 APPROVE report=T-500-review-1.md
2026-11-13 11:30:00 lead T-500 MERGE abc123
EVENTS
printf '# Now — pass 3\nLargest loss: 12 min\nT-500 waited 5 min for the tester.\n' >.team/observer/NOW.md
printf '## S-1 · Batch the tester queue\n- Status: open\n- Problem: queue\n' >.team/observer/SUGGESTIONS.md
html=$("$squad" report)
check "report writes one HTML page" test -s "$html"
check "the page has its seven tabs, To test first" sh -c "for t in To-test Decisions Observer Timeline QA Cost Events; do grep -q \"data-t=.\$t.\" '$html' || exit 1; done"
check "the page shows each decision with its status and the GPT consult" sh -c "grep -q 'D-001' '$html' && grep -q 'open decision for V!' '$html' && grep -q 'GPT consult (consult/1.md)' '$html'"
check "the page shows the observer's now and suggestions" sh -c "grep -q 'T-500 waited 5 min for the tester' '$html' && grep -q 'Batch the tester queue' '$html'"
check "the timeline has the task's minutes: total 90, dev 30, test 25, review 8" grep -qE '<tr><td>T-500</td><td>merged</td><td class=n>90</td><td class=n>30</td><td class=n>25</td><td class=n>8</td>' "$html"
check "the cost tab sums the seat minutes and the Claude and Codex usage points" grep -qE '<tr><td>T-500</td><td class=n>63</td><td class=n>6</td><td class=n>3</td></tr>' "$html"
check "the live report shows the cost too" sh -c "printf q | '$squad' report --live | grep -qE 'T-500 +merged .*\| 6 · 3'"
check "an event records Codex usage when Codex has data" sh -c "CODEX_HOME='$cx' '$squad' done dev-a T-303 BLOCKED >/dev/null; grep -E ' dev-a T-303 BLOCKED .* c=42/7' .team/events.log"
check "the QA tab counts the tester's FAIL" grep -qE '<tr><td>T-500</td><td>[a-z]+</td><td class=n>[0-9]+</td><td class=n>0</td><td class=n>1</td>' "$html"
check "the page escapes HTML in the files" sh -c "printf '<script>x</script>\n' >>.team/observer/NOW.md; '$squad' report >/dev/null; ! grep -q '<script>x' '$html'"
printf 'see http://x"onmouseover="alert(1) now\n' >>.team/observer/NOW.md
printf '\n## D-9<b>x</b> · t\n- Status: final\n' >>.team/DECISIONS.md
"$squad" report >/dev/null
check "a quote in a link cannot add an attribute" refuses grep -q '" *onmouseover=' "$html"
check "a decision id with markup is escaped" refuses grep -q 'D-9<b>' "$html"
printf '## S-1 · Batch\n- Status: adopted\n' >.team/observer/SUGGESTIONS.md
check "the live report runs with no open suggestion" sh -c "printf q | '$squad' report --live | grep -q 'OPEN SUGGESTIONS' "
check "init copies the lessons file" test -f .team/LESSONS.md
printf '10:00:00 dev-a T-9 DONE\n10:30:00 tester T-9 PASS\n' >.team/events.log
check "the report reads an older events.log (time only)" sh -c "'$squad' report >/dev/null && grep -q '<td>T-9</td>' '$html'"

# 006 · one herdr session per repository, and resume
reset_log
check "outside herdr, up brings the team up in the repository's own session" sh -c "env -u HERDR_ENV SQUAD_NO_ATTACH=1 '$squad' up >/dev/null 2>&1; grep -q 'sock=$tmp/home/.config/herdr/sessions/proj4/herdr.sock' '$MOCK_LOG'"
reset_log
check "outside herdr, up then attaches the session" sh -c "env -u HERDR_ENV '$squad' up >/dev/null 2>&1; grep -q '^herdr session attach proj4' '$MOCK_LOG'"
check "inside another repository's session, up refuses and names the session" sh -c "echo /x.sock >.team/herdr.sock; HERDR_SOCKET_PATH=/other/herdr.sock '$squad' up 2>&1 | grep -q 'herdr session attach proj4'"
rm -f .team/herdr.sock
check "a Claude seat records its session id from its SessionStart hook" sh -c "echo '{\"session_id\":\"11111111-2222-3333-4444-555555555555\",\"source\":\"clear\"}' | '$squad' session-id dev-b && grep -qx 11111111-2222-3333-4444-555555555555 .team/seats/dev-b.session"
check "the session-id hook never fails" sh -c "echo 'not json' | '$squad' session-id dev-b"
check "Claude seats start with the hook settings" grep -qE "^herdr agent start dev-b --kind claude .* --settings $tmp/proj4/.team/seats/dev-b.settings.json" "$MOCK_LOG"
check "the settings run squad session-id for the seat" sh -c "jq -e '.hooks.SessionStart[0].hooks[0].command | contains(\"session-id\") and contains(\"dev-b\")' .team/seats/dev-b.settings.json"
mkdir -p "$tmp/home/.claude/projects/x" && : >"$tmp/home/.claude/projects/x/11111111-2222-3333-4444-555555555555.jsonl"
echo 22222222-0000-0000-0000-000000000000 >.team/seats/dev-c.session
mkdir -p "$CODEX_HOME/sessions/2026/11/13"
printf '{"type":"session_meta","payload":{"id":"cdx-0001"}}\n' >"$CODEX_HOME/sessions/2026/11/13/rollout-2026-11-13T10-00-00-cdx-0001.jsonl"
printf '{"type":"session_meta","payload":{"id":"cdx-other"}}\n' >"$CODEX_HOME/sessions/2026/11/13/rollout-2026-11-13T11-00-00-cdx-other.jsonl"
layout_up 160
check "after a restart a Claude seat resumes its own conversation" grep -qE '^herdr agent start dev-b --kind claude .* -- --resume 11111111-2222-3333-4444-555555555555 --model claude-opus-5-5' "$MOCK_LOG"
check "a seat whose conversation is gone starts fresh and says so" sh -c "grep -qE '^herdr agent start dev-c --kind claude .* -- --model' '$MOCK_LOG' && grep -q ' dev-c - FRESH_START' .team/events.log"
check "the Codex reviewer resumes its own recorded session, not a newer one" grep -qE '^herdr agent start rev-gpt --kind codex .* -- resume cdx-0001 -m gpt-6.1-sol' "$MOCK_LOG"
check "a restart is logged with the resumed seats" grep -qE ' squad - RESTART resumed: .*dev-b' .team/events.log
reset_log; rm -f .team/.briefed/*
SQUAD_FRESH=1 MOCK_WIDTH=160 "$squad" up >/dev/null 2>&1
check "up --fresh starts new conversations" refuses grep -qE '^herdr agent start .* (--resume|-- resume) ' "$MOCK_LOG"
reset_log; rm -f .team/.briefed/*
MOCK_FAIL_RESUME=1 MOCK_WIDTH=160 "$squad" up >/dev/null 2>&1
check "a refused resume falls back to a fresh start once, and says so" sh -c "grep -qE '^herdr agent start dev-b .* -- --resume ' '$MOCK_LOG' && grep -qE '^herdr agent start dev-b --kind claude .* -- --model claude-opus-5-5' '$MOCK_LOG' && grep -q ' dev-b - FRESH_START resume of' .team/events.log"
reset_log; rm -f .team/.briefed/*
check "a layout with no client attached (height 0) still starts" env MOCK_WIDTH=0 MOCK_HEIGHT=0 "$squad" up
sleep 30 & other_up=$!; ln -s "$other_up" .team/up.lock
check "a second squad up refuses while one runs" sh -c "'$squad' up 2>&1 | grep -q \"another 'squad up' for this team is running (pid $other_up\""
kill "$other_up"; wait "$other_up" 2>/dev/null || true; rm -f .team/up.lock
reset_log; rm -f .team/.briefed/*
taken_out=$(MOCK_TAKEN=dev-b "$squad" up 2>&1 || true)
check "a seat name taken in another workspace is named as such" grep -q 'already runs a seat named .dev-b. (usually a second .squad up.)' <<<"$taken_out"
check "up removes its lock when it ends" test ! -L .team/up.lock

# ---- 008 · snapshot runs, process groups, sample mode, team.conf kept up to date --------
cd "$tmp/proj4"
dc="$tmp/proj4-team/dev-c"
git -C "$dc" switch -q -c task/T-800 team/integration
echo one >"$dc/marker.txt"; git -C "$dc" add marker.txt; git -C "$dc" commit -qm "T-800 marker"
want=$(git -C "$dc" rev-parse --short HEAD)
sed -i.bak "s#^setup.*#setup echo ran >>'$tmp/setup-runs'#" .team/team.conf && rm -f .team/team.conf.bak; rm -f "$tmp/setup-runs"
out=$( cd "$dc" && "$squad" heavy dev-c T-800 -- sh -c 'git rev-parse --short HEAD; pwd -P' 2>/dev/null )
check "a dev's run happens in its snapshot, at the commit it recorded" sh -c "printf '%s' \"\$1\" | grep -qx '$want' && printf '%s' \"\$1\" | grep -qx '$tmp/proj4-team/.runs/dev-c'" _ "$out"
check "the run names its snapshot" grep -qE " dev-c T-800 HEAVY_START sha=$want limit=10m in=.runs/dev-c " .team/events.log
( cd "$dc" && "$squad" heavy dev-c T-801 -- sh -c 'sleep 2; cat marker.txt' >"$tmp/snapout" 2>/dev/null ) & hb=$!
sleep 1; echo two >"$dc/marker.txt"; wait "$hb"; git -C "$dc" checkout -q marker.txt
check "the dev's worktree can change while its run reads the snapshot" grep -qx one "$tmp/snapout"
check "the setup ran once in the snapshot" test "$(wc -l <"$tmp/setup-runs" | tr -d ' ')" = 1
"$squad" heavy dev-c T-802 -- true >/dev/null 2>&1
check "the setup does not run again while no lockfile changed" test "$(wc -l <"$tmp/setup-runs" | tr -d ' ')" = 1
echo '{}' >"$dc/package-lock.json"; git -C "$dc" add package-lock.json; git -C "$dc" commit -qm lock
"$squad" heavy dev-c T-803 -- true >/dev/null 2>&1
check "a changed lockfile runs the setup again" test "$(wc -l <"$tmp/setup-runs" | tr -d ' ')" = 2
sed -i.bak "s#^setup.*#setup#" .team/team.conf && rm -f .team/team.conf.bak
mkdir -p "$dc/sub"; echo x >"$dc/sub/f"; git -C "$dc" add sub; git -C "$dc" commit -qm sub
check "the run starts in the same subfolder of the snapshot" sh -c "cd '$dc/sub' && '$squad' heavy dev-c T-804 -- pwd -P 2>/dev/null | grep -qx '$tmp/proj4-team/.runs/dev-c/sub'"

# process groups
rc=0; SQUAD_HEAVY_LIMIT_SECONDS=1 "$squad" heavy tester T-805 -- sh -c 'sleep 42.25 & sleep 42.5' >/dev/null 2>&1 || rc=$?
check "a timed-out run ends every process of its group" sh -c "test $rc = 124 && ! pgrep -f 'sleep 42[.]25' >/dev/null && ! pgrep -f 'sleep 42[.]5' >/dev/null"
check "a stopped run never passes, even when it exits 0 on the signal" sh -c "SQUAD_HEAVY_LIMIT_SECONDS=1 '$squad' heavy tester T-806 -- sh -c 'trap \"exit 0\" TERM; sleep 43.1 & wait' >/dev/null 2>&1; test \$? = 124"
perl -e 'setpgrp(0, 0); exec "sh", "-c", "sleep 44.4 & sleep 44.5"' & orphan=$!
sleep 0.5; ln -s "dev-a:999999:$(date +%s)" "$HV"/lock; printf '%s %s\n' "$orphan" "$(ps -o lstart= -p "$orphan" | tr -s ' ' | sed 's/^ //; s/ $//')" >"$HV"/lock.pgid
check "a dead owner's leftover run is ended before the lock is free" sh -c "'$squad' heavy tester T-807 -- true >/dev/null 2>&1 && ! pgrep -f 'sleep 44.[45]' >/dev/null"
wait "$orphan" 2>/dev/null || true

# sample mode
s1=$("$squad" heavy dev-c T-808 --sample -- echo '--shard={shard}' 2>/dev/null)
s2=$("$squad" heavy dev-c T-808 --sample -- echo '--shard={shard}' 2>/dev/null)
check "--sample puts one fixed shard of ten in the command" sh -c "printf '%s' \"\$1\" | grep -qxE -- '--shard=([1-9]|10)/10' && test \"\$1\" = \"\$2\"" _ "$s1" "$s2"
check "the sample is in the events" grep -qE ' dev-c T-808 HEAVY_START .* sample=([1-9]|10)/10 ' .team/events.log
check "--sample without {shard} is refused" sh -c "'$squad' heavy dev-c T-809 --sample -- echo all 2>&1 | grep -q 'needs {shard}'"
check "{shard} without --sample is refused" refuses "$squad" heavy dev-c T-809 -- echo '--shard={shard}'

# update-conf
cd "$tmp"; mkdir -p old && ( cd old && git init -q && git commit -q --allow-empty -m i )
mkdir -p old/.team
cat >old/.team/team.conf <<'OLDCONF'
seat lead    claude  lead    -  --model claude-fable-5-2
seat dev-a   claude  dev     -  --model claude-opus-5-5 --effort medium
seat dev-b   claude  dev     -  --model claude-opus-5-5 --effort medium
seat tester  claude  tester  -  --model claude-sonnet-5-5 --effort low

base team/integration
rounds 4
setup npm ci
OLDCONF
cd old
check "update-conf adds what an old team.conf lacks and says so" sh -c "'$squad' update-conf | grep -q 'line(s) added from preset .default.'"
check "it adds the new settings" sh -c "for k in heavy_timeout heavy_timeout_dev sample_percent verify_hook consult stall_minutes observe_minutes escalate_model; do grep -qE \"^\$k \" .team/team.conf || exit 1; done"
check "it adds the GPT reviewer for the team's own devs, and the observer" sh -c "grep -qE '^seat rev-gpt codex reviewer dev-a,dev-b -m gpt-6.1-sol' .team/team.conf && grep -qE '^seat +observer +claude +observer' .team/team.conf"
check "it keeps what was there" sh -c "grep -qx 'rounds 4' .team/team.conf && grep -qx 'setup npm ci' .team/team.conf && test \$(grep -c '^rounds' .team/team.conf) = 1"
check "the updated file is valid" "$squad" status
check "a second run adds nothing" sh -c "'$squad' update-conf | grep -q 'nothing to add'"
printf 'seat lead claude lead -\nseat dev-a claude dev -\nupgrade off\n' >.team/team.conf
"$squad" update-conf >/dev/null
check "upgrade off leaves team.conf alone" test "$(wc -l <.team/team.conf | tr -d ' ')" = 3
printf 'seat lead claude lead -\nseat dev-a claude dev -\nseat tester claude tester -\n' >.team/team.conf
"$squad" update-conf >/dev/null
check "an old unmarked one-dev team is taken as small: settings, no new seats" sh -c "head -1 .team/team.conf | grep -qx '# preset: small' && ! grep -qE 'reviewer|observer' .team/team.conf && grep -q '^heavy_timeout_dev' .team/team.conf"
printf '# preset: small\nseat lead claude lead -\nseat dev-a claude dev -\nseat tester claude tester -\n' >.team/team.conf
"$squad" update-conf >/dev/null
check "a small team gets the settings but no reviewer or observer" sh -c "! grep -qE 'reviewer|observer' .team/team.conf && grep -q '^heavy_timeout_dev' .team/team.conf"
check "init records the preset of a new team" sh -c "cd '$tmp' && '$squad' new proj8 --preset large >/dev/null && head -1 proj8/.team/team.conf | grep -qx '# preset: large'"
mkdir -p "$XDG_CONFIG_HOME/squad"; printf 'seat lead claude lead -\nseat dev-a claude dev -\nseat dev-b claude dev -\nseat dev-c claude dev -\nseat tester claude tester -\n' >"$XDG_CONFIG_HOME/squad/team.conf"
check "init from an old personal default brings it up to date" sh -c "cd '$tmp' && '$squad' new proj9 >/dev/null && grep -qE '^seat rev-gpt codex reviewer dev-a,dev-b,dev-c ' proj9/.team/team.conf && grep -q '^verify_hook off' proj9/.team/team.conf"
rm -f "$XDG_CONFIG_HOME/squad/team.conf"
cd "$tmp/proj4"
# GPT review of 007-008
cd "$tmp/proj4"
( cd "$dc" && "$squad" heavy dev-c T-820 -- sh -c 'sleep 2; cat marker.txt' >"$tmp/run1" 2>/dev/null ) & r1=$!
for _ in $(seq 1 100); do grep -q ' dev-c T-820 HEAVY_START ' .team/events.log && break; sleep 0.1; done   # run 1 holds the lock and its snapshot
echo three >"$dc/marker.txt"; git -C "$dc" commit -qam three
( cd "$dc" && "$squad" heavy dev-c T-821 -- cat marker.txt >"$tmp/run2" 2>/dev/null ) & r2=$!
wait "$r1" "$r2"
check "a second run of the same seat waits and does not reset the snapshot in use" sh -c "grep -qx one '$tmp/run1' && grep -qx three '$tmp/run2'"
SQUAD_STOP_GRACE=1 "$squad" heavy tester T-822 -- sh -c '(trap "" TERM; sleep 45.5) & exit 0' >/dev/null 2>&1 || true
check "a child that ignores TERM after its leader ended is stopped too" sh -c "! pgrep -f 'sleep 45[.]5' >/dev/null && test ! -L $HV/lock"
sleep 60 & holder=$!; ln -s "dev-a:$holder:$(( $(date +%s) - 400 )):600" "$HV"/lock
"$squad" heavy tester T-823 -- true >/dev/null 2>&1 & w=$!
sleep 2
check "a live run within its own limit is not taken for stale" sh -c "readlink $HV/lock | grep -q '^dev-a:$holder:'"
kill "$holder"; wait "$holder" "$w" 2>/dev/null || true
git -C "$tmp/proj4" worktree remove --force "$tmp/proj4-team/.runs/dev-c"
sed -i.bak "s#^setup.*#setup echo ran >>'$tmp/setup-runs'#" .team/team.conf && rm -f .team/team.conf.bak
"$squad" heavy dev-c T-824 -- true >/dev/null 2>&1
check "a new snapshot always runs its setup" test "$(wc -l <"$tmp/setup-runs" | tr -d ' ')" = 3
sed -i.bak "s#^setup.*#setup#" .team/team.conf && rm -f .team/team.conf.bak
sed -i.bak 's/^sample_percent .*/sample_percent 51/' .team/team.conf && rm -f .team/team.conf.bak
check "a share over 50 % still samples (2 shards, not the whole suite)" sh -c "'$squad' heavy dev-c T-825 --sample -- echo '--shard={shard}' 2>/dev/null | grep -qxE -- '--shard=[12]/2'"
sed -i.bak 's/^sample_percent .*/sample_percent 10/' .team/team.conf && rm -f .team/team.conf.bak
printf '19:00:00 dev-a 001 DONE\n' >>.team/events.log
printf '%s tester T-830 DISPATCH round=1\n' "$(date '+%Y-%m-%d %H:%M:%S')" >>.team/events.log
check "the tester's contract dispatch does not open the gate for the dev" refuses env MOCK_DYNAMIC=1 SQUAD_DISPATCH_WAIT=2 "$squad" dispatch dev-a T-830
sleep 60 & reused=$!; printf '%s Mon Jan  1 00:00:00 2001\n' "$reused" >"$HV"/lock.pgid; ln -s "dev-a:999999:$(date +%s):600" "$HV"/lock
"$squad" heavy tester T-831 -- true >/dev/null 2>&1
check "a reused pid's group is not killed by the stale-lock cleanup" kill -0 "$reused"
kill "$reused"; wait "$reused" 2>/dev/null || true
check "only the exact task id is taken as under way (001 is not 1)" refuses env MOCK_DYNAMIC=1 SQUAD_DISPATCH_WAIT=2 "$squad" dispatch dev-a 1
check "squad clean removes the snapshots" sh -c "cp -R . '$tmp/p4copy' >/dev/null 2>&1; true; '$squad' clean >/dev/null 2>&1; test ! -d '$tmp/proj4-team/.runs'"
cd "$tmp/old"; printf 'seat lead claude lead -\n  upgrade off\n' >.team/team.conf; "$squad" update-conf >/dev/null
check "an indented upgrade off is honoured" test "$(wc -l <.team/team.conf | tr -d ' ')" = 2
cd "$tmp/proj4"
# CodeRabbit, PR #10
cd "$tmp/proj4"
check "the heavy lock is one for the machine: another repository sees this run" sh -c "'$squad' heavy tester T-840 -- sh -c 'cd \"$tmp/proj\" && \"$squad\" heavy --status' | grep -q 'lock: tester@proj4 since'"
rm -f .team/.briefed/*; MOCK_WIDTH=160 "$squad" up >/dev/null 2>&1 || true   # squad clean above removed the worktrees
sed -i.bak "s#^setup.*#setup sleep 30.17#" .team/team.conf && rm -f .team/team.conf.bak
git -C "$tmp/proj4" worktree remove --force "$tmp/proj4-team/.runs/dev-c" 2>/dev/null || true
setup_out=$(SQUAD_HEAVY_LIMIT_SECONDS=2 "$squad" heavy dev-c T-841 -- true 2>&1 || true)
check "a snapshot setup over the limit is stopped and nothing runs" sh -c "printf '%s' \"\$1\" | grep -q 'could not prepare the snapshot' && ! pgrep -f 'sleep 30[.]17' >/dev/null && test ! -L '$HV/lock'" _ "$setup_out"
sed -i.bak "s#^setup.*#setup#" .team/team.conf && rm -f .team/team.conf.bak
perl -e 'setpgrp(0, 0); exec "sh", "-c", "sleep 46.6 & exit 0"' & lead_pid=$!; wait "$lead_pid" 2>/dev/null || true
printf '%s %s\n' "$lead_pid" "Mon Jan  1 00:00:00 2001" >"$HV/lock.pgid"; ln -s "dev-a:999999:$(date +%s):600" "$HV/lock"
"$squad" heavy tester T-842 -- true >/dev/null 2>&1
check "a dead leader's surviving group members are stopped before the lock is free" sh -c "! pgrep -f 'sleep 46[.]6' >/dev/null"
check "the roadmap keeps the containers reminder" grep -qF 'one container per seat' "$here/../docs/ROADMAP.md"

# ---- 009 · the owner tests what can be seen and gives feedback ---------------------------
cd "$tmp/proj4"
check "the shipped presets set owner visual" sh -c "grep -qx 'owner visual' '$here/../presets/default.conf'"
"$squad" init >/dev/null 2>&1
check "with owner visual the lead decides what the eye cannot see" sh -c "grep -q 'A decision the eye cannot see' .team/roles/lead.md && ! grep -q 'The human owns every decision' .team/roles/lead.md && ! grep -q 'owner:' .team/roles/lead.md"
cp .team/team.conf "$tmp/conf.keep"; sed -i.bak 's/^owner .*/owner all/' .team/team.conf && rm -f .team/team.conf.bak; grep -q '^owner ' .team/team.conf || echo 'owner all' >>.team/team.conf
"$squad" init >/dev/null 2>&1
check "with owner all the v2 text stays" sh -c "grep -q 'The human owns every decision' .team/roles/lead.md && ! grep -q 'A decision the eye cannot see' .team/roles/lead.md"
cp "$tmp/conf.keep" .team/team.conf; "$squad" init >/dev/null 2>&1
cat >.team/DECISIONS.md <<'DEC'
# Decisions

## D-010 · Tooltip gap
- Time: 2026-11-13 20:00
- Question: 11 or 12 px?
- Options: 1. 11 2. 12
- Claude: 11, measured
- GPT: none: not a real issue
- Sources: reference/hive-ui-v1.1.html, computed
- Decision: 11 px
- Why: the preview wins
- Status: to test by V!
- See: overlays-tooltip--states, 1280 px, light and dark: the gap equals the preview's

## D-011 · Date picker wait
- Time: 2026-11-13 20:01
- Question: how long to wait
- Options: 1. 1 s 2. settle helper
- Claude: settle helper
- GPT: none: not a real issue
- Sources: react-aria 3.53.1 source
- Decision: settle helper
- Why: frames, not time
- Status: final
DEC
check "a decision to test with its See line passes the check" "$squad" decisions --check
check "the ledger names it to-test" grep -q ' - DECISION D-010 to-test' .team/events.log
html=$("$squad" report)
check "the To test tab lists the visual decision with where to look, not the final one" sh -c "sed -n '/id=To-test/,/<\\/section>/p' '$html' | grep -q 'overlays-tooltip--states' && ! sed -n '/id=To-test/,/<\\/section>/p' '$html' | grep -q 'D-011'"
check "the live view lists what to test" sh -c "printf q | '$squad' report --live | grep -q 'D-010 Tooltip gap — look: overlays-tooltip--states'"
printf '\n## D-012 · No place\n- Time: t\n- Question: q\n- Options: o\n- Claude: c\n- GPT: g\n- Sources: s\n- Decision: d\n- Why: w\n- Status: to test by V!\n' >>.team/DECISIONS.md
check "a decision to test without a See line is refused" refuses "$squad" decisions --check
check "with owner visual nothing in the lead role says to decide provisionally" refuses grep -q 'decide provisionally' .team/roles/lead.md
printf '\n## D-013 · No see, provisional\n- Time: t\n- Question: q\n- Options: o\n- Claude: c\n- GPT: g\n- Sources: s\n- Decision: keep the card\n- Why: w\n- Status: provisional — open decision for V!\n' >>.team/DECISIONS.md
"$squad" report >/dev/null
check "a decision without a See line keeps its columns in the To test tab" grep -qE '<td>D-013 · No see, provisional</td><td>-</td><td>keep the card</td>' "$html"
printf 'x\n<!-- owner:all -->\n<!-- owner:visual -->\nin\n<!-- /owner:visual -->\nleak\n<!-- /owner:all -->\n' >"$tmp/nested.md"
check "nested owner sections are a template error" sh -c "! '$squad' _owner-filter visual <'$tmp/nested.md' >'$tmp/nested.out' 2>/dev/null && ! grep -q leak '$tmp/nested.out'"
printf 'a\n<!-- owner:all -->\nhidden\n' >"$tmp/open.md"
check "an unclosed owner section is a template error" refuses "$squad" _owner-filter visual <"$tmp/open.md"
printf 'a\n<!-- owner:all -->\nold\n<!-- /owner:all -->\n<!-- owner:visual -->\nnew\n<!-- /owner:visual -->\nb\n' >"$tmp/ok.md"
check "a well-formed template keeps only its mode" sh -c "test \"\$('$squad' _owner-filter visual <'$tmp/ok.md' | tr '\n' ' ')\" = 'a new b '"
reset_log
check "squad feedback saves, logs and tells the lead" sh -c "'$squad' feedback 'The tooltip gap looks 1 px too tight in dark' | grep -q 'F-1 saved and sent' && grep -q '^## F-1 · ' .team/FEEDBACK.md && grep -q 'too tight in dark' .team/FEEDBACK.md && grep -q ' owner - FEEDBACK F-1 The tooltip gap' .team/events.log && grep -q 'agent prompt lead \[squad\] Feedback F-1 from V!' '$MOCK_LOG'"
printf 'Card raised: the shadow is too strong at 390 px\nCompare with the preview.\n' >"$tmp/fb.txt"
check "squad feedback --file takes a longer note as F-2" sh -c "'$squad' feedback --file '$tmp/fb.txt' >/dev/null && grep -q '^## F-2 · ' .team/FEEDBACK.md && grep -q 'Compare with the preview.' .team/FEEDBACK.md"
check "empty feedback is refused" refuses "$squad" feedback '   '
# root ignores folder write permissions: this case needs a non-root run
if [ "$(id -u)" -ne 0 ]; then
  chmod a-w .team
  check "a lock that cannot be created fails with a message instead of hanging" sh -c "SQUAD_MUTEX_TRIES=3 '$squad' feedback 'x' 2>&1 | grep -q 'cannot create the lock'"
  chmod u+w .team
fi
printf '## F-9 · pasted heading\nnote\n' >"$tmp/fb9.txt"; "$squad" feedback --file "$tmp/fb9.txt" >/dev/null
"$squad" feedback 'after a pasted heading' >/dev/null
check "feedback ids follow the highest F-number, not a line count" sh -c "grep -q '^## F-3 · ' .team/FEEDBACK.md && grep -B3 'after a pasted heading' .team/FEEDBACK.md | grep -q '^## F-10 · '"
check "the report shows the open feedback" sh -c "'$squad' report >/dev/null && grep -q 'too tight in dark' '$html'"
cd "$tmp/old"; printf 'seat lead claude lead -\nseat dev-a claude dev -\nseat dev-b claude dev -\nseat tester claude tester -\n' >.team/team.conf
"$squad" update-conf >/dev/null
check "update-conf gives an older team owner visual" grep -qx 'owner visual' .team/team.conf
cd "$tmp/proj4"

echo
echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
