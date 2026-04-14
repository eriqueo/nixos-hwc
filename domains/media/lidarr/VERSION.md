# lidarr Version Tracking

**Current Version**: `2.13.3`
**Last Updated**: 2025-12-04
**API Version**: v1
**Image**: `lscr.io/linuxserver/lidarr:2.13.3`

## Known Issues
- **NullReferenceException in Distance.Clean()**: Present in master/latest branch
- **Workaround**: Using stable 2.13.3 release instead of develop branch

## Version History
- **2.13.3** (2025-12-04): Stable release, avoids NullRef bug in folder scanning

## Update Process
1. Check releases: https://github.com/Lidarr/Lidarr/releases
2. Verify Distance.Clean() bug is fixed in newer versions
3. Test new version in staging environment
4. Update `domains/server/containers/lidarr/options.nix`
5. Run `nix flake check && sudo nixos-rebuild test --flake .#hwc-server`
6. Monitor logs for NullReferenceException during folder scans
7. Apply with `sudo nixos-rebuild switch --flake .#hwc-server`
8. Update this VERSION.md file

## API Compatibility
- **soularr**: Requires lidarr API v1
- **Compatible soularr versions**: 1.2.3+
