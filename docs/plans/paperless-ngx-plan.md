# Paperless-NGX Deployment Plan

**Version**: 1.0
**Created**: 2026-02-19
**Charter Version**: v10.3
**Status**: Planning

---

## Overview

Deploy **Paperless-NGX** as a Charter-compliant containerized document management system for OCR, archival, and searchable document storage.

### Use Cases

1. **Receipt Archive**: Scan/import receipts with automatic OCR and tagging
2. **Invoice Management**: Vendor invoices with correspondent tracking
3. **Tax Documents**: Annual archival with full-text search
4. **Business Documents**: Contracts, statements, correspondence
5. **General Archival**: Any document requiring long-term searchable storage

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      Caddy Reverse Proxy                         │
│              https://hwc.ocelot-wahoo.ts.net/docs               │
└───────────────────────────────┬─────────────────────────────────┘
                                │
                    ┌───────────▼───────────────┐
                    │       Paperless-NGX       │
                    │  - Web UI (Django)        │
                    │  - REST API               │
                    │  - OCR Engine (Tesseract) │
                    │  - Task Queue (Celery)    │
                    │  - Document Consumer      │
                    └───────────┬───────────────┘
                                │
              ┌─────────────────┼─────────────────┐
              │                 │                 │
    ┌─────────▼───────┐  ┌──────▼──────┐  ┌───────▼───────┐
    │   PostgreSQL    │  │    Redis    │  │    Storage    │
    │  (paperless db) │  │ (task queue)│  │  (documents)  │
    └─────────────────┘  └─────────────┘  └───────────────┘

    Storage Layout:
    ┌─────────────────────────────────────────────────────────────┐
    │  /mnt/hot/documents/                (SSD - active)          │
    │    ├── consume/        ← Drop zone for auto-import          │
    │    ├── export/         ← Document exports                   │
    │    └── staging/        ← Pre-processing area                │
    │                                                             │
    │  /mnt/media/documents/paperless/    (HDD - archive)         │
    │    ├── originals/      ← Original files (immutable)         │
    │    ├── archive/        ← OCR'd PDF/A versions               │
    │    └── thumbnails/     ← Preview images                     │
    │                                                             │
    │  /opt/paperless/                    (Container config)      │
    │    └── data/           ← SQLite index, search index         │
    └─────────────────────────────────────────────────────────────┘
```

---

## Module Structure (Charter-Compliant)

```
domains/server/containers/paperless/
├── options.nix           # hwc.server.containers.paperless.*
├── index.nix            # Aggregator with OPTIONS/IMPLEMENTATION/VALIDATION
├── sys.nix              # System packages (tesseract-ocr languages)
└── parts/
    ├── config.nix       # Container definition
    └── directories.nix  # tmpfiles rules for storage
```

**Namespace**: `hwc.server.containers.paperless.*`

---

## Implementation

### Phase 1: Module Creation

1. Create directory structure
2. Write `options.nix` with all configuration options
3. Write `index.nix` aggregator
4. Write `parts/config.nix` with container definition
5. Add `sys.nix` for system-level OCR packages (optional)

### Phase 2: Secrets & Database

1. Create encrypted secrets:
   - `paperless-secret-key.age` - Django secret key
   - `paperless-admin-password.age` - Initial admin password
2. Add database to PostgreSQL `ensureDatabases`
3. Configure database permissions

### Phase 3: Storage & Routes

1. Create tmpfiles rules for directory structure
2. Add Caddy route at `/docs`
3. Configure firewall for Tailscale access

### Phase 4: Integration & Testing

1. Import module in `profiles/business.nix`
2. Enable in `machines/server/config.nix`
3. Test with `nix flake check`
4. Deploy with `nixos-rebuild test`

---

## Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | false | Enable Paperless-NGX |
| `image` | string | ghcr.io/paperless-ngx/paperless-ngx:2.14 | Container image |
| `port` | port | 8000 | Internal web port |
| `database.name` | string | paperless | PostgreSQL database |
| `database.host` | string | 10.89.0.1 | PostgreSQL host (container gateway) |
| `storage.consumeDir` | path | /mnt/hot/documents/consume | Watch folder |
| `storage.mediaDir` | path | /mnt/media/documents/paperless | Archive location |
| `storage.exportDir` | path | /mnt/hot/documents/export | Export folder |
| `ocr.languages` | list | ["eng"] | Tesseract language codes |
| `ocr.outputType` | enum | pdfa | Output format (pdf/pdfa/pdfa-2) |
| `consumer.polling` | int | 60 | Seconds between folder scans |
| `consumer.deleteOriginals` | bool | false | Delete after import |
| `resources.memory` | string | 4g | Container memory limit |
| `resources.cpus` | string | 2.0 | Container CPU limit |

---

## Secrets Required

```bash
# Generate Django secret key
openssl rand -base64 32 | \
  age -r $(sudo age-keygen -y /etc/age/keys.txt) \
  > domains/secrets/parts/server/paperless-secret-key.age

# Set admin password
echo "your-secure-password" | \
  age -r $(sudo age-keygen -y /etc/age/keys.txt) \
  > domains/secrets/parts/server/paperless-admin-password.age
```

---

## Route Configuration

```nix
# Added to domains/server/native/routes.nix
{
  name = "paperless";
  mode = "subpath";
  path = "/docs";
  upstream = "http://127.0.0.1:8000";
  needsUrlBase = true;  # Paperless supports PAPERLESS_FORCE_SCRIPT_NAME
  headers = { "X-Forwarded-Prefix" = "/docs"; };
}
```

**Access URL**: `https://hwc.ocelot-wahoo.ts.net/docs`

---

## Validation Assertions

```nix
assertions = [
  {
    assertion = !cfg.enable || config.hwc.server.databases.postgresql.enable;
    message = "paperless requires PostgreSQL (hwc.server.databases.postgresql.enable)";
  }
  {
    assertion = !cfg.enable || config.hwc.server.databases.redis.enable;
    message = "paperless requires Redis for task queue";
  }
];
```

---

## Implementation Checklist

- [ ] Create `domains/server/containers/paperless/options.nix`
- [ ] Create `domains/server/containers/paperless/index.nix`
- [ ] Create `domains/server/containers/paperless/parts/config.nix`
- [ ] Create `domains/server/containers/paperless/parts/directories.nix`
- [ ] Encrypt `paperless-secret-key.age`
- [ ] Encrypt `paperless-admin-password.age`
- [ ] Add secrets to `domains/secrets/declarations/server.nix`
- [ ] Add `paperless` to PostgreSQL databases list
- [ ] Add route to `domains/server/native/routes.nix`
- [ ] Import in `profiles/business.nix`
- [ ] Enable in `machines/server/config.nix`
- [ ] Run `nix flake check`
- [ ] Deploy with `sudo nixos-rebuild test --flake .#hwc-server`
- [ ] Verify web UI accessible at `/docs`
- [ ] Test document consumption workflow

---

## Post-Deployment

1. **Configure Tags**: Create tags for document types (receipt, invoice, statement, etc.)
2. **Set Up Correspondents**: Add vendors/contacts
3. **Configure Mail Import** (optional): Auto-import email attachments
4. **Mobile App**: Connect Paperless mobile scanner app
5. **API Integration**: Document REST API for future automation

---

## References

- [Paperless-NGX Documentation](https://docs.paperless-ngx.com/)
- [Paperless-NGX GitHub](https://github.com/paperless-ngx/paperless-ngx)
- [Immich Container Pattern](../../domains/server/containers/immich/) - Reference implementation
