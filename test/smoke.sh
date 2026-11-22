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
                  echo "{\"result\":{\"agents\":[{\"name\":\"dev-a\",\"agent_status\":\"$st\"},{\"name\":\"observer\",\"agent_status\":\"idle\"},{\"name\":\"lead\",\"agent_status\":\"working\"},{\"name\":\"tester\",\"agent_status\":\"${MOCK_TESTER:-idle}\"}]}}"
                # MOCK_AGENTS_GONE: the list once a seat was told to exit (/exit or /quit)
                elif [ -n "${MOCK_AGENTS_GONE:-}" ] && [ -e "$(dirname "$MOCK_LOG")/exited" ]; then echo "$MOCK_AGENTS_GONE"
                # MOCK_AGENTS_LATER: the list once a pane's process was read (a seat that changes state inside one tick)
                elif [ -n "${MOCK_AGENTS_LATER:-}" ] && [ -e "$(dirname "$MOCK_LOG")/pinfo" ]; then echo "$MOCK_AGENTS_LATER"
                elif [ -n "${MOCK_AGENTS:-}" ]; then echo "$MOCK_AGENTS"; else echo '{"result":{"agents":[]}}'; fi ;;
  # MOCK_PROMPT_SLEEP: the prompt takes this many seconds; MOCK_ON_PROMPT: a command that runs when a prompt arrives
  # ($3: the seat, $4: the text): a seat whose state or screen changes because of the prompt
  "agent prompt") if [ "$3" = "${MOCK_FAIL_PROMPT:-}" ]; then echo '{"error":"agent_not_found"}' >&2; exit 1; fi
                [ -z "${MOCK_PROMPT_SLEEP:-}" ] || sleep "$MOCK_PROMPT_SLEEP"
                [ -z "${MOCK_ON_PROMPT:-}" ] || eval "$MOCK_ON_PROMPT" >/dev/null 2>&1
                case "$4" in /exit|/quit) : >"$(dirname "$MOCK_LOG")/exited" ;; esac
                if [ "${MOCK_DYNAMIC:-}" = 1 ] && [ "$3" = dev-a ]; then
                    case "$4" in /*) echo idle ;; *) if [ "${MOCK_NEVER_WORK:-}" = 1 ]; then echo idle; else echo working; fi ;; esac >"$(dirname "$MOCK_LOG")/state"; fi
                  echo '{}' ;;
  # MOCK_PANE_FILE: every pane shows this file while it exists (a dialog that goes away during a test)
  # MOCK_PANE_ONLY: only this seat's pane shows MOCK_PANE_TEXT; every other pane shows an empty prompt
  "agent read") if [ -n "${MOCK_PANE_ONLY:-}" ] && [ "$3" != "$MOCK_PANE_ONLY" ]; then printf 'Claude Code\n❯ \n'
                elif [ -s "${MOCK_PANE_FILE:-}" ]; then cat "$MOCK_PANE_FILE"
                elif [ -n "${MOCK_PANE_TEXT:-}" ]; then echo "$MOCK_PANE_TEXT"
                elif [ "${MOCK_DYNAMIC:-}" = 1 ]; then st=$(cat "$(dirname "$MOCK_LOG")/state" 2>/dev/null || echo idle)
                  if [ "$st" = working ]; then printf '✻ Working… (esc to interrupt)\n❯ \n'; else printf 'Claude Code\n❯ \n'; fi
                fi ;;
  "agent send-keys") echo '{}' ;;
  # MOCK_BUSY_PANES: panes whose program runs; any other pane has only its shell
  # MOCK_CMDLINE: the command line of the program in every pane
  "pane process-info") [ -z "${MOCK_AGENTS_LATER:-}" ] || : >"$(dirname "$MOCK_LOG")/pinfo"
                       if [ -n "${MOCK_CMDLINE:-}" ]; then echo "{\"result\":{\"process_info\":{\"foreground_processes\":[{\"cmdline\":\"$MOCK_CMDLINE\"}]}}}"; exit 0; fi
                       case " ${MOCK_BUSY_PANES:-} " in *" $4 "*) echo "{\"result\":{\"process_info\":{\"foreground_processes\":[{\"cmdline\":\"-zsh -c /x/check.sh\"}]}}}" ;;
                         *) echo '{"result":{"process_info":{"foreground_processes":[{"cmdline":"-zsh"}]}}}' ;; esac ;;
  "config check") if [ "${MOCK_BAD_CONFIG:-}" = 1 ]; then echo '{"error":"bad config"}'; exit 1; fi; echo '{}' ;;
  # MOCK_NOTIFY_SLEEP: the notification takes this many seconds
  "notification show") [ -z "${MOCK_NOTIFY_SLEEP:-}" ] || sleep "$MOCK_NOTIFY_SLEEP"
                if [ -n "${MOCK_NOTIFY:-}" ]; then echo "$MOCK_NOTIFY"; else echo '{}'; fi ;;
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
# the operating system's notification (notify_os): a stand-in that only records the call
printf '#!/bin/sh\necho "osascript $*" >>"$MOCK_LOG"\n' >"$tmp/bin/osascript"; chmod +x "$tmp/bin/osascript"

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
wait_log() { local k=0; until log_has "$1"; do k=$((k + 1)); [ "$k" -lt 80 ] || return 1; sleep 0.1; done; }   # a line a background command writes
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
check "codex seats get a short pointer to their seat file as developer_instructions" grep -qE '^herdr agent start lead .* -c developer_instructions="You are seat lead on an agent team. Before anything else, read [^ ]+/seats/lead[^ ]*: it is your identity' "$MOCK_LOG"
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
# 019: after a herdr restart the helper panes hold only a shell: resume runs them again
reset_log
hp='{"result":{"panes":[{"pane_id":"w2:p1","label":"lead"},{"pane_id":"w2:p2","label":"dev-a"},{"pane_id":"w2:p3","label":"dev-b"},{"pane_id":"w2:p4","label":"rev-sol"},{"pane_id":"w2:p5","label":"rev-claude"},{"pane_id":"w2:p6","label":"tester"},{"pane_id":"w2:p7","label":"watch"},{"pane_id":"w2:p8","label":"report"},{"pane_id":"w2:p9","label":"changes"}]}}'
env MOCK_WS="$ws" MOCK_PANES="$hp" MOCK_AGENTS="$agents" MOCK_BUSY_PANES="w2:p8" "$squad" up >/dev/null 2>&1 || true
check "019: resume starts the strip again in a pane that holds only a shell" grep -q 'pane run w2:p7 .*/squad watch sock' "$MOCK_LOG"
check "019: resume starts lazygit again in its pane" grep -q 'pane run w2:p9 lazygit' "$MOCK_LOG"
check "019: a helper pane whose program runs is left alone" refuses grep -q 'pane run w2:p8' "$MOCK_LOG"

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
check "the lead merges through squad merge" grep -qF "$squad_abs merge CANDIDATE-<n>" .team/roles/lead.md
check "squad git runs an allowed write" sh -c "cd '$tmp/proj-team/dev-a' && '$squad' git switch -c t-probe >/dev/null 2>&1 && git branch --show-current | grep -qx t-probe"
# 022: the integration branch, and only it, is pushed to origin, with no arguments
git init -q --bare "$tmp/origin.git"; git remote add origin "$tmp/origin.git"
check "022: squad git push refuses a task branch" refuses sh -c "cd '$tmp/proj-team/dev-a' && '$squad' git push"
check "022: squad git push refuses main" refuses sh -c "cd '$tmp/proj' && '$squad' git push"
check "022: squad git push refuses any argument" refuses sh -c "cd '$tmp/proj-team/integration' && '$squad' git push --force"
check "022: squad git push refuses a refspec" refuses sh -c "cd '$tmp/proj-team/integration' && '$squad' git push origin team/integration:main"
cp .team/team.conf "$tmp/team.conf.bak"; echo "base team/custom" >>.team/team.conf
check "022: squad git push follows the base in team.conf (team/integration is not it any more)" refuses sh -c "cd '$tmp/proj-team/integration' && '$squad' git push"
echo "base main" >>.team/team.conf
check "022: squad git push refuses a base named main" refuses sh -c "cd '$tmp/proj' && '$squad' git push"
cp "$tmp/team.conf.bak" .team/team.conf; echo "base production" >>.team/team.conf
git switch -q -c production
check "022: squad git push refuses a base named production" refuses "$squad" git push
git switch -q -
cp "$tmp/team.conf.bak" .team/team.conf
check "022: a refused push leaves the remote empty" test -z "$(git -C "$tmp/origin.git" for-each-ref)"
git -C "$tmp/proj-team/integration" -c user.name=t -c user.email=t@t tag -a v-probe -m probe
git config push.followTags true
check "022: squad git push pushes the integration branch" sh -c "cd '$tmp/proj-team/integration' && '$squad' git push >/dev/null 2>&1"
git config --unset push.followTags
check "022: origin has the integration branch, and only it" test "$(git -C "$tmp/origin.git" for-each-ref --format='%(refname)')" = refs/heads/team/integration
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
check "the shipped default has a GPT Sol reviewer at medium effort" grep -qE '^seat +rev-gpt +codex +reviewer +dev-a,dev-b,dev-c +-m gpt-6.1-sol -c model_reasoning_effort=medium -a never$' "$shipped/default.conf"
check "the shipped default has an observer on Sonnet" grep -qE '^seat +observer +claude +observer +- +--model claude-sonnet-5-5' "$shipped/default.conf"
check "every shipped preset has one lead and a tester" sh -c "for f in '$shipped'/*.conf; do test \"\$(grep -cE '^seat .* lead ' \$f)\" = 1 && grep -qE '^seat .* tester ' \$f || exit 1; done"
check "every shipped preset turns the verify hook off and consults GPT Sol" sh -c "for f in '$shipped'/*.conf; do grep -qx 'verify_hook off' \$f && grep -q '^consult codex --search exec -m gpt-6.1-sol' \$f || exit 1; done"
cd "$tmp"
check "new creates a project with the shipped default team" "$squad" new proj4
cd proj4; reset_log
check "init creates the goal, the decisions log and the task template" test -f .team/GOAL.md -a -f .team/DECISIONS.md -a -f .team/tasks/_TEMPLATE.md
check "a new team starts with a draft plan (no task before the owner approves it)" grep -qx 'Status: draft' .team/PLAN.md
printf '# Plan: tests\n\nStatus: approved by the owner 2026-11-16 10:00\n' >.team/PLAN.md   # the dispatch tests below start tasks
mkdir -p "$HOME/.config/squad/approvals"; { shasum -a 256 .team/PLAN.md 2>/dev/null || sha256sum .team/PLAN.md; } | cut -d' ' -f1 >"$HOME/.config/squad/approvals/proj4-PLAN.md.sha256"   # the owner's seal
check "up starts the shipped team" "$squad" up
check "the lead runs the strongest model and may read the devs' worktrees" grep -qE "^herdr agent start lead --kind claude .* -- --model claude-fable-5-2 --add-dir $tmp/proj4/.team --add-dir [^ ]+ --add-dir $tmp/proj4-team " "$MOCK_LOG"
check "devs run at medium effort" grep -qE '^herdr agent start dev-a --kind claude .* -- --model claude-opus-5-5 --effort medium ' "$MOCK_LOG"
check "devs get no access to other worktrees" refuses grep -qE "^herdr agent start dev-a .* --add-dir $tmp/proj4-team " "$MOCK_LOG"
check "the tester is the cheap seat" grep -qE '^herdr agent start tester --kind claude .* -- --model claude-sonnet-5-5 --effort low ' "$MOCK_LOG"
check "nine seats start, the reviewer on Codex" sh -c "test \"\$(grep -c '^herdr agent start' '$MOCK_LOG')\" = 9 && grep -qE '^herdr agent start rev-gpt --kind codex .* -- -m gpt-6.1-sol -c model_reasoning_effort=medium ' '$MOCK_LOG'"
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
printf 'echo one\nsh -c "exit 3"\n# a comment\necho three\n' >"$tmp/batch.cmds"
brc=0; "$squad" heavy tester CANDIDATE-90 --batch "$tmp/batch.cmds" >/dev/null 2>&1 || brc=$?
check "a batch runs every command of a candidate under one lock, each with its own start and end" sh -c "grep -c ' tester CANDIDATE-90 HEAVY_START .*step=[123]/3' .team/events.log | grep -qx 4 && grep -q ' tester CANDIDATE-90 HEAVY_END rc=3 .* step=2/3' .team/events.log && test $brc = 3"
# the lock's time budget has room for the flake rule: each step can run twice (026)
printf 'readlink %s/lock >%s/lockval\ntrue\n' "$HV" "$tmp" >"$tmp/batch2.cmds"
SQUAD_HEAVY_LIMIT_SECONDS=50 "$squad" heavy tester CANDIDATE-92 --batch "$tmp/batch2.cmds" >/dev/null 2>&1 || true
check "026: the lock's time budget of a batch covers a second run of each step (flake_rerun)" grep -qE ':200$' "$tmp/lockval"
printf 'sleep 20\necho after\n' >"$tmp/batch3.cmds"
brc=0; SQUAD_HEAVY_LIMIT_SECONDS=1 "$squad" heavy tester CANDIDATE-93 --batch "$tmp/batch3.cmds" >/dev/null 2>&1 || brc=$?
check "026: a batch step stopped by the time limit (exit 124) is not run again" sh -c "test $brc = 124 && grep -c ' tester CANDIDATE-93 HEAVY_START ' .team/events.log | grep -qx 1"
check "--limit gives a candidate step its own time limit" sh -c "'$squad' heavy tester CANDIDATE-91 --limit 30 -- true && grep -q ' tester CANDIDATE-91 HEAVY_START .*limit=30m' .team/events.log"
check "--limit is refused for a dev" refuses "$squad" heavy dev-a T-6 --limit 30 -- true
check "squad timed stops a command that hangs (exit 124)" sh -c "start=\$(date +%s); '$squad' timed 1 -- sleep 30 >/dev/null 2>&1; rc=\$?; test \$rc = 124 && test \$(( \$(date +%s) - start )) -lt 15"
check "squad timed passes a command's own exit code" sh -c "'$squad' timed 10 -- sh -c 'exit 7'; test \$? = 7"
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
check "dispatch fails when the seat never starts, and logs it" sh -c "rm -f '$tmp/state'; ! MOCK_DYNAMIC=1 MOCK_NEVER_WORK=1 SQUAD_DISPATCH_WAIT=2 '$squad' dispatch dev-a T-100 2>/dev/null && grep -q ' dev-a T-100 DISPATCH_NOT_STARTED' .team/events.log"
echo working >"$tmp/state"; printf 'x\n' >.team/reports/T-131-contract.md
check "dispatch to a busy seat queues it and returns at once" sh -c "MOCK_DYNAMIC=1 SQUAD_QUEUE_POLL=1 SQUAD_DISPATCH_WAIT=3 '$squad' dispatch dev-a T-131 | grep -q 'is busy: T-131 waits' && grep -q ' dev-a T-131 DISPATCH_QUEUED' .team/events.log"
echo idle >"$tmp/state"
check "the queued task is sent when the seat is free" sh -c "for k in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do grep -q ' dev-a T-131 DISPATCH round' .team/events.log && exit 0; sleep 1; done; exit 1"
sleep 3; rm -f "$tmp/state"
printf 'x\n' >.team/reports/T-132-contract.md; printf 'x\n' >.team/reports/T-133-contract.md; printf 'x\n' >.team/reports/T-134-contract.md
echo working >"$tmp/state"; MOCK_DYNAMIC=1 SQUAD_QUEUE_POLL=1 "$squad" dispatch dev-a T-132 >/dev/null 2>&1; echo blocked >"$tmp/state"; sleep 4
check "a queued task never goes to a seat that waits on a prompt or a question" refuses grep -q ' dev-a T-132 DISPATCH round' .team/events.log
echo idle >"$tmp/state"
check "it goes once the seat is idle" sh -c "for k in \$(seq 1 15); do grep -q ' dev-a T-132 DISPATCH round' .team/events.log && exit 0; sleep 1; done; exit 1"
sleep 3; echo working >"$tmp/state"; MOCK_DYNAMIC=1 SQUAD_QUEUE_POLL=1 "$squad" dispatch dev-a T-133 >/dev/null 2>&1
printf '%s dev-a T-133 DISPATCH round=1 (sent by hand)\n' "$(date '+%Y-%m-%d %H:%M:%S')" >>.team/events.log; echo idle >"$tmp/state"
check "a queued task already sent by hand is dropped, not sent twice" sh -c "for k in \$(seq 1 15); do grep -q ' dev-a T-133 DISPATCH_DROPPED' .team/events.log && exit 0; sleep 1; done; exit 1"
sleep 2; rm -f "$tmp/state"; mkdir -p .team/seats; ln -sfn 999999 .team/seats/dev-a.dispatching
check "a lock left by a killed queue is cleared, so the seat is not blocked" sh -c "MOCK_DYNAMIC=1 SQUAD_DISPATCH_WAIT=3 '$squad' dispatch dev-a T-134 2>&1 | grep -qv 'is busy' && test ! -L .team/seats/dev-a.dispatching"
rm -f "$tmp/state"
cp .team/events.log "$tmp/events.keep"; printf '2026-01-01 10:00:00 rev-gpt T-160 CHANGES review=3\n' >>.team/events.log; reset_log
"$squad" watch --once >/dev/null 2>&1
check "the watchdog tells the owner and the lead when the team stalls while a verdict waits" sh -c "grep -q ' lead - STALLED .*T-160 CHANGES' .team/events.log && grep -q 'notification show squad: proj4 stalled' '$MOCK_LOG' && grep -q 'agent prompt lead .*T-160 CHANGES' '$MOCK_LOG'"
check "a notification herdr did not show is in events.log, on one line" grep -q ' lead - NOTIFY_NOT_SHOWN no answer: squad: proj4 stalled$' .team/events.log
reset_log; "$squad" watch --once >/dev/null 2>&1
check "it tells them once per stall" refuses grep -q 'notification show squad: proj4 stalled' "$MOCK_LOG"
cp "$tmp/events.keep" .team/events.log
agents_on='{"result":{"agents":[{"name":"lead","agent_status":"blocked","pane_id":"w2:p1","agent":"claude"}]}}'
reset_log; MOCK_AGENTS="$agents_on" MOCK_PANE_TEXT="You've hit your Fable limit · resets Nov 20 at 9am" "$squad" watch --once >/dev/null 2>&1
check "a seat at its usage limit: the owner gets a notification, events.log a LIMIT line" sh -c "grep -q ' lead - LIMIT resets Nov 20 at 9am' .team/events.log && grep -q 'notification show squad: lead at its usage limit' '$MOCK_LOG'"
rm -f .team/observer/.watchdog/limit-lead; printf 'limit_fallback claude-opus-5-5\n' >>.team/team.conf
agents_li='{"result":{"agents":[{"name":"lead","agent_status":"idle","pane_id":"w2:p1","agent":"claude"}]}}'
# 2c: nothing is sent to a seat that shows a dialog (herdr: blocked, or a menu in its pane): only the owner is told
rm -f .team/observer/.watchdog/held-limit-lead
reset_log; MOCK_AGENTS="$agents_on" MOCK_PANE_TEXT="You've hit your Fable limit · resets Nov 20 at 9am" "$squad" watch --once >/dev/null 2>&1
check "2c: with limit_fallback a seat that herdr shows blocked gets no key and no /model: only the owner is told" sh -c "! grep -qE 'agent (send-keys|prompt) lead' '$MOCK_LOG' && grep -q 'notification show squad: lead at its usage limit' '$MOCK_LOG' && ! grep -q ' lead - FALLBACK' .team/events.log"
rm -f .team/observer/.watchdog/held-limit-lead
reset_log; MOCK_AGENTS="$agents_li" MOCK_PANE_TEXT="$(printf "You've hit your Fable limit · resets Nov 20 at 9am\n❯ 1. Stop and wait for the reset\n  2. Upgrade")" "$squad" watch --once >/dev/null 2>&1
check "2c: nor a seat whose pane shows a menu" sh -c "! grep -qE 'agent (send-keys|prompt) lead' '$MOCK_LOG' && grep -q 'notification show squad: lead at its usage limit' '$MOCK_LOG' && ! grep -q ' lead - FALLBACK' .team/events.log"
reset_log; MOCK_AGENTS="$agents_li" MOCK_PANE_TEXT="You've hit your Fable limit · resets Nov 20 at 9am" "$squad" watch --once >/dev/null 2>&1
check "with limit_fallback the seat switches to that model" sh -c "grep -q 'agent prompt lead /model claude-opus-5-5' '$MOCK_LOG' && grep -q ' lead - FALLBACK model=claude-opus-5-5' .team/events.log"
sed -i.bak '/^limit_fallback /d' .team/team.conf; rm -f .team/team.conf.bak .team/observer/.watchdog/limit-lead .team/observer/.watchdog/held-limit-lead
agents_w='{"result":{"agents":[{"name":"lead","agent_status":"working","pane_id":"w2:p1","agent":"claude"}]}}'
reset_log; MOCK_AGENTS="$agents_w" MOCK_PANE_TEXT="reading a diff that says: You've hit your limit" "$squad" watch --once >/dev/null 2>&1
check "a seat at work that only shows the words is left alone" refuses grep -q 'notification show squad: lead at its usage limit' "$MOCK_LOG"
reset_log; MOCK_AGENTS="$agents_on" MOCK_PANE_TEXT="You've hit your limit · resets 3pm" "$squad" watch --once >/dev/null 2>&1
check "the short wording 'hit your limit' is recognized" grep -q 'notification show squad: lead at its usage limit' "$MOCK_LOG"
rm -f .team/observer/.watchdog/limit-lead
cp .team/events.log "$tmp/events.keep"; printf '2026-01-01 10:00:00 rev-gpt T-161 CHANGES review=3\n' >>.team/events.log; ln -s "tester@proj4:$$:$(date +%s):1200" "$HV/lock"
reset_log; "$squad" watch --once >/dev/null 2>&1
check "no stall alert while a heavy run holds the lock" refuses grep -q 'notification show squad: proj4 stalled' "$MOCK_LOG"
rm -f "$HV/lock"; cp "$tmp/events.keep" .team/events.log
rm -rf .team/observer/.watchdog; printf '2026-01-01 09:00:00 lead T-170 APPROVE\n2026-01-01 09:05:00 tester CANDIDATE-70 DISPATCH round=1\n2026-01-01 09:40:00 tester CANDIDATE-70 FAIL\n' >>.team/events.log
reset_log; "$squad" watch --once >/dev/null 2>&1
check "an approved task whose candidate failed waits for the lead again (the stall alert names it)" grep -q ' lead - STALLED .*T-170 APPROVE' .team/events.log
cp "$tmp/events.keep" .team/events.log
rm -f "$tmp/state"
check "a dev starts without a contract while the tester is in a run, and the contract is queued for the tester" sh -c "MOCK_DYNAMIC=1 MOCK_TESTER=working SQUAD_QUEUE_POLL=1 SQUAD_DISPATCH_WAIT=5 '$squad' dispatch dev-a T-102 >/dev/null 2>&1 && grep -q ' dev-a T-102 CONTRACT_DEFERRED' .team/events.log && grep -q ' tester T-102 DISPATCH_QUEUED contract=1' .team/events.log"
agents_ti='{"result":{"agents":[{"name":"tester","agent_status":"idle","pane_id":"w2:p9","agent":"claude"},{"name":"dev-a","agent_status":"idle","pane_id":"w2:p3","agent":"claude"}]}}'
check "with an idle tester the contract still comes first" sh -c "MOCK_AGENTS='$agents_ti' '$squad' dispatch dev-a T-103 2>&1 | grep -q 'no contract for T-103'"
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

# 027 · the round limit is in code: round 5 goes out, round 6 is refused and the owner is told once
reset_log; rm -f "$tmp/state"; printf 'x\n' >.team/reports/T-R27-contract.md
for r in 1 2 3 4; do printf 'VERDICT: CHANGES\n' >".team/reports/T-R27-review-$r.md"; done
check "027: a dispatch of round 5 (the limit) goes out" env MOCK_DYNAMIC=1 SQUAD_DISPATCH_WAIT=5 "$squad" dispatch dev-a T-R27
printf 'VERDICT: CHANGES\n' >.team/reports/T-R27-review-5.md; reset_log; rm -f "$tmp/state"
check "027: a dispatch of round 6 is refused with a message" sh -c "out=\$(MOCK_DYNAMIC=1 SQUAD_DISPATCH_WAIT=5 '$squad' dispatch dev-a T-R27 2>&1); test \$? != 0 && printf '%s' \"\$out\" | grep -q 'T-R27 is at round 6: the round limit is 5'"
check "027: the refusal is logged as ROUND_LIMIT" ev ' dev-a T-R27 ROUND_LIMIT round=6 limit=5$'
check "027: nothing is sent to the seat" refuses log_has "agent prompt dev-a"
check "027: the owner gets a notification that names the task and its review files" grep -q 'notification show squad: T-R27 reached the round limit --body .*T-R27-review-1.md.*T-R27-review-5.md' "$MOCK_LOG"
MOCK_DYNAMIC=1 SQUAD_DISPATCH_WAIT=5 "$squad" dispatch dev-a T-R27 >/dev/null 2>&1 || true
check "027: a second refused dispatch sends no second notification" test "$(grep -c 'notification show squad: T-R27' "$MOCK_LOG")" = 1
reset_log; rm -f "$tmp/state"; cp .team/team.conf "$tmp/conf27"; printf 'round_limit 6\n' >>.team/team.conf
check "027: round_limit in team.conf moves the limit" env MOCK_DYNAMIC=1 SQUAD_DISPATCH_WAIT=5 "$squad" dispatch dev-a T-R27
check "027: round_limit needs a number" sh -c "printf 'round_limit many\n' >>.team/team.conf; ! '$squad' status >/dev/null 2>&1"
cp "$tmp/conf27" .team/team.conf; reset_log; rm -f "$tmp/state"
# a task the lead approved at the limit goes back to its dev when its candidate fails
printf '2026-11-21 08:00:00 lead T-R27 APPROVE head=x\n' >>.team/events.log
check "027: a task whose newest verdict of the lead is APPROVE is sent past the limit (a failed candidate)" env MOCK_DYNAMIC=1 SQUAD_DISPATCH_WAIT=5 "$squad" dispatch dev-a T-R27
printf '2026-11-21 08:10:00 lead T-R27 CHANGES head=x\n' >>.team/events.log; reset_log; rm -f "$tmp/state"
check "027: after the lead's CHANGES the limit holds again" refuses env MOCK_DYNAMIC=1 SQUAD_DISPATCH_WAIT=5 "$squad" dispatch dev-a T-R27
reset_log; rm -f "$tmp/state"

# 027 · squad tokens: numbers from the seats' session files (fixtures with invented numbers), per seat and per task
( cd "$tmp" && "$squad" new proj27 >/dev/null 2>&1 ); cd "$tmp/proj27"
printf 'seat %s\n' 'lead codex lead -' 'dev-a claude dev -' 'dev-b claude dev -' 'rev-sol codex reviewer dev-a' 'tester claude tester -' >.team/team.conf
export CLAUDE_CONFIG_DIR="$tmp/home/.claude"
mkdir -p "$CLAUDE_CONFIG_DIR/projects/-fixture-dev-a" "$CODEX_HOME/sessions/2026/11/20" .team/seats
cp "$here/fixtures/sessions/claude-1.jsonl" "$CLAUDE_CONFIG_DIR/projects/-fixture-dev-a/aaaaaaaa-0000-4000-8000-000000000001.jsonl"
cp "$here/fixtures/sessions/claude-2.jsonl" "$CLAUDE_CONFIG_DIR/projects/-fixture-dev-a/aaaaaaaa-0000-4000-8000-000000000002.jsonl"
cp "$here/fixtures/sessions/codex-1.jsonl" "$CODEX_HOME/sessions/2026/11/20/rollout-2026-11-20T10-06-00-bbbbbbbb-0000-4000-8000-000000000001.jsonl"
# a /clear starts a new session: the hook keeps every id of the seat, not only the newest
printf '{"session_id":"aaaaaaaa-0000-4000-8000-000000000001"}' | "$squad" session-id dev-a
printf '{"session_id":"aaaaaaaa-0000-4000-8000-000000000002"}' | "$squad" session-id dev-a
printf 'bbbbbbbb-0000-4000-8000-000000000001\n' >.team/seats/rev-sol.session
printf '%s\n' '2026-11-20 10:00:00 dev-a T-701 DISPATCH round=1' '2026-11-20 10:05:00 dev-a T-701 DONE' \
  '2026-11-20 10:06:00 rev-sol T-701 DISPATCH round=1' '2026-11-20 10:09:00 rev-sol T-701 APPROVE' \
  '2026-11-20 11:00:00 dev-a T-702 DISPATCH round=1' '2026-11-20 12:00:00 dev-a T-702 DONE' \
  '2026-11-20 12:01:00 tester T-702 DISPATCH round=1' '2026-11-20 12:05:00 tester T-702 PASS' \
  '2026-11-20 12:06:00 dev-b T-703 DISPATCH round=1' '2026-11-20 12:08:00 dev-b T-703 DONE' \
  '2026-11-20 12:10:00 lead T-701 MERGE' '2026-11-20 12:10:00 lead T-702 MERGE' '2026-11-20 12:10:00 lead T-703 MERGE' >.team/events.log
