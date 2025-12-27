# Filesystem Organization Charter

**Owner**: Eric
**Scope**: `~/` — All user home directory organization
**Goal**: Deterministic, scalable, and maintainable filesystem structure with clear domain separation

---

## Core Principles

1. **3-Digit Prefix**: All top-level folders use `XXX_name` format with underscores (no dashes)
2. **Domain Separation**: Hundreds place indicates domain (100=work, 200=personal, etc.)
3. **Nested Structure**: Dewey-style tens-place categories: `X00_inbox`, `X10_documents`, `X20_projects`, `X30_reference`, `X40_assets`, `X90_archive`
4. **Inbox-First**: Process items through `000_inbox/` before filing
5. **Domain-Specific Storage**: Reference materials live within their relevant domain (not cross-domain)

---

## Top-Level Structure

```
~/
├── 000_inbox/              # Global processing queue
│   └── downloads/          # Browser downloads, temp files
├── 100_hwc/                # Work domain
├── 200_personal/           # Personal domain
├── 300_tech/               # Technology/development domain
├── 400_mail/               # Mail (Maildir, mbox)
├── 500_media/              # Cross-domain media library
└── 900_vaults/             # Cloud sync (Obsidian, etc.)
```

---

## Domain-Level Structure

Each domain (`100_hwc/`, `200_personal/`, `300_tech/`) follows this pattern (underscores, no dashes):

```
1XX_domain/
├── 100_inbox/              # Domain-specific processing queue
├── 110_documents/          # Domain documents
├── 120_projects/           # Projects / development work
├── 130_reference/          # Domain reference materials
├── 140_assets/             # Domain-specific assets/media
└── 190_archive/            # Completed/archived items (optional)
```

**Numbering Within Domains:**
- `X00-X09`: Inbox/processing
- `X10-X19`: Documents/files
- `X20-X29`: Projects/development
- `X30-X39`: Reference materials
- `X40-X49`: Assets/media
- `X90-X99`: Archive/completed

---

## Domain Definitions

### `000_inbox/` - Global Processing Queue
**Purpose**: Entry point for all incoming items
**Contents**: Downloads, screenshots, unsorted files
**Rule**: Process items FROM inbox TO appropriate domain
**Goal**: Keep empty (GTD-style)

### `100_hwc/` - Work Domain
**Purpose**: All work/business-related content
**Examples**: Client projects, business documents, work media
**Boundary**: Anything related to Heartwood Collective work

### `200_personal/` - Personal Domain
**Purpose**: Personal life management
**Examples**: Personal projects, finances, health, hobbies
**Boundary**: Non-work, non-technical personal items

### `300_tech/` - Technology Domain
**Purpose**: Development, learning, technical experiments
**Examples**: Code projects, tutorials, documentation, configs
**Boundary**: Technology-focused activities (learning, building, experimenting)

### `500_media/` - Cross-Domain Media
**Purpose**: Personal media library (not domain-specific)
**Examples**: Photos, music, videos
**Structure**:
```
500_media/
├── 510_pictures/
│   ├── screenshots/
│   └── 599_inbox/
├── 520_music/
└── 530_videos/
```

### `400_mail/` - Mail
**Purpose**: Mail storage and related configs
**Examples**: `Maildir/`, `mbox`, mail configs (if needed)

### `900_vaults/` - Cloud Sync
**Purpose**: Synced knowledge bases and cloud storage
**Examples**: Obsidian vaults, Proton Drive, sync folders
**Boundary**: Items managed by external sync services

---

## XDG Integration

System automatically maps XDG directories (update paths to match Dewey/underscore scheme):
- `XDG_DOWNLOAD_DIR` → `~/000_inbox/downloads/`
- `XDG_DOCUMENTS_DIR` → `~/100_hwc/110_documents/`
- `XDG_TEMPLATES_DIR` → `~/100_hwc/130_reference/templates/`
- `XDG_PICTURES_DIR` → `~/500_media/510_pictures/`
- `XDG_MUSIC_DIR` → `~/500_media/520_music/`
- `XDG_VIDEOS_DIR` → `~/500_media/530_videos/`
- `XDG_DESKTOP_DIR` → `~/000_inbox/`
- `XDG_PUBLICSHARE_DIR` → `~/000_inbox/`

*(Configured in `domains/system/core/paths.nix`)*

---

## Workflow Rules

### Processing Inbox
1. Items land in `000_inbox/downloads/` (browsers, screenshots)
2. Review inbox regularly
3. Move items to appropriate domain:
   - Work-related → `100_hwc/000-inbox/`
   - Personal → `200_personal/000-inbox/`
   - Tech/dev → `300_tech/000-inbox/`
   - Media → `500_media/`
4. From domain inbox, file into appropriate subfolder:
   - Documents → `110-documents/`
   - Development → `120-development/`
   - Reference → `130-reference/`

### Choosing a Domain
Ask: "What is the primary context for this item?"
- **Work context?** → `100_hwc/` (includes work documents, templates, reference)
- **Personal life?** → `200_personal/` (includes personal docs, reference)
- **Learning/building tech?** → `300_tech/` (includes tech docs, tutorials, configs)
- **Media asset?** → `500_media/` (photos, music, videos only)

### Archive Strategy
- **Option A**: Per-domain archive (`190-archive/`, `290-archive/`)
- **Option B**: Cross-domain `900_archive/` (future expansion)
- **Current**: Archive within each domain as needed

---

## Anti-Patterns

❌ **Don't create duplicate paths**
Bad: Creating separate cross-domain reference folders
Good: Store reference materials within their relevant domain (`100_hwc/130-reference/`, etc.)

❌ **Don't skip inbox processing**
Bad: Download → move directly to deep folder
Good: Download → `000_inbox/` → review → file appropriately

❌ **Don't mix domains**
Bad: Work project in `200_personal/120-projects/`
Good: Clear domain boundaries

❌ **Don't let inbox grow unbounded**
Goal: Process inbox weekly (or more frequently)

---

## Future Expansion

Additional domains can be added following the same pattern:
- `600_health/` - Health & fitness tracking
- `700_finance/` - Financial management
- `800_archive/` - Cross-domain archive
- `900_backup/` - Local backup staging

**Rule**: Assign a hundreds-place digit, follow internal structure pattern

---

## Charter Version

**Version**: v2.0 - Integration with HWC Architecture Charter v6.0
**Last Updated**: 2025-10-28
**Status**: Active implementation
**Related**: See `charter.md` for complete NixOS architecture documentation

---

## Implementation Notes

- NixOS paths synchronized in `domains/system/core/paths.nix`
- XDG directories configured at system level (`/etc/xdg/user-dirs.defaults`)
- Yazi shortcuts configured in `domains/home/apps/yazi/parts/keymap.nix`
- Environment variables exported: `HWC_INBOX_DIR`, `HWC_WORK_DIR`, etc.
