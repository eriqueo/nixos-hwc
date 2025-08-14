# Quick Reference Card

## Daily Commands
```bash
# Check old system
cd /etc/nixos && sudo nixos-rebuild build --flake .#hwc-server

# Check new system  
cd /etc/nixos-next && sudo nixos-rebuild build --flake .#test-refactor

# Quick validation
/etc/nixos-next/operations/validation/quick-check.sh
```

## Emergency Rollback

```bash
# If something breaks:
cd /etc/nixos
git checkout main
sudo nixos-rebuild switch --flake .#hwc-server

# Nuclear option:
sudo nixos-rebuild switch --rollback
```

## Progress Tracker

|Day|Goal            |Status|Rollback Point        |
|---|----------------|------|----------------------|
|1  |Create structure|[ ]   |Git branch            |
|2  |First build     |[ ]   |Delete /etc/nixos-next|
|3  |First service   |[ ]   |Remove service module |

## Key Paths

- Old (working): `/etc/nixos`
- New (building): `/etc/nixos-next`
- Logs: `/etc/nixos-next/MIGRATION_LOG.md`

## Mental Model

- Old house: Still living in it (don’t touch!)
- New house: Building next door (safe to experiment)
- Moving day: Not for weeks (no pressure)