tok=$(TZ=UTC "$squad" tokens 2>&1 || true)
check "027: tokens shows a Claude seat's calls and input, cache-read, cache-write and output tokens (one model call counted once)" grep -qE '^dev-a +all +4 +113 +3301 +241 +80$' <<<"$tok"
check "027: tokens shows a task's part of a seat (dispatch to report)" grep -qE '^T-701 +dev-a +2 +105 +3000 +200 +70$' <<<"$tok"
check "027: a later task of the same seat is read from its later session" grep -qE '^T-702 +dev-a +1 +7 +300 +40 +9$' <<<"$tok"
check "027: a Codex seat shows its token counts when its session file holds them" grep -qE '^T-701 +rev-sol +2 +300 +1200 +0 +600$' <<<"$tok"
check "027: a task's total is the sum of its seats" grep -qE '^T-701 +all +4 +405 +4200 +200 +670$' <<<"$tok"
check "027: a seat with no session file shows 'not measured', not 0" bash -c "grep -qE '^lead +all +not measured\$' <<<\"\$1\" && grep -qE '^T-702 +tester +not measured\$' <<<\"\$1\"" _ "$tok"
check "027: a task total with a part not measured says so" grep -qE '^T-702 +all +1 +7 +300 +40 +9 +\+ not measured$' <<<"$tok"
check "027: tokens prints numbers only, no text from a session" refuses grep -qE 'fixture' <<<"$tok"
TZ=UTC "$squad" report >/dev/null 2>&1 || true
check "027: the report shows the tokens of a merged task" grep -q '<td>T-701</td>.*<td class=n>405 · 4200 · 200 · 670</td></tr>' .team/report.html
check "027: the report marks a merged task with a part not measured" grep -q '<td>T-702</td>.*<td class=n>7 · 300 · 40 · 9 + ?</td></tr>' .team/report.html
check "027: the report shows ? for a merged task with no measured tokens, never 0" grep -q '<td>T-703</td><td class=n>[0-9]*</td><td class=n>[^<]*</td><td class=n>[^<]*</td><td class=n>?</td></tr>' .team/report.html
# a session file with no token records is no measurement; lines added in the second of the cache write are read
cp "$here/fixtures/sessions/codex-empty.jsonl" "$CODEX_HOME/sessions/2026/11/20/rollout-2026-11-20T09-00-00-cccccccc-0000-4000-8000-000000000001.jsonl"
printf 'cccccccc-0000-4000-8000-000000000001\n' >.team/seats/lead.session
printf '%s\n' '{"type":"assistant","timestamp":"2026-11-20T12:40:00.000Z","message":{"id":"msg_fixture_5","model":"fixture-model","content":[],"usage":{"input_tokens":2,"cache_creation_input_tokens":2,"cache_read_input_tokens":2,"output_tokens":2}}}' >>"$CLAUDE_CONFIG_DIR/projects/-fixture-dev-a/aaaaaaaa-0000-4000-8000-000000000002.jsonl"
touch .team/seats/tokens/*.tsv   # the cache is not older than the session file (bash 3.2 compares whole seconds)
tok=$(TZ=UTC "$squad" tokens 2>&1 || true)
check "027: a Codex session file with no token records shows 'not measured', not 0" grep -qE '^lead +all +not measured$' <<<"$tok"
check "027: lines added to a session file in the second of the cache write are read" grep -qE '^dev-a +all +5 +115 +3303 +243 +82$' <<<"$tok"
unset CLAUDE_CONFIG_DIR; cd "$tmp/proj4"

# 027 · the templates: the class of a defect, correctness before style, consumers in the brief, the tests of the changed files
T27="$here/../templates"
check "027: a review finding names the class of the defect and the places (reviewer, lead)" sh -c "grep -q 'names the class of the defect' '$T27/roles/reviewer.md' && grep -q 'names the class of the defect' '$T27/roles/lead.md'"
check "027: the dev fixes the class, not only the places named" grep -q 'Fix the class' "$T27/roles/dev.md"
check "027: the reviewer checks correctness against the brief and skips style" grep -q 'correctness against the brief.*[Ss]kip style' "$T27/roles/reviewer.md"
check "027: a brief lists the consumers of a changed part" grep -q 'Consumers' "$T27/roles/lead.md"
check "027: a dev runs the tests of the changed files; never the full suite" sh -c "grep -q 'tests of the files you changed' '$T27/roles/dev.md' && grep -q 'full suite is the tester' '$T27/roles/dev.md' && grep -q 'Never the full suite\.' '$T27/PROTOCOL.md'"
check "027: the round limit is named in the protocol as enforced by squad dispatch" grep -q 'squad dispatch. refuses a later round' "$T27/PROTOCOL.md"

# 001 · squad merge and the ledger
( cd "$tmp/proj4-team/dev-a" && git switch -q -c task/T-100 team/integration && echo x >t100.txt && git add t100.txt && git commit -qm "T-100" )
check "a task alone is not merged: it goes through a tested candidate (018)" refuses "$squad" merge T-100
check "event lines carry the date and the time" grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2} ' .team/events.log

# 001 · the verify switch
check "verify_hook off marks every team worktree" sh -c "for w in integration dev-a dev-b dev-c tester; do test -f '$tmp/proj4-team/'\$w/.agents-verify-off || exit 1; done"
check "the marker stays out of commits" grep -qxF '.agents-verify-off' "$tmp/proj4/.git/info/exclude"
check "a team without verify_hook off leaves the worktrees unmarked" test ! -e "$tmp/proj-team/integration/.agents-verify-off"

# 001 · squad notify: a rule change reaches the seats at work
reset_log; printf '%s dev-b T-200 DISPATCH round=1\n' "$(date '+%Y-%m-%d %H:%M:%S')" >>.team/events.log
check "notify tells each seat with an open task" sh -c "'$squad' notify 'SPEC Checks' 'run vitest related first' >/dev/null && grep -q 'agent prompt dev-b \[squad\] Rule changed' '$MOCK_LOG' && grep -q ' RULE SPEC Checks' .team/events.log"
# 2b: a seat that shows a dialog is skipped and named, so the lead can send the rule again
reset_log; nout=$(MOCK_AGENTS='{"result":{"agents":[{"name":"dev-b","agent_status":"blocked"}]}}' "$squad" notify 'SPEC Checks' 'rule two' 2>&1) || true
check "2b: notify types nothing into a seat that herdr shows blocked" refuses log_has "agent prompt dev-b"
check "2b: and prints which seats it skipped" grep -qE 'not told.* dev-b' <<<"$nout"
reset_log; nout=$(MOCK_PANE_TEXT=$(printf 'Do you want to proceed?\n❯ 1. Yes\n  2. No') "$squad" notify 'SPEC Checks' 'rule three' 2>&1) || true
check "2b: nor into a seat whose pane shows a menu" refuses log_has "agent prompt dev-b"
check "2b: that seat is named too" grep -qE 'not told.* dev-b' <<<"$nout"

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
check "the tabs come in order: review, changes, plan, observer, report" sh -c "grep -o 'label [a-z]*' '$MOCK_LOG' | tr '\n' ' ' | grep -q 'label review label changes label plan label observer label report'"
check "the planner has its own tab, plan" grep -q 'tab create --workspace .* --label plan' "$MOCK_LOG"
check "the plan tab has two agents: Claude plans, GPT Sol critiques with -a never" sh -c "grep -qE '^herdr agent start planner --kind claude .* --model claude-fable-5-2' '$MOCK_LOG' && grep -qE '^herdr agent start plan-gpt --kind codex .* -m gpt-6.1-sol .*-a never' '$MOCK_LOG'"
# ---- 012: the plan -----------------------------------------------------------------
cp .team/PLAN.md "$tmp/plan.keep"; rm -f .team/PLAN.md
sha() { { shasum -a 256 "$1" 2>/dev/null || sha256sum "$1"; } | cut -d' ' -f1; }
# the owner types APPROVE at a terminal: the tests give the command a pseudo-terminal
approve() { if script --version 2>/dev/null | grep -q util-linux; then (sleep 2; printf 'APPROVE\n'; sleep 2) | script -qec "$squad plan --approve" /dev/null; else (sleep 2; printf 'APPROVE\n'; sleep 2) | script -q /dev/null "$squad" plan --approve; fi; }
check "a team without a PLAN.md (started before the planner) goes on: the gate asks only for feature plans" sh -c "! '$squad' dispatch dev-a T-779 2>&1 | grep -q 'approves the plan'"
check "a goal that starts with F- stays a goal" sh -c "rm -f .team/PLAN.md; '$squad' plan 'F-35 flight sim' >/dev/null && grep -qx '# Plan: F-35 flight sim' .team/PLAN.md"
check "a feature id with more than F-<number> never becomes a path" sh -c "! '$squad' plan --check 'F-1/../x' 2>&1 | grep -q 'F-1/../x'"
printf '# Plan: (the goal: squad plan "<goal>")\n\nStatus: draft\n' >.team/PLAN.md
check "the draft plan from init gets the goal" sh -c "'$squad' plan 'a notes app' >/dev/null && grep -qx '# Plan: a notes app' .team/PLAN.md"
rm -f .team/PLAN.md
check "plan writes PLAN.md with every section and gives the planner the goal" sh -c "'$squad' plan 'a todo app' >/dev/null && for h in 'Goal' 'Platform and versions' 'Sources' 'Limits of the platform' 'Feasibility' 'Risks' 'Tasks' 'Open decisions for the owner'; do grep -q \"^## \$h\" .team/PLAN.md || exit 1; done && grep -q 'agent prompt planner .*Plan this: a todo app' '$MOCK_LOG'"
check "dispatch refuses a task before the owner approves the plan" sh -c "out=\$('$squad' dispatch dev-a T-777 2>&1); test \$? != 0 && printf '%s' \"\$out\" | grep -q 'before the owner approves the plan'"
mkdir -p .team/plan/proofs; echo "ran: node --version -> v24" >.team/plan/proofs/F1-node.txt
good='| F-1 | Node 24 runs the app | https://nodejs.org/docs/latest-v24.x/api/ | F1-node.txt | proven |'
cp .team/PLAN.md .team/PLAN.keep2
mkplan() { awk '/^## Feasibility/ { print; print "| # | Claim | Official source | Proof | Result |"; print "|:--|:--|:--|:--|:--|"; while ((getline l < "/dev/stdin") > 0) print l; skip = 1; next } skip && /^\|/ { next } /^## / { skip = 0 } { print }' .team/PLAN.keep2 >.team/PLAN.md; }
printf '# Critique\n- [x] F-1: holds — Answer: the Node docs say so\nITEMS: 1\n' >.team/plan/critique.md
printf '%s\n' "$good" '| F-2 | runs `a \| b` in the shell | https://www.gnu.org/software/bash/manual/ | F1-node.txt | proven |' | mkplan
check "plan --check passes a complete plan (aligned separator, a pipe inside a cell)" "$squad" plan --check
printf '%s\n' '| F-1 | Node 24 runs the app | node docs | F1-node.txt | proven |' | mkplan
check "plan --check fails a claim without an official URL, and names it" sh -c "'$squad' plan --check 2>&1 | grep -q 'F-1: no official source URL'"
printf '%s\n' '| F-1 | Node 24 runs the app | https://nodejs.org/ | F9-missing.txt | proven |' | mkplan
check "plan --check fails a missing proof file" sh -c "'$squad' plan --check 2>&1 | grep -q 'F-1: proof file missing'"
printf '%s\n' '| F-1 | Node 24 runs the app | https://nodejs.org/ | . | proven |' | mkplan
check "plan --check fails a folder given as a proof" sh -c "'$squad' plan --check 2>&1 | grep -q 'F-1: proof file missing or empty'"
printf '%s\n' '| F-1 | Node 24 runs the app | https://nodejs.org/ | /etc/hosts | proven |' | mkplan
check "plan --check fails a proof outside .team/plan/proofs" sh -c "'$squad' plan --check 2>&1 | grep -q 'F-1: the proof must be a file in .team/plan/proofs/'"
printf '%s\n' '| F-1 | Node 24 runs the app | https://nodejs.org/ | F1-node.txt | unproven: no machine |' | mkplan
check "plan --check fails an unproven claim" sh -c "'$squad' plan --check 2>&1 | grep -q 'F-1: not proven'"
printf '%s\n' '| F-1 | Node 24 runs the app | https://nodejs.org/ | F1-node.txt | pending |' | mkplan
check "plan --check fails any result that is not proven" sh -c "'$squad' plan --check 2>&1 | grep -q 'F-1: not proven (pending)'"
sed -i.bak 's/^- (each part the goal touches.*/- herdr terminal, bash 3.2/' .team/PLAN.keep2; rm -f .team/PLAN.keep2.bak; echo '<html>' >.team/plan/proofs/F2-look.html
printf '%s\n' "$good" '| F-2 | the sidebar colours | https://herdr.dev/docs | F2-look.html | proven |' | mkplan
check "plan --check fails an HTML proof on a terminal platform" sh -c "'$squad' plan --check 2>&1 | grep -q 'F-2: a mockup for a terminal must be a capture of a real program'"
sed -i.bak 's/^- herdr terminal, bash 3.2/- Next.js client 15, Supabase client/' .team/PLAN.keep2; rm -f .team/PLAN.keep2.bak
printf '%s\n' "$good" '| F-2 | the page look | https://nextjs.org/docs | F2-look.html | proven |' | mkplan
check "a web platform with a 'client' library may prove a look with HTML" "$squad" plan --check
printf '%s\n' "$good" | mkplan; printf '# Critique\n- [ ] F-1: the version is not in the lock file\nITEMS: 1\n' >.team/plan/critique.md
check "plan --check fails while a critique item has no answer" sh -c "'$squad' plan --check 2>&1 | grep -q 'has no answer: F-1: the version'"
check "the critique goes to the GPT critic seat in the plan tab" sh -c "'$squad' plan --critique >/dev/null && grep -q 'agent prompt plan-gpt .*Critique the plan' '$MOCK_LOG'"
printf '# Critique\n- [x] F-1: holds\n' >.team/plan/critique.md
check "a critique without its ITEMS line is not complete" sh -c "'$squad' plan --check 2>&1 | grep -q \"no 'ITEMS: <n>' line\""
printf '# Critique\n- [x] F-1: holds\nITEMS: 2\n' >.team/plan/critique.md
check "a critique whose ITEMS count does not match is not complete" sh -c "'$squad' plan --check 2>&1 | grep -q 'says ITEMS: 2 but has 1'"
printf '# Critique\n- [x] F-1: the proof is missing\nITEMS: 1\n' >.team/plan/critique.md
check "an item marked done without an Answer is not complete" sh -c "'$squad' plan --check 2>&1 | grep -q 'marked done but has no'"
printf '%s\n' "$good" '| | unsupported claim | | | unproven |' | mkplan; printf '# Critique\nITEMS: 0\n' >.team/plan/critique.md
check "a claim row without an id fails the check" sh -c "'$squad' plan --check 2>&1 | grep -q 'a feasibility row has no id'"
printf '%s\n' "$good" | mkplan
check "team.conf owner_name names the human in squad's messages" sh -c "printf 'owner_name Maria\n' >>.team/team.conf; TEAM_ROLE=lead '$squad' plan --approve 2>&1 | grep -q 'only Maria approves'; rc=\$?; sed -i.bak '/^owner_name /d' .team/team.conf; rm -f .team/team.conf.bak; exit \$rc"
check "an agent cannot approve a plan" sh -c "TEAM_ROLE=lead '$squad' plan --approve 2>&1 | grep -q 'only the owner approves'"
printf '# Critique\n- [x] F-1: the version — Answer: added the lock file line\nITEMS: 1\n' >.team/plan/critique.md
check "approve without a terminal is refused" sh -c "'$squad' plan --approve </dev/null 2>&1 | grep -q 'from your own terminal'"
check "a 'Status: approved' line written into the plan does not open the gate" sh -c "sed -i.bak 's/^Status: draft/Status: approved by the owner 2026-01-01 00:00/' .team/PLAN.md; rm -f .team/PLAN.md.bak; '$squad' dispatch dev-a T-777 2>&1 | grep -q 'before the owner approves the plan'"
sed -i.bak 's/^Status: approved by the owner 2026-01-01 00:00/Status: draft/' .team/PLAN.md; rm -f .team/PLAN.md.bak
approve >/dev/null 2>&1 || true
check "the owner approves a complete plan at a terminal, with the date" grep -qE '^Status: approved by the owner [0-9]{4}-' .team/PLAN.md
check "dispatch passes the plan gate once the plan is approved" sh -c "! '$squad' dispatch dev-a T-777 2>&1 | grep -q 'approves the plan'"
printf '# T-778\n- Plan: F-1\n' >.team/tasks/T-778.md
check "a task of a feature plan waits for that plan's approval" sh -c "'$squad' dispatch dev-a T-778 2>&1 | grep -q 'feature plan F-1, which the owner has not approved'"
echo "- one more task" >>.team/PLAN.md
check "an edit after the approval voids it" sh -c "'$squad' dispatch dev-a T-777 2>&1 | grep -q 'before the owner approves the plan'"
rm -f .team/tasks/T-778.md .team/PLAN.keep2; rm -rf .team/plan .team/consult "$tmp/bin/codex"; printf '#!/bin/sh\n' >"$tmp/bin/codex"; chmod +x "$tmp/bin/codex"; cp "$tmp/plan.keep" .team/PLAN.md; { shasum -a 256 .team/PLAN.md 2>/dev/null || sha256sum .team/PLAN.md; } | cut -d' ' -f1 >"$HOME/.config/squad/approvals/proj4-PLAN.md.sha256"
check "the observer is not a reviewer pane" refuses grep -qE 'pane split .* --cwd [^ ]+ .*observer' "$MOCK_LOG"
check "the observer reads the devs' worktrees" grep -qE "^herdr agent start observer --kind claude .* --add-dir $tmp/proj4-team " "$MOCK_LOG"

# 003 · trouble: stalled, login; the observer's passes
reset_log; rm -rf .team/observer/.seen .team/observer/.alerted "$tmp/state"
printf '%s dev-a T-400 DISPATCH round=1\n' "$(date '+%Y-%m-%d %H:%M:%S')" >>.team/events.log
mkdir -p .team/observer/.seen && echo $(( $(date +%s) - 3600 )) >.team/observer/.seen/dev-a
check "a seat with an open task and no work is stalled" sh -c "MOCK_DYNAMIC=1 '$squad' watch --once | grep -q 'dev-a ○ stalled'"
check "the stall is logged once and the lead is told" sh -c "grep -q ' dev-a T-400 SEAT_STALLED' .team/events.log && grep -q 'agent prompt lead \[squad\] dev-a is stalled on T-400' '$MOCK_LOG'"
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
- Status: provisional — open decision for the owner
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
check "the page shows each decision with its status and the GPT consult" sh -c "grep -q 'D-001' '$html' && grep -q 'open decision for the owner' '$html' && grep -q 'GPT consult (consult/1.md)' '$html'"
check "the page shows the observer's now and suggestions" sh -c "grep -q 'T-500 waited 5 min for the tester' '$html' && grep -q 'Batch the tester queue' '$html'"
check "the timeline has the task's minutes: total 90, dev 30, test 25, review 8" grep -qE '<tr><td>T-500</td><td>merged</td><td class=n>90</td><td class=n>30</td><td class=n>25</td><td class=n>8</td>' "$html"
check "the cost tab sums the seat minutes and the Claude and Codex usage points" grep -qE '<tr><td>T-500</td><td class=n>63</td><td class=n>6</td><td class=n>3</td><td class=n>\?</td></tr>' "$html"
check "the live report shows the cost too" sh -c "printf q | '$squad' report --live | grep -qE 'T-500 +merged .*│ 6 · 3\$'"
check "an event records Codex usage when Codex has data" sh -c "CODEX_HOME='$cx' '$squad' done dev-a T-303 BLOCKED >/dev/null; grep -E ' dev-a T-303 BLOCKED .* c=42/7' .team/events.log"
check "the QA tab counts the tester's FAIL" grep -qE '<tr><td>T-500</td><td>[a-z]+</td><td class=n>[0-9]+</td><td class=n>0</td><td class=n>1</td>' "$html"
check "the page escapes HTML in the files" sh -c "printf '<script>x</script>\n' >>.team/observer/NOW.md; '$squad' report >/dev/null; ! grep -q '<script>x' '$html'"
printf 'see http://x"onmouseover="alert(1) now\n' >>.team/observer/NOW.md
printf '\n## D-9<b>x</b> · t\n- Status: final\n' >>.team/DECISIONS.md
"$squad" report >/dev/null
check "a quote in a link cannot add an attribute" refuses grep -q '" *onmouseover=' "$html"
check "a decision id with markup is escaped" refuses grep -q 'D-9<b>' "$html"
printf '## S-1 · Batch\n- Status: adopted\n' >.team/observer/SUGGESTIONS.md
check "the live report runs with no open suggestion" sh -c "printf q | '$squad' report --live | grep -q 'OBSERVER' "
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
want=$(git -C "$dc" rev-parse --short HEAD); wantfull=$(git -C "$dc" rev-parse HEAD)
sed -i.bak "s#^setup.*#setup echo ran >>'$tmp/setup-runs'#" .team/team.conf && rm -f .team/team.conf.bak; rm -f "$tmp/setup-runs"
out=$( cd "$dc" && "$squad" heavy dev-c T-800 -- sh -c 'git rev-parse --short HEAD; pwd -P' 2>/dev/null )
check "a dev's run happens in its snapshot, at the commit it recorded" sh -c "printf '%s' \"\$1\" | grep -qx '$want' && printf '%s' \"\$1\" | grep -qx '$tmp/proj4-team/.runs/dev-c'" _ "$out"
check "the run names its snapshot" grep -qE " dev-c T-800 HEAVY_START sha=$wantfull limit=10m in=.runs/dev-c " .team/events.log
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
check "update-conf adds the planner seat (Fable 5.2), once" sh -c "test \$(grep -cE '^seat +planner +claude +planner ' .team/team.conf) = 1 && grep -qE -- '--model claude-fable-5-2' .team/team.conf"
check "a second run adds nothing" sh -c "'$squad' update-conf | grep -q 'nothing to add'"
printf 'name lead Atlas mauve\nnotify on\nstep 2\n' >>.team/team.conf
check "a team.conf with the Squad Deck lines (name, notify, step) still loads" "$squad" status
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
check "with owner visual the lead decides what the eye cannot see" sh -c "grep -q 'A decision the eye cannot see' .team/roles/lead.md && ! grep -q 'The human owns every decision' .team/roles/lead.md && ! grep -q '<!-- /\?owner:' .team/roles/lead.md"
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
- Status: to test by the owner
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
check "the live view lists what to test" sh -c "printf q | '$squad' report --live | grep -A1 'D-010  Tooltip gap' | grep -q 'look: overlays-tooltip--states'"
printf '\n## D-012 · No place\n- Time: t\n- Question: q\n- Options: o\n- Claude: c\n- GPT: g\n- Sources: s\n- Decision: d\n- Why: w\n- Status: to test by the owner\n' >>.team/DECISIONS.md
check "a decision to test without a See line is refused" refuses "$squad" decisions --check
check "with owner visual nothing in the lead role says to decide provisionally" refuses grep -q 'decide provisionally' .team/roles/lead.md
printf '\n## D-013 · No see, provisional\n- Time: t\n- Question: q\n- Options: o\n- Claude: c\n- GPT: g\n- Sources: s\n- Decision: keep the card\n- Why: w\n- Status: provisional — open decision for the owner\n' >>.team/DECISIONS.md
"$squad" report >/dev/null
check "a decision without a See line keeps its columns in the To test tab" grep -qE '<td>D-013 · No see, provisional</td><td>-</td><td>keep the card</td>' "$html"
printf 'x\n<!-- owner:all -->\n<!-- owner:visual -->\nin\n<!-- /owner:visual -->\nleak\n<!-- /owner:all -->\n' >"$tmp/nested.md"
check "nested owner sections are a template error" sh -c "! '$squad' _owner-filter visual <'$tmp/nested.md' >'$tmp/nested.out' 2>/dev/null && ! grep -q leak '$tmp/nested.out'"
printf 'a\n<!-- owner:all -->\nhidden\n' >"$tmp/open.md"
check "an unclosed owner section is a template error" refuses "$squad" _owner-filter visual <"$tmp/open.md"
printf 'a\n<!-- owner:all -->\nold\n<!-- /owner:all -->\n<!-- owner:visual -->\nnew\n<!-- /owner:visual -->\nb\n' >"$tmp/ok.md"
check "a well-formed template keeps only its mode" sh -c "test \"\$('$squad' _owner-filter visual <'$tmp/ok.md' | tr '\n' ' ')\" = 'a new b '"
reset_log
check "squad feedback saves, logs and tells the lead" sh -c "'$squad' feedback 'The tooltip gap looks 1 px too tight in dark' | grep -q 'F-1 saved and sent' && grep -q '^## F-1 · ' .team/FEEDBACK.md && grep -q 'too tight in dark' .team/FEEDBACK.md && grep -q ' owner - FEEDBACK F-1 The tooltip gap' .team/events.log && grep -q 'agent prompt lead \[squad\] Feedback F-1 from the owner' '$MOCK_LOG'"
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

# ---- 010 · seats never block, verified starts, true stalls, hung runs ----------------------
cd "$tmp/proj4"
check "the shipped observer never waits on a prompt (dontAsk), the tester is unchanged" sh -c "grep -qE '^seat +observer .* --permission-mode dontAsk$' '$here/../presets/default.conf' && ! grep -qE '^seat +tester .*permission-mode' '$here/../presets/default.conf'"
reset_log; rm -f .team/.briefed/*; MOCK_WIDTH=160 "$squad" up >/dev/null 2>&1 || true
check "the reviewer starts with -a never" grep -qE '^herdr agent start rev-gpt --kind codex .* -a never ' "$MOCK_LOG"
check "the observer's settings allow only its own folder and read commands" sh -c "jq -e '.permissions.allow | (map(select(startswith(\"Edit(\"))) == [\"Edit(/$tmp/proj4/.team/observer/**)\"]) and (map(select(test(\"heavy --status\"))) | length == 2)' .team/seats/observer.settings.json"
check "the observer's rules match its commands as written (squad and the full path)" sh -c "jq -e '.permissions.allow | index(\"Bash(squad heavy --status)\") and index(\"Bash(squad herdr agent read *)\")' .team/seats/observer.settings.json && grep -qF '/bin/squad herdr agent read <seat>' .team/roles/observer.md"
check "a dev's settings carry no allow list" sh -c "jq -e 'has(\"permissions\") | not' .team/seats/dev-a.settings.json"
cd "$tmp/old"; printf '# preset: default\nseat lead claude lead -\nseat dev-a claude dev -\nseat rev claude reviewer dev-a\nseat rev-x codex reviewer dev-a -m gpt-6.1-sol\nseat obs claude observer - --model claude-sonnet-5-5\n' >.team/team.conf
"$squad" update-conf >/dev/null
check "update-conf adds -a never to a Codex reviewer and dontAsk to an observer" sh -c "grep -qx 'seat rev-x codex reviewer dev-a -m gpt-6.1-sol -a never' .team/team.conf && grep -qx 'seat obs claude observer - --model claude-sonnet-5-5 --permission-mode dontAsk' .team/team.conf && grep -qx 'seat rev claude reviewer dev-a' .team/team.conf"
"$squad" update-conf >/dev/null
check "and only once" test "$(grep -c -- '^seat rev-x .*-a never' .team/team.conf)" = 1
printf '# preset: default\nseat lead claude lead -\nseat dev-a claude dev -\nseat rev-y codex reviewer dev-a --yolo\nseat obs claude observer - --permission-mode=plan\n' >.team/team.conf
"$squad" update-conf >/dev/null
check "a reviewer that bypasses approvals, or an observer with its own mode, is left alone" sh -c "grep -qx 'seat rev-y codex reviewer dev-a --yolo' .team/team.conf && grep -qx 'seat obs claude observer - --permission-mode=plan' .team/team.conf"
cd "$tmp/proj4"; printf 'x\n' >.team/reports/T-850-contract.md; reset_log; rm -f "$tmp/state"
# (the trial of 21 Nov 2026: such a seat got "/clear" typed into its dialog; now nothing is typed and the task waits in the queue)
check "dispatch to a seat that shows a menu instead of its prompt types nothing: the task waits" sh -c "MOCK_DYNAMIC=1 MOCK_PANE_TEXT='Allow the playwright MCP server to run tool?  enter to submit | esc to cancel' SQUAD_DISPATCH_QUEUE_WAIT=1 SQUAD_QUEUE_POLL=1 '$squad' dispatch dev-a T-850 >/dev/null 2>&1; sleep 4; grep -q ' dev-a T-850 DISPATCH_QUEUED' .team/events.log && ! grep -q 'agent prompt dev-a' '$MOCK_LOG'"
rm -rf .team/seats/dev-a.pending
reset_log; rm -f "$tmp/state"
check "dispatch sends once the seat is at its prompt and sees the turn start" env MOCK_DYNAMIC=1 SQUAD_DISPATCH_WAIT=5 "$squad" dispatch dev-a T-850
printf '%s dev-a T-851 DONE-FOR-SWITCH\n' "$(date '+%Y-%m-%d %H:%M:%S')" >>.team/events.log; reset_log; rm -f "$tmp/state"
check "a task stopped for a switch (DONE-FOR-SWITCH) goes on without a contract" env MOCK_DYNAMIC=1 SQUAD_DISPATCH_WAIT=5 "$squad" dispatch dev-a T-851
rc=0; SQUAD_SILENT_SECONDS=3 SQUAD_WATCH_TICK=1 "$squad" heavy tester T-852 -- sleep 47.3 >/dev/null 2>&1 || rc=$?
cp .team/team.conf "$tmp/conf.keep2"; sed -i.bak 's/^idle_minutes .*/idle_minutes 010/' .team/team.conf && rm -f .team/team.conf.bak
check "a minute value with a leading zero is read as decimal" sh -c "'$squad' watch --once >/dev/null 2>&1"
cp "$tmp/conf.keep2" .team/team.conf
check "a run with no output and no CPU is stopped as hung" sh -c "test $rc = 124 && grep -q ' tester T-852 HUNG ' .team/events.log && ! pgrep -f 'sleep 47[.]3' >/dev/null && test ! -L '$HV/lock'"
rc=0; out=$(SQUAD_SILENT_SECONDS=3 SQUAD_WATCH_TICK=1 "$squad" heavy tester T-853 -- sh -c 'for i in 1 2 3 4 5 6; do echo tick $i; sleep 1; done' 2>&1) || rc=$?
check "a run that keeps printing is not hung, and its output reaches the caller" sh -c "test $rc = 0 && printf '%s' \"\$1\" | grep -q 'tick 6' && ! printf '%s' \"\$1\" | grep -q 'Killed'" _ "$out"
printf '%s tester T-854 DISPATCH round=1\n' "$(date '+%Y-%m-%d %H:%M:%S')" >>.team/events.log
mkdir -p .team/observer/.seen && echo $(( $(date +%s) - 3600 )) >.team/observer/.seen/tester; date +%s >.team/seats/tester.heartbeat
reset_log; rm -rf .team/observer/.alerted
agents_t='{"result":{"agents":[{"name":"tester","agent_status":"idle"},{"name":"lead","agent_status":"working"}]}}'
check "a seat with a live heavy run (fresh heartbeat) is not stalled" sh -c "MOCK_AGENTS='$agents_t' '$squad' watch --once | grep -v 'stalled' | grep -q 'tester ○'"
rm -f .team/seats/tester.heartbeat; echo $(( $(date +%s) - 3600 )) >.team/observer/.seen/tester
check "without the heartbeat the same seat is stalled" sh -c "MOCK_AGENTS='$agents_t' '$squad' watch --once | grep -q 'tester ○ stalled'"
reset_log; rm -rf .team/observer/.idle
agents_d='{"result":{"agents":[{"name":"dev-b","agent_status":"idle"},{"name":"lead","agent_status":"working"}]}}'
mkdir -p .team/observer/.idle && echo $(( $(date +%s) - 600 )) >.team/observer/.idle/dev-b
MOCK_AGENTS="$agents_d" "$squad" watch --once >/dev/null; MOCK_AGENTS="$agents_d" "$squad" watch --once >/dev/null
check "an idle dev with no task is told to the lead once" sh -c "test \$(grep -c 'agent prompt lead \[squad\] dev-b has had no task' '$MOCK_LOG') = 1 && grep -q ' dev-b - IDLE ' .team/events.log"

# GPT review of 010
cd "$tmp/proj4"; printf 'x\n' >.team/reports/T-860-contract.md; reset_log
check "a numbered picker is a menu, not a ready prompt: nothing is typed and the task waits" sh -c "MOCK_PANE_TEXT='Select model
❯ 1. Default (recommended)
  2. Opus' SQUAD_DISPATCH_QUEUE_WAIT=1 SQUAD_QUEUE_POLL=1 '$squad' dispatch dev-a T-860 >/dev/null 2>&1; sleep 4; grep -q ' dev-a T-860 DISPATCH_QUEUED' .team/events.log && ! grep -q 'agent prompt dev-a' '$MOCK_LOG'"
rm -rf .team/seats/dev-a.pending
reset_log
rm -f "$tmp/state"
reset_log
check "a stranded /clear in the input line is not a ready prompt" sh -c "! MOCK_PANE_TEXT='❯ /clear' SQUAD_DISPATCH_WAIT=2 '$squad' dispatch dev-a T-860 >/dev/null 2>&1 && ! grep -q 'agent prompt dev-a Task T-860' '$MOCK_LOG'"
check "a task that already ran and ended counts as started" env MOCK_DYNAMIC=1 MOCK_NEVER_WORK=1 MOCK_PANE_TEXT="> Task T-860 is yours. Read $tmp/proj4/.team/tasks/T-860.md and follow your role file.
Done.
❯ " SQUAD_DISPATCH_WAIT=3 "$squad" dispatch dev-a T-860
check "a seat with a menu after sending gets no Enter" sh -c "! grep -q 'agent send-keys' '$MOCK_LOG'"
printf '%s dev-c T-861 DISPATCH round=1\n%s dev-c T-861 DISPATCH_NOT_STARTED x\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$(date '+%Y-%m-%d %H:%M:%S')" >>.team/events.log
check "a dispatch that did not start leaves no open task" refuses grep -q '^dev-c T-861$' <<<"$(bash -c ". /dev/null"; awk '{ if ($1 ~ /^[0-9][0-9][0-9][0-9]-/) { s = $3; t = $4; e = $5 } else { s = $2; t = $3; e = $4 } if (e == "DISPATCH") open[s] = t; else if (e ~ /^(DONE|BLOCKED|PASS|FAIL|APPROVE|CHANGES|CONTRACT|DISPATCH_FAILED|DISPATCH_NOT_STARTED)$/ && open[s] == t) delete open[s] } END { for (s in open) print s, open[s] }' .team/events.log)"
check "the shipped squad closes DISPATCH_NOT_STARTED in open_tasks" grep -q 'DISPATCH_FAILED|DISPATCH_NOT_STARTED)' "$here/../bin/squad"
ln -s "tester@proj4:999999:$(date +%s):1200" "$HV/lock" 2>/dev/null || true
printf '%s tester T-862 DISPATCH round=1\n' "$(date '+%Y-%m-%d %H:%M:%S')" >>.team/events.log
mkdir -p .team/observer/.seen && echo $(( $(date +%s) - 3600 )) >.team/observer/.seen/tester; rm -f .team/seats/tester.heartbeat; rm -rf .team/observer/.alerted
check "a stale lock with a dead owner does not make a seat busy" sh -c "MOCK_AGENTS='{\"result\":{\"agents\":[{\"name\":\"tester\",\"agent_status\":\"idle\"},{\"name\":\"lead\",\"agent_status\":\"working\"}]}}' '$squad' watch --once | grep -q 'tester ○ stalled'"
rm -f "$HV/lock"
cd "$tmp/old"; printf '# preset: default\nseat lead claude lead -\nseat dev-a claude dev -\nseat rev-x codex reviewer dev-a -m gpt-6.1-sol  # the GPT reviewer\n' >.team/team.conf
"$squad" update-conf >/dev/null
printf '# preset: default\nseat lead claude lead -\nseat dev-a claude dev -\n  seat obs2 claude observer - --model x\n' >.team/team.conf
"$squad" update-conf >/dev/null
check "an indented observer seat gets dontAsk too" grep -qx 'seat obs2 claude observer - --model x --permission-mode dontAsk' .team/team.conf
printf '# preset: default\nseat lead claude lead -\nseat dev-a claude dev -\nseat rev-x codex reviewer dev-a -m gpt-6.1-sol  # the GPT reviewer\n' >.team/team.conf
"$squad" update-conf >/dev/null
check "a seat line with a comment gets its flag before the comment" sh -c "grep -qx 'seat rev-x codex reviewer dev-a -m gpt-6.1-sol -a never  # the GPT reviewer' .team/team.conf && '$squad' status | grep -q 'rev-x .*-a never'"
cd "$tmp/proj4"

