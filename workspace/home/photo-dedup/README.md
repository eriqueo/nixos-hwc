# photo-dedup

Interactive photo deduplication tool for preparing external libraries before importing to Immich.

## Usage

```bash
photo-dedup                          # Interactive mode
photo-dedup /path/to/photos          # Specify directory
```

## What It Does

1. **Scans** the directory for photos (jpg, png, heic, raw, etc.)
2. **Phase 1**: Finds exact duplicates using `rmlint` (byte-identical)
3. **Phase 2**: Finds similar images using `czkawka` (perceptual hashing)
4. **Quarantines** duplicates to `.duplicates/` (never deletes)
5. **Generates** a report in `.dedup-reports/`

## Features

- **Interactive prompts** with sensible defaults
- **Reference directories** - Check against existing Immich library
- **Configurable similarity** - VeryHigh, High, Medium, Low
- **Safe quarantine** - Moves files, never deletes
- **Audit trail** - JSON reports for everything

## Workflow

```
External Photos
      │
      ▼
┌─────────────────────┐
│    photo-dedup      │
│  (run interactively)│
└──────────┬──────────┘
           │
           ▼
┌─────────────────────────────────────┐
│  Source Directory                   │
│  ├── photos/          (clean)       │
│  ├── .duplicates/     (quarantine)  │
│  └── .dedup-reports/  (audit logs)  │
└─────────────────────────────────────┘
           │
           ▼
  Review .duplicates/
           │
           ▼
  rm -rf .duplicates/  (when satisfied)
           │
           ▼
  Add to Immich as external library
```

## Dependencies

- `rmlint` - Exact duplicate detection
- `czkawka` - Similar image detection
- `jq` - JSON processing

All available in nixpkgs:
```bash
nix-shell -p rmlint czkawka jq
```

## Examples

### Basic usage
```bash
photo-dedup /mnt/media/old-laptop-photos
```

### Check against Immich + other libraries
```bash
photo-dedup /mnt/media/new-photos
# When prompted:
#   Check against Immich library? [Y/n]: y
#   Immich library path [/mnt/media/photos/archive]: <enter>
#   Add another reference directory? [y/N]: y
#   Path: /mnt/media/external-library-1
```

## Output Structure

```
/mnt/media/photos/
├── IMG_001.jpg                    # Kept (original)
├── IMG_002.jpg                    # Kept (unique)
├── .duplicates/
│   └── 2026-02-26_143022/
│       ├── exact/
│       │   └── IMG_001_copy.jpg   # Exact duplicate
│       └── similar/
│           └── IMG_001_edited.jpg # Similar image
└── .dedup-reports/
    └── 2026-02-26_143022/
        ├── exact-duplicates.json
        ├── similar-images.json
        └── dedup-report.txt
```

## Notes

- **Never touches Immich** - Works only on unmanaged directories
- **Safe for repeated runs** - Quarantine is timestamped
- **Review before deleting** - Check `.duplicates/` manually
- **Keep reports** - Useful if you need to know what was removed
