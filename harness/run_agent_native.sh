#!/usr/bin/env bash
# One Codex agent run against a built experiment, mirroring eval/docker/entrypoints/agent-entry.sh
# (codex adapter + KEEP_GOING leg loop) but inside bwrap instead of docker.
#
#   run_agent_native.sh <exp_dir> <run_name> <budget_min> <gpu> [model] [reasoning_effort]
#
# The run's task/ folder must already exist (run_agent_sandbox.py --dry-run assembles it).
set -euo pipefail
source "$(dirname "$0")/_bwrap_base.sh"

EXP=$(realpath "$1"); RUN=$2; BUDGET_MIN=$3; GPU=$4
MODEL=${5:-gpt-5.6-luna}; EFFORT=${6:-medium}
RUN_DIR=$EXP/runs/$RUN
STAGE=$(ls -d "$EXP"/stages/*/ | head -1)
[ -f "$RUN_DIR/task/instructions.md" ] || { echo "missing $RUN_DIR/task (dry-run first)" >&2; exit 64; }

mkdir -p "$RUN_DIR"/{workspace/.agent,workspace/tmp,submissions,agent_home/.codex,bench_cache} "$STAGE/bench/.cache"
mkdir -p "$ROOT/ovcache"
# Codex login (ChatGPT subscription) — copied, never the host's own ~/.codex
cp ~/.codex/auth.json "$RUN_DIR/agent_home/.codex/auth.json"
[ -f ~/.codex/config.toml ] && cp ~/.codex/config.toml "$RUN_DIR/agent_home/.codex/"

NUDGE='You stopped, but this session is still running and the task is not finished.
Nothing has been lost — your workspace, your files and the environment are as you left
them. Pick up where you were: check the current state of your work, then carry on. Keep
the best version you have in /workspace/solution/ and run `submit` whenever it improves.
Keep working without stopping until the task is solved.'

BOX=( "$BWRAP" "${BWRAP_SYS[@]}" \
    --ro-bind "$STAGE/bench" /bench \
    --bind "$RUN_DIR/bench_cache" /bench/.cache \
    --ro-bind "$RUN_DIR/task" /task \
    --bind "$RUN_DIR/workspace" /workspace \
    --bind "$RUN_DIR/submissions" /submissions \
    --bind "$REPO/.venv" /opt/venv \
    --ro-bind "$ROOT/node_env" /opt/node \
    --ro-bind "$REPO/eval/docker/entrypoints/submit" /opt/bin/submit \
    --bind "$RUN_DIR/agent_home" /agent \
    --bind "$ROOT/ovcache" /ovcache \
    --chdir /workspace \
    --clearenv \
    --setenv HOME /agent \
    --setenv USER agent \
    --setenv PATH /opt/venv/bin:/opt/bin:/opt/node/bin:/usr/local/bin:/usr/bin:/bin \
    --setenv PYTHONPATH /bench:/task/tools \
    --setenv XDG_CACHE_HOME /ovcache \
    --setenv TMPDIR /workspace/tmp \
    --setenv OMNI_KIT_ACCEPT_EULA YES --setenv ACCEPT_EULA Y --setenv PRIVACY_CONSENT Y \
    --setenv CUDA_VISIBLE_DEVICES "$GPU" \
    --setenv LD_LIBRARY_PATH "$SYSLIBS" \
    --setenv TERM dumb )

leg() {  # $1 = prompt, $2 = "resume" or ""
  local -a cmd=(codex exec --sandbox danger-full-access --skip-git-repo-check
                -m "$MODEL" -c "model_reasoning_effort=\"$EFFORT\"")
  [ -n "${2:-}" ] && cmd+=(resume --last)
  local left=$(( DEADLINE - $(date +%s) ))
  (( left > 0 )) || return 0
  echo "=== leg $(date -Is) resume=${2:-no} left=${left}s" >> "$RUN_DIR/workspace/.agent/legs.log"
  timeout -k 30 "$left" "${BOX[@]}" "${cmd[@]}" "$1" >> "$RUN_DIR/workspace/.agent/transcript.txt" 2>> "$RUN_DIR/workspace/.agent/stderr.log" || true
}

START=$(date +%s); DEADLINE=$(( START + ${BUDGET_MIN%.*} * 60 ))
python3 -c 'import json,sys; k=["exp","run","model","reasoning_effort","gpu","budget_min","started"]; d=dict(zip(k,sys.argv[1:])); d.update(agent="codex", substrate="bwrap (no docker GPU on host)"); print(json.dumps(d, indent=1))' \
  "$EXP" "$RUN" "$MODEL" "$EFFORT" "$GPU" "$BUDGET_MIN" "$(date -Is)" > "$RUN_DIR/run.json"

leg "$(cat "$RUN_DIR/task/instructions.md")" ""
while (( $(date +%s) < DEADLINE )); do
  leg "$NUDGE" resume
done
echo "=== budget reached $(date -Is)" >> "$RUN_DIR/workspace/.agent/legs.log"
# final solution/ always counts as the last submission
[ -f "$RUN_DIR/workspace/solution/solve.py" ] && echo "final solution present" >> "$RUN_DIR/workspace/.agent/legs.log"