# ---- 016 · herdr's own sidebar shows the squad ------------------------------------------
now() { date '+%Y-%m-%d %H:%M:%S'; }
seats='{"result":{"agents":[{"name":"dev-a","agent":"claude","pane_id":"w2:p3","agent_status":"idle"},{"name":"tester","agent":"claude","pane_id":"w2:p6","agent_status":"working"}]}}'
printf '| T-870 | Sidebar ünïcödé title that is much longer than sixty characters, so squad cuts it | open |\n' >>.team/TASKS.md
printf '%s dev-a T-870 DISPATCH round=2\n%s dev-a T-870 DONE\n%s tester T-870 PASS\n' "$(now)" "$(now)" "$(now)" >>.team/events.log
rm -rf .team/observer/.ui; reset_log; MOCK_AGENTS=$seats "$squad" watch --once >/dev/null 2>&1
check "016: a seat's sidebar entry has its name, role, ticket and round" grep -q 'pane report-metadata w2:p3 --source squad:seat --agent claude --display-agent dev-a --title T-870 · Sidebar .*--token role=dev --token ticket=T-870 .*--token when=r2 · 0m' "$MOCK_LOG"
check "016: a dev that is done follows its task's newer test result" grep -q 'w2:p3 .*--token phase=TEST PASSED' "$MOCK_LOG"
check "016: a blocked seat reads NEEDS YOU" grep -q 'w2:p3 .*--state-label blocked=NEEDS YOU' "$MOCK_LOG"
check "016: a long title is cut at 60 characters, never inside a letter" sh -c "t=\$(grep -o 'T-870 · Sidebar[^-]*' '$MOCK_LOG' | head -1 | sed 's/^T-870 · //; s/ *\$//'); printf '%s' \"\$t\" | iconv -f UTF-8 -t UTF-8 >/dev/null && [ \"\$(printf '%s' \"\$t\" | LC_ALL=en_US.UTF-8 wc -m | tr -d ' ')\" -le 60 ]"
printf '%s tester T-871 PASS\n%s dev-a T-871 DISPATCH round=2\n%s dev-a T-871 DONE\n' "$(now)" "$(now)" "$(now)" >>.team/events.log
reset_log; MOCK_AGENTS=$seats "$squad" watch --once >/dev/null 2>&1
check "016: an older test result does not count for a newer round" grep -q 'w2:p3 .*--token phase=WAITS FOR TEST' "$MOCK_LOG"
printf '%s dev-a T-872 DISPATCH round=1\n%s dev-a T-872 DONE\n%s rev-x T-872 CHANGES review=1\n' "$(now)" "$(now)" "$(now)" >>.team/events.log
reset_log; MOCK_AGENTS=$seats "$squad" watch --once >/dev/null 2>&1
check "016: a dev that is done follows the reviewer's verdict" grep -q 'w2:p3 .*--token ticket=T-872 .*--token phase=CHANGES ASKED' "$MOCK_LOG"
check "trial 6: one check (watch --once) does not send an unchanged seat again" refuses grep -q 'report-metadata w2:p6 --source squad:seat' "$MOCK_LOG"
reset_log; MOCK_AGENTS=$seats SQUAD_WATCH_POLL=2 "$squad" watch >/dev/null 2>&1 & wp=$!   # a long-running watch: the strip's start
wait_log 'report-metadata w2:p6 --source squad:seat' || true; kill "$wp" 2>/dev/null || true; wait "$wp" 2>/dev/null || true
check "016: a new strip (squad up, a herdr restart) sends every seat again" grep -q 'report-metadata w2:p6 --source squad:seat' "$MOCK_LOG"
reset_log; MOCK_WS='{"result":{"workspaces":[{"label":"proj4 team","workspace_id":"w2"}]}}' MOCK_AGENTS=$seats "$squad" watch --once >/dev/null 2>&1
check "016: the team's progress goes to its workspace entry" grep -q 'workspace report-metadata w2 --source squad:team --token team=[0-9]*/[0-9]* merged --token lock=lock free --token needs=nobody waits' "$MOCK_LOG"
check "016: the team is in the list for the tab bar line" grep -qx "$PWD/.team" "$HOME/.config/squad/teams/proj4"
printf '10:00:00 dev-b T-874 DISPATCH round=1\n10:05:00 dev-b T-874 DONE\n' >>.team/events.log
seats_b='{"result":{"agents":[{"name":"dev-b","agent":"claude","pane_id":"w2:p4","agent_status":"idle"},{"name":"mine","agent":"claude","pane_id":"w2:p9","agent_status":"blocked"}]}}'
rm -rf .team/observer/.ui; reset_log; MOCK_WS='{"result":{"workspaces":[{"label":"proj4 team","workspace_id":"w2"}]}}' MOCK_AGENTS=$seats_b "$squad" watch --once >/dev/null 2>&1
check "016: an older event without a date still gives the seat its task and phase" grep -q 'w2:p4 .*--token ticket=T-874 .*--token phase=WAITS FOR TEST' "$MOCK_LOG"
check "016: the owner's own blocked agent does not count as a seat that needs them" grep -q 'workspace report-metadata w2 .*--token needs=nobody waits' "$MOCK_LOG"
printf '%s dev-b T-875 DISPATCH round=1\n%s dev-b T-875 DISPATCH_NOT_STARTED x\n' "$(now)" "$(now)" >>.team/events.log
seats_c='{"result":{"agents":[{"name":"dev-b","agent":"claude","pane_id":"w2:p4","agent_status":"blocked"}]}}'
reset_log; MOCK_WS='{"result":{"workspaces":[{"label":"proj4 team","workspace_id":"w2"}]}}' MOCK_AGENTS=$seats_c "$squad" watch --once >/dev/null 2>&1
check "016: a dispatch that did not start shows NOT STARTED, not CODING" grep -q 'w2:p4 .*--token phase=NOT STARTED' "$MOCK_LOG"
check "016: a blocked squad seat counts as one that needs the owner" grep -q 'workspace report-metadata w2 .*--token needs=1 need you' "$MOCK_LOG"
printf '%s dev-b T-876 DISPATCH round=1\n%s dev-b T-877 DISPATCH_FAILED queue timeout\n' "$(now)" "$(now)" >>.team/events.log
reset_log; MOCK_AGENTS=$seats_c "$squad" watch --once >/dev/null 2>&1
check "016: a queued task that times out does not hide the task the seat runs" grep -q 'w2:p4 .*--token ticket=T-876 .*--token phase=CODING' "$MOCK_LOG"
# the tab bar line: only squad's seats count; a team that is gone leaves the list
rm -f "$HOME/.config/squad/teams"/*
echo "$PWD/.team" >"$HOME/.config/squad/teams/a"; echo "$tmp/gone/.team" >"$HOME/.config/squad/teams/b"; echo /x/sock >.team/herdr.sock
line=$(MOCK_AGENTS='{"result":{"agents":[{"name":"dev-a","agent_status":"blocked","tokens":{"role":"dev"}},{"name":"tester","agent_status":"working","tokens":{"role":"tester"}},{"name":"mine","agent_status":"blocked"}]}}' "$squad" herdr-line)
check "016: the tab bar line counts squad's seats only" test "$line" = "proj4: 1 need you · 1 working"
check "016: a team whose folder is gone leaves the list" test ! -e "$HOME/.config/squad/teams/b"
check "016: a team at rest stays out of the line" test "$(MOCK_AGENTS='{"result":{"agents":[]}}' "$squad" herdr-line)" = "squad: nobody needs you"
rm -f .team/herdr.sock "$HOME/.config/squad/teams/a"
check "016: a team without its own herdr socket is not counted" test "$(MOCK_AGENTS='{"result":{"agents":[{"name":"x","agent_status":"blocked","tokens":{"role":"dev"}}]}}' "$squad" herdr-line)" = "squad: nobody needs you"
# ui-setup writes squad's block into herdr's config once, with a backup from before squad
cfg="$XDG_CONFIG_HOME/herdr/config.toml"; mkdir -p "$(dirname "$cfg")"; printf '[ui.toast]\ndelivery = "herdr"\n' >"$cfg"
reset_log; "$squad" ui-setup >/dev/null 2>&1; "$squad" ui-setup >/dev/null 2>&1
check "016: ui-setup writes the sidebar block once" test "$(grep -c '^# squad sidebar (ticket 016)' "$cfg")" = 1
check "016: ui-setup keeps the owner's settings" grep -q '^delivery = "herdr"' "$cfg"
check "016: the first backup is the config from before squad" sh -c "! grep -q 'squad sidebar' '$cfg.before-squad' && grep -q delivery '$cfg.before-squad'"
check "016: ui-setup checks the config with herdr" grep -q "herdr config check" "$MOCK_LOG"
printf '[ui]\nstatus_indicators = "dots"\n' >"$cfg"
check "016: ui-setup refuses a config with the owner's own [ui] table" refuses "$squad" ui-setup
check "016: and leaves that config as it was" test "$(cat "$cfg")" = "$(printf '[ui]\nstatus_indicators = "dots"')"
printf '  [ ui ] # mine\nx = 1\n' >"$cfg"
check "016: a [ui] header with spaces is the owner's table too" refuses "$squad" ui-setup
# v_notify writes herdr's answer to events.log when the owner did not see the notification
for why in disabled rate_limited; do
  cp .team/events.log "$tmp/events.keep"; rm -rf .team/observer/.watchdog .team/observer/.alerted; rm -f "$HV/lock"
  printf '2026-01-01 10:00:00 rev-x T-873 CHANGES review=3\n' >>.team/events.log
  MOCK_NOTIFY="{\"result\":{\"reason\":\"$why\"}}" "$squad" watch --once >/dev/null 2>&1
  check "016: a '$why' answer from herdr is in events.log" grep -q " NOTIFY_NOT_SHOWN $why: squad: proj4 stalled" .team/events.log
  sed -i.bak "s/^[0-9-]* [0-9:]* \(lead - NOTIFY_NOT_SHOWN\)/2026-01-01 10:40:00 \1/" .team/events.log; rm -f .team/events.log.bak   # the record, one stall interval later
  MOCK_NOTIFY="{\"result\":{\"reason\":\"$why\"}}" "$squad" watch --once >/dev/null 2>&1
  check "016: that record does not count as a new stall ('$why')" sh -c "test \$(grep -c ' lead - STALLED .*T-873' .team/events.log) = 1"
  cp "$tmp/events.keep" .team/events.log
done
printf '[ui.toast]\ndelivery = "herdr"\n' >"$cfg"
check "016: ui-setup refuses a config herdr does not accept" refuses env MOCK_BAD_CONFIG=1 "$squad" ui-setup
check "016: and puts the owner's config back" test "$(cat "$cfg")" = "$(printf '[ui.toast]\ndelivery = "herdr"')"
# the sorted Agents list goes over herdr's socket: a small stand-in socket logs each call
sk=$(mktemp -u /tmp/sqXXXXXX); python3 - "$sk" "$MOCK_LOG" <<'PY2' &
import json, os, socket, sys
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); s.bind(sys.argv[1]); s.listen(5); s.settimeout(60)
while True:
    try: c, _ = s.accept()
    except OSError: break
    q = json.loads(c.makefile().readline())
    open(sys.argv[2], "a").write("socket %s %s\n" % (q["method"], json.dumps(q["params"])))
    c.sendall((json.dumps({"id": q["id"], "result": {}}) + "\n").encode()); c.close()
PY2
skpid=$!; for _ in 1 2 3 4 5 6 7 8 9 10; do [ -S "$sk" ] && break; sleep 0.3; done
echo "$sk" >.team/herdr.sock; reset_log; MOCK_AGENTS=$seats "$squad" watch --once >/dev/null 2>&1
check "016: a new strip sets the Agents list: squad's seats, who needs the owner first" grep -q 'socket agent.view.set .*"exists".*"role".*"attention"' "$MOCK_LOG"
echo "$PWD/.team" >"$HOME/.config/squad/teams/proj4"
MOCK_WS='{"result":{"workspaces":[{"workspace_id":"w2","label":"proj4 team"}]}}' "$squad" down >/dev/null 2>&1
check "016: down takes the team out of the tab bar line" test ! -e "$HOME/.config/squad/teams/proj4"
check "016: down clears the Agents list" grep -q 'socket agent.view.clear' "$MOCK_LOG"
echo "$PWD/.team" >"$HOME/.config/squad/teams/proj4"; reset_log; "$squad" down >/dev/null 2>&1
check "016: down cleans up also when the workspace was closed in herdr" sh -c "test ! -e '$HOME/.config/squad/teams/proj4' && grep -q 'socket agent.view.clear' '$MOCK_LOG'"
kill "$skpid" 2>/dev/null || true; rm -f "$sk" .team/herdr.sock

# ---- 017 · the report tab: each seat's work first, in colour ---------------------------
printf '| T-880 | Report seat line title | merged |\n' >>.team/TASKS.md
printf '%s dev-a T-880 DISPATCH round=1\n%s dev-a T-880 DONE\n%s lead T-880 MERGE abc1234\n%s observer - OBSERVE pass=9 20 min\n' "$(now)" "$(now)" "$(now)" "$(now)" >>.team/events.log
mkdir -p .team/observer; printf '# Now — pass 3, 10:40\nLargest loss: none. Same state.\n\n# Pass 2, 10:20\nLargest loss: none. Same state.\n\n# Pass 1, 10:00\nLargest loss: none. Same state.\n' >.team/observer/NOW.md
rep=$(printf q | MOCK_AGENTS=$seats "$squad" report --live 2>/dev/null || true)
check "017: the report starts with each seat's line: name, role, phase, ticket, title" grep -qE '^  . dev-a +dev +MERGED +T-880 +Report seat line title' <<<"$rep"
check "017: repeated observer passes fold into one line" sh -c "printf '%s' \"\$1\" | grep -q 'the same for 3 passes' && test \$(printf '%s' \"\$1\" | grep -c 'Largest loss') = 1" _ "$rep"
check "017: the observer's routine passes are not in the events" refuses grep -q 'OBSERVE pass=9' <<<"$rep"
check "017: without a terminal the report has no colour codes" refuses grep -q $'\033' <<<"$rep"
err=$(printf q | COLUMNS=30 MOCK_AGENTS=$seats "$squad" report --live 2>&1 >/dev/null || true)
check "017: a narrow pane prints no error" test -z "$err"
printf '10:00:00 dev-a T-881 DONE\n' >>.team/events.log
check "017: an event without a date is still in the events" sh -c "printf q | MOCK_AGENTS='$seats' '$squad' report --live 2>/dev/null | grep -q 'dev-a .*T-881 .*DONE'"
off=$(printf q | MOCK_AGENTS='{"error":{"message":"offline"}}' "$squad" report --live 2>/dev/null || true)
check "017: herdr's error answer does not stop the report; the seats show off" sh -c "printf '%s' \"\$1\" | grep -q EVENTS && printf '%s' \"\$1\" | grep -qE 'dev-a +dev +off'" _ "$off"
mkdir -p "$tmp/fresh017" && cd "$tmp/fresh017" && git init -q && git commit -q --allow-empty -m init && "$squad" init >/dev/null 2>&1
check "017: a new team without events.log shows the whole report" sh -c "printf q | '$squad' report --live 2>/dev/null | grep -q EVENTS"
check "017: a new team does not show 'your feedback open: 0'" sh -c "! printf q | '$squad' report --live 2>/dev/null | grep -q 'feedback open: 0'"
cd "$tmp/proj4"
tty_report() { if script --version 2>/dev/null | grep -q util-linux; then printf q | script -qec "$squad report --live" /dev/null; else printf q | script -q /dev/null "$squad" report --live; fi; }
col=$(tty_report 2>/dev/null || true); plain=$(NO_COLOR=1 tty_report 2>/dev/null || true)
check "017: in a terminal the report is in colour" grep -q $'\033\\[38;2' <<<"$col"
check "017: NO_COLOR turns the colour off" sh -c "printf '%s' \"\$1\" | grep -q EVENTS && ! printf '%s' \"\$1\" | grep -q \"\$(printf '\\033')\"" _ "$plain"
printf '%s planner F-1 PLAN_START First goal\n%s planner F-2 PLAN_START Second goal\n%s owner F-1 PLAN_APPROVED\n' "$(now)" "$(now)" "$(now)" >>.team/events.log
plan=$(printf q | MOCK_AGENTS='{"result":{"agents":[{"name":"planner","agent_status":"working"},{"name":"tester","agent_status":"working"}]}}' "$squad" report --live 2>/dev/null || true)
check "017: an approval of an older plan does not mark the newest plan approved" grep -qE 'planner +planner +PLANNING +F-2 +Second goal +0m' <<<"$plan"
printf '%s dev-b T-882 DISPATCH round=1\n%s dev-b T-882 DONE\n%s tester T-882 DISPATCH round=1\n%s rev-x T-882 APPROVE review=1\n' "$(now)" "$(now)" "$(now)" "$(now)" >>.team/events.log
check "017: a reviewer's approval does not hide a test that is still running" grep -qE 'tester +tester +TESTING +T-882' <<<"$(printf q | MOCK_AGENTS='{"result":{"agents":[{"name":"planner","agent_status":"working"},{"name":"tester","agent_status":"working"}]}}' "$squad" report --live 2>/dev/null || true)"

# ---- 019 · a queued dispatch whose team is gone stops ------------------------------------
printf 'x\n' >.team/reports/T-890-contract.md
echo working >"$tmp/state"; MOCK_DYNAMIC=1 SQUAD_QUEUE_POLL=1 "$squad" dispatch dev-a T-890 >/dev/null 2>&1 || true
qpid=""; for _ in 1 2 3 4 5 6 7 8 9 10; do   # the waiter writes its file a moment after dispatch returns
  for f in .team/seats/dev-a.pending/*-T-890; do [ -e "$f" ] && qpid=$(basename "$f" | cut -d- -f2); done
  [ -z "$qpid" ] || break; sleep 0.5; done
check "019: the dispatch waits in the queue" test -n "$qpid"
mv .team "$tmp/team.away"; sleep 4
check "019: a queued dispatch whose team folder is gone stops" refuses kill -0 "${qpid:-1}"
mv "$tmp/team.away" .team; rm -f "$tmp/state" .team/seats/dev-a.pending/*-T-890   # a deleted team does not come back

# ---- 020 · honest numbers ----------------------------------------------------------------
printf '2026-11-18 09:00:00 dev-b T-891 DISPATCH round=1 u=?/90 c=?/50\n2026-11-18 09:10:00 dev-b T-891 DONE u=44/90 c=22/50\n' >>.team/events.log
printf '2026-11-18 09:00:00 dev-b T-892 DISPATCH round=1 u=40/90 c=20/50\n2026-11-18 09:10:00 dev-b T-892 DONE u=44/90 c=22/50\n' >>.team/events.log
printf '2026-11-18 09:00:00 dev-b T-897 DISPATCH round=1 u=90/90 c=20/50\n2026-11-18 09:10:00 dev-b T-897 DONE u=5/90 c=22/50\n' >>.team/events.log
costs=$(printf q | "$squad" report --live 2>/dev/null || true)
check "020: a missing cost reading shows ?, not 0" grep -qE 'T-891 .*│ \? · \?$' <<<"$costs"
check "020: a quota reset shows ? for that quota" grep -qE 'T-897 .*│ \? · 2$' <<<"$costs"
check "020: a task with both readings keeps its number" grep -qE 'T-892 .*│ 4 · 2$' <<<"$costs"
check "020: the HTML Cost tab shows ? too" sh -c "'$squad' report >/dev/null 2>&1; grep -q '<td>T-891</td><td class=n>[0-9]*</td><td class=n>?</td>' .team/report.html"
printf '# T-893\n## Acceptance\n| # | Check |\n|---|---|\n| 1 | a |\n| 2 | b |\n| 3 | c |\n' >.team/tasks/T-893.md
printf 'RESULT: PASS\nAcceptance:\n| # | Result | Evidence |\n|---|---|---|\n| 1 | pass | x |\n| 2 | pending | y |\n| 3 | unavailable | z |\n' >.team/reports/T-893-test.md
"$squad" "done" tester T-893 PASS >/dev/null 2>&1 || true
check "020: a PASS with untested rows says which rows in events.log" grep -qE ' tester T-893 PASS .*untested=2,3' .team/events.log
sed 's/T-893/T-894/' .team/tasks/T-893.md >.team/tasks/T-894.md
printf 'RESULT: PASS\nAcceptance:\n| # | Result | Evidence |\n|---|---|---|\n| 1 | pass | x |\n| 2 | pass | y |\n| 3 | pass | z |\n' >.team/reports/T-894-test.md
"$squad" "done" tester T-894 PASS >/dev/null 2>&1 || true
check "020: a PASS with every row passing has no untested part" sh -c "grep -q ' tester T-894 PASS' .team/events.log && ! grep -q ' tester T-894 PASS .*untested' .team/events.log"
# a queued dispatch whose waiter died is sent again by the strip, with its arguments
printf 'x\n' >.team/reports/T-895-contract.md; mkdir -p .team/seats/dev-a.pending
printf 'squad-request\0dev-a\0T-895\0' >".team/seats/dev-a.pending/1000000000000000000-999999-T-895"
echo idle >"$tmp/state"; MOCK_DYNAMIC=1 SQUAD_DISPATCH_WAIT=3 "$squad" watch --once >/dev/null 2>&1 || true
check "020: the lead hears of a queued task whose waiter died, with the command to send it" sh -c "grep -q ' dev-a T-895 DISPATCH_LOST' .team/events.log && grep -q 'agent prompt lead .*T-895 waited for dev-a.*squad dispatch dev-a T-895' '$MOCK_LOG'"
check "020: squad does not send it by itself, nor queue it again" sh -c "! grep -qE ' dev-a T-895 (DISPATCH round|DISPATCH_QUEUED)' .team/events.log"
printf 'squad-request\0dev-a\0T-904\0' >".team/seats/dev-a.pending/1000000000000000005-999999-T-904"
MOCK_FAIL_PROMPT=lead MOCK_DYNAMIC=1 "$squad" watch --once >/dev/null 2>&1 || true
check "020: when the lead cannot be told, the request stays for the next tick" sh -c "ls .team/seats/dev-a.pending/*-T-904 >/dev/null 2>&1 && ! grep -q ' dev-a T-904 DISPATCH_LOST' .team/events.log"
MOCK_DYNAMIC=1 "$squad" watch --once >/dev/null 2>&1 || true
check "020: the next tick tells the lead, once" test "$(grep -c ' dev-a T-904 DISPATCH_LOST' .team/events.log)" = 1
# a send that never started does not count as sent
printf 'x\n' >.team/reports/T-896-contract.md; echo working >"$tmp/state"
MOCK_DYNAMIC=1 SQUAD_QUEUE_POLL=1 SQUAD_DISPATCH_WAIT=3 "$squad" dispatch dev-a T-896 >/dev/null 2>&1 || true
printf '%s dev-a T-896 DISPATCH round=1\n%s dev-a T-896 DISPATCH_NOT_STARTED x\n' "$(now)" "$(now)" >>.team/events.log; echo idle >"$tmp/state"
check "020: a queued task is not dropped after a send that never started" sh -c "for k in \$(seq 1 15); do [ \$(grep -c ' dev-a T-896 DISPATCH round' .team/events.log) -ge 2 ] && ! grep -q ' dev-a T-896 DISPATCH_DROPPED' .team/events.log && exit 0; sleep 1; done; exit 1"
rm -f "$tmp/state"
# a waiter stopped by a signal (a herdr restart) keeps its request; the strip sends it again
printf 'x\n' >.team/reports/T-898-contract.md; echo working >"$tmp/state"
MOCK_DYNAMIC=1 SQUAD_QUEUE_POLL=1 SQUAD_DISPATCH_WAIT=3 "$squad" dispatch dev-a T-898 >/dev/null 2>&1 || true
qf=""; for _ in 1 2 3 4 5 6 7 8 9 10; do for f in .team/seats/dev-a.pending/*-T-898; do [ -e "$f" ] && qf=$f; done; [ -z "$qf" ] || break; sleep 0.5; done
qpid=""; [ -z "$qf" ] || qpid=$(basename "$qf" | cut -d- -f2)
check "020: the queue file names the live waiter" sh -c "[ -n '$qpid' ] && [ '$qpid' -gt 1 ] && kill -0 '$qpid'"
if [ -n "$qpid" ] && [ "$qpid" -gt 1 ]; then kill -TERM "$qpid" 2>/dev/null || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$qpid" 2>/dev/null || break; sleep 0.5; done; fi   # the waiter has ended
check "020: a waiter stopped by a signal keeps its request" test -e "$qf"
echo idle >"$tmp/state"; MOCK_DYNAMIC=1 SQUAD_QUEUE_POLL=1 SQUAD_DISPATCH_WAIT=3 "$squad" watch --once >/dev/null 2>&1 || true
check "020: the lead hears of that request" grep -q ' dev-a T-898 DISPATCH_LOST' .team/events.log
# a request that was already delivered is not sent again
printf 'squad-request\0dev-a\0T-899\0' >".team/seats/dev-a.pending/1000000000000000001-999999-T-899"
printf '%s dev-a T-899 DISPATCH_QUEUED x\n%s dev-a T-899 DISPATCH round=1\n' "$(now)" "$(now)" >>.team/events.log
MOCK_DYNAMIC=1 SQUAD_QUEUE_POLL=1 "$squad" watch --once >/dev/null 2>&1 || true; sleep 2
check "020: a delivered request whose waiter died is not reported as lost" refuses grep -q ' dev-a T-899 DISPATCH_LOST' .team/events.log
check "020: and its file is gone, with no claim left and no new queue entry" sh -c "for f in .team/seats/dev-a.pending/*-T-899 .team/seats/claims/*-T-899; do [ -e \"\$f\" ] && exit 1; done; ! grep -q ' dev-a T-899 DISPATCH_QUEUED waits' .team/events.log"
# a request whose text has a line break is read back whole; a contract request is named as one
printf 'squad-request\0tester\0T-900\0--contract\0line one\nline two\0' >".team/seats/tester.pending/1000000000000000002-999999-T-900"
reset_log; MOCK_DYNAMIC=1 "$squad" watch --once >/dev/null 2>&1 || true
printf 'x\n' >.team/reports/T-905-contract.md; printf 'squad-request\0tester\0T-905\0--contract\0' >".team/seats/tester.pending/1000000000000000006-999999-T-905"
MOCK_DYNAMIC=1 "$squad" watch --once >/dev/null 2>&1 || true
check "020: a lost contract request whose contract is written is not reported" refuses grep -q ' tester T-905 DISPATCH_LOST' .team/events.log
check "020: a lost contract request is named with --contract" grep -q 'agent prompt lead .*squad dispatch tester T-900 --contract' "$MOCK_LOG"
# a failed contract send does not cancel a delivered test request (each purpose on its own)
printf '%s tester T-901 DISPATCH_QUEUED x\n%s tester T-901 DISPATCH round=1\n%s tester T-901 DISPATCH contract=1 round=1\n%s tester T-901 DISPATCH_NOT_STARTED x\n' "$(now)" "$(now)" "$(now)" "$(now)" >>.team/events.log
printf 'squad-request\0tester\0T-901\0' >".team/seats/tester.pending/1000000000000000003-999999-T-901"
MOCK_DYNAMIC=1 SQUAD_QUEUE_POLL=1 "$squad" watch --once >/dev/null 2>&1 || true; sleep 2
check "020: a failed contract send does not cancel a delivered test request" refuses grep -q ' tester T-901 DISPATCH_LOST' .team/events.log
# a reading at one end only is unknown too
printf '2026-11-18 09:00:00 dev-b T-902 DISPATCH round=1\n2026-11-18 09:10:00 dev-b T-902 DONE u=44/90 c=22/50\n' >>.team/events.log
printf '2026-11-18 09:00:00 dev-b T-903 DISPATCH round=1\n2026-11-18 09:10:00 dev-b T-903 DONE\n' >>.team/events.log
check "020: a task never measured shows ?, not 0" grep -qE 'T-903 .*│ \? · \?$' <<<"$(printf q | "$squad" report --live 2>/dev/null || true)"
printf 'squad-request\0dev-a\0T-1.claim\0' >".team/seats/dev-a.pending/1000000000000000004-999999-T-1.claim"
check "020: a task id ending in .claim is handled too" sh -c "MOCK_DYNAMIC=1 '$squad' watch --once >/dev/null 2>&1; grep -q ' dev-a T-1.claim DISPATCH_LOST' .team/events.log"
sed -n '/^request_kind()/,/^}/p' "$squad" >"$tmp/rk.sh"
check "020: text that contains --contract is a normal request" test "$(bash -c ". '$tmp/rk.sh'; request_kind tester T-1 'Read --contract notes'")" = 0
check "020: the --contract option is a contract request" test "$(bash -c ". '$tmp/rk.sh'; request_kind tester T-1 --escalate --contract")" = 1
check "020: a reading at one end only shows ?" grep -qE 'T-902 .*│ \? · \?$' <<<"$(printf q | "$squad" report --live 2>/dev/null || true)"

# ---- 018 · integration candidates: only the tested commit is promoted -------------------
I="$tmp/proj4-team/integration"; DB="$tmp/proj4-team/dev-b"; TW="$tmp/proj4-team/tester"
base0=$(git -C "$I" rev-parse HEAD)
git -C "$DB" switch -q -c task/T-910 team/integration && echo a >"$DB/t910.txt" && git -C "$DB" add t910.txt && git -C "$DB" commit -qm "T-910"
git -C "$DB" switch -q -c task/T-911 team/integration && echo b >"$DB/t911.txt" && git -C "$DB" add t911.txt && git -C "$DB" commit -qm "T-911"
# audit case 1: a task with no evidence never reaches integration
check "018: merge of a single task is refused" refuses "$squad" merge T-910
check "018: and integration did not move" test "$(git -C "$I" rev-parse HEAD)" = "$base0"
printf '# CANDIDATE-1\n## Acceptance\n| # | Check |\n|---|---|\n| 1 | the suite passes |\n' >.team/tasks/CANDIDATE-1.md
printf '  # the commit the checks see\ngit rev-parse HEAD >%s/seen\n   \n' "$tmp" >.team/tasks/CANDIDATE-1.checks   # an indented comment and a blank line count as no check
check "018: a candidate is refused for a task the lead did not approve" refuses "$squad" candidate CANDIDATE-1 T-910 T-911
printf 'x\n' >.team/reports/T-910-review-1.md; printf 'x\n' >.team/reports/T-911-review-1.md
"$squad" "done" lead T-910 APPROVE >/dev/null 2>&1; "$squad" "done" lead T-911 APPROVE >/dev/null 2>&1
check "018: an approval records the exact task commit" grep -qE " lead T-910 APPROVE .*head=$(git -C "$DB" rev-parse task/T-910)" .team/events.log
git -C "$DB" switch -q task/T-911 && echo c >>"$DB/t911.txt" && git -C "$DB" commit -qam "T-911 after review"
check "018: a task changed after its approval stays out of a candidate" refuses "$squad" candidate CANDIDATE-1 T-910 T-911
"$squad" "done" lead T-911 APPROVE >/dev/null 2>&1
check "018: the lead builds the candidate from the approved commits" "$squad" candidate CANDIDATE-1 T-910 T-911
cand=$(git -C "$I" rev-parse candidate/CANDIDATE-1 2>/dev/null || echo none)
check "018: the candidate holds the base and both task commits" sh -c "for c in $base0 $(git -C "$DB" rev-parse task/T-910) $(git -C "$DB" rev-parse task/T-911); do git -C '$I' merge-base --is-ancestor \$c '$cand' || exit 1; done"
# audit case 3: the runner tests the candidate commit, wherever it is called from
echo dirty >"$TW/dirty.txt"
check "018: a dirty tester worktree is refused" refuses "$squad" heavy tester CANDIDATE-1 --batch .team/tasks/CANDIDATE-1.checks
rm -f "$TW/dirty.txt"
( cd "$DB" && "$squad" heavy tester CANDIDATE-1 --batch "$tmp/proj4/.team/tasks/CANDIDATE-1.checks" >/dev/null 2>&1 ) || true
check "018: the checks ran on the candidate commit, not the caller's" test "$(cat "$tmp/seen" 2>/dev/null)" = "$cand"
check "018: the run logs the full commit" grep -q " tester CANDIDATE-1 HEAVY_START sha=$cand " .team/events.log
check "018: the runner wrote a receipt with each check's result" sh -c "grep -qx 'sha=$cand' .team/receipts/CANDIDATE-1/receipt && grep -qx 'step1=0' .team/receipts/CANDIDATE-1/receipt"
# audit case 2: PASS needs the brief, a passing report and the runner's receipt
printf 'RESULT: PASS\nAcceptance:\n| # | Result | Evidence |\n|---|---|---|\n| 1 | pending | later |\n' >.team/reports/CANDIDATE-1-test.md
check "018: PASS with a pending row is refused" refuses "$squad" "done" tester CANDIDATE-1 PASS
printf 'RESULT: FAIL\nAcceptance:\n| # | Result | Evidence |\n|---|---|---|\n| 1 | pass | ok |\n' >.team/reports/CANDIDATE-1-test.md
check "018: PASS with a report that says FAIL is refused" refuses "$squad" "done" tester CANDIDATE-1 PASS
printf 'RESULT: PASS\nAcceptance:\n| # | Result | Evidence |\n|---|---|---|\n| 1 | pass | ok |\n' >.team/reports/CANDIDATE-1-test.md
cp .team/receipts/CANDIDATE-1/receipt "$tmp/receipt.keep" 2>/dev/null || : >"$tmp/receipt.keep"; sed -i.bak 's/^step1=0$/step1=2/' .team/receipts/CANDIDATE-1/receipt 2>/dev/null || true; rm -f .team/receipts/CANDIDATE-1/receipt.bak
check "018: PASS with a failed check in the receipt is refused" refuses "$squad" "done" tester CANDIDATE-1 PASS
rm -f .team/receipts/CANDIDATE-1/receipt
check "018: PASS without the runner's receipt is refused" refuses "$squad" "done" tester CANDIDATE-1 PASS
cp "$tmp/receipt.keep" .team/receipts/CANDIDATE-1/receipt
mv .team/tasks/CANDIDATE-1.md "$tmp/brief.keep"
check "018: PASS without the brief is refused" refuses "$squad" "done" tester CANDIDATE-1 PASS
mv "$tmp/brief.keep" .team/tasks/CANDIDATE-1.md
printf 'RESULT: PASS\nAcceptance:\n| # | Result | Evidence |\n|---|---|---|\n| 1 | pass | ok |\n| 2 | pending | later |\n' >.team/reports/CANDIDATE-1-test.md
check "018: PASS with any row that is not pass is refused, also a row the brief does not have" refuses "$squad" "done" tester CANDIDATE-1 PASS
printf 'RESULT: PASS\nAcceptance:\n| # | Result | Evidence |\n|---|---|---|\n| 1 | pass | ok |\n' >.team/reports/CANDIDATE-1-test.md
check "018: only the tester reports a candidate's PASS" refuses "$squad" "done" lead CANDIDATE-1 PASS
check "018: a seat reports only as itself" refuses env TEAM_ROLE=dev-a "$squad" "done" tester CANDIDATE-1 PASS
check "018: PASS with the brief, a passing report and a matching receipt is accepted" "$squad" "done" tester CANDIDATE-1 PASS
check "018: the PASS names the build it is for" grep -qE ' tester CANDIDATE-1 PASS .*build=[0-9a-f]{64}' .team/events.log
# promotion: integration becomes exactly the tested commit, unless something moved
printf 'echo changed\n' >>.team/tasks/CANDIDATE-1.checks
check "018: a check list changed after the run stops the promotion" refuses "$squad" merge CANDIDATE-1
check "026: the refusal for a changed check list says to build a new candidate with the next free number" sh -c "'$squad' merge CANDIDATE-1 2>&1 | grep -q 'check list of CANDIDATE-1 changed.*build a new candidate with the next free number'"
sed -i.bak '$d' .team/tasks/CANDIDATE-1.checks; rm -f .team/tasks/CANDIDATE-1.checks.bak
cp .team/tasks/CANDIDATE-1.md "$tmp/brief.keep"; echo more >>.team/tasks/CANDIDATE-1.md
check "026: the refusal for a changed brief says the same" sh -c "'$squad' merge CANDIDATE-1 2>&1 | grep -q 'brief of CANDIDATE-1 changed.*build a new candidate with the next free number'"
cp "$tmp/brief.keep" .team/tasks/CANDIDATE-1.md
h910=$(git -C "$DB" rev-parse task/T-910)
git -C "$DB" switch -q task/T-910 && echo d >>"$DB/t910.txt" && git -C "$DB" commit -qam "T-910 late change" && git -C "$DB" switch -q --detach
check "018: a task changed after the candidate stops the promotion" refuses "$squad" merge CANDIDATE-1
git -C "$DB" update-ref refs/heads/task/T-910 "$h910"   # the task back at its approved commit
git -C "$I" switch -q --detach
check "018: an integration worktree that is not on the team branch stops the promotion" refuses "$squad" merge CANDIDATE-1
git -C "$I" switch -q team/integration
echo mine >"$I/t911.txt"
check "018: a file in the way in the integration worktree stops the promotion" refuses "$squad" merge CANDIDATE-1
check "018: and nothing moved" test "$(git -C "$I" rev-parse HEAD)" = "$base0"
rm -f "$I/t911.txt"
check "018: the tested candidate is promoted" "$squad" merge CANDIDATE-1
check "018: integration is exactly the tested commit" test "$(git -C "$I" rev-parse HEAD)" = "$cand"
check "018: each task of the candidate is logged as merged" sh -c "grep -q ' lead T-910 MERGE ' .team/events.log && grep -q ' lead T-911 MERGE ' .team/events.log"
check "018: the integration worktree shows the merged files" test -f "$I/t911.txt"
check "018: the report shows the promoted candidate as merged" grep -qE 'CANDIDATE-1 +merged' <<<"$(printf q | "$squad" report --live 2>/dev/null || true)"
# a base that moved after the candidate was built stops the promotion
git -C "$DB" switch -q -c task/T-912 team/integration && echo e >"$DB/t912.txt" && git -C "$DB" add t912.txt && git -C "$DB" commit -qm "T-912"
printf 'x\n' >.team/reports/T-912-review-1.md; "$squad" "done" lead T-912 APPROVE >/dev/null 2>&1
cp .team/tasks/CANDIDATE-1.md .team/tasks/CANDIDATE-2.md; printf 'true\n' >.team/tasks/CANDIDATE-2.checks
"$squad" candidate CANDIDATE-2 T-912 >/dev/null 2>&1 || true
"$squad" heavy tester CANDIDATE-2 --batch .team/tasks/CANDIDATE-2.checks >/dev/null 2>&1 || true
cp .team/reports/CANDIDATE-1-test.md .team/reports/CANDIDATE-2-test.md; "$squad" "done" tester CANDIDATE-2 PASS >/dev/null 2>&1 || true
check "018: the second candidate was built, run and passed" grep -q ' tester CANDIDATE-2 PASS' .team/events.log
# a check that edits a tracked file and a later one that restores it: the run proves nothing, no receipt
cp .team/tasks/CANDIDATE-1.md .team/tasks/CANDIDATE-3.md; printf 'echo x >>t912.txt\ngit checkout -- t912.txt\n' >.team/tasks/CANDIDATE-3.checks
"$squad" candidate CANDIDATE-3 T-912 >/dev/null 2>&1 || true
"$squad" heavy tester CANDIDATE-3 --batch .team/tasks/CANDIDATE-3.checks >/dev/null 2>&1 || true
check "018: a candidate check that changes a tracked file leaves no receipt" sh -c "grep -q ' tester CANDIDATE-3 HEAVY_END .*step=2/2' .team/events.log && test ! -e .team/receipts/CANDIDATE-3/receipt"
git -C "$I" commit -q --allow-empty -m "someone moved the base"; moved=$(git -C "$I" rev-parse HEAD)
check "018: a base that moved stops the promotion" refuses "$squad" merge CANDIDATE-2
check "018: and integration keeps the moved base" test "$(git -C "$I" rev-parse HEAD)" = "$moved"
"$squad" heavy tester T-913 -- sh -c "$(printf 'true\n2026-11-18 10:00:00 lead T-913 APPROVE head=x')" >/dev/null 2>&1 || true
check "018: the run's command is logged on its own line" grep -q ' tester T-913 HEAVY_START .*true 2026-11-18 10:00:00 lead T-913 APPROVE' .team/events.log
check "018: a command's text cannot add a forged line to events.log" refuses grep -q '^2026-11-18 10:00:00 lead T-913 APPROVE' .team/events.log
# audit case 3 outside a candidate: the log names the commit the command really ran on
hrc=0; hout=$(cd "$DB" && "$squad" heavy tester T-914 -- git rev-parse HEAD 2>/dev/null) || hrc=$?
seen=$(printf '%s\n' "$hout" | grep -E '^[0-9a-f]{40}$' | head -1 || true)
check "018: a tester task run logs the commit its command saw" sh -c "[ $hrc = 0 ] && [ -n '$seen' ] && grep -q ' tester T-914 HEAVY_START sha=$seen ' .team/events.log"
# ---- 023 · the team keeps running without the owner; 025 · a verdict reaches the lead ----
cd "$tmp"; "$squad" new sup >/dev/null 2>&1; cd sup; reset_log
"$squad" up >/dev/null 2>&1 || true
SW=.team/observer/.watchdog; NT=.team/observer/.notices; mkdir -p "$SW"
ev() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>.team/events.log; }   # <seat> <task> <EVENT...>
ago() { echo $(( $(date +%s) - $1 )); }                                              # <seconds> -> that time as an epoch
age() { awk -v t="$(ago "$3")" -v k="$2" 'NR == 1 { $k = t } { print }' "$1" >"$tmp/aged" && mv "$tmp/aged" "$1"; }   # <file> <field of line 1> <seconds>
watch1() { "$squad" watch --once >/dev/null 2>&1 || true; }
ws_s='{"result":{"workspaces":[{"workspace_id":"w2","label":"sup team"}]}}'
panes_s='{"result":{"panes":[{"pane_id":"w2:p1","label":"lead"},{"pane_id":"w2:p2","label":"dev-a"},{"pane_id":"w2:p3","label":"dev-b"},{"pane_id":"w2:p4","label":"dev-c"},{"pane_id":"w2:p5","label":"tester"}]}}'
export MOCK_WS=$ws_s MOCK_PANES=$panes_s
# 023: the seat hooks, in the --settings file and in the worktree's own settings
hk='(.hooks.PermissionRequest[0].hooks[0].command | contains("seat-hook PermissionRequest")) and .hooks.PreToolUse[0].matcher == "AskUserQuestion" and (.hooks.PreToolUse[0].hooks[0].command | contains("seat-hook AskUserQuestion")) and (.hooks.StopFailure[0].hooks[0].command | contains("seat-hook StopFailure")) and ([.hooks.SessionStart[].hooks[].command | select(contains("seat-hook SessionStart"))] | length == 1) and ([.hooks.Stop[].hooks[].command | select(endswith("seat-hook Stop"))] | length == 1)'
check "023: a Claude seat's settings carry the hooks for a permission request, a question, a failed stop, a stop and a start" jq -e "$hk" .team/seats/dev-a.settings.json
check "023: the settings still record the session id" jq -e '.hooks.SessionStart[0].hooks[0].command | contains("session-id")' .team/seats/dev-a.settings.json
check "023: the same hooks are in the worktree's .claude/settings.local.json" jq -e "$hk" "$tmp/sup-team/dev-a/.claude/settings.local.json"
check "023: that file is not a change for git" test -z "$(git -C "$tmp/sup-team/dev-a" status --porcelain)"
# a group that holds squad's command of an earlier write and the user's own command: only squad's entry is replaced
jq -n --arg c "$(jq -r '.hooks.SessionStart[].hooks[].command | select(contains("seat-hook SessionStart"))' .team/seats/dev-a.settings.json)" '{permissions: {allow: ["Bash(ls)"]}, hooks: {Stop: [{hooks: [{type: "command", command: "mine"}]}], SessionStart: [{matcher: "startup", hooks: [{type: "command", command: $c}, {type: "command", command: "mine2"}]}]}}' >"$tmp/sup-team/tester/.claude/settings.local.json"
"$squad" up >/dev/null 2>&1 || true
check "023: other content of the worktree's settings is kept, and the hooks are there once" jq -e "$hk"' and .permissions.allow == ["Bash(ls)"] and .hooks.Stop[0].hooks[0].command == "mine" and (.hooks.PermissionRequest | length == 1)' "$tmp/sup-team/tester/.claude/settings.local.json"
check "023: a hook group with squad's command and the user's own keeps the user's command and the group's other fields" jq -e '.hooks.SessionStart[0] == {matcher: "startup", hooks: [{type: "command", command: "mine2"}]}' "$tmp/sup-team/tester/.claude/settings.local.json"
# 023: a blocked seat is told to the owner after 5 min, once per wait, while other seats work
ev dev-a T-500 DISPATCH round=1
a_blk='{"result":{"agents":[{"name":"lead","agent_status":"working","pane_id":"w2:p1"},{"name":"dev-a","agent_status":"blocked","pane_id":"w2:p2"},{"name":"dev-b","agent_status":"working","pane_id":"w2:p3"}]}}'
ask=$(printf '│ Which database should the migration use?\n│ ❯ 1. Postgres\n│   2. SQLite')
reset_log; MOCK_AGENTS=$a_blk MOCK_PANE_TEXT=$ask watch1
check "023: a seat blocked for less than 5 min is not told to the owner yet" refuses log_has "notification show squad: dev-a waits for you"
ago 400 >"$SW/blocked-dev-a"
reset_log; MOCK_AGENTS=$a_blk MOCK_PANE_TEXT=$ask watch1
check "023: a seat blocked for 5 min: the owner's notification names the seat, its task and the first line of its question (other seats work)" log_has "notification show squad: dev-a waits for you (T-500) --body Which database should the migration use? --sound request"
reset_log; MOCK_AGENTS=$a_blk MOCK_PANE_TEXT=$ask watch1
check "023: one notification per wait" refuses log_has "notification show squad: dev-a waits for you"
# 025: a condition that still holds is repeated every 30 min, 3 times at most, and stops when it ends
echo "1 $(ago 1900)" >"$SW/held-wait-dev-a"
reset_log; MOCK_AGENTS=$a_blk MOCK_PANE_TEXT=$ask watch1
check "025: a notification for a condition that still holds is repeated after 30 min" log_has "notification show squad: dev-a waits for you (T-500) --body Which database should the migration use? (reminder 1 of 3)"
echo "4 $(ago 1900)" >"$SW/held-wait-dev-a"
reset_log; MOCK_AGENTS=$a_blk MOCK_PANE_TEXT=$ask watch1
check "025: it is repeated 3 times at most" refuses log_has "notification show squad: dev-a waits for you"
a_wrk='{"result":{"agents":[{"name":"lead","agent_status":"working","pane_id":"w2:p1"},{"name":"dev-a","agent_status":"working","pane_id":"w2:p2"},{"name":"dev-b","agent_status":"working","pane_id":"w2:p3"}]}}'
MOCK_AGENTS=$a_wrk watch1
check "025: the repeat stops when the condition ends" test ! -e "$SW/held-wait-dev-a" -a ! -e "$SW/blocked-dev-a"
# 023: one stalled seat is told to the owner while other seats work
ev dev-c T-501 DISPATCH round=1; mkdir -p .team/observer/.seen; ago 3600 >.team/observer/.seen/dev-c
a_st='{"result":{"agents":[{"name":"lead","agent_status":"working","pane_id":"w2:p1"},{"name":"dev-a","agent_status":"working","pane_id":"w2:p2"},{"name":"dev-b","agent_status":"working","pane_id":"w2:p3"},{"name":"dev-c","agent_status":"idle","pane_id":"w2:p4"}]}}'
reset_log; MOCK_AGENTS=$a_st watch1
check "023: one stalled seat is told to the owner while other seats work" log_has "notification show squad: dev-c stalled on T-501 --body it has an open task and has not worked for"
ev dev-c T-501 DONE
# K: the watch's own finding is not the seat's report: a seat that showed a dialog keeps its open task
ev dev-c T-503 DISPATCH round=1; rm -rf .team/observer/.seen .team/observer/.alerted .team/observer/.idle
a_cb='{"result":{"agents":[{"name":"lead","agent_status":"working","pane_id":"w2:p1"},{"name":"dev-a","agent_status":"working","pane_id":"w2:p2"},{"name":"dev-b","agent_status":"working","pane_id":"w2:p3"},{"name":"dev-c","agent_status":"blocked","pane_id":"w2:p4"}]}}'
MOCK_AGENTS=$a_cb watch1
check "K: a seat that shows a dialog is logged with the watch's own event name" grep -q ' dev-c T-503 SEAT_BLOCKED$' .team/events.log
mkdir -p .team/observer/.seen .team/observer/.idle; ago 3600 >.team/observer/.seen/dev-c; ago 600 >.team/observer/.idle/dev-c
reset_log; kout=$(MOCK_AGENTS=$a_st "$squad" watch --once 2>/dev/null || true)
check "K: after the dialog the seat still has its open task: it becomes stalled" grep -q 'dev-c ○ stalled' <<<"$kout"
check "K: the stall has the watch's own event name" grep -q ' dev-c T-503 SEAT_STALLED$' .team/events.log
check "K: and it gets no IDLE alarm" sh -c "! grep -q ' dev-c - IDLE' .team/events.log && ! grep -q 'dev-c has had no task' '$MOCK_LOG'"
ev dev-c T-503 DONE; rm -rf .team/observer/.seen .team/observer/.alerted .team/observer/.idle; rm -f "$SW"/held-*
a_dead='{"result":{"agents":[{"name":"lead","agent_status":"working","pane_id":"w2:p1"},{"name":"dev-b","agent_status":"working","pane_id":"w2:p3"}]}}'
a_bare='{"result":{"agents":[{"name":"lead","agent_status":"working","pane_id":"w2:p1"},{"name":"dev-b","agent_status":"idle","pane_id":"w2:p3"}]}}'
a_gone='{"result":{"agents":[{"name":"lead","agent_status":"working","pane_id":"w2:p1"}]}}'
rdy=$(printf 'Claude Code\n❯ ')   # the seat's pane: its empty prompt, no dialog
bare1() { MOCK_AGENTS=$a_bare MOCK_AGENTS_GONE=$a_gone MOCK_CMDLINE="claude --resume 1234" MOCK_PANE_TEXT=${1:-$rdy} SQUAD_EXIT_WAIT=3 watch1; }   # dev-b: idle, without options
untouched() { ! grep -qE "agent (prompt|start|send-keys) $1|pane run " "$MOCK_LOG"; }   # <seat>: squad typed nothing into its pane
# seat_restart off (the default; the owner, 21 Nov 2026): the watch ends and starts no seat: it logs the case and tells the owner
no_typing() { ! grep -qE 'agent (start|send-keys) |pane run ' "$MOCK_LOG" && ! grep 'agent prompt ' "$MOCK_LOG" | grep -qv 'agent prompt lead \[squad\] '; }   # only squad's notices to the lead
reset_log; MOCK_AGENTS=$a_dead watch1; MOCK_AGENTS=$a_dead watch1
check "seat_restart off (the default): a seat that is gone with a task open is not started, and nothing is typed into any seat" no_typing
check "seat_restart off: the owner is told once what to do" test "$(grep -c 'notification show squad: dev-a is gone (T-500) --body dev-a is gone: run squad up. --sound request' "$MOCK_LOG")" = 1
check "seat_restart off: events.log has the case once" test "$(grep -c ' dev-a T-500 SEAT_GONE' .team/events.log)" = 1
reset_log; rm -f "$tmp/exited"; bare1; bare1
check "seat_restart off: a seat that runs without its squad options is not ended or started, and nothing is typed into any seat" no_typing
check "seat_restart off: the owner is told once what to do" test "$(grep -c 'notification show squad: dev-b runs without its squad options --body dev-b runs without its squad options: end its agent in its pane when its work is finished, then run squad up. --sound request' "$MOCK_LOG")" = 1
check "seat_restart off: events.log has the case once" test "$(grep -c ' dev-b - SEAT_NO_OPTIONS' .team/events.log)" = 1
a_back='{"result":{"agents":[{"name":"lead","agent_status":"working","pane_id":"w2:p1"},{"name":"dev-a","agent_status":"working","pane_id":"w2:p2"},{"name":"dev-b","agent_status":"idle","pane_id":"w2:p3"}]}}'
MOCK_AGENTS=$a_back MOCK_CMDLINE="claude --append-system-prompt-file $tmp/sup/.team/seats/dev-b.md" MOCK_PANE_TEXT=$rdy watch1
check "seat_restart off: the alert ends when the seat runs again" sh -c "! ls '$SW' | grep -qE '^held-(gone|options)-'"
cp .team/team.conf "$tmp/sup.conf0"; printf 'seat_restart maybe\n' >>.team/team.conf
check "seat_restart is on or off" refuses "$squad" status
cp "$tmp/sup.conf0" .team/team.conf; printf 'seat_restart on\n' >>.team/team.conf
rm -f "$SW"/held-*; rm -f "$tmp/exited"
# 023, with seat_restart on: a seat that is gone with a task open is started again, at most once per 10 min, 3 times an hour
reset_log; MOCK_AGENTS=$a_dead watch1
check "023: a seat that is gone with a task open is started again with its full options, while other seats work" grep -qE "^herdr agent start dev-a --kind claude --pane w2:p2 .* --append-system-prompt-file $tmp/sup/.team/seats/dev-a.md --settings $tmp/sup/.team/seats/dev-a.settings.json" "$MOCK_LOG"
check "023: the restart is an event line" grep -q ' dev-a T-500 SEAT_RESTART its agent was gone' .team/events.log
check "023: a dev with an open task gets its task again after the restart" grep -q "agent prompt dev-a \[squad\] squad started you again at .* Your open task: Task T-500 is yours" "$MOCK_LOG"
reset_log; MOCK_AGENTS=$a_dead watch1
check "023: a seat is restarted at most once in 10 min" refuses log_has "agent start dev-a"
printf '%s\n%s\n%s\n' "$(ago 3000)" "$(ago 2000)" "$(ago 700)" >"$SW/restart-dev-a"
reset_log; MOCK_AGENTS=$a_dead watch1
check "023: after 3 restarts of a seat in one hour squad stops and tells the owner" sh -c "! grep -q 'agent start dev-a' '$MOCK_LOG' && grep -q 'notification show squad: dev-a does not stay up' '$MOCK_LOG' && grep -q ' dev-a T-500 SEAT_RESTART_STOPPED 3 restarts in one hour' .team/events.log"
printf '%s\n%s\n%s\n' "$(ago 5000)" "$(ago 4500)" "$(ago 4000)" >"$SW/restart-dev-a"; echo "4 $(ago 1900)" >"$SW/held-restart-dev-a"
reset_log; MOCK_AGENTS=$a_dead watch1
check "023: an hour after the stop squad still starts nothing and sends no new series of notifications" sh -c "! grep -q 'agent start dev-a' '$MOCK_LOG' && ! grep -q 'notification show squad: dev-a' '$MOCK_LOG' && test -e '$SW/restart-dev-a.stopped'"
MOCK_AGENTS=$a_wrk watch1
check "023: a seat that is seen healthy ends the stop" test ! -e "$SW/restart-dev-a.stopped"
: >"$SW/restart-dev-a.stopped"; reset_log; MOCK_AGENTS=$(jq -n --arg s "$(awk '$1 == "seat" { print $2 }' .team/team.conf)" '{result: {agents: ($s | split("\n") | map({name: ., pane_id: "w2:p1", workspace_id: "w2", agent: "claude"}))}}') "$squad" up >/dev/null 2>&1 || true
check "023: squad up removes the stop and the restart record (and starts no seat that runs)" sh -c "! ls '$SW' | grep -q '^restart-' && ! grep -q '^herdr agent start' '$MOCK_LOG'"
ev dev-a T-500 DONE; rm -f "$SW"/restart-* "$SW"/held-*
a_nolead='{"result":{"agents":[{"name":"dev-b","agent_status":"working","pane_id":"w2:p3"}]}}'
ln -s $$ .team/up.lock; reset_log; MOCK_AGENTS=$a_nolead watch1; rm -f .team/up.lock
check "023: while squad up runs, the watch starts no seat" refuses log_has "agent start lead"
reset_log; MOCK_AGENTS=$a_nolead watch1
check "023: a lead that is gone is started again and told to go on from the files" sh -c "grep -q '^herdr agent start lead --kind claude --pane w2:p1 ' '$MOCK_LOG' && grep -q 'agent prompt lead squad restarted the team at' '$MOCK_LOG' && grep -q ' lead - SEAT_RESTART its agent was gone' .team/events.log"
rm -f "$SW"/restart-*; reset_log; MOCK_AGENTS=$a_nolead MOCK_PANES='{"result":{"panes":[]}}' watch1
check "023: a seat whose pane is closed is not started: the owner is told to run squad up" sh -c "! grep -q 'agent start' '$MOCK_LOG' && grep -q 'notification show squad: lead is gone' '$MOCK_LOG'"
rm -f "$SW"/restart-* "$SW"/held-*
# 023: a seat that runs without its squad options is started again with them, when it is idle
ev dev-b T-502 DISPATCH round=2; rm -rf .team/observer/.seen
reset_log; rm -f "$tmp/exited"; bare1
check "023: a seat that runs without its squad options is ended at its own prompt and started again with them" sh -c "grep -q 'agent prompt dev-b /exit' '$MOCK_LOG' && grep -qE '^herdr agent start dev-b --kind claude --pane w2:p3 .* --append-system-prompt-file $tmp/sup/.team/seats/dev-b.md' '$MOCK_LOG' && grep -q ' dev-b T-502 SEAT_RESTART it ran without its squad options' .team/events.log"
check "023: its open task is sent again, as the round it was" grep -q "agent prompt dev-b \[squad\] squad started you again at .* Your open task: T-502 needs changes" "$MOCK_LOG"
rm -f "$tmp/exited" "$SW"/restart-*
reset_log; bare1
check "023: when the options still do not show after squad's restart, it does not restart again: the owner is told" sh -c "! grep -q 'agent prompt dev-b /exit' '$MOCK_LOG' && grep -q \"notification show squad: check dev-b's options\" '$MOCK_LOG'"
rm -f "$SW"/bare-* "$SW"/held-*
reset_log; MOCK_AGENTS=$a_bare MOCK_AGENTS_GONE=$a_gone MOCK_CMDLINE="claude --resume 1234 --append-system-prompt-file $tmp/sup/.team/seats/dev-b.md" watch1
check "023: a seat that runs with its squad options is left alone" refuses log_has "agent prompt dev-b /exit"
a_bwork='{"result":{"agents":[{"name":"lead","agent_status":"working","pane_id":"w2:p1"},{"name":"dev-b","agent_status":"working","pane_id":"w2:p3"}]}}'
reset_log; MOCK_AGENTS=$a_bwork MOCK_CMDLINE="claude --resume 1234" watch1
check "023: a seat at work is not restarted" refuses log_has "agent prompt dev-b /exit"
# 1: squad types only into a seat that is free now: the state is read again before the restart
rm -f "$tmp/exited" "$tmp/pinfo" "$SW"/restart-* "$SW"/bare-* "$SW"/held-* "$SW"/defer-*
reset_log; MOCK_AGENTS_LATER=$a_bwork bare1
check "1: a seat that turns working between the tick's reading and the restart gets nothing typed" untouched dev-b
check "1: the restart is put off, not counted" test -e "$SW/defer-dev-b" -a ! -e "$SW/restart-dev-b"
mkdir -p "$HV/queue"
fresh1() { rm -f "$tmp/exited" "$tmp/pinfo" "$SW"/restart-* "$SW"/bare-* "$SW"/defer-* "$SW"/held-*; reset_log; }   # no earlier restart: nothing but the seat's state holds squad back
for sig in run queue background delivery; do
  case "$sig" in run) date +%s >.team/seats/dev-b.heartbeat ;; queue) : >"$HV/queue/999999999980-$$-dev-b@sup" ;;
    background) printf '1 %s\n' "$(date +%s)" >.team/seats/dev-b.background ;; delivery) ln -s $$ .team/seats/dev-b.dispatching ;; esac
  fresh1; bare1
  check "1: a seat without options that is busy ($sig) gets nothing typed" untouched dev-b
  rm -f .team/seats/dev-b.heartbeat "$HV/queue/999999999980-$$-dev-b@sup" .team/seats/dev-b.background .team/seats/dev-b.dispatching
done
fresh1; bare1 "$ask"
check "1: a seat without options that shows a menu gets nothing typed" untouched dev-b
check "1: the owner is not told at once" refuses log_has "notification show squad: dev-b needs a restart"
ago 700 >"$SW/defer-dev-b"; reset_log; bare1 "$ask"
check "1: when it stays so for 10 min the owner is told, and still nothing is typed" sh -c "grep -q 'notification show squad: dev-b needs a restart' '$MOCK_LOG' && ! grep -qE 'agent (prompt|start) dev-b' '$MOCK_LOG'"
fresh1; MOCK_AGENTS=$a_nolead MOCK_BUSY_PANES=w2:p1 watch1
check "1: a seat that reads off is not started when its pane shows more than a bare shell" untouched lead
a_unnamed='{"result":{"agents":[{"name":null,"agent_status":"idle","pane_id":"w2:p1"},{"name":"dev-b","agent_status":"working","pane_id":"w2:p3"}]}}'
fresh1; MOCK_AGENTS=$a_unnamed watch1
check "1: nor when an agent without a name runs in its pane" untouched lead
# 2: the exit works and the start fails: the owner is told
fresh1; MOCK_FAIL=dev-b bare1
check "2: when the seat ended and its start fails the owner is told" sh -c "grep -q 'agent prompt dev-b /exit' '$MOCK_LOG' && grep -q 'notification show squad: dev-b did not start again' '$MOCK_LOG' && grep -q ' dev-b T-502 SEAT_RESTART_FAILED it did not become ready' .team/events.log"
rm -f "$tmp/exited" "$SW"/restart-* "$SW"/held-*
# 023: the hooks are the first signal; they print nothing and answer nothing
perm='{"session_id":"s1","permission_mode":"default","tool_name":"Bash","tool_input":{"command":"rm -rf build"}}'
reset_log; hout=$(printf '%s' "$perm" | TEAM_ROLE=dev-b "$squad" seat-hook PermissionRequest 2>&1)
check "023: a permission request tells the owner at once, with the tool and its input" wait_log "notification show squad: dev-b waits for you (T-502) --body permission for Bash: rm -rf build --sound request"
check "023: the hook prints nothing (squad never answers for the seat)" test -z "$hout"
check "023: the wait is in the seat's state file" grep -q 'permission for Bash: rm -rf build' .team/seats/dev-b.owner-wait
a_bblk='{"result":{"agents":[{"name":"lead","agent_status":"working","pane_id":"w2:p1"},{"name":"dev-b","agent_status":"blocked","pane_id":"w2:p3"}]}}'
reset_log; MOCK_AGENTS=$a_bblk watch1
check "023: the watch does not tell the owner a second time for the wait the hook reported" refuses log_has "notification show squad: dev-b waits for you"
rm -f .team/seats/dev-b.owner-wait
reset_log; printf '%s' '{"tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Which plan do you want?"}]}}' | TEAM_ROLE=dev-b "$squad" seat-hook AskUserQuestion
check "023: a question to the owner (AskUserQuestion) tells the owner its text" wait_log "notification show squad: dev-b waits for you (T-502) --body Which plan do you want? --sound request"
# 10: the dialog does not wait for the notification commands
rm -f .team/seats/dev-b.owner-wait "$SW"/held-wait-dev-b; reset_log; t0=$(date +%s)
printf '%s' "$perm" | MOCK_NOTIFY_SLEEP=3 TEAM_ROLE=dev-b "$squad" seat-hook PermissionRequest
check "10: the hook returns before the notification command ends" test $(( $(date +%s) - t0 )) -lt 3
check "10: the state file is written before the hook returns" grep -q 'permission for Bash: rm -rf build' .team/seats/dev-b.owner-wait
check "10: and the notification still goes out" wait_log "notification show squad: dev-b waits for you (T-502)"
wait_log "osascript" || true   # the background notification ended
rm -f .team/seats/dev-b.owner-wait
reset_log; t0=$(date +%s); hout=$(printf '%s' '{"error":"authentication_failed"}' | MOCK_NOTIFY_SLEEP=3 TEAM_ROLE=dev-b "$squad" seat-hook StopFailure 2>&1)
check "3: the StopFailure hook returns before the notification command ends, and prints nothing" test $(( $(date +%s) - t0 )) -lt 3 -a -z "$hout"
check "023: a turn that ends on a sign-in error is told to the owner at once" sh -c "grep -q ' dev-b T-502 SEAT_STOPPED authentication_failed' .team/events.log"
check "3: and the notification still goes out" wait_log "notification show squad: dev-b stopped: authentication_failed"
wait_log "osascript" || true   # the background notification ended
printf '%s' '{"error":"authentication_failed"}' | TEAM_ROLE=dev-b "$squad" seat-hook StopFailure; sleep 2
check "023: the same failure reported twice is told once" test "$(grep -c 'notification show squad: dev-b stopped' "$MOCK_LOG")" = 1
reset_log; printf '%s' '{"error":"rate_limit"}' | TEAM_ROLE=dev-b "$squad" seat-hook StopFailure
check "023: a turn that ends on a usage limit is told to the owner at once" wait_log "notification show squad: dev-b at its usage limit"
wait_log "osascript" || true
printf '%s' '{"session_id":"s9","source":"resume"}' | TEAM_ROLE=tester "$squad" seat-hook SessionStart
check "023: a seat resumed without its squad options reports it at its start" sh -c "grep -q ' tester - SEAT_NO_OPTIONS source=resume' .team/events.log && test -f .team/seats/tester.no-options"
check "7: the owner is told there too (no watch may run)" wait_log "notification show squad: tester runs without its squad options --body tester runs without its squad options: end its agent in its pane when its work is finished, then run squad up."
printf '%s' '{"session_id":"s9","source":"resume"}' | TEAM_ROLE=tester "$squad" seat-hook SessionStart; sleep 1
check "7: once per seat" test "$(grep -c 'notification show squad: tester runs without its squad options' "$MOCK_LOG")" = 1
sh -c "printf '%s' '{\"session_id\":\"s9\",\"source\":\"resume\"}' | TEAM_ROLE=dev-a '$squad' seat-hook SessionStart; true" hook --append-system-prompt-file "$tmp/sup/.team/seats/dev-a.md"
check "023: a seat started with its squad options reports nothing" refuses grep -q ' dev-a - SEAT_NO_OPTIONS' .team/events.log
echo s77 >.team/seats/dev-c.session
shown='{"result":{"reason":"shown"}}'   # herdr showed the notification: no NOTIFY_NOT_SHOWN line comes later from the background
printf '%s' '{"session_id":"s77","source":"resume"}' | MOCK_NOTIFY=$shown "$squad" seat-hook SessionStart
check "023: without TEAM_ROLE the seat is known by its recorded conversation" grep -q ' dev-c - SEAT_NO_OPTIONS source=resume' .team/events.log
printf '%s' '{"session_id":"s77","background_tasks":[{"id":"b1"},{"id":"b2"}]}' | "$squad" seat-hook Stop
check "12: the shared Stop hook records the seat's background work without a seat argument" grep -qE '^2 [0-9]+$' .team/seats/dev-c.background
rm -f .team/seats/dev-c.background
cp .team/events.log "$tmp/ev.before"; printf '%s' '{"session_id":"nobody","source":"resume"}' | "$squad" seat-hook SessionStart
check "023: a Claude session that is no seat is ignored, and the hook never fails" sh -c "cmp -s .team/events.log '$tmp/ev.before' && echo 'not json' | '$squad' seat-hook PermissionRequest"
a_tst='{"result":{"agents":[{"name":"lead","agent_status":"working","pane_id":"w2:p1"},{"name":"tester","agent_status":"idle","pane_id":"w2:p5"}]}}'
reset_log; rm -f "$tmp/exited" .team/seats/dev-c.no-options "$SW"/held-*; MOCK_AGENTS=$a_tst MOCK_AGENTS_GONE=$a_gone MOCK_PANE_TEXT=$rdy SQUAD_EXIT_WAIT=3 watch1
check "14: the Stop hook prints nothing and exits 0 outside a git repository" sh -c "cd '$tmp/home' && out=\$(echo '{\"background_tasks\":[]}' | TEAM_ROLE=dev-a '$squad' seat-hook Stop 2>&1) && test -z \"\$out\""
check "4: squad seat-stop is no command (the Stop hook is squad seat-hook Stop)" sh -c "! echo '{}' | '$squad' seat-stop dev-a >/dev/null 2>&1 && ! grep -q 'seat-stop' '$squad'"
check "14: the session hook too" sh -c "cd '$tmp/home' && out=\$(echo '{\"session_id\":\"s1\"}' | '$squad' session-id dev-a 2>&1) && test -z \"\$out\""
check "023: the watch starts the seat that reported no options again" sh -c "grep -q '^herdr agent start tester --kind claude --pane w2:p5 ' '$MOCK_LOG' && test ! -e .team/seats/tester.no-options"
rm -f "$tmp/exited" "$SW"/restart-* "$SW"/bare-* "$SW"/held-*
# 023: a long-running watch runs the new bin/squad when the file changes
mkdir -p "$tmp/sq2"; cp -R "$here/../bin" "$here/../templates" "$here/../presets" "$tmp/sq2/"
SQUAD_WATCH_POLL=1 MOCK_WS='' MOCK_PANES='' "$tmp/sq2/bin/squad" watch >/dev/null 2>&1 & wpid=$!
sleep 3
printf '#!/bin/sh\necho "new squad $*" >"%s/reloaded"\n' "$tmp" >"$tmp/sq2/squad.new"; chmod +x "$tmp/sq2/squad.new"; mv "$tmp/sq2/squad.new" "$tmp/sq2/bin/squad"
k=0; while [ ! -f "$tmp/reloaded" ] && [ "$k" -lt 30 ]; do k=$((k + 1)); sleep 1; done
check "023: a long-running squad watch runs the new bin/squad when the file changes" grep -qx 'new squad watch' "$tmp/reloaded"
kill "$wpid" 2>/dev/null || true; wait "$wpid" 2>/dev/null || true

# 025: a notice to the lead stays pending until the lead acts on the task
rm -rf "$NT" "$SW"; mkdir -p "$SW"; unset MOCK_WS MOCK_PANES
reset_log; "$squad" "done" dev-a T-510 BLOCKED >/dev/null 2>&1
check "025: a notice to the lead is kept as a pending record" grep -q 'dev-a finished T-510: BLOCKED' "$NT/T-510.dev-a"
reset_log; watch1
check "025: a fresh notice is not sent again" refuses log_has "agent prompt lead [squad] dev-a finished T-510"
age "$NT/T-510.dev-a" 1 1000
reset_log; watch1
check "025: after notice_redeliver_minutes the notice line is sent to the lead again" grep -q 'agent prompt lead \[squad\] dev-a finished T-510: BLOCKED.*(Sent again: no event of yours for T-510 since ' "$MOCK_LOG"
check "025: the owner is not told before notice_owner_minutes" refuses log_has "notification show squad: T-510 BLOCKED waits for the lead"
reset_log; watch1
check "025: the notice is sent again only every notice_redeliver_minutes" refuses log_has "agent prompt lead [squad] dev-a finished T-510"
age "$NT/T-510.dev-a" 1 2000
reset_log; watch1; watch1
check "025: after notice_owner_minutes the owner is told, once" test "$(grep -c 'notification show squad: T-510 BLOCKED waits for the lead' "$MOCK_LOG")" = 1
ev lead T-510 CHANGES; watch1
check "025: an event of the lead for the task ends the pending notice" test ! -e "$NT/T-510.dev-a"
"$squad" "done" rev-gpt T-511 CHANGES >/dev/null 2>&1; age "$NT/T-511.rev-gpt" 1 2000
ev dev-a T-511 DISPATCH round=2
reset_log; watch1
check "025: a new dispatch of the task ends a reviewer's pending verdict, and nothing is sent" sh -c "test ! -e '$NT/T-511.rev-gpt' && ! grep -q 'T-511' '$MOCK_LOG'"
ev dev-a T-511 DONE
# 4: what ends a pending notice
notice() { mkdir -p "$NT"; printf '%s %s %s %s %s\n[squad] %s finished %s: %s\n' "$(ago "$4")" "$(wc -l <.team/events.log | tr -d ' ')" "$1" "$3" "$2" "$1" "$2" "$3" >"$NT/$2.$1"; }   # <seat> <task> <status> <age in s>
ev lead CANDIDATE-7 CANDIDATE sha=abc base=def tasks=T-550 T-551
notice tester CANDIDATE-7 PASS 60; notice dev-a T-552 DONE 60
ev dev-b T-559 DISPATCH round=1; ev dev-b T-559 DISPATCH_QUEUED waits; ev tester T-552 DISPATCH contract=1 round=1; watch1
check "4: a dispatch of another task does not end a candidate's PASS notice" test -e "$NT/CANDIDATE-7.tester"
check "4: a contract request to the tester does not end a dev's DONE notice for the task" test -e "$NT/T-552.dev-a"
ev lead CANDIDATE-7 CANDIDATE_MERGED abc; watch1
check "4: CANDIDATE_MERGED for it ends a candidate's PASS notice" test ! -e "$NT/CANDIDATE-7.tester"
ev lead CANDIDATE-8 CANDIDATE sha=abc base=def tasks=T-553 T-554
notice tester CANDIDATE-8 FAIL 60; ev dev-b T-559 DISPATCH round=2; watch1
check "4: a dispatch of another task does not end a candidate's FAIL notice" test -e "$NT/CANDIDATE-8.tester"
ev dev-a T-554 DISPATCH round=2; watch1
check "4: a dispatch of one of its tasks ends a candidate's FAIL notice" test ! -e "$NT/CANDIDATE-8.tester"
notice tester CANDIDATE-8 FAIL 60; ev lead CANDIDATE-9 CANDIDATE sha=abd base=def tasks=T-553 T-554; watch1
check "4: a newer candidate build ends a candidate's notice" test ! -e "$NT/CANDIDATE-8.tester"
ev dev-b T-559 DONE; ev tester T-552 CONTRACT; ev dev-a T-554 DONE
check "4: squad seen is for the lead" refuses env TEAM_ROLE=dev-a "$squad" seen T-552
check "4: squad seen <task> ends a notice that needs no event of the lead" sh -c "TEAM_ROLE=lead '$squad' seen T-552 >/dev/null && grep -q ' lead T-552 SEEN$' .team/events.log && { '$squad' watch --once >/dev/null 2>&1; test ! -e '$NT/T-552.dev-a'; }"
notice dev-a T-555 BLOCKED 4000; ago 1000 >"$NT/.sent-T-555.dev-a"; echo 2 >"$NT/.owner-T-555.dev-a"
reset_log; watch1
check "4: after the owner was told a notice is sent again a bounded number of times" sh -c "grep -q 'agent prompt lead \[squad\] dev-a finished T-555' '$MOCK_LOG' && grep -qx 3 '$NT/.owner-T-555.dev-a'"
ago 1000 >"$NT/.sent-T-555.dev-a"; reset_log; watch1
check "4: then it is not sent again" refuses log_has "agent prompt lead [squad] dev-a finished T-555"
rm -rf "$NT"
# 5: nothing is typed into a lead that shows a dialog
a_lblk='{"result":{"agents":[{"name":"lead","agent_status":"blocked","pane_id":"w2:p1"},{"name":"dev-b","agent_status":"working","pane_id":"w2:p3"}]}}'
a_lidle='{"result":{"agents":[{"name":"lead","agent_status":"idle","pane_id":"w2:p1"},{"name":"dev-b","agent_status":"working","pane_id":"w2:p3"}]}}'
notice dev-a T-556 BLOCKED 2000
reset_log; MOCK_AGENTS=$a_lblk watch1
check "5: a notice is not sent again to a lead that is blocked on a dialog" sh -c "! grep -q 'agent prompt lead' '$MOCK_LOG' && test ! -e '$NT/.sent-T-556.dev-a'"
check "5: the owner is still told" log_has "notification show squad: T-556 BLOCKED waits for the lead"
rm -f "$NT"/.sent-*; reset_log; MOCK_AGENTS=$a_lidle MOCK_PANE_TEXT=$ask watch1
check "5: nor to a lead whose pane shows a menu" refuses log_has "agent prompt lead"
reset_log; MOCK_AGENTS=$a_lidle MOCK_PANE_TEXT=$rdy watch1
check "5: it goes out when the dialog is gone" log_has "agent prompt lead [squad] dev-a finished T-556"
rm -rf "$NT" "$SW"; mkdir -p "$SW"
# 6: a state file that is empty (half-written) does not end the watch
: >"$SW/blocked-dev-a"; ev dev-a T-557 DISPATCH round=1
reset_log; MOCK_AGENTS=$a_blk MOCK_PANE_TEXT=$ask watch1
check "6: an empty state file does not end the watch: the tick goes on and the owner is told" log_has "notification show squad: dev-a waits for you (T-557)"
ev dev-a T-557 DONE; rm -rf "$SW" "$NT"; mkdir -p "$SW"
cp .team/team.conf "$tmp/sup.conf"; printf 'notice_redeliver_minutes 1\nnotice_owner_minutes 2\n' >>.team/team.conf
"$squad" "done" tester T-512 FAIL >/dev/null 2>&1; age "$NT/T-512.tester" 1 150
reset_log; watch1
check "025: notice_redeliver_minutes and notice_owner_minutes of team.conf are used" sh -c "grep -q 'agent prompt lead \[squad\] tester finished T-512: FAIL' '$MOCK_LOG' && grep -q 'notification show squad: T-512 FAIL waits for the lead' '$MOCK_LOG'"
cp "$tmp/sup.conf" .team/team.conf; rm -rf "$NT"
# 025: squad wait-owner: a chosen wait for the owner
reset_log
check "025: squad wait-owner writes the wait, logs it and tells the owner" sh -c "'$squad' wait-owner 'T-520: which payment provider?' >/dev/null && test -f .team/owner-wait && grep -q ' lead - WAIT_OWNER T-520: which payment provider?' .team/events.log && grep -q 'notification show squad: sup waits for you --body T-520: which payment provider? --sound request' '$MOCK_LOG'"
check "11: squad wait-owner is for the lead: another seat is refused and nothing changes" sh -c "! TEAM_ROLE=dev-a '$squad' wait-owner 'mine' >/dev/null 2>&1 && ! grep -q ' WAIT_OWNER mine' .team/events.log && grep -q 'which payment provider' .team/owner-wait"
check "025: with notify_os on (the default) the owner also gets an operating-system notification" grep -q '^osascript .*end run squad: sup waits for you T-520: which payment provider?' "$MOCK_LOG"
reset_log; watch1
check "025: no reminder before owner_reminder_hours" refuses log_has "still waits for you"
age .team/owner-wait 3 15000
reset_log; watch1; watch1
check "025: the owner is reminded every owner_reminder_hours, once each time" test "$(grep -c 'notification show squad: sup still waits for you --body T-520: which payment provider?' "$MOCK_LOG")" = 1
cp .team/events.log "$tmp/ev.keep"; printf '2026-01-01 10:00:00 rev-gpt T-530 CHANGES review=1\n' >.team/events.log
reset_log; watch1
check "025: while the wait is set the team-wide stall alarm is silent" refuses log_has "notification show squad: sup stalled"
rm -f .team/owner-wait
reset_log; watch1
check "025: without the wait the same stall is told to the owner" log_has "notification show squad: sup stalled"
MOCK_AGENTS=$a_wrk watch1; reset_log; watch1
check "3: a tick in which a seat works does not start the stall's notifications again" refuses log_has "notification show squad: sup stalled"
for f in "$SW"/held-stall-*; do echo "1 $(ago 1900)" >"$f"; done
reset_log; watch1
check "025: a stall that still holds is told again after 30 min" grep -q 'notification show squad: sup stalled .*(reminder 1 of 3)' "$MOCK_LOG"
cp "$tmp/ev.keep" .team/events.log; ev lead T-530 APPROVE; watch1
check "025: the stall's repeat stops when the team moves again" sh -c "! ls '$SW' | grep -q '^held-stall-'"
"$squad" wait-owner "T-521: the logo" >/dev/null 2>&1
check "025: squad wait-owner --done ends the wait" sh -c "'$squad' wait-owner --done >/dev/null && test ! -e .team/owner-wait && grep -q ' lead - WAIT_OWNER_DONE' .team/events.log"
"$squad" wait-owner "T-522: the price" >/dev/null 2>&1; ev dev-a T-540 DISPATCH round=1; watch1
check "025: a new dispatch ends the wait" sh -c "test ! -e .team/owner-wait && grep -q ' lead - WAIT_OWNER_DONE a new dispatch' .team/events.log"
"$squad" "done" dev-b T-541 BLOCKED >/dev/null 2>&1; age "$NT/T-541.dev-b" 1 2000; "$squad" wait-owner "T-541: dev-b's question" >/dev/null 2>&1
reset_log; watch1
check "025: a BLOCKED the lead answered with squad wait-owner is not sent again" sh -c "test ! -e '$NT/T-541.dev-b' && ! grep -q 'finished T-541' '$MOCK_LOG'"
"$squad" wait-owner --done >/dev/null 2>&1
# 025: notify_os off keeps herdr's notification only
printf 'notify_os off\n' >>.team/team.conf
reset_log; "$squad" wait-owner "os off" >/dev/null 2>&1; "$squad" wait-owner --done >/dev/null 2>&1
check "025: notify_os off keeps herdr's notification only" sh -c "grep -q 'notification show squad: sup waits for you --body os off' '$MOCK_LOG' && ! grep -q '^osascript' '$MOCK_LOG'"
printf 'notify_os maybe\n' >>.team/team.conf
check "025: notify_os is on or off" refuses "$squad" status
cp "$tmp/sup.conf" .team/team.conf
check "025: the lead's role file says when to run squad wait-owner" grep -qF "$squad_abs wait-owner" .team/roles/lead.md
check "4: the lead's role file says when to run squad seen" grep -qF "$squad_abs seen <ID>" .team/roles/lead.md
# ---- 024 · a dispatch never interrupts a busy seat; a dev is never idle for long ----------
cd "$tmp/proj4"; rm -f "$tmp/state" "$HV/lock" .team/seats/*.heartbeat .team/seats/*.background; rm -rf .team/observer/.seen .team/observer/.alerted .team/observer/.idle
# -h and --help print the help and change nothing (the lead's report: 'squad plan --help' wrote a draft plan)
snap24() { { find .team "$tmp/proj4-team" -maxdepth 1 | sort; find .team -type f ! -name '*.log' ! -name 'herdr.sock' -exec cksum {} + | sort; ls "$tmp"; git worktree list; } | cksum; }
cp .team/PLAN.md "$tmp/plan.keep24"; rm -f .team/PLAN.md   # a team from before the planner: no PLAN.md, dispatches go on
reset_log; s0=$(snap24); p0=$(grep -c ' PLAN_START ' .team/events.log || true)
hout=$("$squad" plan --help 2>&1) || true
check "024: squad plan --help prints the help" grep -q '^Usage:' <<<"$hout"
check "024: squad plan --help writes no plan and starts no planner" sh -c "test ! -e .team/PLAN.md && test \"\$(grep -c ' PLAN_START ' .team/events.log)\" = '$p0' && ! grep -qv '^herdr agent list' '$MOCK_LOG'"
hbad=0
for c in new init up brief status clean down config doctor presets "done" usage watch git heavy update-conf dispatch merge candidate notify consult plan ui-setup timed start-seat decisions feedback report permissions; do
  for h in -h --help; do o=$("$squad" "$c" "$h" 2>/dev/null </dev/null) || hbad=$((hbad + 1)); grep -q '^Usage:' <<<"$o" || hbad=$((hbad + 1)); done
done
check "024: -h and --help print the help on every command" test "$hbad" = 0
check "024: and they change no file and send herdr nothing" sh -c "test '$(snap24)' = '$s0' && ! grep -qv '^herdr agent list' '$MOCK_LOG' && test \"\$(grep -c ' PLAN_START ' .team/events.log)\" = '$p0'"
check "024: squad plan refuses an option it does not know, and writes no plan" sh -c "! '$squad' plan --aprove >/dev/null 2>&1 && ! '$squad' plan 'a goal' --help >/dev/null 2>&1 && test ! -e .team/PLAN.md"
cp "$tmp/plan.keep24" .team/PLAN.md

# the Stop hook: a Claude seat's settings call 'squad seat-hook Stop', which records its background tasks
check "024: a seat's settings carry the Stop hook beside the SessionStart hook" sh -c "jq -e '(.hooks.Stop[0].hooks[0].command | test(\"/squad. seat-hook Stop\$\")) and (.hooks.SessionStart[0].hooks[0].command | test(\"session-id\"))' .team/seats/dev-a.settings.json"
printf '{"session_id":"s1","background_tasks":[{"id":"b1","type":"shell"}],"session_crons":[]}' | TEAM_ROLE=dev-a "$squad" seat-hook Stop || true
check "024: the Stop hook records a seat that waits for its own background work" grep -qE '^1 [0-9]+$' .team/seats/dev-a.background
# a dispatch to a seat that herdr shows idle, while it waits for its own work: queued, nothing cleared
waits24() { # <task>: the task is queued for dev-a and, 4 s later, dev-a got no prompt at all
  local o; o=$(MOCK_DYNAMIC=1 SQUAD_QUEUE_POLL=1 SQUAD_DISPATCH_WAIT=5 "$squad" dispatch dev-a "$1" 2>&1) || return 1
  grep -q "is busy: $1 waits" <<<"$o" || return 1
  sleep 4
  grep -q " dev-a $1 DISPATCH_QUEUED" .team/events.log && ! grep -q " dev-a $1 DISPATCH round" .team/events.log && ! grep -q 'agent prompt dev-a' "$MOCK_LOG"
}
sent24() { local _; for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do grep -q " dev-a $1 DISPATCH round" .team/events.log && return 0; sleep 1; done; return 1; }
for t in T-920 T-921 T-922; do printf 'x\n' >".team/reports/$t-contract.md"; done
reset_log; echo idle >"$tmp/state"
check "024: a dispatch to a seat that waits on background work stays queued; nothing is cleared" waits24 T-920
printf '{"session_id":"s1","background_tasks":[]}' | TEAM_ROLE=dev-a "$squad" seat-hook Stop || true
check "024: it is sent once the seat's turn ends with no background work" sent24 T-920
sleep 3; reset_log; echo idle >"$tmp/state"; mkdir -p "$HV/queue"; : >"$HV/queue/999999999990-$$-dev-a@proj4"
check "024: a dispatch to a seat that waits in the heavy lock queue stays queued; nothing is cleared" waits24 T-921
rm -f "$HV/queue/999999999990-$$-dev-a@proj4"
check "024: it is sent once the seat left the queue" sent24 T-921
sleep 3; reset_log; echo idle >"$tmp/state"
git -C "$tmp/proj4-team/dev-a" add -A; git -C "$tmp/proj4-team/dev-a" commit -qm "wip 024" || true   # a dev's run needs a clean worktree
"$squad" heavy dev-a T-922 -- sleep 12 >/dev/null 2>&1 & hv24=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -L "$HV/lock" ] && break; sleep 0.5; done
check "024: a dispatch to a seat whose heavy run is alive stays queued; nothing is cleared" waits24 T-922
check "024: the run was still alive then" kill -0 "$hv24"
wait "$hv24" || true
check "024: it is sent once the run ended" sent24 T-922
sleep 3; rm -f "$tmp/state"
# the same seat gets no STALLED and no IDLE alarm
agents_c='{"result":{"agents":[{"name":"dev-c","agent_status":"idle"},{"name":"lead","agent_status":"working"}]}}'
printf '%s dev-c T-923 DISPATCH round=1\n' "$(now)" >>.team/events.log
stall24() { rm -rf .team/observer/.alerted; mkdir -p .team/observer/.seen; echo $(( $(date +%s) - 3600 )) >.team/observer/.seen/dev-c; MOCK_AGENTS="$agents_c" "$squad" watch --once 2>/dev/null | grep -q 'dev-c ○ stalled'; }
: >"$HV/queue/999999999991-$$-dev-c@proj4"
check "024: a seat that waits in the heavy lock queue is not stalled" refuses stall24
: >"$HV/queue/999999999992-999999-dev-c@proj4"; rm -f "$HV/queue/999999999991-$$-dev-c@proj4"
check "024: a queue place whose process is gone does not count: the seat is stalled" stall24
rm -f "$HV/queue/999999999992-999999-dev-c@proj4"; : >"$HV/queue/999999999993-$$-dev-c@other"
check "024: nor does a seat of the same name in another team" stall24
rm -f "$HV/queue/999999999993-$$-dev-c@other"
printf '{"background_tasks":[{"id":"b1"}]}' | TEAM_ROLE=dev-c "$squad" seat-hook Stop || true
check "024: a seat that waits for its own background work is not stalled" refuses stall24
printf '2 %s\n' $(( $(date +%s) - 3660 )) >.team/seats/dev-c.background
check "024: a Stop hook reading older than an hour does not count" stall24
printf '{"background_tasks":[{"id":"b1"}]}' | TEAM_ROLE=dev-c "$squad" seat-hook Stop || true; printf '{"session_id":"s3","source":"compact"}' | "$squad" session-id dev-c
check "9: a compaction keeps the reading (the session id is still recorded)" sh -c "grep -qE '^1 [0-9]+$' .team/seats/dev-c.background && grep -qx s3 .team/seats/dev-c.session"
printf '{"session_id":"s2","source":"clear"}' | "$squad" session-id dev-c
check "024: a new or cleared session forgets the reading" sh -c "test ! -e .team/seats/dev-c.background && grep -qx s2 .team/seats/dev-c.session"
printf '%s dev-c T-923 DONE\n' "$(now)" >>.team/events.log
cp .team/TASKS.md "$tmp/tasks.keep24"
printf '# Tasks\n\n| ID | Title | Owner | Status | Depends on |\n|---|---|---|---|---|\n| T-001 | a | dev-a | merged | - |\n| T-002 | b | - | todo | - |\n| T-003 | c | - | todo | T-002 |\n' >.team/TASKS.md
idle24() { MOCK_AGENTS="$agents_c" "$squad" watch --once >/dev/null 2>&1 || true; }   # dev-c: idle, no open task
rm -rf .team/observer/.idle; mkdir -p .team/observer/.idle; echo $(( $(date +%s) - 1860 )) >.team/observer/.idle/dev-c
: >"$HV/queue/999999999994-$$-dev-c@proj4"; reset_log; i0=$(grep -c ' dev-c - IDLE ' .team/events.log || true); idle24
check "024: a dev with no task that waits in the heavy lock queue gets no IDLE alarm" sh -c "! grep -q 'dev-c has had no task' '$MOCK_LOG' && ! grep -q 'notification show squad: dev-c' '$MOCK_LOG' && test \"\$(grep -c ' dev-c - IDLE ' .team/events.log)\" = '$i0'"
rm -f "$HV/queue/999999999994-$$-dev-c@proj4"
# 8: the background reading counts only while the seat's task is open (a dev server it keeps alive after its report)
printf '1 %s\n' "$(date +%s)" >.team/seats/dev-c.background; echo $(( $(date +%s) - 600 )) >.team/observer/.idle/dev-c; reset_log; idle24
check "8: a seat with no open task is not busy by its background work: its IDLE alarm comes" log_has "agent prompt lead [squad] dev-c has had no task"
rm -f .team/seats/dev-c.background; rm -rf .team/observer/.idle; mkdir -p .team/observer/.idle
# no task for 30 min with open tasks: the owner gets one notification, after the lead was told
echo $(( $(date +%s) - 600 )) >.team/observer/.idle/dev-c; reset_log; idle24
check "024: at 5 min the lead is told, the owner is not" sh -c "grep -q 'agent prompt lead \[squad\] dev-c has had no task for 10 min' '$MOCK_LOG' && ! grep -q 'notification show squad: dev-c' '$MOCK_LOG'"
echo $(( $(date +%s) - 1860 )) >.team/observer/.idle/dev-c; reset_log; idle24; idle24
check "024: at 30 min the owner gets one notification: the seat, the minutes, the open tasks" sh -c "test \"\$(grep -c 'notification show squad: dev-c has no task --body dev-c has had no task for 31 min; 2 open task(s)' '$MOCK_LOG')\" = 1 && ! grep -q 'agent prompt lead \[squad\] dev-c has had no task' '$MOCK_LOG'"
check "024: and events.log has the line" grep -q ' dev-c - IDLE no task for 31 min, 2 open task(s): the owner is told' .team/events.log
printf '# Tasks\n\n| ID | Title | Owner | Status | Depends on |\n|---|---|---|---|---|\n| T-001 | a | dev-a | merged | - |\n' >.team/TASKS.md
rm -f .team/observer/.idle/dev-c.told.owner; reset_log; idle24
check "024: with no open task the owner is not told" refuses grep -q 'notification show squad: dev-c' "$MOCK_LOG"
cp "$tmp/tasks.keep24" .team/TASKS.md; rm -rf .team/observer/.idle
# ---- 2a · squad's own messages wait while the lead shows a dialog (herdr: blocked, or a menu in its pane) ----
agents_lb='{"result":{"agents":[{"name":"dev-c","agent_status":"idle"},{"name":"lead","agent_status":"blocked"}]}}'
agents_lf='{"result":{"agents":[{"name":"dev-c","agent_status":"idle"},{"name":"lead","agent_status":"idle"}]}}'
tick() { MOCK_AGENTS=$1 MOCK_PANE_TEXT=${2:-} "$squad" watch --once >/dev/null 2>&1 || true; }   # <agents> [<every pane's text>]
no_lead() { ! grep -q 'agent prompt lead' "$MOCK_LOG"; }
mkdir -p .team/observer/.idle; echo $(( $(date +%s) - 600 )) >.team/observer/.idle/dev-c; i0=$(grep -c ' dev-c - IDLE ' .team/events.log || true)
reset_log; tick "$agents_lb"; MOCK_PANE_ONLY=lead tick "$agents_lf" "$ask"
check "2a: an idle dev is not told to a lead that is blocked or shows a menu, and is not marked as told" sh -c "! grep -q 'agent prompt lead' '$MOCK_LOG' && test ! -e .team/observer/.idle/dev-c.told && test \"\$(grep -c ' dev-c - IDLE ' .team/events.log)\" = '$i0'"
reset_log; tick "$agents_lf" "$rdy"; tick "$agents_lf" "$rdy"
check "2a: the lead is told when the dialog is gone, once" test "$(grep -c 'agent prompt lead \[squad\] dev-c has had no task' "$MOCK_LOG")" = 1
printf '%s dev-c T-924 DISPATCH round=1\n' "$(now)" >>.team/events.log
rm -rf .team/observer/.alerted; mkdir -p .team/observer/.seen; echo $(( $(date +%s) - 3600 )) >.team/observer/.seen/dev-c
reset_log; tick "$agents_lb"; MOCK_PANE_ONLY=lead tick "$agents_lf" "$ask"
check "2a: a stalled seat is not told to a lead that shows a dialog" no_lead
check "2a: its event is logged once" test "$(grep -c ' dev-c T-924 SEAT_STALLED' .team/events.log)" = 1
reset_log; tick "$agents_lf" "$rdy"; tick "$agents_lf" "$rdy"
check "2a: the lead is told of the stalled seat when the dialog is gone, once" test "$(grep -c 'agent prompt lead \[squad\] dev-c is stalled on T-924' "$MOCK_LOG")" = 1
check "2a: the event is not logged again" test "$(grep -c ' dev-c T-924 SEAT_STALLED' .team/events.log)" = 1
printf '%s dev-c T-924 DONE\n' "$(now)" >>.team/events.log
mkdir -p .team/seats/dev-a.pending; printf 'squad-request\0dev-a\0T-931\0' >".team/seats/dev-a.pending/1000000000000000009-999999-T-931"
reset_log; tick "$agents_lb"
check "2a: a lost request is not told to a lead that shows a dialog: it stays for a later tick" sh -c "! grep -q 'agent prompt lead' '$MOCK_LOG' && ls .team/seats/dev-a.pending/*-T-931 >/dev/null 2>&1 && ! grep -q ' dev-a T-931 DISPATCH_LOST' .team/events.log"
reset_log; tick "$agents_lf" "$rdy"
check "2a: the lead hears of it when the dialog is gone" sh -c "grep -q 'agent prompt lead .*T-931 waited for dev-a' '$MOCK_LOG' && grep -q ' dev-a T-931 DISPATCH_LOST' .team/events.log"
# a queued dispatch that fails while the lead shows a dialog: its request is kept, and the watch tells the lead later
agents_q='{"result":{"agents":[{"name":"dev-a","agent_status":"working"},{"name":"lead","agent_status":"blocked"}]}}'
printf 'x\n' >.team/reports/T-932-contract.md
reset_log; MOCK_AGENTS=$agents_q SQUAD_DISPATCH_QUEUE_WAIT=2 SQUAD_QUEUE_POLL=1 "$squad" dispatch dev-a T-932 >/dev/null 2>&1 || true
k=0; until grep -q ' dev-a T-932 DISPATCH_FAILED' .team/events.log || [ "$k" -ge 20 ]; do k=$((k + 1)); sleep 1; done; sleep 2
check "2a: a queued dispatch that fails while the lead shows a dialog types nothing into the lead and keeps its request" sh -c "grep -q ' dev-a T-932 DISPATCH_FAILED' .team/events.log && ! grep -q 'agent prompt lead' '$MOCK_LOG' && ls .team/seats/dev-a.pending/*-T-932 >/dev/null 2>&1"
reset_log; tick "$agents_lf" "$rdy"
check "2a: the watch tells the lead when the dialog is gone" grep -q 'agent prompt lead .*T-932 waited for dev-a' "$MOCK_LOG"
# the team stall line (the newest event is an old verdict)
cp .team/events.log "$tmp/ev.keep2a"; printf '2026-01-01 10:00:00 rev-gpt T-930 CHANGES review=1\n' >.team/events.log
rm -f .team/observer/.watchdog/stall-* .team/observer/.watchdog/held-stall-*
reset_log; tick "$agents_lb"
check "2a: a team stall is told to the owner, and nothing is typed into a lead that shows a dialog" sh -c "grep -q 'notification show squad: proj4 stalled' '$MOCK_LOG' && ! grep -q 'agent prompt lead' '$MOCK_LOG'"
reset_log; tick "$agents_lf" "$rdy"; tick "$agents_lf" "$rdy"
check "2a: the lead gets the stall line when the dialog is gone, once" test "$(grep -c 'agent prompt lead \[squad\] No event for .*T-930 CHANGES' "$MOCK_LOG")" = 1
cp "$tmp/ev.keep2a" .team/events.log
# ---- 026 · candidate runs lose less time ---------------------------------------------
c2=$(git -C "$I" rev-parse candidate/CANDIDATE-2)
"$squad" candidate CANDIDATE-2 T-912 >"$tmp/cout" 2>&1 && crc=0 || crc=$?
check "026: a candidate number that has a commit is refused, with the next free number" sh -c "[ $crc != 0 ] && grep -q 'CANDIDATE-4' '$tmp/cout' && [ \$(git -C '$I' rev-parse candidate/CANDIDATE-2) = $c2 ]"
cp .team/tasks/CANDIDATE-1.md .team/tasks/CANDIDATE-8.md; printf 'true\n' >.team/tasks/CANDIDATE-8.checks; mkdir -p .team/receipts/CANDIDATE-8
"$squad" candidate CANDIDATE-8 T-912 >"$tmp/cout" 2>&1 && crc=0 || crc=$?
check "026: a candidate number that has only a receipt is refused too" sh -c "[ $crc != 0 ] && grep -q 'CANDIDATE-9' '$tmp/cout' && ! git -C '$I' rev-parse -q --verify candidate/CANDIDATE-8"
rm -rf .team/receipts/CANDIDATE-8 .team/tasks/CANDIDATE-8.*
# a step that fails on its first run only (the hive case: "Failed to fetch dynamically imported module")
cp .team/tasks/CANDIDATE-1.md .team/tasks/CANDIDATE-4.md
printf 'echo one\ntest -f %s/flaky || { : >%s/flaky; echo first-run failure; exit 7; }\necho three\n' "$tmp" "$tmp" >.team/tasks/CANDIDATE-4.checks
"$squad" candidate CANDIDATE-4 T-912 >/dev/null 2>&1 || true
echo old >.team/receipts/CANDIDATE-4   # a plain-file receipt from before ticket 026: a new run replaces it with the folder
frc=0; "$squad" heavy tester CANDIDATE-4 --batch .team/tasks/CANDIDATE-4.checks >/dev/null 2>&1 || frc=$?
R=.team/receipts/CANDIDATE-4
check "026: a new run replaces an old plain-file receipt with the folder" test -f $R/receipt
check "026: a batch step that fails once and passes alone does not fail the batch" sh -c "[ $frc = 0 ] && grep -qx 'step2=0' $R/receipt && grep -qx 'steps=3' $R/receipt"
check "026: the receipt names the flaky step" grep -qx 'flakes=2' $R/receipt
check "026: a FLAKE event is logged" grep -q ' tester CANDIDATE-4 FLAKE step=2/3 ' .team/events.log
check "026: the flake is one line in flakes.log" sh -c "[ \$(grep -c ' CANDIDATE-4 step=2/3 ' .team/flakes.log) = 1 ]"
check "026: a candidate batch keeps one log per step beside the receipt" sh -c "grep -qx one $R/step-1.log && test -f $R/step-2.log && grep -qx three $R/step-3.log && grep -qx 'first-run failure' $R/step-2.first.log"
# flake_rerun 0: any failure fails the batch, as before; the logs stay after the failure
cp .team/tasks/CANDIDATE-1.md .team/tasks/CANDIDATE-5.md; rm -f "$tmp/flaky"
cp .team/tasks/CANDIDATE-4.checks .team/tasks/CANDIDATE-5.checks
"$squad" candidate CANDIDATE-5 T-912 >/dev/null 2>&1 || true
printf 'flake_rerun 0\n' >>.team/team.conf
frc=0; "$squad" heavy tester CANDIDATE-5 --batch .team/tasks/CANDIDATE-5.checks >/dev/null 2>&1 || frc=$?
sed -i.bak '/^flake_rerun /d' .team/team.conf; rm -f .team/team.conf.bak
R=.team/receipts/CANDIDATE-5
check "026: with flake_rerun 0 a failed step fails the batch" sh -c "[ $frc = 7 ] && grep -qx 'step2=7' $R/receipt && ! grep -q ' CANDIDATE-5 FLAKE' .team/events.log && [ \$(grep -c ' tester CANDIDATE-5 HEAVY_START ' .team/events.log) = 3 ]"
check "026: the step logs are kept after a failure" sh -c "grep -qx 'first-run failure' $R/step-2.log && grep -qx three $R/step-3.log"
check "026: a receipt with a failed step is no PASS" refuses "$squad" "done" tester CANDIDATE-5 PASS
check "026: flake_rerun takes only 0 or 1" sh -c "printf 'flake_rerun 2\n' >>.team/team.conf; '$squad' heavy --status >/dev/null 2>&1; rc=\$?; sed -i.bak '/^flake_rerun /d' .team/team.conf; rm -f .team/team.conf.bak; [ \$rc != 0 ]"
# a candidate that is run again starts clean: the PASS receipt of the first run does not stay
cp .team/tasks/CANDIDATE-1.md .team/tasks/CANDIDATE-6.md; printf 'test ! -f %s/again || echo x >>t912.txt\n' "$tmp" >.team/tasks/CANDIDATE-6.checks
"$squad" candidate CANDIDATE-6 T-912 >/dev/null 2>&1 || true
"$squad" heavy tester CANDIDATE-6 --batch .team/tasks/CANDIDATE-6.checks >/dev/null 2>&1 || true
r6=$(grep -cx 'step1=0' .team/receipts/CANDIDATE-6/receipt 2>/dev/null || true); : >"$tmp/again"
"$squad" heavy tester CANDIDATE-6 --batch .team/tasks/CANDIDATE-6.checks >/dev/null 2>&1 || true   # this run changes a tracked file: it writes no receipt
git -C "$TW" checkout -q -- . 2>/dev/null || true
check "026: a stale PASS receipt is removed when the same candidate is run again" sh -c "[ '$r6' = 1 ] && test ! -e .team/receipts/CANDIDATE-6/receipt"
cp .team/reports/CANDIDATE-1-test.md .team/reports/CANDIDATE-4-test.md
check "026: the tester's PASS takes the receipt of a batch with a flake" "$squad" "done" tester CANDIDATE-4 PASS
# a plain-file receipt from before ticket 026 (.team/receipts/CANDIDATE-<N>) is no longer read (V!, 21 Nov 2026)
mv .team/receipts/CANDIDATE-4 "$tmp/r4"; cp "$tmp/r4/receipt" .team/receipts/CANDIDATE-4
"$squad" merge CANDIDATE-4 >"$tmp/cout" 2>&1 && crc=0 || crc=$?
check "026: squad merge refuses a plain-file receipt from before the change" sh -c "[ $crc != 0 ] && grep -q 'run the checks of CANDIDATE-4 again' '$tmp/cout'"
rm -f .team/receipts/CANDIDATE-4; mv "$tmp/r4" .team/receipts/CANDIDATE-4
"$squad" merge CANDIDATE-4 >"$tmp/cout" 2>&1 && crc=0 || crc=$?
check "026: and squad merge takes the folder receipt of a batch with a flake" sh -c "[ $crc = 0 ] && grep -q 'is now CANDIDATE-4' '$tmp/cout'"
# the wait for the lock is on record
"$squad" heavy tester T-926 -- sleep 3 >/dev/null 2>&1 &
for _ in $(seq 1 100); do grep -q ' tester T-926 HEAVY_START ' .team/events.log && break; sleep 0.1; done
"$squad" heavy tester T-927 -- true >/dev/null 2>&1 || true
wait
check "026: a seat that waits for the lock logs HEAVY_WAIT" grep -q ' tester T-927 HEAVY_WAIT ' .team/events.log
check "026: HEAVY_START carries the seconds waited" grep -qE ' tester T-927 HEAVY_START .* waited=[1-9][0-9]*s ' .team/events.log
check "026: a run that did not wait logs no wait" sh -c "! grep -q ' tester T-926 HEAVY_WAIT' .team/events.log && ! grep -q ' tester T-926 HEAVY_START .*waited=' .team/events.log"
# the observer gets no pass while the team has no open task
mv .team/events.log "$tmp/events.keep"; O=.team/observer
obs() { reset_log; MOCK_DYNAMIC=1 "$squad" watch --once --observe >/dev/null 2>&1 || true; grep -q 'agent prompt observer Observer pass' "$MOCK_LOG"; }
printf '2026-11-21 09:00:00 dev-a T-950 DISPATCH round=1\n2026-11-21 09:30:00 lead T-950 MERGE abc\n' >.team/events.log
echo 0 >$O/.last-pass
check "026: no observer pass while every dispatched task is merged" refuses obs
echo $(( $(date +%s) - 7200 )) >$O/.last-pass; rm -f $O/.last-marks   # the MERGE above is no "new event" for the next pass
check "026: no timed pass either while no task is open" refuses obs
printf '2026-11-21 10:00:00 dev-a T-951 DISPATCH round=1\n' >>.team/events.log
check "026: the first event after that starts the timer again, from that moment" refuses obs
echo $(( $(date +%s) - 7200 )) >$O/.last-pass
check "026: an open task gets its timed pass" obs
printf '2026-11-21 10:10:00 lead T-951 WITHDRAWN\n' >>.team/events.log; echo 0 >$O/.last-pass
check "026: a withdrawn task is not open" refuses obs
printf '2026-11-21 10:20:00 tester CANDIDATE-9 HEAVY_START sha=abc step=1/2 true\n' >>.team/events.log; echo 0 >$O/.last-pass
ln -s "tester@proj4:$$:$(date +%s):600" "$HV"/lock
check "026: a candidate run in progress counts as work" obs
rm -f "$HV"/lock
printf '2026-11-21 10:30:00 tester CANDIDATE-9 HEAVY_END rc=0 1m step=1/2\n' >>.team/events.log; echo 0 >$O/.last-pass
check "026: a candidate run that ended does not" refuses obs
# a dispatch that failed or did not start closes what that attempt opened, and nothing else
printf '2026-11-21 10:40:00 dev-a T-952 DISPATCH round=1\n2026-11-21 10:40:20 dev-a T-952 DISPATCH_NOT_STARTED no running turn in 20s\n' >>.team/events.log; echo 0 >$O/.last-pass
check "026: a dispatch that did not start is no open task for the observer" refuses obs
printf '2026-11-21 10:41:00 dev-a T-953 DISPATCH round=1\n2026-11-21 10:41:05 dev-a T-953 DISPATCH_FAILED could not send\n' >>.team/events.log; echo 0 >$O/.last-pass
check "026: a dispatch that failed is no open task for the observer" refuses obs
printf '2026-11-21 10:42:00 dev-b T-954 DISPATCH round=1\n2026-11-21 10:42:10 dev-a T-954 DISPATCH round=1\n2026-11-21 10:42:15 dev-a T-954 DISPATCH_FAILED could not send\n' >>.team/events.log; echo 0 >$O/.last-pass
check "026: a failed dispatch does not close another seat's dispatch of the same task" obs
cat .team/events.log >>"$tmp/events.keep"; mv "$tmp/events.keep" .team/events.log
# ---- the real trial of 21 Nov 2026 (herdr 0.9.5, Claude Code 2.1.323): squad never types into a seat that shows a dialog ----
cd "$tmp"; "$squad" new trial >/dev/null 2>&1; cd trial; reset_log
printf 'seat lead claude lead -\nseat dev-a claude dev -\nseat dev-b claude dev -\nseat tester claude tester -\nupgrade off\n' >.team/team.conf
"$squad" up >/dev/null 2>&1 || true
SW=.team/observer/.watchdog; NT=.team/observer/.notices; mkdir -p "$SW"
# the screen of a question in a 45-column pane, as the second trial captured it (herdr showed the seat idle): the selected
# row is 13 lines above the bottom, and "Esc to cancel" is wrapped onto two lines
longq="$here/fixtures/panes/long-question.txt"
t_up='{"result":{"agents":[{"name":"lead","agent_status":"working","pane_id":"w2:p1"},{"name":"dev-a","agent_status":"working","pane_id":"w2:p2"},{"name":"dev-b","agent_status":"idle","pane_id":"w2:p3"}]}}'
t_free='{"result":{"agents":[{"name":"lead","agent_status":"idle","pane_id":"w2:p1"},{"name":"dev-a","agent_status":"working","pane_id":"w2:p2"},{"name":"dev-b","agent_status":"working","pane_id":"w2:p3"}]}}'
t_gone='{"result":{"agents":[{"name":"lead","agent_status":"working","pane_id":"w2:p1"},{"name":"dev-b","agent_status":"working","pane_id":"w2:p3"}]}}'
hook() { printf '%s' "$3" | TEAM_ROLE=$1 "$squad" seat-hook "$2"; }   # <seat> <event> <the hook's JSON>
asks() { hook "$1" AskUserQuestion '{"tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Which storage?"}]}}'; }
perm() { hook "$1" PermissionRequest '{"tool_name":"Bash","tool_input":{"command":"rm x"}}'; }
answered() { hook "$1" PostToolUse '{"tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Which storage?"}],"answers":{"Which storage?":"Disk"}}}'; }   # <seat>: the owner answered its question
W=.team/seats/dev-b.owner-wait
# 2: has_menu reads the whole visible screen and a wrapped footer (seen through squad notify, which skips a seat with a dialog)
ev dev-a T-960 DISPATCH round=1
told() { reset_log; MOCK_AGENTS=$t_up MOCK_PANE_TEXT=$1 "$squad" notify PROTOCOL.md "a rule" >/dev/null 2>&1 || true; log_has "agent prompt dev-a [squad] Rule changed"; }   # <every pane's text>
check "trial 2: a long question is a dialog: its selected row is 13 lines above the bottom, outside the last 12" refuses told "$(cat "$longq")"
check "trial 2: a dialog footer wrapped onto two lines is a dialog (the selected row is off the screen)" refuses told "$(tail -8 "$longq")"
check "trial 2: a prompt with '/clear' stranded in its input line is no dialog" told "$(printf 'Claude Code\n❯ /clear')"
check "trial 2: a dialog's words far above an empty prompt are no dialog" told "$(printf 'I wrote the text: press esc to cancel.\n%s\n❯ ' "$(seq 1 14)")"
ev dev-a T-960 DONE
# 1: the hook's record of an open dialog, and what ends it
jq_hooks='(.hooks.PostToolUse[0].hooks[0].command | endswith("seat-hook PostToolUse")) and (.hooks.PostToolUse[0] | has("matcher") | not) and (.hooks.UserPromptSubmit[0].hooks[0].command | endswith("seat-hook UserPromptSubmit"))'
check "trial 1: a Claude seat's settings carry the PostToolUse and UserPromptSubmit hooks" jq -e "$jq_hooks" .team/seats/dev-a.settings.json
check "trial 1: the worktree's settings carry them too" jq -e "$jq_hooks" "$tmp/trial-team/dev-a/.claude/settings.local.json"
perm dev-b
check "trial 1: the record names when, the tool, the length of events.log and the checksum of the call's input" grep -qE '^[0-9]+ Bash [0-9]+ [0-9]+$' "$W"
hout=$(hook dev-b PostToolUse '{"tool_name":"Read"}' 2>&1)
check "trial 1: the end of another tool does not end the record, and the hook prints nothing" test -f "$W" -a -z "$hout"
hook dev-b PostToolUse '{"tool_name":"Bash","tool_input":{"command":"rm x"}}'
check "trial 1: the end of the tool the dialog asked for ends the record (PostToolUse)" test ! -e "$W"
asks dev-b; check "trial 1: a question is recorded with its tool" grep -qE '^[0-9]+ AskUserQuestion [0-9]+ [0-9]+$' "$W"
answered dev-b
check "trial 1: an answered question ends the record (PostToolUse)" test ! -e "$W"
asks dev-b; hook dev-b Stop '{"background_tasks":[]}'
check "trial 1: the end of the turn ends the record (Stop)" test ! -e "$W"
asks dev-b; hook dev-b UserPromptSubmit '{"prompt":"go on"}'
check "trial 1: a submitted prompt ends the record (UserPromptSubmit)" test ! -e "$W"
asks dev-b; hook dev-b SessionStart '{"source":"clear"}'
check "trial 1: a new start of the session ends the record (SessionStart)" test ! -e "$W"
rm -f .team/seats/dev-b.no-options .team/seats/dev-b.background; sleep 1   # the background notifications ended
# herdr shows a seat with a question in a narrow pane as idle for the whole dialog: the record counts for longer than 2 minutes
printf 'x\n' >.team/reports/T-961-contract.md
asks dev-b; age "$W" 1 300; ev dev-b T-961 SEAT_STALLED; ev dev-b T-961 DISPATCH_QUEUED waits
MOCK_AGENTS=$t_up watch1
check "trial 1: an old record stays while nothing the seat did says the dialog is over (squad's own events of the seat do not count)" test -f "$W"
reset_log; MOCK_AGENTS=$t_up "$squad" dispatch dev-b T-961 >/dev/null 2>&1 || true
check "trial 1: and it still holds the seat's dispatch" sh -c "grep -q ' dev-b T-961 DISPATCH_QUEUED waits for dev-b' .team/events.log && ! grep -q 'agent prompt dev-b' '$MOCK_LOG'"
pkill -f "squad dispatch dev-b T-961" 2>/dev/null || true; rm -rf .team/seats/dev-b.pending
printf '0 %s\n' "$(date +%s)" >.team/seats/dev-b.background; MOCK_AGENTS=$t_up watch1
check "trial 1: a stale record does not count: the seat ended a turn after it (a newer Stop)" test ! -e "$W"
rm -f .team/seats/dev-b.background
asks dev-b; age "$W" 1 300; ev dev-b T-961 DONE; MOCK_AGENTS=$t_up watch1
check "trial 1: a stale record does not count: the seat reported after it (a newer event in events.log)" test ! -e "$W"
sleep 1; asks dev-b; ev dev-b T-961 DONE; MOCK_AGENTS=$t_up watch1
check "trial 1: a record younger than 2 minutes counts whatever came after it" test -f "$W"
rm -f "$W" "$SW"/held-*
# 3: a dispatch types nothing into a seat that shows a dialog: it waits in the queue and goes out when the dialog is gone
printf 'x\n' >.team/reports/T-962-contract.md; printf 'x\n' >.team/reports/T-963-contract.md
typed() { grep -qE "agent (prompt|send-keys) $1" "$MOCK_LOG"; }   # <seat>: squad typed into its pane
sent_soon() { local k=0; until grep -q " dev-a $1 DISPATCH round=1" .team/events.log && log_has "agent prompt dev-a Task $1 is yours"; do k=$((k + 1)); [ "$k" -lt 30 ] || return 1; sleep 1; done; }   # <task>
cp "$longq" "$tmp/pane"; echo idle >"$tmp/state"; reset_log
MOCK_DYNAMIC=1 MOCK_PANE_FILE="$tmp/pane" SQUAD_QUEUE_POLL=1 SQUAD_DISPATCH_WAIT=5 "$squad" dispatch dev-a T-962 >/dev/null 2>&1 || true
sleep 3
check "trial 3: a dispatch to a seat that herdr shows idle while its pane shows a long question is queued" grep -q ' dev-a T-962 DISPATCH_QUEUED' .team/events.log
check "trial 3: nothing is typed into that seat: no /clear, no task" refuses typed dev-a
rm -f "$tmp/pane"   # the owner answered the question
check "trial 3: the task goes out when the dialog is gone" sent_soon T-962
ev dev-a T-962 DONE; echo idle >"$tmp/state"; asks dev-a; reset_log
MOCK_DYNAMIC=1 SQUAD_QUEUE_POLL=1 SQUAD_DISPATCH_WAIT=5 "$squad" dispatch dev-a T-963 >/dev/null 2>&1 || true
sleep 3
check "trial 3: a seat whose only sign of a dialog is the hook's record gets its dispatch queued, and nothing typed" sh -c "grep -q ' dev-a T-963 DISPATCH_QUEUED' .team/events.log && ! grep -qE 'agent (prompt|send-keys) dev-a' '$MOCK_LOG'"
answered dev-a
check "trial 3: it goes out when the hook says the question is answered" sent_soon T-963
ev dev-a T-963 DONE; rm -f "$tmp/state"
# 4: squad's own lines to the lead wait while the lead shows a dialog, and none is lost
reset_log; dout=$(MOCK_AGENTS=$t_free MOCK_PANE_TEXT=$(cat "$longq") "$squad" "done" dev-a T-964 BLOCKED 2>&1) || true
check "trial 4: squad done types nothing into a lead that shows a dialog, and says that its notice is held" sh -c "! grep -q 'agent prompt lead' '$MOCK_LOG' && printf '%s\n' \"\$1\" | grep -q '^held: lead shows a dialog' && grep -q ' dev-a T-964 BLOCKED' .team/events.log" _ "$dout"
MOCK_AGENTS=$t_free MOCK_PANE_TEXT=$(cat "$longq") watch1
check "trial 4: the watch does not send it while the dialog is there" refuses log_has "agent prompt lead"
MOCK_AGENTS=$t_free MOCK_PANE_TEXT=$rdy watch1; MOCK_AGENTS=$t_free MOCK_PANE_TEXT=$rdy watch1
check "trial 4: the first tick with the lead free sends the held notice, once, as a first send" sh -c "[ \$(grep -c 'agent prompt lead \[squad\] dev-a finished T-964: BLOCKED' '$MOCK_LOG') = 1 ] && ! grep -q 'T-964.*Sent again' '$MOCK_LOG'"
ev lead T-964 SEEN; watch1
asks lead; reset_log; fout=$(MOCK_AGENTS=$t_free MOCK_PANE_TEXT=$rdy "$squad" feedback "The save button does nothing" 2>&1) || true
check "trial 4: squad feedback types nothing into a lead with an open question (the hook's record), saves it and says it is held" sh -c "! grep -q 'agent prompt lead' '$MOCK_LOG' && printf '%s\n' \"\$1\" | grep -q 'F-1 saved in .team/FEEDBACK.md and held' && grep -q 'The save button does nothing' .team/FEEDBACK.md" _ "$fout"
answered lead
MOCK_AGENTS=$t_free MOCK_PANE_TEXT=$rdy watch1; MOCK_AGENTS=$t_free MOCK_PANE_TEXT=$rdy watch1
check "trial 4: the watch delivers the held feedback when the lead is free, once" test "$(grep -c 'agent prompt lead \[squad\] Feedback F-1 from' "$MOCK_LOG")" = 1
# 6: a seat that is gone: the lead's "is dead … run 'squad up'" line
export MOCK_WS='{"result":{"workspaces":[{"workspace_id":"w2","label":"trial team"}]}}'
export MOCK_PANES='{"result":{"panes":[{"pane_id":"w2:p1","label":"lead"},{"pane_id":"w2:p2","label":"dev-a"},{"pane_id":"w2:p3","label":"dev-b"}]}}'
ev dev-a T-965 DISPATCH round=1; rm -rf .team/observer/.alerted "$SW"; mkdir -p "$SW"
reset_log; MOCK_AGENTS=$t_gone watch1
check "trial 6: seat_restart off: the lead gets the line of a seat that is gone" sh -c "grep -q \"agent prompt lead \[squad\] dev-a is dead on T-965: its agent is gone (closed pane or crash): run 'squad up'\" '$MOCK_LOG' && ! grep -q 'agent start dev-a' '$MOCK_LOG'"
rm -rf .team/observer/.alerted "$SW"; mkdir -p "$SW"; d0=$(grep -c ' dev-a T-965 SEAT_DEAD' .team/events.log)
printf 'seat_restart on\n' >>.team/team.conf; reset_log; MOCK_AGENTS=$t_gone watch1
check "trial 6: seat_restart on: the watch starts the seat again in the same tick, and the event is logged" sh -c "grep -q '^herdr agent start dev-a ' '$MOCK_LOG' && [ \$(grep -c ' dev-a T-965 SEAT_DEAD' .team/events.log) = $((d0 + 1)) ]"
check "trial 6: seat_restart on: the lead does not get the 'is dead … run squad up' line" refuses log_has "agent prompt lead [squad] dev-a is dead"
# 5: a running watch reads team.conf again when it changes
sed -i.bak '/^seat_restart /d' .team/team.conf; rm -f .team/team.conf.bak; rm -rf .team/observer/.alerted "$SW"; mkdir -p "$SW"; reset_log
MOCK_AGENTS=$t_gone SQUAD_WATCH_POLL=1 "$squad" watch >/dev/null 2>&1 & wpid=$!
sleep 4
check "trial 5: with seat_restart off the running watch starts no seat" refuses log_has "agent start dev-a"
printf 'seat_restart on\n' >>.team/team.conf
check "trial 5: a running watch picks up seat_restart on from the changed team.conf" sh -c "for k in \$(seq 1 30); do grep -q '^herdr agent start dev-a ' '$MOCK_LOG' && exit 0; sleep 1; done; exit 1"
printf 'no_such_setting 1\n' >>.team/team.conf; sleep 3
check "trial 5: a team.conf that does not load does not end the running watch" kill -0 "$wpid"
kill "$wpid" 2>/dev/null || true; wait "$wpid" 2>/dev/null || true
unset MOCK_WS MOCK_PANES
# ---- the second trial of 21 Nov 2026: Escape closes a dialog and fires no hook; a seat that shows a dialog is not stalled ----
printf 'seat lead claude lead -\nseat dev-a claude dev -\nseat dev-b claude dev -\nseat tester claude tester -\nupgrade off\n' >.team/team.conf
rm -rf .team/observer/.alerted .team/observer/.seen .team/observer/.idle "$SW"; mkdir -p "$SW" .team/observer/.seen .team/observer/.idle
esc=$(cat "$here/fixtures/panes/after-escape.txt")   # the real screen after Escape: the answer was declined, the prompt is empty
FR=$W.free; HW=$SW/held-wait-dev-b
seen() { printf '%s %s\n' "$(sed -n '1p' "$W" | cut -d' ' -f1)" "$(ago "$1")" >"$FR"; }   # <seconds>: the free prompt was first seen that long ago, for this record
# 8: the screen ends a hook record that Escape left behind
ev dev-b T-966 DISPATCH round=1
asks dev-b; sleep 1; age "$W" 1 60
MOCK_AGENTS=$t_up MOCK_PANE_TEXT=$esc watch1
check "trial 8: one sighting of a free prompt does not end the hook's record, and the owner's alert stays" test -f "$W" -a -f "$FR" -a -f "$HW"
age "$FR" 2 15; MOCK_AGENTS=$t_up MOCK_PANE_TEXT=$esc watch1
check "trial 8: after Escape the second sighting of the free prompt, 10 s later, ends the record" test ! -e "$W" -a ! -e "$FR"
check "trial 8: the owner's alert of that wait ends with it" test ! -e "$HW"
asks dev-b; sleep 1; age "$W" 1 300; seen 15
MOCK_AGENTS=$t_up MOCK_PANE_TEXT=$(cat "$longq") watch1
check "trial 8: a pane that shows a long question keeps the record, and the earlier sighting does not count" test -f "$W" -a ! -e "$FR" -a -f "$HW"
seen 15; MOCK_AGENTS=$t_up watch1
check "trial 8: a pane that cannot be read keeps the record" test -f "$W" -a -f "$HW"
age "$W" 1 5; seen 15; MOCK_AGENTS=$t_up MOCK_PANE_TEXT=$esc watch1
check "trial 8: a record younger than 20 s is kept whatever the screen shows" test -f "$W"
age "$W" 1 300; seen 15; MOCK_AGENTS=$(sed 's/"dev-b","agent_status":"idle"/"dev-b","agent_status":"blocked"/' <<<"$t_up") MOCK_PANE_TEXT=$esc watch1
check "trial 8: a seat that herdr shows blocked keeps the record" test -f "$W"
answered dev-b; ev dev-b T-966 DONE; rm -f "$FR" "$SW"/held-*
printf 'x\n' >.team/reports/T-967-contract.md; echo idle >"$tmp/state"; asks dev-a; sleep 1; age .team/seats/dev-a.owner-wait 1 60; reset_log
qout=$(MOCK_DYNAMIC=1 SQUAD_QUEUE_POLL=1 SQUAD_DISPATCH_WAIT=5 "$squad" dispatch dev-a T-967 2>&1) || true
sleep 4
check "trial 8: a dispatch to a seat with a record that Escape left waits: one sighting is not enough" sh -c "grep -q ' dev-a T-967 DISPATCH_QUEUED' .team/events.log && ! grep -q ' dev-a T-967 DISPATCH round' .team/events.log && ! grep -qE 'agent (prompt|send-keys) dev-a' '$MOCK_LOG'"
check "trial 8: the queued task goes out after the second sighting" sent_soon T-967
sleep 3
check "trial 8: it goes out once, and the record is gone" sh -c "[ \$(grep -c ' dev-a T-967 DISPATCH round=1' .team/events.log) = 1 ] && [ \$(grep -c 'agent prompt dev-a Task T-967 is yours' '$MOCK_LOG') = 1 ] && test ! -e .team/seats/dev-a.owner-wait"
# 10: the message of a dispatch that is held because the seat shows a dialog
check "trial 10: a dispatch held by a dialog says that the seat shows a dialog or a question, not that it is busy" sh -c "printf '%s\n' \"\$1\" | grep -q 'dev-a shows a dialog or a question: T-967 waits and is sent when it is answered' && ! printf '%s\n' \"\$1\" | grep -q 'is busy'" _ "$qout"
ev dev-a T-967 DONE; rm -f "$tmp/state"
# 9: a seat that shows a dialog is blocked, never stalled and never idle (herdr shows a question in a narrow pane as idle)
ev dev-b T-968 DISPATCH round=1; rm -rf .team/observer/.alerted; ago 3600 >.team/observer/.seen/dev-b
asks dev-b; sleep 1; reset_log
bout=$(MOCK_AGENTS=$t_up MOCK_PANE_ONLY=dev-b MOCK_PANE_TEXT=$(cat "$longq") "$squad" watch --once 2>/dev/null || true); MOCK_AGENTS=$t_up MOCK_PANE_ONLY=dev-b MOCK_PANE_TEXT=$(cat "$longq") watch1
check "trial 9: a seat with an open question and an open task past stall_minutes is blocked, not stalled" sh -c "printf '%s\n' \"\$1\" | grep -q 'dev-b ○ blocked' && grep -q ' dev-b T-968 SEAT_BLOCKED\$' .team/events.log && ! grep -q ' dev-b T-968 SEAT_STALLED' .team/events.log" _ "$bout"
check "trial 9: the lead's line says that the seat waits for the owner's answer and that squad queues any dispatch to it" sh -c "[ \$(grep 'agent prompt lead \[squad\] dev-b is blocked on T-968: ' '$MOCK_LOG' | grep -c \"waits for .* answer.*squad queues any dispatch to it\") = 1 ]"
check "trial 9: the lead's line does not say 're-send or re-dispatch'" refuses grep -q 'dev-b.*re-send or re-dispatch' "$MOCK_LOG"
check "trial 9: the owner gets the 'waits for you' alert and no 'stalled' alert" sh -c "test -f '$HW' && test ! -e '$SW/held-stuck-dev-b' && ! grep -q 'notification show squad: dev-b stalled' '$MOCK_LOG'"
answered dev-b; rm -rf .team/observer/.alerted "$SW"; mkdir -p "$SW"; reset_log
MOCK_AGENTS=$t_up MOCK_PANE_ONLY=dev-b MOCK_PANE_TEXT=$(cat "$longq") watch1
check "trial 9: a seat whose only sign of a dialog is the menu on its screen is blocked, not stalled" sh -c "[ \"\$(cat .team/observer/.alerted/dev-b)\" = blocked ] && ! grep -q ' dev-b T-968 SEAT_STALLED' .team/events.log && ! grep -q 'notification show squad: dev-b stalled' '$MOCK_LOG'"
ago 400 >"$SW/blocked-dev-b"; MOCK_AGENTS=$t_up MOCK_PANE_ONLY=dev-b MOCK_PANE_TEXT=$(cat "$longq") watch1
check "trial 9: the owner is told of that seat after 5 minutes, as for a seat that herdr shows blocked" log_has "notification show squad: dev-b waits for you (T-968)"
ev dev-b T-968 DONE; rm -rf .team/observer/.alerted .team/observer/.seen "$SW"; mkdir -p "$SW"
ago 600 >.team/observer/.idle/dev-b; asks dev-b; sleep 1; i0=$(grep -c ' dev-b - IDLE ' .team/events.log || true); reset_log
MOCK_AGENTS=$t_up MOCK_PANE_TEXT=$rdy watch1
check "trial 9: a dev with no task that shows a dialog gets no IDLE alarm" sh -c "! grep -q 'dev-b has had no task' '$MOCK_LOG' && [ \"\$(grep -c ' dev-b - IDLE ' .team/events.log)\" = '$i0' ] && test ! -e .team/observer/.idle/dev-b"
answered dev-b
# 11: the stall clock starts again when the seat showed a dialog or did something (real trial 3: SEAT_STALLED 31 s after Escape)
t_work='{"result":{"agents":[{"name":"lead","agent_status":"working","pane_id":"w2:p1"},{"name":"dev-a","agent_status":"working","pane_id":"w2:p2"},{"name":"dev-b","agent_status":"working","pane_id":"w2:p3"}]}}'
rm -rf .team/observer/.alerted .team/observer/.seen "$SW"; mkdir -p "$SW" .team/observer/.seen
ev dev-b T-970 DISPATCH round=1; ago 3600 >.team/observer/.seen/dev-b
asks dev-b; sleep 1
MOCK_AGENTS=$t_up MOCK_PANE_ONLY=dev-b MOCK_PANE_TEXT=$(cat "$longq") watch1
check "trial 11: a seat that shows a dialog loses its stall clock" test ! -e .team/observer/.seen/dev-b
answered dev-b
for e11 in Stop UserPromptSubmit SessionStart; do
  ago 3600 >.team/observer/.seen/dev-b; hook dev-b "$e11" '{"background_tasks":[],"source":"clear","session_id":"s11"}'
  check "trial 11: the seat's $e11 hook starts its stall clock again" test ! -e .team/observer/.seen/dev-b
done
rm -rf .team/observer/.alerted; reset_log; MOCK_AGENTS=$t_up MOCK_PANE_TEXT=$rdy watch1
check "trial 11: a seat that was just active is not stalled at the next tick" sh -c "! grep -q ' dev-b T-970 SEAT_STALLED' .team/events.log && ! grep -q 'notification show squad: dev-b stalled' '$MOCK_LOG'"
# the free-prompt proof does not count while herdr shows the seat at work (a working screen keeps an empty prompt line)
asks dev-b; sleep 1; age "$W" 1 60; seen 30
MOCK_AGENTS=$t_work MOCK_PANE_TEXT=$esc watch1
check "trial 11: the screen does not end a hook record while herdr shows the seat at work" test -f "$W"
answered dev-b; ev dev-b T-970 DONE
# ---- the review of the trial fixes (21 Nov 2026): no false sign of a dialog, and no key into a dialog that a sign shows ----
idle="$here/fixtures/panes/idle.txt"   # the real screen of an idle seat (45 columns): its last message, the echoed prompts, the status line
permq="$here/fixtures/panes/permission.txt"   # the real screen of a permission dialog
t_idle='{"result":{"agents":[{"name":"lead","agent_status":"idle","pane_id":"w2:p1"},{"name":"dev-a","agent_status":"idle","pane_id":"w2:p2"},{"name":"dev-b","agent_status":"idle","pane_id":"w2:p3"}]}}'
rm -rf .team/observer/.alerted .team/observer/.seen .team/observer/.idle "$SW" "$NT"; mkdir -p "$SW" .team/observer/.seen
# 12: the screen sign is the dialog's structure (a footer below the last rule, a selected numbered row with its next row), not its words
ev dev-a T-971 DISPATCH round=1
check "trial 12: the real idle screen is no dialog" told "$(cat "$idle")"
check "trial 12: an idle screen whose last message has the line 'and did not run squad done, to allow the' is no dialog" told "$(sed '23s/.*/  and did not run squad done, to allow the/' "$idle")"
check "trial 12: an idle screen whose last message has the line 'Do you want to keep the old test too?' is no dialog" told "$(sed '24s/.*/  Do you want to keep the old test too?/' "$idle")"
check "trial 12: an idle screen whose last message wraps '… press esc to' / 'cancel the run …' is no dialog" told "$(sed -e '23s/.*/  To stop the check, press esc to/' -e '24s/.*/  cancel the run. I stop here./' "$idle")"
check "trial 12: an idle screen with the echoed prompt '❯ 1. Rebase on integration 2. Fix the lint' 22 lines above the bottom is no dialog" told "$(sed '10s/.*/❯ 1. Rebase on integration 2. Fix the lint/' "$idle")"
check "trial 12: the real question screen is a dialog" refuses told "$(cat "$longq")"
check "trial 12: the real permission screen is a dialog" refuses told "$(cat "$permq")"
check "trial 12: a selected numbered row with its next row is a dialog without a footer" refuses told "$(sed -n '1,26p' "$permq")"
check "trial 12: the real screen after Escape is no dialog" told "$esc"
ev dev-a T-971 DONE
# 13: the Enter that re-submits a stranded task never goes into a dialog that herdr or the hook shows
stuck() { printf 'Claude Code\n❯ Task %s is yours. Read %s/trial/.team/tasks/%s.md and follow your role file.' "$1" "$tmp" "$1"; }   # <task>: its text stays in the input line
printf 'x\n' >.team/reports/T-972-contract.md; printf 'x\n' >.team/reports/T-973-contract.md; rm -f "$tmp/pinfo"; reset_log
MOCK_AGENTS=$t_idle MOCK_AGENTS_LATER=$(sed 's/"dev-a","agent_status":"idle"/"dev-a","agent_status":"blocked"/' <<<"$t_idle") MOCK_ON_PROMPT="case \$4 in Task*) : >'$tmp/pinfo' ;; esac" \
  MOCK_PANE_TEXT=$(stuck T-972) SQUAD_DISPATCH_WAIT=4 "$squad" dispatch dev-a T-972 >/dev/null 2>&1 || true
