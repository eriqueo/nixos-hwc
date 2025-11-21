# Receipts OCR Pipeline - Operational Runbook

## Table of Contents
1. [Quick Start](#quick-start)
2. [System Architecture](#system-architecture)
3. [Daily Operations](#daily-operations)
4. [Troubleshooting](#troubleshooting)
5. [Monitoring](#monitoring)
6. [Maintenance](#maintenance)

---

## Quick Start

### Setup (First Time)

1. **Initialize Database Schema**
```bash
# As postgres user
sudo -u postgres psql heartwood_business < workspace/projects/receipts-pipeline/database/schema.sql
```

2. **Deploy Python Service Code**
```bash
# Copy source code to service directory
sudo cp -r workspace/projects/receipts-pipeline/src/* /hot/business/receipts-ocr/src/
sudo chown -R eric:users /hot/business/receipts-ocr
```

3. **Start Services**
```bash
sudo systemctl start receipts-ocr
sudo systemctl status receipts-ocr
```

4. **Import n8n Workflow**
```bash
# Import via n8n UI or CLI
n8n import:workflow --input=workspace/projects/receipts-pipeline/n8n-workflows/receipt-intake.json
```

### Test the Pipeline

```bash
# Test with CLI
receipt-ocr process /path/to/test-receipt.jpg

# Test with API
curl -X POST http://localhost:8001/api/ocr/receipt \
  -F "file=@/path/to/receipt.jpg" \
  -F "job_id=1"

# Check processing status
curl http://localhost:8001/api/stats
```

---

## System Architecture

### Components

1. **Receipt Intake (n8n)**
   - Triggers: Email, Webhook, File Watcher
   - Location: `/home/user/nixos-hwc/domains/home/apps/n8n/parts/n8n-workflows/workflows/`

2. **OCR Service (Python)**
   - API: http://localhost:8001
   - Service: `receipts-ocr.service`
   - Code: `/hot/business/receipts-ocr/`

3. **Database (PostgreSQL)**
   - Database: `heartwood_business`
   - Tables: `receipts`, `receipt_items`, `jobs`, `vendors`
   - Service: `postgresql.service`

4. **LLM Normalization (Ollama)**
   - API: http://localhost:11434
   - Model: llama3.2
   - Service: `ollama.service`

### Data Flow

```
Receipt Image
    ↓
n8n Intake (validates, uploads)
    ↓
OCR Service API (extracts text)
    ↓
Tesseract OCR (image → text)
    ↓
Data Extraction (parse fields)
    ↓
Ollama LLM (normalize, categorize)
    ↓
PostgreSQL (store structured data)
    ↓
Notification (ntfy)
```

---

## Daily Operations

### Processing Receipts

#### Method 1: Email
- Forward receipt to `receipts@yourdomain.com`
- n8n will automatically pick it up
- Check n8n execution log

#### Method 2: File Drop
```bash
# Copy receipt to watched folder
cp receipt.jpg /hot/receipts/watched/

# n8n will detect and process automatically
```

#### Method 3: CLI
```bash
# Process single receipt
receipt-ocr process /path/to/receipt.jpg --job-id=5

# View stats
receipt-ocr stats
```

#### Method 4: API
```bash
# Upload via API
curl -X POST http://localhost:8001/api/ocr/receipt \
  -F "file=@receipt.jpg" \
  -F "job_id=5" \
  -F "category=Materials"
```

### Reviewing Low-Confidence Receipts

```bash
# Get receipts needing review
curl http://localhost:8001/api/receipts/pending-review

# Review and update receipt
curl -X PATCH http://localhost:8001/api/receipts/123 \
  -H "Content-Type: application/json" \
  -d '{
    "vendor_normalized": "Home Depot",
    "total_amount": 156.78,
    "receipt_date": "2025-01-15",
    "job_id": 5,
    "reviewed_by": "eric"
  }'
```

### Querying Receipt Data

```sql
-- Connect to database
sudo -u postgres psql heartwood_business

-- View recent receipts
SELECT * FROM v_receipts_enriched
ORDER BY receipt_date DESC
LIMIT 10;

-- Job cost summary
SELECT * FROM v_job_cost_summary
WHERE job_number = 'JOB-2025-001';

-- Receipts by vendor
SELECT
    vendor_normalized,
    COUNT(*) as receipt_count,
    SUM(total_amount) as total_spent
FROM receipts
WHERE receipt_date >= '2025-01-01'
GROUP BY vendor_normalized
ORDER BY total_spent DESC;

-- Receipts pending review
SELECT * FROM v_receipts_pending_review;
```

---

## Troubleshooting

### Service Won't Start

```bash
# Check service status
sudo systemctl status receipts-ocr

# View logs
sudo journalctl -u receipts-ocr -f

# Check dependencies
sudo systemctl status postgresql
sudo systemctl status ollama

# Test database connection
sudo -u postgres psql heartwood_business -c "SELECT COUNT(*) FROM receipts;"

# Test Ollama
curl http://localhost:11434/api/tags
```

### OCR Not Extracting Data

**Symptoms**: OCR completes but no vendor/total/date extracted

**Causes**:
1. Poor image quality
2. Unusual receipt format
3. Low OCR confidence

**Solutions**:
```bash
# Check OCR raw text
psql heartwood_business -c "SELECT id, ocr_raw_text FROM receipts WHERE id = 123;"

# Reprocess with better image preprocessing
# (adjust preprocessing in ocr_processor.py)

# Manual review
curl -X PATCH http://localhost:8001/api/receipts/123 \
  -H "Content-Type: application/json" \
  -d '{"vendor_normalized": "...", "total_amount": 100.00, "reviewed_by": "eric"}'
```

### LLM Normalization Failing

**Symptoms**: Receipts process but vendor_normalized is empty

**Diagnosis**:
```bash
# Check Ollama is running
curl http://localhost:11434/api/tags

# Check Ollama logs
sudo journalctl -u ollama -f

# Test LLM directly
curl http://localhost:11434/api/generate \
  -d '{"model": "llama3.2", "prompt": "Normalize this vendor: WALMART #1234", "stream": false}'
```

**Solutions**:
1. Restart Ollama: `sudo systemctl restart ollama`
2. Pull model if missing: `ollama pull llama3.2`
3. Increase timeout in config
4. Disable LLM temporarily: Set `OLLAMA_ENABLED=false`

### Database Connection Errors

```bash
# Check PostgreSQL is running
sudo systemctl status postgresql

# Test connection
sudo -u postgres psql -l

# Check database exists
sudo -u postgres psql -c "\l" | grep heartwood_business

# Recreate database if needed
sudo -u postgres createdb heartwood_business
sudo -u postgres psql heartwood_business < database/schema.sql
```

### n8n Workflow Not Triggering

```bash
# Check n8n is running
sudo systemctl status n8n

# View n8n logs
sudo journalctl -u n8n -f

# Check workflow is active
curl http://localhost:5678/api/v1/workflows

# Test webhook manually
curl -X POST http://localhost:5678/webhook/receipt-upload \
  -F "file=@test-receipt.jpg"
```

### High Failure Rate

**Symptoms**: Many receipts in `failed` status

**Investigation**:
```sql
-- Check failure reasons
SELECT
    step,
    status,
    error_message,
    COUNT(*) as count
FROM receipt_processing_log
WHERE status = 'failed'
  AND timestamp > NOW() - INTERVAL '24 hours'
GROUP BY step, status, error_message
ORDER BY count DESC;

-- View failed receipts
SELECT id, image_path, status, ocr_raw_text
FROM receipts
WHERE status = 'failed'
ORDER BY upload_timestamp DESC
LIMIT 10;
```

**Common Fixes**:
1. Check image file permissions
2. Verify storage paths exist
3. Check disk space: `df -h /hot`
4. Review preprocessing parameters

---

## Monitoring

### Health Checks

```bash
# API health
curl http://localhost:8001/health

# Service status
sudo systemctl status receipts-ocr postgresql ollama n8n

# Database health
sudo -u postgres psql heartwood_business -c "SELECT COUNT(*) FROM receipts;"

# Processing stats
curl http://localhost:8001/api/stats
```

### Key Metrics

```sql
-- Daily processing stats
SELECT
    DATE(upload_timestamp) as date,
    COUNT(*) as total_receipts,
    COUNT(*) FILTER (WHERE status = 'completed') as completed,
    COUNT(*) FILTER (WHERE status = 'failed') as failed,
    AVG(ocr_confidence) as avg_confidence,
    COUNT(*) FILTER (WHERE needs_review = TRUE) as needs_review
FROM receipts
WHERE upload_timestamp > NOW() - INTERVAL '30 days'
GROUP BY DATE(upload_timestamp)
ORDER BY date DESC;

-- Processing times
SELECT
    step,
    COUNT(*) as executions,
    AVG(duration_ms) as avg_ms,
    MAX(duration_ms) as max_ms
FROM receipt_processing_log
WHERE timestamp > NOW() - INTERVAL '24 hours'
  AND status = 'success'
GROUP BY step
ORDER BY avg_ms DESC;

-- Top vendors by spend
SELECT
    vendor_normalized,
    COUNT(*) as receipt_count,
    SUM(total_amount) as total_spent,
    AVG(total_amount) as avg_amount
FROM receipts
WHERE status = 'completed'
  AND receipt_date >= DATE_TRUNC('month', CURRENT_DATE)
GROUP BY vendor_normalized
ORDER BY total_spent DESC
LIMIT 10;
```

### Alerts

Set up ntfy notifications for:
- Failure rate > 10%
- Queue depth > 50 receipts
- OCR service down
- Database connection lost

```bash
# Test notification
curl -X POST http://localhost:8080/topic/receipts-errors \
  -d "title=Test Alert" \
  -d "message=Testing notification system"
```

---

## Maintenance

### Daily
- Review receipts pending manual review
- Check failure notifications
- Verify service health

### Weekly
- Review processing statistics
- Check disk space usage
- Archive old processed images
- Update vendor normalizations

### Monthly
- Backup database
- Review and clean up failed receipts
- Update expense categories
- Tune OCR confidence threshold

### Database Backup

```bash
# Backup database
sudo -u postgres pg_dump heartwood_business > backup_$(date +%Y%m%d).sql

# Backup to cold storage
sudo -u postgres pg_dump heartwood_business | gzip > /cold/backups/receipts_$(date +%Y%m%d).sql.gz
```

### Archive Old Receipts

```sql
-- Archive receipts older than 2 years
UPDATE receipts
SET status = 'archived'
WHERE receipt_date < NOW() - INTERVAL '2 years'
  AND status = 'completed';
```

### Clean Up Failed Receipts

```bash
# Move failed receipt images to failed folder
psql heartwood_business -t -c "
SELECT image_path FROM receipts WHERE status = 'failed'
" | while read path; do
    mv "$path" /hot/receipts/failed/
done

# Update database
psql heartwood_business -c "
UPDATE receipts
SET image_path = REPLACE(image_path, '/raw/', '/failed/')
WHERE status = 'failed'
"
```

### Update Models

```bash
# Update Ollama model
ollama pull llama3.2

# Restart service
sudo systemctl restart receipts-ocr
```

---

## Common Tasks

### Add New Job

```sql
INSERT INTO jobs (job_number, job_name, client_name, start_date, budget, status)
VALUES ('JOB-2025-005', 'Kitchen Remodel - Smith', 'John Smith', '2025-01-20', 50000.00, 'approved');
```

### Add New Vendor

```sql
INSERT INTO vendors (name_normalized, name_variants, category)
VALUES ('Home Depot', ARRAY['HOME DEPOT', 'THE HOME DEPOT', 'HD'], 'hardware_store');
```

### Assign Receipt to Job

```bash
curl -X PATCH http://localhost:8001/api/receipts/123 \
  -H "Content-Type: application/json" \
  -d '{"job_id": 5, "reviewed_by": "eric"}'
```

---

## Support

### Log Locations
- OCR Service: `sudo journalctl -u receipts-ocr`
- PostgreSQL: `sudo journalctl -u postgresql`
- n8n: `sudo journalctl -u n8n`
- Ollama: `sudo journalctl -u ollama`

### Configuration Files
- Python Config: `/hot/business/receipts-ocr/src/config.py`
- NixOS Module: `domains/server/business/parts/receipts-ocr.nix`
- Database Schema: `workspace/projects/receipts-pipeline/database/schema.sql`
- n8n Workflow: `workspace/projects/receipts-pipeline/n8n-workflows/receipt-intake.json`

### Emergency Contacts
- System Admin: Your contact info
- Database Admin: Your contact info
- NixOS Support: https://nixos.org/community

---

## FAQ

**Q: Can I reprocess a receipt?**
A: Yes, use the CLI: `receipt-ocr process /path/to/image.jpg`

**Q: How do I batch process receipts?**
A: Use a loop:
```bash
for img in /path/to/receipts/*.jpg; do
    receipt-ocr process "$img" --job-id=5
done
```

**Q: What image formats are supported?**
A: JPG, PNG, PDF (first page only)

**Q: Can I use this for invoices too?**
A: Yes, the system works for any receipt-like document

**Q: How accurate is the OCR?**
A: Typically 70-90% depending on image quality. LLM normalization improves accuracy.

**Q: What happens if OCR fails?**
A: Receipt is marked as failed, moved to failed folder, and notification sent

**Q: Can I edit receipts after processing?**
A: Yes, via API or directly in PostgreSQL database
