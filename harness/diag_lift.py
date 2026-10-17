"""Diagnose dev-vs-grader mismatch: run a solution's stage_1 under one env-construction mode
and report the bulb's peak height.

  mode=dev     ENVS.get(p)().build(num_envs=1); env.reset()            (what task.md tells the agent)
  mode=seeded  build(num_envs=1, seed=0); env.reset(seed=0)             (what grade.py does)
  mode=render  seeded + cameras + grade.py's start_renderer             (grade.py --render)
"""
import os
import sys

mode = sys.argv[1]
from isaaclab.app import AppLauncher

app = AppLauncher(headless=True, enable_cameras=(mode == "render")).app

import importlib.util
from pathlib import Path

import robobench
import torch

robobench.discover()
from robobench.core.registries import ENVS

P = "assembly.bulb.franka.osc"
if mode == "dev":
    env = ENVS.get(P)().build(num_envs=1)
    env.reset()
else:
    env = ENVS.get(P)().build(num_envs=1, seed=0)
    if mode == "render":
        sys.path.insert(0, "/grader")
        spec = importlib.util.spec_from_file_location("grade", "/grader/grade.py")
        g = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(g)
        Path("/out").mkdir(exist_ok=True)
        g.start_renderer(env, Path("/out"))
    env.reset(seed=0)

b = env.scene.bulbs[0]
print("DIAG start bulb pos", b.data.root_pos_w.tolist(), flush=True)
peak = {"z": float(b.data.root_pos_w[0, 2])}
_step = env.step


def step(a):
    _step(a)
    peak["z"] = max(peak["z"], float(b.data.root_pos_w[0, 2]))


env.step = step
sys.path.insert(0, "/solution")
from stages import stage_1  # noqa: E402

stage_1.run(env)
print(f"DIAG mode={mode} final_z={float(b.data.root_pos_w[0, 2]):.3f} peak_z={peak['z']:.3f} "
      f"stage1_check={stage_1.check(env)}", flush=True)
os._exit(0)