check "trial 13: a stranded task gets no Enter when herdr shows the seat blocked, and the dispatch is not started" sh -c "grep -q 'agent prompt dev-a Task T-972' '$MOCK_LOG' && ! grep -q 'agent send-keys dev-a' '$MOCK_LOG' && grep -q ' dev-a T-972 DISPATCH_NOT_STARTED' .team/events.log"
rm -f "$tmp/pinfo"; reset_log
MOCK_AGENTS=$t_idle MOCK_ON_PROMPT="case \$4 in Task*) printf '%s' '{\"tool_name\":\"AskUserQuestion\",\"tool_input\":{\"questions\":[{\"question\":\"Which storage?\"}]}}' | TEAM_ROLE=dev-a '$squad' seat-hook AskUserQuestion ;; esac" \
  MOCK_PANE_TEXT=$(stuck T-973) SQUAD_DISPATCH_WAIT=4 "$squad" dispatch dev-a T-973 >/dev/null 2>&1 || true
check "trial 13: a stranded task gets no Enter when the seat's hook recorded a dialog, and the dispatch is not started" sh -c "grep -q 'agent prompt dev-a Task T-973' '$MOCK_LOG' && ! grep -q 'agent send-keys dev-a' '$MOCK_LOG' && grep -q ' dev-a T-973 DISPATCH_NOT_STARTED' .team/events.log"
answered dev-a; reset_log
MOCK_AGENTS=$t_idle MOCK_PANE_TEXT=$(stuck T-973) SQUAD_DISPATCH_WAIT=4 "$squad" dispatch dev-a T-973 >/dev/null 2>&1 || true
check "trial 13: with no sign of a dialog the stranded task still gets its one Enter" test "$(grep -c 'agent send-keys dev-a enter' "$MOCK_LOG")" = 1
sleep 1; rm -f "$SW"/held-*
# 14: the watch ends only the record it decided on: the record of a new dialog, written in between, stays
rec_at() { head -1 "$W" 2>/dev/null | cut -d' ' -f1; }   # the time of dev-b's record
asks dev-b; sleep 1; age "$W" 1 60; seen 15; old14=$(rec_at)
( sleep 2; asks dev-b ) & hp=$!
SQUAD_TEST_CLAIM_PAUSE=4 MOCK_AGENTS=$t_up MOCK_PANE_TEXT=$esc watch1; wait "$hp" || true
check "trial 14: a new dialog's record that replaces the old one while the watch ends it is kept" test -n "$(rec_at)" -a "$(rec_at)" != "$old14"
check "trial 14: no claimed record is left behind" sh -c "! ls .team/seats/ | grep -q 'owner-wait.claim'"
age "$W" 1 60; seen 15; MOCK_AGENTS=$t_up MOCK_PANE_TEXT=$esc watch1
check "trial 14: a record that nothing replaced still ends at the second sighting" test ! -e "$W" -a ! -e "$FR"
asks dev-b; sleep 1; age "$W" 1 60; old14=$(rec_at)
( sleep 2; asks dev-b ) & hp=$!
printf '%s' '{"background_tasks":[]}' | SQUAD_TEST_CLAIM_PAUSE=4 TEAM_ROLE=dev-b "$squad" seat-hook Stop; wait "$hp" || true
check "trial 14: the seat's hook ends only the record it read: a new dialog's record stays" test -n "$(rec_at)" -a "$(rec_at)" != "$old14"
answered dev-b; sleep 1; rm -f "$SW"/held-* .team/seats/dev-b.background
# 15: each held line asks the lead's state again: the first line can make the lead open a dialog
notice dev-a T-974 BLOCKED 10; notice dev-b T-975 BLOCKED 10; : >"$NT/.unsent-T-974.dev-a"; : >"$NT/.unsent-T-975.dev-b"
rm -f "$tmp/pane"; reset_log
MOCK_AGENTS=$t_free MOCK_PANE_TEXT=$rdy MOCK_PANE_FILE="$tmp/pane" MOCK_ON_PROMPT="cp '$longq' '$tmp/pane'" watch1
check "trial 15: two held notices: the second is not typed into the dialog that the lead opened after the first" sh -c "[ \$(grep -c 'agent prompt lead' '$MOCK_LOG') = 1 ] && [ \$(ls -A '$NT' | grep -c '^\.unsent-') = 1 ]"
rm -f "$tmp/pane"; reset_log; MOCK_AGENTS=$t_free MOCK_PANE_TEXT=$rdy watch1
check "trial 15: the second notice goes out when the lead is free again" sh -c "[ \$(grep -c 'agent prompt lead \[squad\] dev-. finished T-97[45]: BLOCKED' '$MOCK_LOG') = 1 ] && [ \$(ls -A '$NT' | grep -c '^\.unsent-') = 0 ]"
rm -rf "$NT"
# 16: two watches at once send a kept line once
LL=.team/observer/.lead-lines; mkdir -p "$LL"; printf '[squad] a kept line\n' >"$LL/1-1-1"; reset_log
MOCK_AGENTS=$t_free MOCK_PANE_TEXT=$rdy MOCK_PROMPT_SLEEP=3 watch1 & w1=$!
MOCK_AGENTS=$t_free MOCK_PANE_TEXT=$rdy MOCK_PROMPT_SLEEP=3 watch1 & w2=$!
wait "$w1" "$w2" || true
check "trial 16: two watches that run at once send a kept line to the lead once" sh -c "[ \$(grep -c 'agent prompt lead \[squad\] a kept line' '$MOCK_LOG') = 1 ] && [ -z \"\$(ls -A '$LL')\" ]"
printf '[squad] a claimed line\n' >"$LL/.claim.999999.2-2-2"; reset_log; MOCK_AGENTS=$t_free MOCK_PANE_TEXT=$rdy watch1
check "trial 16: a line whose claimer is gone is sent by the next tick" sh -c "[ \$(grep -c 'agent prompt lead \[squad\] a claimed line' '$MOCK_LOG') = 1 ] && [ -z \"\$(ls -A '$LL')\" ]"
printf '[squad] a held line\n' >"$LL/3-3-3"; reset_log; MOCK_AGENTS=$t_free MOCK_PANE_TEXT=$(cat "$longq") watch1
check "trial 16: a line that is not sent (the lead shows a dialog) keeps its name" sh -c "! grep -q 'agent prompt lead' '$MOCK_LOG' && test -f '$LL/3-3-3'"
rm -rf "$LL"
# 17: the record ends with the call it was written for, not with any call of the same tool
perm dev-b
hook dev-b PostToolUse '{"tool_name":"Bash","tool_input":{"command":"ls"}}'
check "trial 17: the end of another call of the same tool (in parallel, or in a subagent) does not end the record" test -f "$W"
hook dev-b PostToolUse '{"tool_name":"Bash","tool_input":{"command":"rm x"},"tool_response":{"stdout":""}}'
check "trial 17: the end of the call the dialog asked for ends the record" test ! -e "$W"
asks dev-b; hook dev-b PostToolUse '{"tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Another question?"}],"answers":{"Another question?":"Yes"}}}'
check "trial 17: the answer to another question does not end the record" test -f "$W"
answered dev-b
check "trial 17: the answer to its question ends the record: the answers in the input do not count" test ! -e "$W"
perm dev-b; hook dev-b PermissionRequest '{"tool_name":"Bash","tool_input":{"command":"rm y"}}'
check "trial 17: a second permission request for another call is recorded at once (only the same call, reported twice, is dropped)" sh -c "sed -n '2p' '$W' | grep -q 'rm y'"
hook dev-b PostToolUse '{"tool_name":"Bash","tool_input":{"command":"rm x"}}'
check "trial 17: the end of the first call does not end the second call's record" test -f "$W"
hook dev-b PostToolUse '{"tool_name":"Bash","tool_input":{"command":"rm y"}}'
printf '%s Bash 5\npermission for Bash: rm z\n' "$(date +%s)" >"$W"; hook dev-b PostToolUse '{"tool_name":"Bash","tool_input":{"command":"rm z"}}'
check "trial 17: a record of an older squad (no checksum) ends with the tool's name" test ! -e "$W"
sleep 1; rm -f "$SW"/held-*
# 18: a tool that failed has ended too (PostToolUseFailure: https://code.claude.com/docs/en/hooks)
jq_fail='(.hooks.PostToolUseFailure[0].hooks[0].command | endswith("seat-hook PostToolUseFailure")) and (.hooks.PostToolUseFailure[0] | has("matcher") | not) and (.hooks | keys | length == 8)'
check "trial 18: a Claude seat's settings carry the PostToolUseFailure hook, and the file is valid JSON" jq -e "$jq_fail" .team/seats/dev-a.settings.json
check "trial 18: the worktree's settings carry it too" jq -e '.hooks.PostToolUseFailure[0].hooks[0].command | endswith("seat-hook PostToolUseFailure")' "$tmp/trial-team/dev-a/.claude/settings.local.json"
perm dev-b; hook dev-b PostToolUseFailure '{"tool_name":"Bash","tool_input":{"command":"ls"},"error":"Exit code 1"}'
check "trial 18: the failure of another call does not end the record" test -f "$W"
hout=$(hook dev-b PostToolUseFailure '{"tool_name":"Bash","tool_input":{"command":"rm x"},"error":"Exit code 1","is_interrupt":false}' 2>&1)
check "trial 18: the failure of the call the dialog asked for ends the record, and the hook prints nothing" test ! -e "$W" -a -z "$hout"
sleep 1; rm -f "$SW"/held-*
# 19: an empty stall clock (the seat's hook removed the file while the watch read it) starts the clock now
ev dev-b T-976 DISPATCH round=1; rm -rf .team/observer/.alerted; : >.team/observer/.seen/dev-b; reset_log
sout=$(MOCK_AGENTS=$t_up MOCK_PANE_TEXT=$rdy "$squad" watch --once 2>/dev/null || true)
check "trial 19: a seat with an empty stall clock is not stalled, and its clock starts now" sh -c "! printf '%s\n' \"\$1\" | grep -q 'dev-b ○ stalled' && ! grep -q ' dev-b T-976 SEAT_STALLED' .team/events.log && grep -qE '^[0-9]+\$' .team/observer/.seen/dev-b" _ "$sout"
ago 3600 >.team/observer/.seen/dev-b; sout=$(MOCK_AGENTS=$t_up MOCK_PANE_TEXT=$rdy "$squad" watch --once 2>/dev/null || true)
check "trial 19: a seat whose clock is older than stall_minutes is still stalled" sh -c "printf '%s\n' \"\$1\" | grep -q 'dev-b ○ stalled'" _ "$sout"
ev dev-b T-976 DONE; rm -rf .team/observer/.alerted .team/observer/.seen "$SW"; mkdir -p "$SW"
# 20: the cost of a tick: a seat's dialog check asks herdr for no agent list of its own, and the watch's seat checks share one read of its screen
asks dev-b; sleep 1; age "$W" 1 60
MOCK_AGENTS=$t_idle MOCK_PANE_ONLY=dev-b MOCK_PANE_TEXT=$(cat "$longq") watch1   # the lead is told of the seat here
reset_log; MOCK_AGENTS=$t_idle MOCK_PANE_ONLY=dev-b MOCK_PANE_TEXT=$(cat "$longq") watch1
lists=$(grep -c '^herdr agent list' "$MOCK_LOG"); reads=$(grep -c '^herdr agent read dev-b ' "$MOCK_LOG")
echo "     trial 20: one tick, three idle seats, one with a question: $lists 'agent list' calls, $reads reads of that seat's screen"
check "trial 20: one watch tick with three idle seats makes at most 3 'agent list' calls: none for a seat" test "$lists" -le 3
check "trial 20: and reads the screen of the idle seat with a question at most 3 times" test "$reads" -le 3
answered dev-b; sleep 1
# 21: two watches at once send a held notice once (real trial 4: the notice of squad done arrived twice)
reset_log; MOCK_AGENTS=$t_free MOCK_PANE_TEXT=$(cat "$longq") "$squad" "done" dev-a T-971 BLOCKED >/dev/null 2>&1 || true
( sleep 30 ) & tick21=$!; ln -s "$tick21" "$NT/.tick"   # the lock: a symbolic link to its owner's pid, made in one step
MOCK_AGENTS=$t_free MOCK_PANE_TEXT=$rdy watch1
check "trial 21: a watch sends no notice while another watch's tick holds the notices" refuses log_has "agent prompt lead [squad] dev-a finished T-971"
kill "$tick21" 2>/dev/null || true; wait "$tick21" 2>/dev/null || true
MOCK_AGENTS=$t_free MOCK_PANE_TEXT=$rdy watch1; MOCK_AGENTS=$t_free MOCK_PANE_TEXT=$rdy watch1
check "trial 21: a tick whose holder is gone takes the notices, and the held notice goes out once" sh -c "[ \$(grep -c 'agent prompt lead \[squad\] dev-a finished T-971: BLOCKED' '$MOCK_LOG') = 1 ] && test ! -e '$NT/.tick'"
"$squad" seen T-971 >/dev/null 2>&1 || TEAM_ROLE=lead "$squad" seen T-971 >/dev/null 2>&1 || true
# ---- the findings of the bot review of PR #27 ----
# 22: the lock of the notices from an older squad (a folder with a pid file) does not hold the notices for ever
"$squad" "done" dev-a T-977 BLOCKED >/dev/null 2>&1 || true; mkdir -p "$NT/.tick"; : >"$NT/.unsent-T-977.dev-a"; reset_log
MOCK_AGENTS=$t_free MOCK_PANE_TEXT=$rdy watch1
check "trial 22: a lock folder that an older squad left is cleared, and the held notice goes out once" sh -c "[ \$(grep -c 'agent prompt lead \[squad\] dev-a finished T-977: BLOCKED' '$MOCK_LOG') = 1 ] && test ! -e '$NT/.tick' -a ! -L '$NT/.tick'"
ev lead T-977 SEEN; watch1
# 23: 'squad seen' between the report's event and the kept notice counts: the boundary is the report's own line
reset_log; ( sleep 1; ev lead T-978 SEEN ) & hp=$!
SQUAD_TEST_NOTICE_PAUSE=3 MOCK_AGENTS=$t_free MOCK_PANE_TEXT=$rdy "$squad" "done" dev-a T-978 BLOCKED >/dev/null 2>&1 || true; wait "$hp" || true
age "$NT/T-978.dev-a" 1 2000; reset_log; MOCK_AGENTS=$t_free MOCK_PANE_TEXT=$rdy watch1
check "trial 23: a 'squad seen' that came right after the report is not skipped: the notice is not sent again" sh -c "test ! -e '$NT/T-978.dev-a' && ! grep -q 'finished T-978' '$MOCK_LOG'"
ev lead T-979 SEEN; MOCK_AGENTS=$t_free MOCK_PANE_TEXT=$rdy "$squad" "done" dev-a T-979 BLOCKED >/dev/null 2>&1 || true
age "$NT/T-979.dev-a" 1 2000; reset_log; MOCK_AGENTS=$t_free MOCK_PANE_TEXT=$rdy watch1
check "trial 23: a 'squad seen' before the report leaves the new notice pending" sh -c "test -f '$NT/T-979.dev-a' && grep -q 'finished T-979: BLOCKED.*Sent again' '$MOCK_LOG'"
ev lead T-979 SEEN; watch1
# 24: a new dialog of the same second as the record that ends is another record: it stays
perm dev-b; sleep 1; old24=$(rec_at)
( sleep 2; printf '%s Bash 0 999\npermission for Bash: rm q\n' "$old24" >"$W" ) & hp=$!
printf '%s' '{"background_tasks":[]}' | SQUAD_TEST_CLAIM_PAUSE=4 TEAM_ROLE=dev-b "$squad" seat-hook Stop; wait "$hp" || true
check "trial 24: the record of a new dialog with the time of the old one is kept" grep -q 'rm q' "$W"
rm -f "$W" .team/seats/dev-b.background; sleep 1; rm -f "$SW"/held-*
# 25: a dialog that opens after the clear of a queued dispatch holds the task: it has not failed
printf 'x\n' >.team/reports/T-980-contract.md; rm -f "$tmp/pinfo"; reset_log; rc25=0
SQUAD_DISPATCH_QUEUED=1 MOCK_AGENTS=$t_idle MOCK_AGENTS_LATER=$(sed 's/"dev-a","agent_status":"idle"/"dev-a","agent_status":"blocked"/' <<<"$t_idle") MOCK_ON_PROMPT="case \$4 in /clear) : >'$tmp/pinfo' ;; esac" \
  MOCK_PANE_TEXT=$rdy SQUAD_DISPATCH_WAIT=3 "$squad" dispatch dev-a T-980 >/dev/null 2>&1 || rc25=$?
