#!/usr/bin/env bash
# box_diag.sh <solution_dir> <gpu> <out_dir> <mode> — run diag_lift.py in the same bwrap box as grading
set -euo pipefail
source "$(dirname "$0")/_bwrap_base.sh"
SOL=$(realpath "$1"); GPU=$2; OUT=$3; MODE=$4
STAGE=$REPO/experiments/bulb_luna/stages/01_bulb_franka
mkdir -p "$OUT/.bench_cache" "$OUT/.home"; OUT=$(realpath "$OUT")
"$BWRAP" "${BWRAP_SYS[@]}" --unshare-net \
  --ro-bind "$STAGE/bench" /bench --bind "$OUT/.bench_cache" /bench/.cache \
  --ro-bind "$SOL" /solution --ro-bind "$REPO/eval/grader" /grader --bind "$OUT" /out \
  --ro-bind "$(dirname "$(realpath "$0")")/diag_lift.py" /diag_lift.py \
  --bind "$REPO/.venv" /opt/venv --bind "$OUT/.home" /agent --bind "$ROOT/ovcache" /ovcache \
  --chdir /out --clearenv --setenv HOME /agent --setenv PATH /opt/venv/bin:/usr/bin:/bin \
  --setenv PYTHONPATH /bench --setenv XDG_CACHE_HOME /ovcache --setenv TMPDIR /tmp --setenv HF_HUB_OFFLINE 1 \
  --setenv OMNI_KIT_ACCEPT_EULA YES --setenv ACCEPT_EULA Y --setenv PRIVACY_CONSENT Y \
  --setenv CUDA_VISIBLE_DEVICES "$GPU" --setenv LD_LIBRARY_PATH "$SYSLIBS" \
  python /diag_lift.py "$MODE"
