# soularr Version Tracking

**Current Version**: `1.2.3`
**Last Updated**: 2025-12-04
**API Compatibility**: slskd 0.21.x
**Image**: `docker.io/mrusse08/soularr:1.2.3`

## Known Issues
- None

## Version History
- **1.2.3** (2025-12-04): Initial pinned version, compatible with slskd 0.21.4 API

## Update Process
1. Check releases: https://github.com/mrusse08/soularr/releases
2. Verify API compatibility with current slskd version
3. Test new version in staging environment
4. Update `domains/server/containers/soularr/options.nix`
5. Run `nix flake check && sudo nixos-rebuild test --flake .#hwc-server`
6. Monitor logs for 404 errors or API issues
7. Apply with `sudo nixos-rebuild switch --flake .#hwc-server`
8. Update this VERSION.md file

## API Dependencies
- **slskd**: Requires slskd 0.21.x with API v0
- **lidarr**: Requires lidarr 2.x API v1
