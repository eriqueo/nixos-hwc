# bitwarden

## Purpose
Installs the Bitwarden desktop client for the self-hosted Vaultwarden account.

## Boundaries
- Manages `hwc.home.apps.bitwarden.enable` and the desktop package.
- The client owns its writable settings and credentials. Set its self-hosted server to `https://vaultwarden.hwc.iheartwoodcraft.com` at login.

## Structure
- `index.nix` — Home Manager package using `mkSimpleApp`; preserves the upstream executable and native resources, with a session-bus relay for portal requests and the wrapped executable as the autostart/browser integration entry point.
- `portal-launcher.py` — private runtime socket and one relay per client invocation; startup refuses a failed relay, and termination waits at most five seconds per child. No vault data is stored here.
- `test_portal_launcher.py` — startup failure and deadline, argument preservation, app exit, relay exit and signal cleanup checks. The flake check runs against the package's actual launcher.

## Changelog
- 2026-09-30: Restore file selection through a separate session-bus connection, retaining Bitwarden's process isolation. A hardened client was denied by the portal directly and opened a GTK picker through the relay. Preserve native files and wrapped entry points; fail package construction if upstream resource layout changes. Remove the relay when direct portal requests from a hardened client succeed upstream.
- 2026-09-26: Added the desktop client for the existing Vaultwarden service.
