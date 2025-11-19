# Receipts OCR Pipeline

Robust, AI-assisted receipt processing pipeline for a remodeling business, orchestrated by n8n and powered by Python OCR + LLM.

## Features

- 📸 **Multi-Source Intake**: Email, file upload, watched folder, API
- 🔍 **OCR Processing**: Tesseract-based text extraction with image preprocessing
- 🤖 **LLM Normalization**: Local Ollama for vendor normalization and categorization
- 💾 **PostgreSQL Storage**: Structured data with job tracking and cost analysis
- 🔄 **n8n Orchestration**: Workflow automation with robust error handling
- 📊 **Business Intelligence**: Job costing, vendor analysis, expense categorization
- 🔔 **Notifications**: Real-time alerts for failures and review needs

## Architecture

```
┌─────────────────┐
│  Receipt Image  │
└────────┬────────┘
         │
    ┌────▼────┐
    │  n8n    │ ◄── Email/Webhook/File Watcher
    └────┬────┘
         │
    ┌────▼────────────┐
    │  OCR Service    │
    │  (FastAPI)      │
    ├─────────────────┤
    │  • Tesseract    │
    │  • Preprocessing│
    │  • Extraction   │
    └────┬────────────┘
         │
    ┌────▼────────────┐
    │  LLM Normalize  │
    │  (Ollama)       │
    ├─────────────────┤
    │  • Vendor names │
    │  • Categories   │
    │  • Validation   │
    └────┬────────────┘
         │
    ┌────▼────────────┐
    │  PostgreSQL     │
    ├─────────────────┤
    │  • Receipts     │
    │  • Jobs         │
    │  • Vendors      │
    │  • Categories   │
    └─────────────────┘
```

## Project Structure

```
receipts-pipeline/
├── ARCHITECTURE.md           # System architecture documentation
├── RUNBOOK.md               # Operational runbook for daily use
├── README.md                # This file
├── requirements.txt         # Python dependencies
│
├── src/                     # Python source code
│   ├── __init__.py
│   ├── receipt_ocr_service.py   # FastAPI service + CLI
│   ├── ocr_processor.py          # OCR and extraction logic
│   ├── llm_normalizer.py         # LLM normalization
│   ├── database.py               # PostgreSQL operations
│   └── config.py                 # Configuration management
│
├── database/                # Database schemas
│   └── schema.sql           # PostgreSQL schema definition
│
├── n8n-workflows/          # n8n workflow JSONs
│   └── receipt-intake.json  # Main intake workflow
│
└── monitoring/             # Monitoring scripts
    └── receipt-monitor.sh   # Health check script
```

## Quick Start

### 1. Enable NixOS Module

Edit your NixOS configuration:

```nix
# In your profile or configuration.nix
imports = [
  ../domains/server/business/parts/receipts-ocr.nix
];

hwc.services.business.receipts-ocr = {
  enable = true;
  ollamaEnabled = true;
  autoStart = true;
};

hwc.services.databases.postgresql = {
  enable = true;
  databases = [ "heartwood_business" ];
};
```

Rebuild:
```bash
sudo nixos-rebuild switch
```

### 2. Initialize Database

```bash
sudo -u postgres psql heartwood_business < database/schema.sql
```

### 3. Deploy Python Code

```bash
sudo mkdir -p /hot/business/receipts-ocr
sudo cp -r src/* /hot/business/receipts-ocr/src/
sudo chown -R eric:users /hot/business/receipts-ocr
```

### 4. Start Services

```bash
sudo systemctl start receipts-ocr
sudo systemctl status receipts-ocr
```

### 5. Import n8n Workflow

Import `n8n-workflows/receipt-intake.json` via n8n UI.

### 6. Test

```bash
# CLI test
receipt-ocr process test-receipt.jpg --job-id=1

# API test
curl -X POST http://localhost:8001/api/ocr/receipt \
  -F "file=@test-receipt.jpg"

# Check stats
receipt-ocr stats
```

## Usage

### Processing Receipts

**Via Email:**
Forward receipt to configured email address, n8n will process automatically.

**Via File Drop:**
```bash
cp receipt.jpg /hot/receipts/watched/
```

**Via CLI:**
```bash
receipt-ocr process /path/to/receipt.jpg --job-id=5
```

**Via API:**
```bash
curl -X POST http://localhost:8001/api/ocr/receipt \
  -F "file=@receipt.jpg" \
  -F "job_id=5" \
  -F "category=Materials"
```

### Reviewing Low-Confidence Receipts

```bash
# List receipts needing review
curl http://localhost:8001/api/receipts/pending-review

# Update receipt after manual review
curl -X PATCH http://localhost:8001/api/receipts/123 \
  -H "Content-Type: application/json" \
  -d '{
    "vendor_normalized": "Home Depot",
    "total_amount": 156.78,
    "reviewed_by": "eric"
  }'
```

### Querying Data

