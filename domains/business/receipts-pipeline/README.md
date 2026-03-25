# Receipts OCR Pipeline

Receipt image processing for Heartwood Craft remodeling business.
Part of the business domain — uses the shared `heartwood_business` PostgreSQL database.

## How It Works

```
Receipt Image → n8n Intake → OCR Service (Tesseract) → LLM Normalize (Ollama) → PostgreSQL
```

- **Intake**: Email, webhook, file watcher, or CLI
- **OCR**: Tesseract with image preprocessing (deskew, denoise, threshold)
- **LLM**: Ollama normalizes vendor names and categorizes expenses
- **Storage**: Receipts link to `projects` table (which carries JT job IDs)

## Database

All tables live in `heartwood_business` — see `workspace/business/schema.sql` sections 8-12:
- `vendors` — normalized vendor directory
- `expense_categories` — linked to JT cost codes
- `receipts` — OCR results, linked to `projects` via `project_id`
- `receipt_items` — line items, optionally linked to `catalog_items`
- `receipt_processing_log` — audit trail
- `receipt_review_queue` — manual review queue

## API (port 8001)

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/ocr/receipt` | Process receipt image (file + optional project_id) |
| GET | `/api/receipts/{id}` | Get receipt details |
| PATCH | `/api/receipts/{id}` | Update receipt (manual review) |
| GET | `/api/receipts/pending-review` | Receipts needing review |
| GET | `/api/projects/{id}/receipts` | All receipts for a project |
| GET | `/api/stats` | Processing statistics |

## CLI

```bash
receipt-ocr process /path/to/receipt.jpg --project-id=<uuid>
receipt-ocr stats
receipt-ocr serve --port 8001
```

## NixOS

```nix
hwc.business.receiptsOcr = {
  enable = true;
  port = 8001;
  ollama.enable = true;
  storageRoot = "/mnt/hot/receipts";
};
```

## n8n Integration

Import `n8n-workflows/receipt-intake.json` — it calls the OCR API and sends
ntfy notifications for success, review needed, and failures.
