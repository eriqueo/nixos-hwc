# domains/lib/mkTsNode.nix
#
# One launcher for native units that run Scout TypeScript sources: node itself
# loads tsx as an --import hook, so the unit's main PID is the app.
#
# Why not `node tsx/dist/cli.mjs`: that wrapper is a parent process. With the
# default KillMode=control-group, systemd signals both processes; the wrapper
# waits ~30 ms for the child to report the signal, then relays its own SIGTERM.
# A child busy for 50 ms therefore saw a second signal and took its "exit now"
# path (20/20 runs); at 150 ms the wrapper killed the child (exit 143) even when
# only the parent was signalled. Plain node with the same loader drained cleanly
# 40/40 (scout shutdown spike, 2026-09-29). KillMode=mixed alone would not fix
# the parent-only case. The apps keep their deliberate second-signal escape.
#
# Usage (domains/server/native/ai/<scout>/index.nix):
#   tsNode = import ../../../../lib/mkTsNode.nix { } cfg.workspaceRoot;
#   ExecStartPre = [ "${pkgs.coreutils}/bin/test -f ${tsNode.loader}" ];
#   ExecStart    = tsNode.run node cli "serve --port 8420";
{ }:
workspaceRoot:
rec {
  loader = "${workspaceRoot}/node_modules/tsx/dist/loader.mjs";
  run = node: script: args: "${node} --import ${loader} ${script} ${args}";
}
