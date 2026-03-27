#!/usr/bin/env python3
"""
Receipt OCR Service
===================

FastAPI service for processing receipt images with OCR and LLM normalization.
Part of the Heartwood business domain — stores data in heartwood_business DB.

Endpoints:
    POST /api/ocr/receipt - Process a receipt image
    GET /api/receipts/{id} - Get receipt details
    PATCH /api/receipts/{id} - Update receipt
    GET /api/receipts/pending-review - Get receipts needing review
    GET /api/projects/{id}/receipts - Get receipts for a project

CLI:
    receipt-ocr process <image_path> [--project-id=<uuid>]
    receipt-ocr stats
"""

import asyncio
import hashlib
import logging
import sys
from datetime import datetime
from pathlib import Path
from typing import Optional, List, Dict, Any
from uuid import UUID

from fastapi import FastAPI, File, UploadFile, HTTPException, BackgroundTasks, Form
from pydantic import BaseModel
import uvicorn

from src.ocr_processor import OCRProcessor
from src.llm_normalizer import LLMNormalizer
from src.database import Database
from src.config import Config

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="Receipt OCR Service",
    description="Process receipt images into structured data (heartwood_business)",
    version="2.0.0"
)

# --- Pydantic Models ---

class ReviewUpdate(BaseModel):
    vendor_normalized: Optional[str] = None
    total_amount: Optional[float] = None
    receipt_date: Optional[str] = None
    project_id: Optional[str] = None
    category: Optional[str] = None
    notes: Optional[str] = None
    reviewed_by: str

# --- Service Components ---

config = Config()
db = Database(config.database_url)
ocr = OCRProcessor(config)
llm = LLMNormalizer(config) if config.ollama_enabled else None

# --- API Endpoints ---

@app.get("/")
async def root():
    return {
        "service": "Receipt OCR Service",
        "status": "operational",
        "version": "2.0.0",
        "database": "connected" if db.is_connected() else "disconnected",
        "ollama": "enabled" if llm else "disabled"
    }

@app.get("/health")
async def health_check():
    return {
        "status": "healthy",
        "timestamp": datetime.utcnow().isoformat(),
        "database": db.health_check(),
        "ocr": {"status": "operational"},
        "llm": llm.health_check() if llm else {"status": "disabled"}
    }

@app.post("/api/ocr/receipt")
async def process_receipt(
    background_tasks: BackgroundTasks,
    file: UploadFile = File(...),
    project_id: Optional[str] = Form(None),
    category: Optional[str] = Form(None),
    notes: Optional[str] = Form(None),
    skip_llm: bool = Form(False)
):
    """Process a receipt image with OCR."""
    try:
        if not file.content_type.startswith(('image/', 'application/pdf')):
            raise HTTPException(400, "Invalid file type. Must be image or PDF")

        # Save uploaded file
        upload_path = config.get_upload_path()
        file_path = upload_path / f"{datetime.now().strftime('%Y%m%d_%H%M%S')}_{file.filename}"

        content = await file.read()
        with open(file_path, "wb") as f:
            f.write(content)

        # Compute file hash for duplicate detection
        file_hash = hashlib.sha256(content).hexdigest()

        logger.info(f"Saved uploaded file: {file_path}")

        receipt_id = db.create_receipt(
            image_path=str(file_path),
            filename=file.filename,
            file_size=len(content),
            file_hash=file_hash,
            project_id=project_id,
            notes=notes,
            status='pending'
        )

        db.log_processing_step(receipt_id, 'upload', 'success')

        background_tasks.add_task(
            process_receipt_background,
            receipt_id,
            file_path,
            skip_llm
        )

        return {
            "receipt_id": receipt_id,
            "status": "processing",
            "message": "Receipt uploaded and queued for processing"
        }

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error processing receipt: {e}")
        raise HTTPException(500, f"Processing failed: {str(e)}")


