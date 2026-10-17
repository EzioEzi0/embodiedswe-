# EmbodiedSWE local harness (pluslab02-a6000)

Runs the EmbodiedSWE benchmark end to end (agent solves → official grader → video) on a
host with no root and no GPU inside Docker. The official Docker container is replaced by
bubblewrap with the same mounts; everything else is upstream code.

Write-up: https://claude.ai/artifact/BBouMaaGPHUM5coNAAd6F8

## What lives where

| Here (`~/embodiedswe/`) | Purpose |
|---|---|
| `harness/_bwrap_base.sh` | shared paths + sandbox mounts (`--unshare-pid`, read-only host) |
| `harness/run_agent_native.sh` | one Codex agent run inside the sandbox, budget + keep-going loop |
| `harness/grade_native.sh` | official `eval/grader/grade.py --render`, offline, frames → mp4 |
| `harness/diag_lift.py`, `harness/box_diag.sh` | diagnostic: dev (unseeded) vs grader (seed 0) initial conditions |
| `validate_libglu.patch` | the only change to upstream: `eval/envbuild/validate.py` keeps `LD_LIBRARY_PATH` / `CUDA_VISIBLE_DEVICES` |
| `UPSTREAM_COMMIT` | EmbodiedSWE commit the patch applies to |

Large things stay on `/local1/ezioswangnlp/embodiedswe/` (home is nearly full):

- `EmbodiedSWE/` — upstream clone, `.venv` (Isaac Sim 5.1 / Isaac Lab 2.3.2, 19 GB), all assets
- `EmbodiedSWE/experiments/<exp>/runs/<run>/` — task, workspace, submissions, grades
- `syslibs/` — user-extracted `libGLU` (no sudo); `node_env/` — Node + Codex CLI
- `videos_summary/` — result videos
- `harness` there is a symlink to `~/embodiedswe/harness`

## Run one task

```bash
cd /local1/ezioswangnlp/embodiedswe/EmbodiedSWE
export OMNI_KIT_ACCEPT_EULA=YES CUDA_VISIBLE_DEVICES=6 \
       LD_LIBRARY_PATH=/local1/ezioswangnlp/embodiedswe/syslibs/root/usr/lib/x86_64-linux-gnu

.venv/bin/python eval/scripts/build_env.py --name pcram_sol --stage pc_ram:franka:osc
.venv/bin/python eval/scripts/run_agent_sandbox.py experiments/pcram_sol \
    --agent codex --model gpt-5.6-sol --budget-min 45 --run codex_sol56_01 --dry-run
~/embodiedswe/harness/run_agent_native.sh experiments/pcram_sol codex_sol56_01 45 6 gpt-5.6-sol medium
~/embodiedswe/harness/grade_native.sh experiments/pcram_sol \
    experiments/pcram_sol/runs/codex_sol56_01/workspace/solution \
    experiments/pcram_sol/runs/codex_sol56_01/grades/final 6
```

Pick a GPU nobody else is using: sharing a card made Isaac's env build crash and the grader hang.
Codex must be logged in (`/local1/ezioswangnlp/embodiedswe/node_env/bin/codex login --device-auth`).
