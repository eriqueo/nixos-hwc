# Repository audit tools

`lint.sh` forwards to the current charter checker in `verification/charter.py`.
Run it from any directory. It accepts the same `--root` and `--law` arguments as
`workspace/nixos-dev/charter-lint.sh`; required release checks use this producer.

`drift.py` is a historical heuristic report for manual investigation. Its old
charter categories do not establish current compliance. The repository charter
and release checker own enforceable rules; do not follow old report advice to
create `options.nix` or obsolete profile files.

The former `workspace/utilities/audit` directory is a permanent compatibility
link to this owner. No second implementation is maintained.