check "trial 25: a queued dispatch whose seat shows a dialog after the clear goes back to its waiter (exit 75), and the task is not typed" sh -c "[ $rc25 = 75 ] && grep -q 'agent prompt dev-a /clear' '$MOCK_LOG' && ! grep -q 'agent prompt dev-a Task' '$MOCK_LOG' && ! grep -q ' dev-a T-980 DISPATCH_FAILED' .team/events.log"
rm -f "$tmp/pinfo"
# 26: the owner hears of a dev with no task after 30 min, also when the lead could not be told (it shows a dialog)
cp .team/TASKS.md "$tmp/tasks.keep26"; printf '# Tasks\n\n| ID | Title | Owner | Status | Depends on |\n|---|---|---|---|---|\n| T-002 | b | - | todo | - |\n' >.team/TASKS.md
rm -rf .team/observer/.idle; mkdir -p .team/observer/.idle; ago 1860 >.team/observer/.idle/dev-b; reset_log
MOCK_AGENTS=$(sed 's/"lead","agent_status":"idle"/"lead","agent_status":"blocked"/; s/"dev-a","agent_status":"idle"/"dev-a","agent_status":"working"/' <<<"$t_idle") MOCK_PANE_TEXT=$rdy watch1
check "trial 26: a lead that shows a dialog is not told of the idle dev, and the owner is told at 30 min all the same" sh -c "! grep -q 'agent prompt lead' '$MOCK_LOG' && grep -q 'notification show squad: dev-b has no task --body dev-b has had no task for 31 min; 1 open task(s)' '$MOCK_LOG'"
cp "$tmp/tasks.keep26" .team/TASKS.md; rm -rf .team/observer/.idle .team/observer/.alerted "$SW"; mkdir -p "$SW"
# 27: the restart of a seat that runs without its options waits while its input line holds text ("/exit" would go in after the draft)
printf 'seat_restart on\n' >>.team/team.conf; rm -f "$tmp/exited"; reset_log
bare27() { MOCK_WS='{"result":{"workspaces":[{"workspace_id":"w2","label":"trial team"}]}}' MOCK_PANES='{"result":{"panes":[{"pane_id":"w2:p1","label":"lead"},{"pane_id":"w2:p3","label":"dev-b"}]}}' \
  MOCK_AGENTS='{"result":{"agents":[{"name":"lead","agent_status":"working","pane_id":"w2:p1"},{"name":"dev-b","agent_status":"idle","pane_id":"w2:p3"}]}}' MOCK_CMDLINE="claude --resume 1234" MOCK_PANE_TEXT=$1 SQUAD_EXIT_WAIT=1 watch1; }   # <every pane's text>
