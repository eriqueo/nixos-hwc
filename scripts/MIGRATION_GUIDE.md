# Service Migration Guide

## Migrated Services
1. ntfy - Day 3 - Simple container service

## Migration Process
1. Copy service from old location
2. Rewrite using hwc.services.* namespace
3. Use config.hwc.paths for all paths
4. Test module builds in isolation
5. Add to test machine
6. Validate build

## Next Services (by complexity)
- [ ] transcript-api (simple, no state)
- [ ] grafana (medium, has dashboards)
- [ ] jellyfin (complex, GPU + storage)
