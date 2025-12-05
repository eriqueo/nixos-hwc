# slskd Version Tracking

**Current Version**: `0.21.4`
**Last Updated**: 2025-12-04
**API Version**: v0
**Image**: `slskd/slskd:0.21.4`

## Known Issues
- None

## Version History
- **0.21.4** (2025-12-04): Initial pinned version, stable release with API v0 support

## Update Process
1. Check releases: https://github.com/slskd/slskd/releases
2. Test new version in staging environment
3. Update `domains/server/containers/slskd/options.nix`
4. Run `nix flake check && sudo nixos-rebuild test --flake .#hwc-server`
5. Monitor logs for API compatibility with soularr
6. Apply with `sudo nixos-rebuild switch --flake .#hwc-server`
7. Update this VERSION.md file

## API Compatibility
- **soularr**: Requires slskd API v0 endpoints (`/api/v0/transfers/downloads/`)
- **Compatible soularr versions**: 1.2.3+