bare27 "$(printf 'Claude Code\n❯ a note that is not sent yet')"
check "trial 27: a seat with a draft in its input line is not ended: nothing is typed, the restart is put off" sh -c "! grep -qE 'agent (prompt|start|send-keys) dev-b' '$MOCK_LOG' && test -e '$SW/defer-dev-b'"
bare27 "$rdy"
check "trial 27: with an empty input line the seat is ended at its prompt" log_has "agent prompt dev-b /exit"
sed -i.bak '/^seat_restart /d' .team/team.conf; rm -f .team/team.conf.bak "$tmp/exited" .team/seats/dev-b.no-options; rm -rf .team/observer/.alerted "$SW"; mkdir -p "$SW"
# 28: a reminder of the wait for the owner never brings back a wait that 'squad wait-owner --done' ended meanwhile
"$squad" wait-owner "T-981: the colour" >/dev/null 2>&1; age .team/owner-wait 3 18000; reset_log
( sleep 1; "$squad" wait-owner --done >/dev/null 2>&1 ) & hp=$!
SQUAD_TEST_REMIND_PAUSE=3 MOCK_AGENTS=$t_up MOCK_PANE_TEXT=$rdy watch1; wait "$hp" || true
check "trial 28: a wait that ended while its reminder was written stays ended" test ! -e .team/owner-wait
"$squad" wait-owner "T-982: the font" >/dev/null 2>&1; age .team/owner-wait 3 18000; reset_log
MOCK_AGENTS=$t_up MOCK_PANE_TEXT=$rdy watch1; MOCK_AGENTS=$t_up MOCK_PANE_TEXT=$rdy watch1
check "trial 28: a wait that still holds gets its reminder, once" test "$(grep -c 'notification show squad: trial still waits for you --body T-982: the font' "$MOCK_LOG")" = 1
"$squad" wait-owner --done >/dev/null 2>&1
check "trial 28: the end of the wait removes the reminder's time too" test ! -e .team/owner-wait.reminded
# 29: squad up keeps a team's round_limit: the preset's 'rounds' is the same setting and is not added
cd "$tmp"; "$squad" new rl >/dev/null 2>&1; cd rl
sed -i.bak 's/^rounds .*/round_limit 3/' .team/team.conf; rm -f .team/team.conf.bak; "$squad" update-conf >/dev/null 2>&1 || true
check "trial 29: update-conf adds no 'rounds' line to a team.conf that has round_limit" sh -c "grep -qx 'round_limit 3' .team/team.conf && ! grep -qE '^rounds( |\$)' .team/team.conf"
printf 'x\n' >.team/reports/T-983-review-1.md; printf 'x\n' >.team/reports/T-983-review-2.md; printf 'x\n' >.team/reports/T-983-review-3.md
printf '2026-11-21 09:00:00 dev-a T-983 DONE\n' >>.team/events.log   # a task under way: the plan gate does not hold it
check "trial 29: and the limit of 3 still holds a dispatch of round 4" sh -c "'$squad' dispatch dev-a T-983 2>&1 | grep -q 'the round limit is 3'"
# 30: a queued task of a seat that fails does not close the token window of the task the seat works on
cd "$tmp/proj27"; export CLAUDE_CONFIG_DIR="$tmp/home/.claude"
sed -i.bak 's/^2026-11-20 10:05:00 dev-a T-701 DONE$/2026-11-20 10:02:00 dev-a T-799 DISPATCH_FAILED still busy after 120 min in the queue\
&/' .team/events.log; rm -f .team/events.log.bak
tok=$(TZ=UTC "$squad" tokens 2>&1 || true)
check "trial 30: the failed dispatch of another task leaves the running task's tokens with the task" grep -qE '^T-701 +dev-a +2 +105 +3000 +200 +70$' <<<"$tok"
unset CLAUDE_CONFIG_DIR
# 31: the watch's own finding about a seat (SEAT_BLOCKED) between a dispatch and its failure does not keep the task open
cd "$tmp/proj4"; mv .team/events.log "$tmp/events.keep"
printf '2026-11-21 11:00:00 dev-a T-955 DISPATCH round=1\n2026-11-21 11:00:10 dev-a T-955 SEAT_BLOCKED\n2026-11-21 11:00:20 dev-a T-955 DISPATCH_NOT_STARTED no running turn in 20s\n' >.team/events.log; echo 0 >$O/.last-pass
check "trial 31: a dispatch that did not start after the seat was seen blocked is no open task for the observer" refuses obs
printf '2026-11-21 11:01:00 dev-a T-956 DISPATCH round=1\n2026-11-21 11:02:00 dev-a T-956 DONE\n2026-11-21 11:03:00 dev-a T-956 DISPATCH_FAILED not at its prompt\n' >.team/events.log; echo 0 >$O/.last-pass
check "trial 31: a failed second send of a task the seat reported on does not close the task" obs
mv "$tmp/events.keep" .team/events.log
# 32: the README says what to do with a seat that runs without its options: squad up alone leaves it as it is
check "trial 32: the README tells the owner to end a running seat's agent before squad up" grep -qE '^\| "squad: <seat> runs without its squad options" \| .*end its agent in its pane.*then run `squad up`' "$here/../README.md"
# ---- 028 · one task that fails leaves the candidate; the other tasks still merge ----------
cd "$tmp"; "$squad" new b28 >/dev/null 2>&1; cd b28; reset_log
printf 'seat lead claude lead -\nseat dev-a claude dev -\nseat dev-b claude dev -\nseat tester claude tester -\nupgrade off\n' >.team/team.conf
"$squad" up >/dev/null 2>&1 || true
I="$tmp/b28-team/integration"; DA="$tmp/b28-team/dev-a"
for k in 1 2 3; do
  git -C "$DA" switch -q -c "task/T-$k" team/integration && echo "$k" >"$DA/t$k.txt" && git -C "$DA" add "t$k.txt" && git -C "$DA" commit -qm "T-$k"
  printf '%s dev-a T-%s DISPATCH round=1\n%s dev-a T-%s DONE\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$k" "$(date '+%Y-%m-%d %H:%M:%S')" "$k" >>.team/events.log
  printf 'x\n' >".team/reports/T-$k-review-1.md"; "$squad" "done" lead "T-$k" APPROVE >/dev/null 2>&1 || true