async def process_receipt_background(receipt_id: int, file_path: Path, skip_llm: bool):
    """Background task to process receipt through OCR and LLM pipeline."""
    try:
        db.update_receipt(receipt_id, {'status': 'processing'})
        db.log_processing_step(receipt_id, 'preprocessing', 'started')

        # Run OCR
        logger.info(f"Running OCR on receipt {receipt_id}")
        start_time = datetime.now()
        ocr_result = ocr.process_image(file_path)
        duration_ms = int((datetime.now() - start_time).total_seconds() * 1000)
        db.log_processing_step(receipt_id, 'ocr', 'success', duration_ms=duration_ms)

        # Extract structured data
        extracted = ocr.extract_receipt_data(ocr_result)

        # LLM normalization
        if llm and not skip_llm:
            try:
                logger.info(f"Running LLM normalization on receipt {receipt_id}")
                start_time = datetime.now()
                normalized = llm.normalize_receipt(extracted, ocr_result['text'])
                duration_ms = int((datetime.now() - start_time).total_seconds() * 1000)
                db.log_processing_step(receipt_id, 'llm_normalization', 'success', duration_ms=duration_ms)
                extracted.update(normalized)
            except Exception as e:
                logger.warning(f"LLM normalization failed, using raw OCR: {e}")
                db.log_processing_step(
                    receipt_id, 'llm_normalization', 'failed',
                    error_message=str(e)
                )

        # Link or create vendor
        vendor_id = None
        vendor_name = extracted.get('vendor_normalized') or extracted.get('vendor_raw')
        if vendor_name:
            vendor_id = db.get_or_create_vendor(vendor_name)

        # Build update
        update_data = {
            'status': 'completed',
            'ocr_raw_text': ocr_result['text'],
            'ocr_raw_json': ocr_result,
            'ocr_confidence': extracted.get('confidence', 0.0),
            'receipt_date': extracted.get('date'),
            'vendor_raw': extracted.get('vendor_raw'),
            'vendor_normalized': extracted.get('vendor_normalized'),
            'vendor_id': vendor_id,
            'total_amount': extracted.get('total'),
            'tax_amount': extracted.get('tax'),
            'subtotal': extracted.get('subtotal'),
            'needs_review': extracted.get('confidence', 0) < config.confidence_threshold,
        }
        update_data = {k: v for k, v in update_data.items() if v is not None}

        db.update_receipt(receipt_id, update_data)

        # Insert line items
        if 'items' in extracted and extracted['items']:
            for idx, item in enumerate(extracted['items']):
                db.create_receipt_item(
                    receipt_id=receipt_id,
                    line_number=idx + 1,
                    description=item.get('description'),
                    quantity=item.get('quantity', 1.0),
                    unit_price=item.get('unit_price'),
                    total_price=item.get('total_price')
                )

        # Queue for review if needed
        if update_data.get('needs_review'):
            db.add_to_review_queue(
                receipt_id=receipt_id,
                reason=f"Low OCR confidence: {extracted.get('confidence', 0):.2f}",
                priority=1 if extracted.get('confidence', 0) < 0.5 else 0
            )

        db.log_processing_step(receipt_id, 'database_insert', 'success')
        logger.info(f"Successfully processed receipt {receipt_id}")

    except Exception as e:
        logger.error(f"Error in background processing of receipt {receipt_id}: {e}")
        db.update_receipt(receipt_id, {'status': 'failed'})
        db.log_processing_step(receipt_id, 'failure', 'failed', error_message=str(e))


@app.get("/api/receipts/{receipt_id}")
async def get_receipt(receipt_id: int):
    receipt = db.get_receipt(receipt_id)
    if not receipt:
        raise HTTPException(404, "Receipt not found")
    return receipt

