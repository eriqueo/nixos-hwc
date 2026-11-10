# Operator lint entry points

`charter-lint.sh` forwards to the canonical release checker. Use
`./workspace/nixos-dev/charter-lint.sh --law 4` for the wired permission rule,
or omit `--law` for all wired laws. It accepts `--root`, not a positional path.

`permission-lint.sh [path]` is a historical permission-pattern report. It is
not proof of the complete current secret or service policy. Review findings
against CHARTER.md and evaluated configuration. Its `--fix` mode edits source;
review the diff before any commit. `permission-linter.sh` is a permanent
compatibility link to that one implementation.

`container-lint.sh` is a legacy Charter-v6 investigation tool. Its old container
layout assumptions are not current release rules. Use registered owner checks
and the release runner for integration and activation.

`workspace/utilities/lints` is a permanent compatibility directory link here.