done
printf '# CANDIDATE-1\n## Acceptance\n| # | Check |\n|---|---|\n| 1 | the suite passes |\n' >.team/tasks/CANDIDATE-1.md
printf 'echo one\ntest ! -f t2.txt || { echo t2 breaks the suite; exit 3; }\necho three\n' >.team/tasks/CANDIDATE-1.checks
check "028: a candidate with its tasks named is built as before" "$squad" candidate CANDIDATE-1 T-1 T-2 T-3
frc=0; "$squad" heavy tester CANDIDATE-1 --batch .team/tasks/CANDIDATE-1.checks >/dev/null 2>&1 || frc=$?
R=.team/receipts/CANDIDATE-1
check "028: the receipt of a failed candidate names the failed step, its exit code and its log file" sh -c "[ $frc = 3 ] && grep -qx 'failed=step2 rc=3 log=step-2.log' $R/receipt && grep -qx 't2 breaks the suite' $R/step-2.log"
check "028: a step that passed has no failed line" sh -c "[ \$(grep -c '^failed=' $R/receipt) = 1 ]"
printf 'RESULT: FAIL\nAcceptance:\n| # | Result | Evidence |\n|---|---|---|\n| 1 | fail | step 2 |\n' >.team/reports/CANDIDATE-1-test.md
ag28='{"result":{"agents":[{"name":"lead","agent_status":"idle"},{"name":"dev-a","agent_status":"idle"},{"name":"tester","agent_status":"idle"}]}}'
check "028: --task takes only a task of the candidate" refuses env MOCK_AGENTS="$ag28" MOCK_PANE_TEXT="$rdy" "$squad" "done" tester CANDIDATE-1 FAIL --task T-9
check "028: --task goes with a candidate's FAIL only" refuses env MOCK_AGENTS="$ag28" MOCK_PANE_TEXT="$rdy" "$squad" "done" tester CANDIDATE-1 PASS --task T-2
check "028: and nothing was logged by the refused reports" refuses grep -qE ' tester CANDIDATE-1 (FAIL|PASS|CANDIDATE_FAIL)' .team/events.log
reset_log; MOCK_AGENTS="$ag28" MOCK_PANE_TEXT="$rdy" "$squad" "done" tester CANDIDATE-1 FAIL --task T-2 >/dev/null 2>&1 || true
check "028: the tester's FAIL records the task it holds responsible (CANDIDATE_FAIL task=<ID>)" sh -c "grep -q ' tester CANDIDATE-1 FAIL ' .team/events.log && grep -q ' tester CANDIDATE-1 CANDIDATE_FAIL task=T-2\$' .team/events.log"
check "028: the lead gets one line that names the task, the step log and the command that rebuilds without it" sh -c "[ \$(grep -c 'agent prompt lead ' '$MOCK_LOG') = 1 ] && grep -q 'agent prompt lead .*tester finished CANDIDATE-1: FAIL.*T-2.*$tmp/b28/$R/step-2.log.*squad candidate CANDIDATE-2 --from CANDIDATE-1 --without T-2' '$MOCK_LOG'"
check "028: --from needs --without" refuses "$squad" candidate CANDIDATE-2 --from CANDIDATE-1
check "028: --without takes only a task of the earlier candidate" refuses "$squad" candidate CANDIDATE-2 --from CANDIDATE-1 --without T-9
check "028: a refused rebuild uses no number" sh -c "! test -e .team/candidates/CANDIDATE-2 && ! git -C '$I' rev-parse -q --verify candidate/CANDIDATE-2"
approvals=$(grep -c ' lead T-[123] APPROVE' .team/events.log)
"$squad" candidate CANDIDATE-2 --from CANDIDATE-1 --without T-2 >"$tmp/cout" 2>&1 && crc=0 || crc=$?
c28=$(git -C "$I" rev-parse -q --verify candidate/CANDIDATE-2 || echo none)
check "028: one command builds the next candidate from the same approved commits without the task" sh -c "[ $crc = 0 ] && git -C '$I' merge-base --is-ancestor task/T-1 $c28 && git -C '$I' merge-base --is-ancestor task/T-3 $c28 && ! git -C '$I' merge-base --is-ancestor task/T-2 $c28"
check "028: the new candidate logs which tasks it carries" grep -q ' lead CANDIDATE-2 CANDIDATE .*from=CANDIDATE-1 without=T-2 tasks=T-1 T-3$' .team/events.log
check "028: the brief and the check list come from the earlier candidate" sh -c "grep -qx '# CANDIDATE-2' .team/tasks/CANDIDATE-2.md && cmp -s .team/tasks/CANDIDATE-1.checks .team/tasks/CANDIDATE-2.checks"
check "028: the task that was left out is sent back, with the step log" grep -q " lead T-2 SENT_BACK from=CANDIDATE-1 log=$tmp/b28/$R/step-2.log\$" .team/events.log
check "028: the command's answer names the task that goes back to its dev and the step log, in one line" sh -c "[ \$(grep -c 'T-2' '$tmp/cout') = 1 ] && grep -q 'T-2 .*sent back.*$tmp/b28/$R/step-2.log' '$tmp/cout'"
check "028: the other tasks need no new review" test "$(grep -c ' lead T-[123] APPROVE' .team/events.log)" = "$approvals"
frc=0; "$squad" heavy tester CANDIDATE-2 --batch .team/tasks/CANDIDATE-2.checks >/dev/null 2>&1 || frc=$?
printf 'RESULT: PASS\nAcceptance:\n| # | Result | Evidence |\n|---|---|---|\n| 1 | pass | ok |\n' >.team/reports/CANDIDATE-2-test.md
MOCK_AGENTS="$ag28" MOCK_PANE_TEXT="$rdy" "$squad" "done" tester CANDIDATE-2 PASS >/dev/null 2>&1 || true
"$squad" merge CANDIDATE-2 >/dev/null 2>&1 || true
check "028: the other tasks merge with the new candidate; the task left out does not" sh -c "[ $frc = 0 ] && grep -q ' lead T-1 MERGE ' .team/events.log && grep -q ' lead T-3 MERGE ' .team/events.log && ! grep -q ' lead T-2 MERGE' .team/events.log && test ! -e '$I/t2.txt'"
printf '# Plan: tests\n\nStatus: approved by the owner 2026-11-16 10:00\n' >.team/PLAN.md
mkdir -p "$HOME/.config/squad/approvals"; { shasum -a 256 .team/PLAN.md 2>/dev/null || sha256sum .team/PLAN.md; } | cut -d' ' -f1 >"$HOME/.config/squad/approvals/b28-PLAN.md.sha256"
rm -f "$tmp/state"; reset_log
check "028: the task that was left out is open for its dev again" sh -c "MOCK_DYNAMIC=1 SQUAD_DISPATCH_WAIT=5 '$squad' dispatch dev-a T-2 >/dev/null 2>&1 && grep -q ' dev-a T-2 DISPATCH ' .team/events.log"
check "trial 6: a sent-back task dispatched with no text names the failed candidate and its step log, not the newest review" sh -c "grep -q 'agent prompt dev-a .*T-2 .*CANDIDATE-1 failed.*$tmp/b28/$R/step-2.log' '$MOCK_LOG' && ! grep -q 'agent prompt dev-a .*newest review' '$MOCK_LOG'"
# a task that was sent back waits for the lead, also while the next candidate runs
cp .team/events.log "$tmp/events.keep"; rm -rf .team/observer/.watchdog
printf '2026-01-01 09:00:00 lead T-171 APPROVE\n2026-01-01 09:10:00 lead T-171 SENT_BACK from=CANDIDATE-71\n2026-01-01 09:11:00 tester CANDIDATE-72 DISPATCH round=1\n' >.team/events.log
mkdir -p .team/observer/.ui; echo kept >.team/observer/.ui/trial6
reset_log; MOCK_AGENTS="$ag28" MOCK_PANE_TEXT="$rdy" "$squad" watch --once >/dev/null 2>&1 || true
check "trial 6: watch --once leaves the UI folder of the running watch and its files in place" grep -qx kept .team/observer/.ui/trial6
check "028: a task that was sent back and has no dispatch waits for the lead (the stall alert names it)" grep -q ' lead - STALLED .*T-171 SENT_BACK' .team/events.log
cp "$tmp/events.keep" .team/events.log; rm -rf .team/observer/.watchdog
# a candidate with no receipt (its run wrote none): the tester still names the task, and the rebuild names no log
cp .team/tasks/CANDIDATE-1.md .team/tasks/CANDIDATE-3.md; printf 'true\n' >.team/tasks/CANDIDATE-3.checks
"$squad" candidate CANDIDATE-3 T-1 T-3 >/dev/null 2>&1 || true
printf 'RESULT: FAIL\n' >.team/reports/CANDIDATE-3-test.md
check "028: FAIL --task works for a candidate that has no receipt" sh -c "MOCK_AGENTS='$ag28' '$squad' 'done' tester CANDIDATE-3 FAIL --task T-3 >/dev/null 2>&1 && grep -q ' tester CANDIDATE-3 CANDIDATE_FAIL task=T-3\$' .team/events.log"
check "trial 6: a rebuild from a candidate with no failed step on record says so and names no log path" sh -c "'$squad' candidate CANDIDATE-4 --from CANDIDATE-3 --without T-3 >'$tmp/cout' 2>&1 && grep -q ' lead T-3 SENT_BACK from=CANDIDATE-3\$' .team/events.log && grep -q 'T-3 .*sent back.*no failed step is on record' '$tmp/cout' && ! grep -q 'receipts/CANDIDATE-3' '$tmp/cout'"
# review findings: the rebuild carries the commits of the earlier candidate; a dependent task; a refused rebuild leaves nothing
task28() { # <n> <start point>: task/T-<n> with one commit, done by dev-a and approved by the lead
  git -C "$DA" switch -q -c "task/T-$1" "$2" && echo "$1" >"$DA/t$1.txt" && git -C "$DA" add "t$1.txt" && git -C "$DA" commit -qm "T-$1"
  printf '%s dev-a T-%s DISPATCH round=1\n%s dev-a T-%s DONE\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >>.team/events.log
  printf 'x\n' >".team/reports/T-$1-review-1.md"; "$squad" "done" lead "T-$1" APPROVE >/dev/null 2>&1 || true
}
task28 5 team/integration; task28 6 team/integration; task28 7 task/T-5; task28 8 team/integration   # T-7 is branched from T-5
cp .team/tasks/CANDIDATE-1.md .team/tasks/CANDIDATE-5.md; printf 'true\n' >.team/tasks/CANDIDATE-5.checks
"$squad" candidate CANDIDATE-5 T-5 T-6 T-7 T-8 >/dev/null 2>&1 || true
free28() { ! test -e ".team/candidates/$1" && ! git -C "$I" rev-parse -q --verify "candidate/$1" >/dev/null; }   # <CANDIDATE-n>: the number is not used
"$squad" candidate CANDIDATE-6 --from CANDIDATE-5 --without T-5 >"$tmp/cout" 2>&1 && crc=0 || crc=$?
check "028: a rebuild is refused when a kept task was branched from the task left out; the message names both tasks and the second --without" sh -c "[ $crc != 0 ] && grep -q 'T-7 was branched from T-5.*--without T-7' '$tmp/cout'"
check "028: and that refusal uses no number and logs nothing" sh -c "! test -e .team/candidates/CANDIDATE-6 && ! git -C '$I' rev-parse -q --verify candidate/CANDIDATE-6 && ! grep -q ' SENT_BACK from=CANDIDATE-5' .team/events.log"
t8=$(git -C "$I" rev-parse task/T-8)
printf '%s lead T-8 CHANGES head=%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$t8" >>.team/events.log
check "028: a rebuild with a kept task that is not approved is refused" refuses "$squad" candidate CANDIDATE-6 --from CANDIDATE-5 --without T-6
check "028: a refused rebuild leaves no copied brief and no copied check list" sh -c "! test -e .team/tasks/CANDIDATE-6.md && ! test -e .team/tasks/CANDIDATE-6.checks"
"$squad" candidate CANDIDATE-6 T-6 >"$tmp/cout" 2>&1 && crc=0 || crc=$?
check "028: so a plain candidate of that number still asks for its brief" sh -c "[ $crc != 0 ] && grep -q 'brief first' '$tmp/cout'"
printf '# CANDIDATE-6\n## Acceptance\n| # | Check |\n|---|---|\n| 1 | the lead wrote this |\n' >.team/tasks/CANDIDATE-6.md
"$squad" candidate CANDIDATE-6 --from CANDIDATE-5 --without T-6 >/dev/null 2>&1 || true
check "028: a refused rebuild keeps a brief that the lead wrote" sh -c "grep -q 'the lead wrote this' .team/tasks/CANDIDATE-6.md && ! test -e .team/tasks/CANDIDATE-6.checks"
rm -f .team/tasks/CANDIDATE-6.md
printf '%s lead T-8 APPROVE head=%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$t8" >>.team/events.log
"$squad" candidate CANDIDATE-6 --from CANDIDATE-5 --without T-5 --without T-7 >/dev/null 2>&1 && crc=0 || crc=$?
c28=$(git -C "$I" rev-parse -q --verify candidate/CANDIDATE-6 || echo none)
check "028: with the dependent task left out too, the candidate is built and holds no commit of either" sh -c "[ $crc = 0 ] && grep -q ' lead CANDIDATE-6 CANDIDATE .*tasks=T-6 T-8\$' .team/events.log && git -C '$I' merge-base --is-ancestor task/T-6 $c28 && ! git -C '$I' merge-base --is-ancestor task/T-5 $c28 && ! git -C '$I' merge-base --is-ancestor task/T-7 $c28"
check "028: a built rebuild keeps its copied brief and check list" test -f .team/tasks/CANDIDATE-6.md -a -f .team/tasks/CANDIDATE-6.checks
check "028: the dependent task may be left out alone (the task it was branched from stays)" sh -c "'$squad' candidate CANDIDATE-7 --from CANDIDATE-5 --without T-7 >/dev/null 2>&1 && grep -q ' lead CANDIDATE-7 CANDIDATE .*tasks=T-5 T-6 T-8\$' .team/events.log"
old6=$(git -C "$I" rev-parse task/T-6)
git -C "$DA" switch -q task/T-6 && echo more >>"$DA/t6.txt" && git -C "$DA" commit -qam "T-6 again"; "$squad" "done" lead T-6 APPROVE >/dev/null 2>&1 || true
new6=$(git -C "$I" rev-parse task/T-6)
"$squad" candidate CANDIDATE-8 --from CANDIDATE-5 --without T-8 >"$tmp/cout" 2>&1 && crc=0 || crc=$?
check "028: a kept task with a newer approved commit than the earlier candidate carried is refused; the message names the task and both commits" sh -c "[ $crc != 0 ] && [ $old6 != $new6 ] && grep -q 'T-6 .*$old6.*$new6' '$tmp/cout'"
check "028: and that refusal uses no number and leaves no copy" sh -c "! test -e .team/candidates/CANDIDATE-8 && ! git -C '$I' rev-parse -q --verify candidate/CANDIDATE-8 && ! test -e .team/tasks/CANDIDATE-8.md && ! test -e .team/tasks/CANDIDATE-8.checks"
grep -v '^task=' .team/candidates/CANDIDATE-5 >"$tmp/rec5"; cp "$tmp/rec5" .team/candidates/CANDIDATE-5   # a record from before squad kept each task's commit
"$squad" candidate CANDIDATE-8 --from CANDIDATE-5 --without T-8 >"$tmp/cout" 2>&1 && crc=0 || crc=$?
check "028: an earlier candidate with no record of its commits: today's approved commits are used, and squad says so" sh -c "[ $crc = 0 ] && grep -q 'no record of its tasks. commits' '$tmp/cout' && git -C '$I' merge-base --is-ancestor $new6 \$(git -C '$I' rev-parse candidate/CANDIDATE-8)"
# the dev's seat shows that its task was sent back
cp .team/events.log "$tmp/events.keep"
printf '2026-01-01 09:00:00 dev-b T-173 DISPATCH round=1\n2026-01-01 09:05:00 dev-b T-173 DONE\n2026-01-01 09:06:00 lead T-173 APPROVE\n2026-01-01 09:10:00 lead T-173 SENT_BACK from=CANDIDATE-71\n' >.team/events.log
rep28=$(printf q | MOCK_AGENTS='{"result":{"agents":[{"name":"lead","agent_status":"idle"},{"name":"dev-b","agent_status":"idle"}]}}' "$squad" report --live 2>/dev/null || true)
check "028: the seat of a task that was sent back shows SENT BACK, not APPROVED" grep -qE '^  . dev-b +dev +SENT BACK +T-173' <<<"$rep28"
cp "$tmp/events.keep" .team/events.log
# CodeRabbit (PR #28): a candidate with two failed steps: the lead's lines, the SENT_BACK event and the dev's dispatch text name both logs
task28 11 team/integration; task28 12 team/integration
cp .team/tasks/CANDIDATE-1.md .team/tasks/CANDIDATE-9.md
printf 'test ! -f t11.txt || { echo t11 breaks; exit 4; }\ntest ! -f t12.txt || { echo t12 breaks; exit 5; }\ntrue\n' >.team/tasks/CANDIDATE-9.checks
"$squad" candidate CANDIDATE-9 T-11 T-12 >/dev/null 2>&1 || true
"$squad" heavy tester CANDIDATE-9 --batch .team/tasks/CANDIDATE-9.checks >/dev/null 2>&1 || true
R9="$tmp/b28/.team/receipts/CANDIDATE-9"
printf 'RESULT: FAIL\n' >.team/reports/CANDIDATE-9-test.md
reset_log; MOCK_AGENTS="$ag28" MOCK_PANE_TEXT="$rdy" "$squad" "done" tester CANDIDATE-9 FAIL --task T-12 >/dev/null 2>&1 || true
check "PR 28: two failed steps: the receipt has two failed lines, and the lead's line after FAIL --task names both step logs" sh -c "[ \$(grep -c '^failed=' $R9/receipt) = 2 ] && grep -q 'agent prompt lead .*tester finished CANDIDATE-9: FAIL.*T-12.*$R9/step-1.log, $R9/step-2.log.*--from CANDIDATE-9 --without T-12' '$MOCK_LOG'"
"$squad" candidate CANDIDATE-10 --from CANDIDATE-9 --without T-12 >"$tmp/cout" 2>&1 || true
check "PR 28: two failed steps: the SENT_BACK event names both step logs in one log= field" grep -q " lead T-12 SENT_BACK from=CANDIDATE-9 log=$R9/step-1.log,$R9/step-2.log\$" .team/events.log
check "PR 28: two failed steps: the command's answer names both step logs in one line" sh -c "[ \$(grep -c 'T-12' '$tmp/cout') = 1 ] && grep -q 'T-12 .*sent back.*$R9/step-1.log, $R9/step-2.log' '$tmp/cout'"
printf '%s dev-a T-2 DONE\n' "$(date '+%Y-%m-%d %H:%M:%S')" >>.team/events.log
rm -f "$tmp/state"; reset_log; MOCK_DYNAMIC=1 SQUAD_DISPATCH_WAIT=5 "$squad" dispatch dev-a T-12 >/dev/null 2>&1 || true
check "PR 28: two failed steps: the task dispatched with no text names both step logs" grep -q "agent prompt dev-a .*T-12 .*CANDIDATE-9 failed.*$R9/step-1.log, $R9/step-2.log" "$MOCK_LOG"
# CodeRabbit (PR #28): every task of the failed candidate is left out: nothing is built, each task is sent back with the log
printf '%s dev-a T-12 DONE\n' "$(date '+%Y-%m-%d %H:%M:%S')" >>.team/events.log
task28 13 team/integration
cp .team/tasks/CANDIDATE-1.md .team/tasks/CANDIDATE-11.md; printf 'test ! -f t13.txt || { echo t13 breaks; exit 6; }\n' >.team/tasks/CANDIDATE-11.checks
"$squad" candidate CANDIDATE-11 T-13 >/dev/null 2>&1 || true
"$squad" heavy tester CANDIDATE-11 --batch .team/tasks/CANDIDATE-11.checks >/dev/null 2>&1 || true
R11="$tmp/b28/.team/receipts/CANDIDATE-11"
check "PR 28: a wrong ID beside the only task is refused, and nothing is logged" sh -c "! '$squad' candidate CANDIDATE-12 --from CANDIDATE-11 --without T-13 --without T-99 >/dev/null 2>&1 && ! grep -q ' SENT_BACK from=CANDIDATE-11' .team/events.log"
"$squad" candidate CANDIDATE-12 --from CANDIDATE-11 --without T-13 >"$tmp/cout" 2>&1 && crc=0 || crc=$?
check "PR 28: a one-task candidate without its task: no candidate is built, no number is used, exit 0" sh -c "[ $crc = 0 ] && ! test -e .team/candidates/CANDIDATE-12 && ! git -C '$I' rev-parse -q --verify candidate/CANDIDATE-12 && ! test -e .team/tasks/CANDIDATE-12.md && ! test -e .team/tasks/CANDIDATE-12.checks && ! grep -q ' CANDIDATE-12 ' .team/events.log"
check "PR 28: the only task is logged SENT_BACK once, with the step log" sh -c "[ \$(grep -c ' lead T-13 SENT_BACK from=CANDIDATE-11 log=$R11/step-1.log\$' .team/events.log) = 1 ] && [ \$(grep -c ' T-13 SENT_BACK' .team/events.log) = 1 ]"
check "PR 28: the answer names the task and the step log in one line, and says that a plain new candidate comes after the new approval" sh -c "[ \$(grep -c 'T-13' '$tmp/cout') = 1 ] && grep -q 'T-13 .*sent back.*$R11/step-1.log' '$tmp/cout' && grep -q 'plain new candidate' '$tmp/cout'"
"$squad" candidate CANDIDATE-12 --from CANDIDATE-11 --without T-13 >/dev/null 2>&1 && crc=0 || crc=$?
check "PR 28: a second identical call logs no second SENT_BACK" sh -c "[ $crc = 0 ] && [ \$(grep -c ' T-13 SENT_BACK' .team/events.log) = 1 ]"
rm -f "$tmp/state"; reset_log; MOCK_DYNAMIC=1 SQUAD_DISPATCH_WAIT=5 "$squad" dispatch dev-a T-13 >/dev/null 2>&1 || true
check "PR 28: the dispatch of that task carries the failed-candidate text and the step log" grep -q "agent prompt dev-a .*T-13 .*CANDIDATE-11 failed.*$R11/step-1.log" "$MOCK_LOG"
check "PR 28: the lead's role file says what to do when the failed candidate has no task left" grep -qF 'no task left' .team/roles/lead.md
check "028: the lead's and the tester's role files name the two commands" sh -c "grep -qF -- '--from CANDIDATE-<n> --without <ID>' .team/roles/lead.md && grep -qF -- 'FAIL --task <ID>' .team/roles/tester.md"
check "028: the lead's role file says to write the check list first when a check belongs only to the task left out" grep -q 'write the brief and the check list of .CANDIDATE-<m>. first' .team/roles/lead.md

