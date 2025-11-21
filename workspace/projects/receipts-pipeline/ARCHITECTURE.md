# Receipts OCR Pipeline Architecture

## Overview
End-to-end pipeline for processing receipt images into structured PostgreSQL data with n8n orchestration.

## Pipeline Flow

```
[Trigger] → [n8n Intake] → [OCR Service] → [LLM Normalize] → [PostgreSQL] → [Notify]
```

### 1. Trigger Options
- **Email**: Forward receipts to specific inbox (e.g., receipts@yourdomain.com)
- **Phone Upload**: Mobile app → webhook → n8n
- **Watched Folder**: Local directory monitoring (inotify)
- **Manual Upload**: Web form via n8n webhook

### 2. n8n Intake Workflow
- **Workflow**: `receipt-intake.json`
- **Trigger**: Email/Webhook/File watcher
- **Steps**:
  1. Validate file type (jpg, png, pdf)
  2. Store raw image to hot storage
  3. Call OCR service API
  4. Handle retries (3 attempts with exponential backoff)
  5. On success → next workflow
  6. On failure → alert + quarantine

### 3. OCR Service (Python)
- **Entrypoint**: `receipt_ocr_service.py`
- **API Endpoint**: `POST /api/ocr/receipt`
- **CLI**: `receipt-ocr process <image_path>`
- **Processing**:
  1. Preprocess image (deskew, denoise, enhance contrast)
  2. Run Tesseract OCR
  3. Extract structured fields (date, vendor, total, items, tax)
  4. Return JSON with confidence scores
  5. Flag low-confidence fields for review

### 4. LLM Normalization (Optional)
- **Model**: Local Ollama (llama3.2 or similar)
- **Purpose**:
  - Normalize vendor names ("Walmart #1234" → "Walmart")
  - Categorize expenses (groceries, materials, office, etc.)
  - Extract line items with better accuracy
  - Clean up OCR errors
- **API Endpoint**: `POST /api/llm/normalize`
- **Fallback**: Skip if Ollama unavailable, use raw OCR

### 5. PostgreSQL Schema
```sql
-- Receipts table
CREATE TABLE receipts (
    id SERIAL PRIMARY KEY,
    image_path TEXT NOT NULL,
    upload_timestamp TIMESTAMPTZ DEFAULT NOW(),
    process_timestamp TIMESTAMPTZ,
    status TEXT CHECK (status IN ('pending', 'processing', 'completed', 'failed', 'review_needed')),

    -- OCR extracted data
    receipt_date DATE,
    vendor_raw TEXT,
    vendor_normalized TEXT,
    total_amount NUMERIC(10,2),
    tax_amount NUMERIC(10,2),
    subtotal NUMERIC(10,2),

    -- Business context
    job_id INTEGER REFERENCES jobs(id),
    category TEXT,
    notes TEXT,

    -- Metadata
    ocr_confidence NUMERIC(3,2),
    needs_review BOOLEAN DEFAULT FALSE,
    reviewed_by TEXT,
    reviewed_at TIMESTAMPTZ,

    -- Raw data
    ocr_raw_text TEXT,
    ocr_raw_json JSONB,
    llm_metadata JSONB
);

-- Line items table
CREATE TABLE receipt_items (
    id SERIAL PRIMARY KEY,
    receipt_id INTEGER REFERENCES receipts(id) ON DELETE CASCADE,
    description TEXT,
    quantity NUMERIC(10,2),
    unit_price NUMERIC(10,2),
    total_price NUMERIC(10,2),
    category TEXT,
    tax_rate NUMERIC(5,4)
);

-- Jobs table (for remodeling business)
CREATE TABLE jobs (
    id SERIAL PRIMARY KEY,
    job_name TEXT NOT NULL,
    client_name TEXT,
    start_date DATE,
    end_date DATE,
    status TEXT,
    budget NUMERIC(12,2),
    actual_cost NUMERIC(12,2)
);

-- Vendors table
CREATE TABLE vendors (
    id SERIAL PRIMARY KEY,
    name_normalized TEXT UNIQUE NOT NULL,
    name_variants TEXT[],
    category TEXT,
    account_number TEXT,
    notes TEXT
);

-- Expense categories
CREATE TABLE expense_categories (
    id SERIAL PRIMARY KEY,
    name TEXT UNIQUE NOT NULL,
    parent_category TEXT,
    tax_deductible BOOLEAN DEFAULT TRUE
);

-- Processing audit log
CREATE TABLE receipt_processing_log (
    id SERIAL PRIMARY KEY,
    receipt_id INTEGER REFERENCES receipts(id),
    timestamp TIMESTAMPTZ DEFAULT NOW(),
    step TEXT,
    status TEXT,
    error_message TEXT,
    metadata JSONB
);
```

### 6. Notification & Review
- **Success**: Log to metrics (InfluxDB)
- **Failure**:
  - Send notification (ntfy, email, Slack)
  - Add to review queue
  - Flag in database
- **Low Confidence**:
  - Mark `needs_review = true`
  - Create review task in n8n
  - Optional: Create Streamlit review UI

## Error Handling Strategy

### Retry Logic
- **OCR Failures**: Retry 3x with different preprocessing
- **LLM Timeouts**: Skip LLM, use raw OCR
- **DB Failures**: Queue to Redis, retry every 5 min
- **Ambiguous Data**: Flag for manual review

### Monitoring
- **Metrics**:
  - Receipts processed per day
  - Average OCR confidence
  - Failure rate by stage
  - Items awaiting review
- **Alerts**:
  - Failure rate > 10%
  - Queue depth > 50 items
  - Service down > 5 min

## Integration Points

### n8n Workflows
1. **receipt-intake.json**: Primary intake orchestration
2. **receipt-review-queue.json**: Manage items needing review
3. **receipt-failure-alert.json**: Handle and escalate failures

### Business API Endpoints
- `POST /api/receipts/upload` - Upload new receipt
- `POST /api/receipts/ocr` - Process with OCR
- `POST /api/receipts/normalize` - LLM normalization
- `GET /api/receipts/{id}` - Get receipt details
- `PATCH /api/receipts/{id}` - Update/review receipt
- `GET /api/receipts/pending-review` - List items needing review
- `GET /api/jobs/{id}/receipts` - Get all receipts for a job

### File Storage
- **Raw Images**: `${paths.hot}/receipts/raw/YYYY/MM/`
- **Processed**: `${paths.hot}/receipts/processed/YYYY/MM/`
- **Failed**: `${paths.hot}/receipts/failed/YYYY/MM/`

## Development Workflow

1. **Phase 1**: PostgreSQL schema + basic OCR service
2. **Phase 2**: N8n intake workflow
3. **Phase 3**: LLM normalization
4. **Phase 4**: Review UI (Streamlit)
5. **Phase 5**: Monitoring + alerts

## Security Considerations

- DB credentials via agenix secrets
- API authentication (JWT tokens)
- Input validation (file size, type)
- SQL injection protection (SQLAlchemy ORM)
- Rate limiting on API endpoints