@app.patch("/api/receipts/{receipt_id}")
async def update_receipt(receipt_id: int, update: ReviewUpdate):
    receipt = db.get_receipt(receipt_id)
    if not receipt:
        raise HTTPException(404, "Receipt not found")

    update_data = update.dict(exclude_unset=True)
    update_data['needs_review'] = False
    update_data['reviewed_at'] = datetime.utcnow()

    db.update_receipt(receipt_id, update_data)
    db.complete_review_queue_item(receipt_id, update.reviewed_by)
    db.log_processing_step(
        receipt_id, 'review', 'success',
        metadata={'reviewed_by': update.reviewed_by}
    )

    return {"status": "updated", "receipt_id": receipt_id}

@app.get("/api/receipts/pending-review")
async def get_pending_review(limit: int = 50):
    receipts = db.get_pending_review(limit=limit)
    return {"count": len(receipts), "receipts": receipts}

@app.get("/api/stats")
async def get_stats():
    return db.get_processing_stats()

@app.get("/api/projects/{project_id}/receipts")
async def get_project_receipts(project_id: str):
    """Get all receipts for a project (which carries the JT job link)."""
    receipts = db.get_receipts_by_project(project_id)
    return {"project_id": project_id, "count": len(receipts), "receipts": receipts}

# --- CLI ---

def cli_process(image_path: str, project_id: Optional[str] = None):
    file_path = Path(image_path)
    if not file_path.exists():
        print(f"Error: File not found: {image_path}")
        return 1

    print(f"Processing receipt: {image_path}")

    content = file_path.read_bytes()
    file_hash = hashlib.sha256(content).hexdigest()

    receipt_id = db.create_receipt(
        image_path=str(file_path),
        filename=file_path.name,
        file_size=len(content),
        file_hash=file_hash,
        project_id=project_id,
        status='pending'
    )

    asyncio.run(process_receipt_background(receipt_id, file_path, False))

    receipt = db.get_receipt(receipt_id)

    print(f"\nReceipt processed (ID: {receipt_id})")
    print(f"  Status: {receipt['status']}")
    print(f"  Date: {receipt.get('receipt_date', 'N/A')}")
    print(f"  Vendor: {receipt.get('vendor_normalized') or receipt.get('vendor_raw', 'N/A')}")
    print(f"  Total: ${receipt.get('total_amount', 0):.2f}")
    print(f"  Confidence: {receipt.get('ocr_confidence', 0):.2%}")
    print(f"  Needs Review: {'Yes' if receipt.get('needs_review') else 'No'}")

    return 0

def cli_stats():
    stats = db.get_processing_stats()
    print("\n=== Receipt OCR Statistics ===")
    print(f"Total receipts: {stats.get('total_receipts', 0)}")
    print(f"Completed: {stats.get('completed', 0)}")
    print(f"Failed: {stats.get('failed', 0)}")
    print(f"Pending review: {stats.get('pending_review', 0)}")
    print(f"Average confidence: {stats.get('avg_confidence', 0):.2%}")
    print(f"Success rate: {stats.get('success_rate', 0):.2%}")
    return 0

def main():
    import argparse

    parser = argparse.ArgumentParser(description="Receipt OCR Service")
    subparsers = parser.add_subparsers(dest='command', help='Commands')

    process_parser = subparsers.add_parser('process', help='Process a receipt image')
    process_parser.add_argument('image_path', help='Path to receipt image')
    process_parser.add_argument('--project-id', help='Associated project UUID')

    subparsers.add_parser('stats', help='Show processing statistics')

    serve_parser = subparsers.add_parser('serve', help='Start API server')
    serve_parser.add_argument('--host', default='0.0.0.0', help='Host to bind to')
    serve_parser.add_argument('--port', type=int, default=8001, help='Port to bind to')

    args = parser.parse_args()

    if args.command == 'process':
        return cli_process(args.image_path, args.project_id)
    elif args.command == 'stats':
        return cli_stats()
    elif args.command == 'serve':
        uvicorn.run(app, host=args.host, port=args.port)
        return 0
    else:
        parser.print_help()
        return 1

if __name__ == "__main__":
    sys.exit(main())
