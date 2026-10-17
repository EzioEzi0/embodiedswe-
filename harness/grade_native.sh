#!/usr/bin/env bash
# Grade one delivered solution with the OFFICIAL eval/grader/grade.py, mirroring
# eval/scripts/run_grade.py's container (same mounts, --network none) but inside bwrap.
# --render makes grade.py dump frames; we then stitch them into an mp4.
#
#   grade_native.sh <exp_dir> <solution_dir> <out_dir> <gpu> [seed] [num_envs]
set -euo pipefail
source "$(dirname "$0")/_bwrap_base.sh"

EXP=$(realpath "$1"); SOL=$(realpath "$2"); OUT=$3; GPU=$4; SEED=${5:-0}; NENV=${6:-1}
STAGE=$(ls -d "$EXP"/stages/*/ | head -1)
PRESET=$(python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); print(r["stages"][0]["preset"] if "stages" in r else r["preset"])' "$EXP/resolved.json")
SUITE=${PRESET%%.*}; SCENE=$(echo "$PRESET" | cut -d. -f2)
GRADERS=$REPO/robobench/suites/$SUITE/grader
[ -f "$SOL/solve.py" ] || { echo "no $SOL/solve.py" >&2; exit 1; }
mkdir -p "$OUT" "$STAGE/bench/.cache" "$OUT/.bench_cache" "$OUT/.home" "$ROOT/ovcache"
OUT=$(realpath "$OUT")

"$BWRAP" "${BWRAP_SYS[@]}" --unshare-net \
  --ro-bind "$STAGE/bench" /bench \
  --bind "$OUT/.bench_cache" /bench/.cache \
  --ro-bind "$GRADERS" /graders \
  --ro-bind "$SOL" /solution \
  --ro-bind "$REPO/eval/grader" /grader \
  --bind "$OUT" /out \
  --bind "$REPO/.venv" /opt/venv \
  --bind "$OUT/.home" /agent \
  --bind "$ROOT/ovcache" /ovcache \
  --chdir /out --clearenv \
  --setenv HOME /agent \
  --setenv PATH /opt/venv/bin:/usr/bin:/bin \
  --setenv PYTHONPATH /bench \
  --setenv XDG_CACHE_HOME /ovcache --setenv TMPDIR /tmp \
  --setenv HF_HUB_OFFLINE 1 \
  --setenv OMNI_KIT_ACCEPT_EULA YES --setenv ACCEPT_EULA Y --setenv PRIVACY_CONSENT Y \
  --setenv CUDA_VISIBLE_DEVICES "$GPU" \
  --setenv LD_LIBRARY_PATH "$SYSLIBS" \
  python /grader/grade.py --preset "$PRESET" --scene "$SCENE" --seed "$SEED" --num-envs "$NENV" --render \
  > "$OUT/container.log" 2>&1 || echo "grade.py exited $?" >> "$OUT/container.log"

# frames/*.jpg (sim-time paced) -> mp4
"$REPO/.venv/bin/python" -I - "$OUT" <<'PY'
import json, sys
from pathlib import Path
import imageio.v2 as iio
out = Path(sys.argv[1])
fps = json.loads((out / "render.json").read_text()).get("fps_sim", 10) if (out / "render.json").exists() else 10
frames = sorted((out / "frames").glob("*.jpg"))
if not frames:
    sys.exit("no frames rendered")
with iio.get_writer(out / "grade_video.mp4", fps=fps, quality=8) as w:
    for f in frames:
        w.append_data(iio.imread(f))
print(f"video: {out/'grade_video.mp4'}  ({len(frames)} frames @ {fps} fps)")
PY
echo "verdict:"; cat "$OUT/verdict.json" 2>/dev/null || echo "(no verdict.json — see $OUT/container.log)"