```sql
-- Connect to database
sudo -u postgres psql heartwood_business

-- Recent receipts
SELECT * FROM v_receipts_enriched
ORDER BY receipt_date DESC LIMIT 10;

-- Job cost summary
SELECT * FROM v_job_cost_summary;

-- Vendor spending
SELECT vendor_normalized, SUM(total_amount) as total
FROM receipts
WHERE receipt_date >= '2025-01-01'
GROUP BY vendor_normalized
ORDER BY total DESC;
```

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `DATABASE_URL` | `postgresql://business_user@localhost/heartwood_business` | PostgreSQL connection string |
| `OLLAMA_ENABLED` | `true` | Enable LLM normalization |
| `OLLAMA_URL` | `http://localhost:11434` | Ollama API URL |
| `OLLAMA_MODEL` | `llama3.2` | Ollama model to use |
| `STORAGE_ROOT` | `/hot/receipts` | Receipt storage path |
| `OCR_CONFIDENCE_THRESHOLD` | `0.7` | Auto-review threshold |
| `API_PORT` | `8001` | API server port |

### NixOS Options

```nix
hwc.services.business.receipts-ocr = {
  enable = true;              # Enable service
  host = "127.0.0.1";         # API host
  port = 8001;                # API port
  user = "eric";              # Service user
  databaseUrl = "...";        # PostgreSQL URL
  ollamaEnabled = true;       # Enable LLM
  ollamaUrl = "...";          # Ollama URL
  ollamaModel = "llama3.2";   # LLM model
  storageRoot = "/hot/receipts";
  confidenceThreshold = 0.7;
  autoStart = true;
};
```

## Monitoring

### Health Checks

```bash
# Service health
curl http://localhost:8001/health

# Processing stats
curl http://localhost:8001/api/stats

# System status
sudo systemctl status receipts-ocr postgresql ollama n8n
```

### Metrics

- Total receipts processed
- Success/failure rates
- OCR confidence averages
- Processing times per stage
- Receipts pending review

See [RUNBOOK.md](RUNBOOK.md) for detailed monitoring queries.

## Troubleshooting

### Common Issues

**Service won't start:**
- Check logs: `sudo journalctl -u receipts-ocr -f`
- Verify PostgreSQL is running
- Check database exists and schema is applied

**OCR not extracting data:**
- Check image quality
- Review OCR raw text in database
- Adjust preprocessing parameters

**LLM normalization failing:**
- Verify Ollama is running: `curl http://localhost:11434/api/tags`
- Check model is downloaded: `ollama list`
- Increase timeout or disable LLM temporarily

**n8n workflow not triggering:**
- Check workflow is active
- Verify webhook URL
- Check n8n logs: `sudo journalctl -u n8n -f`

See [RUNBOOK.md](RUNBOOK.md) for comprehensive troubleshooting.

## Development

### Setup Dev Environment

```bash
cd workspace/projects/receipts-pipeline

# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Run service locally
python -m src.receipt_ocr_service serve --port 8001
```

### Running Tests

```bash
# Test OCR
python -m src.receipt_ocr_service process test-images/receipt1.jpg

# Test API
curl -X POST http://localhost:8001/api/ocr/receipt \
  -F "file=@test-images/receipt1.jpg"
```

## Database Schema

See [database/schema.sql](database/schema.sql) for full schema.

### Main Tables

- **receipts**: Core receipt data with OCR results
- **receipt_items**: Line items from receipts
- **jobs**: Remodeling jobs/projects
- **vendors**: Normalized vendor information
- **expense_categories**: Expense categorization
- **receipt_processing_log**: Audit log for processing steps
- **receipt_review_queue**: Manual review queue

### Views

- **v_receipts_enriched**: Receipts with joined job/vendor data
- **v_job_cost_summary**: Job costs and budget tracking
- **v_receipts_pending_review**: Items needing manual review
- **v_processing_stats**: Processing statistics

## API Reference

### Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/` | Health check |
| `GET` | `/health` | Detailed health status |
| `POST` | `/api/ocr/receipt` | Process receipt image |
| `GET` | `/api/receipts/{id}` | Get receipt details |
| `PATCH` | `/api/receipts/{id}` | Update receipt |
| `GET` | `/api/receipts/pending-review` | List receipts needing review |
| `GET` | `/api/stats` | Processing statistics |
| `GET` | `/api/jobs/{id}/receipts` | Get receipts for job |

See source code for request/response schemas.

## Contributing

This is a personal homelab project, but suggestions and improvements are welcome!

## License

MIT License - See LICENSE file

## Support

- **Documentation**: See [ARCHITECTURE.md](ARCHITECTURE.md) and [RUNBOOK.md](RUNBOOK.md)
- **Logs**: `sudo journalctl -u receipts-ocr`
- **Issues**: Check troubleshooting section in RUNBOOK

## Roadmap

- [ ] Streamlit web UI for review queue
- [ ] Advanced receipt parsing (multi-page, complex formats)
- [ ] Integration with accounting software (QuickBooks, Xero)
- [ ] Mobile app for photo upload
- [ ] Advanced analytics and reporting
- [ ] Multi-currency support
- [ ] Receipt duplicate detection
- [ ] Automatic job assignment via ML

---

**Built with:**
- Python 3 + FastAPI
- Tesseract OCR
- Ollama (LLM)
- PostgreSQL
- n8n
- NixOS
