# Music Pipeline Fix Plan

## Investigation Summary

### Issues Identified

1. **slskd Network Attachment Problem**
   - Container runs but is removed from podman database due to `--rm` flag
   - Not properly attached to media-network, breaking DNS resolution
   - Soularr can't reach slskd via `http://slskd:5030`

2. **Soularr-slskd API Version Mismatch**
   - Soularr expects `/api/v0/transfers/downloads/` endpoints
   - Both containers use unpinned `:latest` tags
   - API incompatibility causing 404 errors

3. **Music Library Chaos**
   - Multiple duplicate folders with inconsistent naming
   - Example: "2016 - Everybody's Somebody's Nobody" duplicated multiple times
   - Beets is already configured but needs to be used for cleanup

## Plan Development in Progress

This plan is being developed to address all three issues systematically.