# ---- 029 · the full suite once a night: squad reads the night's result -----------------
cat >"$tmp/bin/gh" <<'EOF'
#!/usr/bin/env bash
echo "gh $*" >>"$MOCK_LOG"
# GH_SLEEP: every call takes this many seconds (a gh that hangs); GH_VIEW_SLEEP: "run view" takes this many seconds
# GH_MODE: fail (exit 1), garbage (an answer that is not JSON), ratelimit (GitHub's rate-limit error),
# notfound (no such workflow), noremote (no GitHub remote), badtoken (a token that GitHub refuses)
[ -z "${GH_SLEEP:-}" ] || sleep "$GH_SLEEP"
case "${GH_MODE:-}" in
  fail) exit 1 ;;
  garbage) echo '<html>502 Bad Gateway</html>'; exit 0 ;;
  ratelimit) echo 'HTTP 403: API rate limit exceeded for user ID 1.' >&2; exit 1 ;;
  notfound) echo 'HTTP 404: workflow nightly.yml not found on the default branch' >&2; exit 1 ;;
  noremote) echo 'failed to determine base repo: no git remotes found' >&2; exit 1 ;;
  badtoken) echo 'HTTP 401: Bad credentials' >&2; exit 1 ;;
esac
# like GitHub: a scheduled run belongs to the default branch (main), whatever ref the workflow checks out
branch=""; prev=""; for a in "$@"; do [ "$prev" != --branch ] || branch=$a; prev=$a; done
case "$1 $2" in
  "run list") if [ -f "${GH_RUNS:-}" ] && { [ -z "$branch" ] || [ "$branch" = main ]; }; then cat "$GH_RUNS"; else echo '[]'; fi ;;
  "run view") [ -z "${GH_VIEW_SLEEP:-}" ] || sleep "$GH_VIEW_SLEEP"; cat "$GH_JOBS" ;;
esac
EOF
chmod +x "$tmp/bin/gh"
export GH_RUNS="$tmp/gh-runs.json" GH_JOBS="$tmp/gh-jobs.json"; rm -f "$GH_RUNS"
gh_run() { printf '[{"databaseId":%s,"headSha":"abc123def4567890","conclusion":"%s","status":"%s","createdAt":"%s","url":"https://github.test/o/r/actions/runs/%s"}]\n' "$1" "$2" "${3:-completed}" "${4:-2026-11-22T02:00:00Z}" "$1" >"$GH_RUNS"; }   # <id> <conclusion> [<status> [<date>]]
printf '{"jobs":[{"name":"unit","conclusion":"success","url":"https://github.test/job/1"},{"name":"storybook","conclusion":"failure","url":"https://github.test/job/2"}]}\n' >"$GH_JOBS"
night() { nrc=0; MOCK_AGENTS="$ag28" MOCK_PANE_TEXT="$rdy" "$squad" nightly >"$tmp/nout" 2>&1 || nrc=$?; }
nwatch() { SQUAD_NIGHTLY_POLL=0 MOCK_AGENTS="$ag28" MOCK_PANE_TEXT="$rdy" "$squad" watch --once >/dev/null 2>&1 || true; }
told() { [ "$(grep -c 'agent prompt lead \[squad\] The nightly run' "$MOCK_LOG")" = "$1" ] && [ "$(grep -c 'notification show squad: the nightly run failed' "$MOCK_LOG")" = "$1" ]; }   # <times the lead and the owner were told>
nightly_events() { [ "$(grep -c " lead - NIGHTLY $1" .team/events.log)" = "$2" ]; }   # <the event's text> <times it is logged>
silent() { told 0 && nightly_events "" 0; }
gh_run 70 failure; reset_log; night
check "029: with no nightly_workflow setting, squad nightly says so and exits 0" sh -c "[ $nrc = 0 ] && grep -q 'nightly_workflow' '$tmp/nout'"
nwatch
check "029: and the watch asks GitHub nothing" refuses grep -q '^gh ' "$MOCK_LOG"
check "029: and stays silent" silent
printf 'nightly_workflow nightly.yml\n' >>.team/team.conf
reset_log; nrc=0; SQUAD_GH=gh-is-not-installed "$squad" nightly >"$tmp/nout" 2>&1 || nrc=$?
check "029: with no gh, squad nightly says so and exits 0" sh -c "[ $nrc = 0 ] && grep -q 'gh (the GitHub CLI) is not installed' '$tmp/nout'"
SQUAD_GH=gh-is-not-installed nwatch
check "029: and the watch stays silent" silent
rm -f "$GH_RUNS"; reset_log; night
check "029: with no scheduled run, squad nightly says so and exits 0" sh -c "[ $nrc = 0 ] && grep -q 'no scheduled run of nightly.yml yet' '$tmp/nout'"
check "029: it asks for the newest scheduled run of the workflow" log_has "gh run list --workflow nightly.yml --event schedule --limit 1 --json databaseId,headSha,conclusion,status,createdAt,url"
nwatch
check "029: and the watch stays silent" silent
gh_run 76 "" in_progress; reset_log; night; nwatch
check "029: a run that has not ended is shown" sh -c "[ $nrc = 0 ] && grep -q 'in_progress' '$tmp/nout'"
check "029: and it is not logged, and nobody is told" silent
gh_run 77 failure; reset_log; night
check "029: squad nightly prints the date, the result and the failed jobs with their URLs" sh -c "[ $nrc = 0 ] && grep -q '2026-11-22T02:00:00Z.*FAIL.*https://github.test/o/r/actions/runs/77' '$tmp/nout' && grep -q 'storybook.*https://github.test/job/2' '$tmp/nout' && ! grep -q 'unit' '$tmp/nout'"
check "029: the run is found with the integration branch not the default branch: no gh call names a branch" refuses grep -q -- '^gh .*--branch' "$MOCK_LOG"
check "029: the run's commit is shown as the workflow's commit, and the lead and the owner are not given it as the tested commit" sh -c "grep -q 'workflow commit abc123def456' '$tmp/nout' && ! grep -E 'agent prompt lead|notification show' '$MOCK_LOG' | grep -q abc123"
check "029: a failed run tells the lead and the owner once" told 1
check "029: the lead's line names the failed job and its URL" grep -q 'agent prompt lead \[squad\] The nightly run.*storybook https://github.test/job/2' "$MOCK_LOG"
night; nwatch
check "029: one NIGHTLY event per run, also when the command and the watch read it again" sh -c "[ \$(grep -c ' lead - NIGHTLY FAIL run=77 workflow_commit=abc123def4567890 ' .team/events.log) = 1 ] && [ \$(grep -c ' NIGHTLY ' .team/events.log) = 1 ] && grep -q 'FAIL' '$tmp/nout'"
check "029: and the lead and the owner are not told again" told 1
gh_run 78 failure; reset_log; nwatch; nwatch
check "029: the watch checks a new scheduled run once" nightly_events "FAIL run=78 " 1
check "029: on FAIL the lead gets one line and the owner one notification" told 1
gh_run 79 success; reset_log; nwatch; nwatch
check "029: on PASS the watch logs the event" nightly_events "PASS run=79 " 1
check "029: and tells nobody" told 0
gh_run 80 failure; reset_log; SQUAD_NIGHTLY_POLL=600 MOCK_AGENTS="$ag28" MOCK_PANE_TEXT="$rdy" "$squad" watch --once >/dev/null 2>&1 || true
check "029: the watch asks GitHub again only after its poll time" sh -c "! grep -q '^gh ' '$MOCK_LOG' && ! grep -q ' NIGHTLY FAIL run=80 ' .team/events.log"
cp .team/events.log "$tmp/events.keep"; rm -rf .team/observer/.watchdog .team/observer/.nightly-*
printf '2026-01-01 10:00:00 lead T-172 CHANGES head=x\n%s lead - NIGHTLY PASS run=81\n' "$(date '+%Y-%m-%d %H:%M:%S')" >.team/events.log; rm -f "$GH_RUNS"; reset_log; nwatch
check "029: a nightly result is no team event: a stall is still told" grep -q ' lead - STALLED .*T-172 CHANGES' .team/events.log
cp "$tmp/events.keep" .team/events.log; rm -rf .team/observer/.watchdog
check "029: the role files and PROTOCOL describe the fast gate and the nightly full run" sh -c "grep -qi 'fast gate' .team/roles/lead.md && grep -q 'squad nightly' .team/roles/lead.md && grep -qi 'fast gate' .team/roles/tester.md && grep -qi 'nightly' .team/roles/tester.md && grep -q 'The fast gate and the nightly full run' .team/PROTOCOL.md"
# review findings: two callers at once, a gh that hangs, a gh that fails, a lead that shows a dialog
gh_run 82 failure; reset_log
( export GH_VIEW_SLEEP=2; night ) & ( export GH_VIEW_SLEEP=2; night ) & ( export GH_VIEW_SLEEP=2; nwatch ) & wait   # all three read the run before one of them records it
check "029: two callers that read the same new run at once log it once" nightly_events "FAIL run=82 " 1
check "029: and the lead and the owner are told once" told 1
quiet() { told 0 && [ "$(grep -c ' lead - NIGHTLY ' .team/events.log)" = "$nev" ]; }   # nobody was told, and no new NIGHTLY event since $nev was read
gh_run 83 failure; reset_log; t0=$(date +%s); nev=$(grep -c ' lead - NIGHTLY ' .team/events.log)
export GH_SLEEP=30 SQUAD_GH_LIMIT=1; night; nwatch; unset GH_SLEEP SQUAD_GH_LIMIT
check "029: a gh that hangs is stopped at the limit: squad nightly says so and exits 0, and the watch goes on" sh -c "[ $nrc = 0 ] && [ $(( $(date +%s) - t0 )) -lt 25 ] && grep -q 'no answer in 1 s' '$tmp/nout'"
check "029: and nothing is logged, and nobody is told" quiet
check "029: and no gh is left running" refuses pgrep -f "$tmp/bin/gh"
for m in fail garbage ratelimit; do
  reset_log; export GH_MODE=$m; night; nwatch; unset GH_MODE
  case "$m" in fail) want='gh could not list the runs of nightly.yml' ;; garbage) want='not a list of runs' ;; *) want='API rate limit exceeded' ;; esac
  check "029: gh answers with '$m': squad nightly says so and exits 0" sh -c "[ $nrc = 0 ] && grep -q '$want' '$tmp/nout'"
  check "029: gh answers with '$m': the watch stays silent" quiet
done
reset_log; nwatch
check "029: after those failures the watch still reads the run when gh answers again" nightly_events "FAIL run=83 " 1
gh_run 84 failure; reset_log
SQUAD_NIGHTLY_POLL=0 MOCK_AGENTS="$ag28" MOCK_PANE_TEXT=$(cat "$longq") "$squad" watch --once >/dev/null 2>&1 || true
check "029: a failed night while the lead shows a dialog: nothing is typed into the lead; the event and the owner's notification are there" sh -c "! grep -q 'agent prompt lead' '$MOCK_LOG' && grep -q ' lead - NIGHTLY FAIL run=84 ' .team/events.log && [ \$(grep -c 'notification show squad: the nightly run failed' '$MOCK_LOG') = 1 ]"
nwatch; nwatch
check "029: the lead gets the line once when the dialog is gone" told 1
# trial 6: gh errors that are not about authentication; a night with many failed jobs; an old run
for m in notfound noremote badtoken; do
  reset_log; export GH_MODE=$m; night; unset GH_MODE
  case "$m" in notfound) want='HTTP 404: workflow nightly.yml not found' ;; noremote) want='no git remotes found' ;; *) want='HTTP 401: Bad credentials' ;; esac
  if [ "$m" = badtoken ]; then check "trial 6: a gh error about authentication gets the hint (see: gh auth status)" sh -c "grep -q '$want' '$tmp/nout' && grep -q 'gh auth status' '$tmp/nout'"
  else check "trial 6: gh answers with '$m': the error is shown with no hint about authentication" sh -c "[ $nrc = 0 ] && grep -q '$want' '$tmp/nout' && ! grep -q 'gh auth status' '$tmp/nout'"; fi
done
{ printf '{"jobs":['; for k in 1 2 3 4 5 6 7 8; do printf '{"name":"job%s","conclusion":"failure","url":"https://github.test/job/%s"},' "$k" "$k"; done; printf '{"name":"unit","conclusion":"success","url":"https://github.test/job/9"}]}\n'; } >"$GH_JOBS"
first5='8 failed jobs: job1 https://github.test/job/1; job2 https://github.test/job/2; job3 https://github.test/job/3; job4 https://github.test/job/4; job5 https://github.test/job/5; and 3 more: https://github.test/o/r/actions/runs/85'
gh_run 85 failure completed "$(jq -nr 'now | todate')"; reset_log; night
check "trial 6: squad nightly still prints every failed job" test "$(grep -c '^  failed: job' "$tmp/nout")" = 8
check "trial 6: the NIGHTLY event carries the number of failed jobs, the first 5 and the run for the others" sh -c "grep -q ' lead - NIGHTLY FAIL run=85 .* failed: $first5\$' .team/events.log && ! grep ' NIGHTLY FAIL run=85 ' .team/events.log | grep -q job6"
check "trial 6: the lead's line carries the same short list" sh -c "grep -q 'agent prompt lead \[squad\] The nightly run.*$first5\. ' '$MOCK_LOG' && ! grep 'agent prompt lead' '$MOCK_LOG' | grep -q job6"
check "trial 6: a run of today gets no remark on its age" sh -c "! grep -q 'days old' '$tmp/nout' && ! grep -q 'days old' '$MOCK_LOG'"
gh_run 86 failure completed "$(jq -nr 'now - 259200 | todate')"; reset_log; night
check "trial 6: a run that is 3 days old is printed with its age" grep -q '(3 days old: the schedule may not be running)  FAIL' "$tmp/nout"
check "trial 6: and the lead's line names that age; the event has no new field" sh -c "grep -q 'agent prompt lead \[squad\] The nightly run of .*(3 days old: the schedule may not be running)' '$MOCK_LOG' && ! grep -q 'NIGHTLY .*days old' .team/events.log"
check "029: the README says that GitHub starts a scheduled workflow only from the default branch, and that the workflow prints the tested commit" sh -c "grep -q 'only from the default branch' '$here/../README.md' && grep -q 'tested commit' '$here/../README.md' && ! grep -q -- '--branch' '$here/../README.md'"
check "029: the README lists the command, the setting and a workflow example" sh -c "grep -q 'squad nightly' '$here/../README.md' && grep -q 'nightly_workflow' '$here/../README.md' && grep -q 'schedule:' '$here/../README.md'"
check "029: the usage text lists squad nightly" sh -c "'$squad' help 2>&1 | grep -q 'squad nightly'"
echo
echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
