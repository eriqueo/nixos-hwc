# Filesystem Organization Charter

**Owner**: Eric
**Scope**: `~/` — All user home directory organization
**Goal**: Deterministic, scalable, and maintainable filesystem structure with clear domain separation

---

## Core Principles

1. **3-Digit Prefix**: All top-level folders use `XXX_name` format
2. **Domain Separation**: Hundreds place indicates domain (100=work, 200=personal, etc.)
3. **Nested Structure**: Each domain has internal organization (110, 120, etc.)
4. **Inbox-First**: Process items through `000_inbox/` before filing
5. **Cross-Domain Assets**: Shared resources (media, reference) at `4xx`/`5xx` level

---

## Top-Level Structure

```
~/
├── 000_inbox/              # Global processing queue
│   └── downloads/          # Browser downloads, temp files
├── 100_hwc/                # Work domain
├── 200_personal/           # Personal domain
├── 300_tech/               # Technology/development domain
├── 400_ref/                # Cross-domain reference materials
├── 500_media/              # Cross-domain media library
└── 900_vaults/             # Cloud sync (Obsidian, etc.)
```

---

## Domain-Level Structure

Each domain (`100_hwc/`, `200_personal/`, `300_tech/`) follows this pattern:

```
1XX_domain/
├── 000-inbox/              # Domain-specific processing queue
├── 110-documents/          # Domain documents
├── 120-projects/           # Active projects
├── 130-reference/          # Domain reference materials
├── 140-media/              # Domain-specific media
└── 190-archive/            # Completed/archived items (optional)
```

**Numbering Within Domains:**
- `X00-X09`: Inbox/processing
- `X10-X19`: Documents/files
- `X20-X29`: Projects/active work
- `X30-X39`: Reference materials
- `X40-X49`: Media/assets
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

### `400_ref/` - Cross-Domain Reference
**Purpose**: Shared reference materials used across domains
**Examples**: Ebooks, manuals, templates, research papers
**Boundary**: Reference-only, not project-specific

### `500_media/` - Cross-Domain Media
**Purpose**: Personal media library (not domain-specific)
**Examples**: Photos, music, videos
**Structure**:
```
500_media/
├── pictures/
│   ├── 01-screenshots/
│   └── 99-inbox/
├── music/
└── videos/
```

### `900_vaults/` - Cloud Sync
**Purpose**: Synced knowledge bases and cloud storage
**Examples**: Obsidian vaults, Proton Drive, sync folders
**Boundary**: Items managed by external sync services

---

## XDG Integration

System automatically maps XDG directories:
- `XDG_DOWNLOAD_DIR` → `~/000_inbox/downloads/`
- `XDG_DOCUMENTS_DIR` → `~/400_ref/documents/`
- `XDG_PICTURES_DIR` → `~/500_media/pictures/`
- `XDG_MUSIC_DIR` → `~/500_media/music/`
- `XDG_VIDEOS_DIR` → `~/500_media/videos/`
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
   - Reference → `400_ref/`
   - Media → `500_media/`
4. From domain inbox, file into appropriate subfolder (`110`, `120`, etc.)

### Choosing a Domain
Ask: "What is the primary context for this item?"
- **Work context?** → `100_hwc/`
- **Personal life?** → `200_personal/`
- **Learning/building tech?** → `300_tech/`
- **Pure reference?** → `400_ref/`
- **Media asset?** → `500_media/`

### Archive Strategy
- **Option A**: Per-domain archive (`190-archive/`, `290-archive/`)
- **Option B**: Cross-domain `900_archive/` (future expansion)
- **Current**: Archive within each domain as needed

---

## Anti-Patterns

❌ **Don't create duplicate paths**
Bad: `100_hwc/documents/` AND `400_ref/hwc-docs/`
Good: `100_hwc/110-documents/` only

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

**Version**: v1.0
**Last Updated**: 2025-10-06
**Status**: Active implementation

---

## Implementation Notes

- NixOS paths synchronized in `domains/system/core/paths.nix`
- XDG directories configured at system level (`/etc/xdg/user-dirs.defaults`)
- Yazi shortcuts configured in `domains/home/apps/yazi/parts/keymap.nix`
- Environment variables exported: `HWC_INBOX_DIR`, `HWC_WORK_DIR`, etc.
