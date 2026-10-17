
ROOT=/local1/ezioswangnlp/embodiedswe
REPO=$ROOT/EmbodiedSWE
BWRAP=$ROOT/node_env/lib/node_modules/@openai/codex/node_modules/@openai/codex-linux-x64/vendor/x86_64-unknown-linux-musl/codex-resources/bwrap
SYSLIBS=$ROOT/syslibs/root/usr/lib/x86_64-linux-gnu   # user-extracted libGLU (Isaac RTX/MDL needs it)

# Host system dirs read-only, /dev + /tmp passthrough; /home and /local1 read-only so the
# agent cannot touch the repo (graders, other runs) except through the explicit binds.
BWRAP_SYS=(
  --die-with-parent --unshare-pid
  --dev-bind /dev /dev --proc /proc
  --ro-bind /usr /usr --ro-bind /etc /etc --ro-bind /bin /bin --ro-bind /sbin /sbin
  --ro-bind /lib /lib --ro-bind /lib64 /lib64
  --bind /tmp /tmp
  --ro-bind /home /home --ro-bind /local1 /local1
  --ro-bind /sys /sys
  --ro-bind /run/systemd/resolve /run/systemd/resolve
)
