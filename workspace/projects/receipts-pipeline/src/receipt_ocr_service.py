#!/usr/bin/env python3
"""
Receipt OCR Service
===================

FastAPI service for processing receipt images with OCR and LLM normalization.

Endpoints:
    POST /api/ocr/receipt - Process a receipt image
    GET /api/receipts/{id} - Get receipt details
    PATCH /api/receipts/{id} - Update receipt
    GET /api/receipts/pending-review - Get receipts needing review

CLI:
    receipt-ocr process <image_path> [--job-id=<id>]
    receipt-ocr review <receipt_id>
    receipt-ocr stats
"""

import asyncio
import logging
import os
import sys
from datetime import datetime
from pathlib import Path
from typing import Optional, List, Dict, Any
from uuid import UUID

from fastapi import FastAPI, File, UploadFile, HTTPException, BackgroundTasks, Form
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field
import uvicorn

from src.ocr_processor import OCRProcessor
from src.llm_normalizer import LLMNormalizer
from src.database import Database
from src.config import Config

# ============================================================================
# Setup logging
# ============================================================================
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# ============================================================================
# FastAPI App
# ============================================================================
app = FastAPI(
    title="Receipt OCR Service",
    description="Process receipt images into structured data",
    version="1.0.0"
)

# ============================================================================
# Pydantic Models
# ============================================================================

class ReceiptResponse(BaseModel):
    """Receipt data response model"""
    id: int
    uuid: UUID
    status: str
    receipt_date: Optional[str]
    vendor_raw: Optional[str]
    vendor_normalized: Optional[str]
    total_amount: Optional[float]
    tax_amount: Optional[float]
    subtotal: Optional[float]
    ocr_confidence: Optional[float]
    needs_review: bool
    image_path: str
    job_id: Optional[int]
    items: List[Dict[str, Any]] = []

class ProcessRequest(BaseModel):
    """Request to process a receipt"""
    job_id: Optional[int] = None
    category: Optional[str] = None
    notes: Optional[str] = None
    skip_llm: bool = False

class ReviewUpdate(BaseModel):
    """Review update model"""
    vendor_normalized: Optional[str] = None
    total_amount: Optional[float] = None
    receipt_date: Optional[str] = None
    job_id: Optional[int] = None
    category: Optional[str] = None
    notes: Optional[str] = None
    reviewed_by: str

# ============================================================================
# Service Components
# ============================================================================

config = Config()
db = Database(config.database_url)
ocr = OCRProcessor(config)
llm = LLMNormalizer(config) if config.ollama_enabled else None

# ============================================================================
# API Endpoints
# ============================================================================

@app.get("/")
async def root():
    """Health check endpoint"""
    return {
        "service": "Receipt OCR Service",
        "status": "operational",
        "version": "1.0.0",
        "database": "connected" if db.is_connected() else "disconnected",
        "ollama": "enabled" if llm else "disabled"
    }

@app.get("/health")
async def health_check():
    """Detailed health check"""
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
    job_id: Optional[int] = Form(None),
    category: Optional[str] = Form(None),
    notes: Optional[str] = Form(None),
    skip_llm: bool = Form(False)
):
    """
    Process a receipt image with OCR

    Args:
        file: Receipt image (jpg, png, pdf)
        job_id: Associated job ID
        category: Expense category
        notes: Additional notes
        skip_llm: Skip LLM normalization

    Returns:
        Receipt data with OCR results
    """
    try:
        # Validate file type
        if not file.content_type.startswith(('image/', 'application/pdf')):
            raise HTTPException(400, "Invalid file type. Must be image or PDF")

        # Save uploaded file
        upload_path = config.get_upload_path()
        file_path = upload_path / f"{datetime.now().strftime('%Y%m%d_%H%M%S')}_{file.filename}"

        with open(file_path, "wb") as f:
            content = await file.read()
            f.write(content)

        logger.info(f"Saved uploaded file: {file_path}")

        # Create database record
        receipt_id = db.create_receipt(
            image_path=str(file_path),
            filename=file.filename,
            file_size=len(content),
            job_id=job_id,
            notes=notes,
            status='pending'
        )

        # Log processing start
        db.log_processing_step(receipt_id, 'upload', 'success')

        # Process in background
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

    except Exception as e:
        logger.error(f"Error processing receipt: {e}")
        raise HTTPException(500, f"Processing failed: {str(e)}")

async def process_receipt_background(receipt_id: int, file_path: Path, skip_llm: bool):
    """
    Background task to process receipt

    Args:
        receipt_id: Database receipt ID
        file_path: Path to image file
        skip_llm: Skip LLM normalization
    """
    try:
        # Update status
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

        # LLM normalization (if enabled and not skipped)
        if llm and not skip_llm:
            try:
                logger.info(f"Running LLM normalization on receipt {receipt_id}")
                start_time = datetime.now()

                normalized = llm.normalize_receipt(extracted, ocr_result['text'])

                duration_ms = int((datetime.now() - start_time).total_seconds() * 1000)
                db.log_processing_step(receipt_id, 'llm_normalization', 'success', duration_ms=duration_ms)

                # Merge normalized data
                extracted.update(normalized)
            except Exception as e:
                logger.warning(f"LLM normalization failed, using raw OCR: {e}")
                db.log_processing_step(
                    receipt_id, 'llm_normalization', 'failed',
                    error_message=str(e)
                )

        # Update database with extracted data
        update_data = {
            'status': 'completed',
            'ocr_raw_text': ocr_result['text'],
            'ocr_raw_json': ocr_result,
            'ocr_confidence': extracted.get('confidence', 0.0),
            'receipt_date': extracted.get('date'),
            'vendor_raw': extracted.get('vendor_raw'),
            'vendor_normalized': extracted.get('vendor_normalized'),
            'total_amount': extracted.get('total'),
            'tax_amount': extracted.get('tax'),
            'subtotal': extracted.get('subtotal'),
            'needs_review': extracted.get('confidence', 0) < config.confidence_threshold
        }

        # Remove None values
        update_data = {k: v for k, v in update_data.items() if v is not None}

        db.update_receipt(receipt_id, update_data)

        # Insert line items if available
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

        # Add to review queue if needed
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
        db.log_processing_step(
            receipt_id, 'failure', 'failed',
            error_message=str(e)
        )

@app.get("/api/receipts/{receipt_id}")
async def get_receipt(receipt_id: int):
    """Get receipt details by ID"""
    receipt = db.get_receipt(receipt_id)

    if not receipt:
        raise HTTPException(404, "Receipt not found")

    return receipt

@app.patch("/api/receipts/{receipt_id}")
async def update_receipt(receipt_id: int, update: ReviewUpdate):
    """Update receipt (for manual review)"""
    # Check receipt exists
    receipt = db.get_receipt(receipt_id)
    if not receipt:
        raise HTTPException(404, "Receipt not found")

    # Update receipt
    update_data = update.dict(exclude_unset=True)
    update_data['needs_review'] = False
    update_data['reviewed_at'] = datetime.utcnow()

    db.update_receipt(receipt_id, update_data)

    # Mark review queue item as completed
    db.complete_review_queue_item(receipt_id, update.reviewed_by)

    # Log review action
    db.log_processing_step(
        receipt_id, 'review', 'success',
        metadata={'reviewed_by': update.reviewed_by}
    )

    return {"status": "updated", "receipt_id": receipt_id}

@app.get("/api/receipts/pending-review")
async def get_pending_review(limit: int = 50):
    """Get receipts pending manual review"""
    receipts = db.get_pending_review(limit=limit)
    return {"count": len(receipts), "receipts": receipts}

@app.get("/api/stats")
async def get_stats():
    """Get processing statistics"""
    return db.get_processing_stats()

@app.get("/api/jobs/{job_id}/receipts")
async def get_job_receipts(job_id: int):
    """Get all receipts for a job"""
    receipts = db.get_receipts_by_job(job_id)
    return {"job_id": job_id, "count": len(receipts), "receipts": receipts}

# ============================================================================
# CLI Interface
# ============================================================================

def cli_process(image_path: str, job_id: Optional[int] = None):
    """CLI: Process a receipt image"""
    from pathlib import Path

    file_path = Path(image_path)
    if not file_path.exists():
        print(f"Error: File not found: {image_path}")
        return 1

    print(f"Processing receipt: {image_path}")

    # Create database record
    receipt_id = db.create_receipt(
        image_path=str(file_path),
        filename=file_path.name,
        file_size=file_path.stat().st_size,
        job_id=job_id,
        status='pending'
    )

    # Process synchronously
    asyncio.run(process_receipt_background(receipt_id, file_path, False))

    # Get result
    receipt = db.get_receipt(receipt_id)

    print(f"\n✓ Receipt processed (ID: {receipt_id})")
    print(f"  Status: {receipt['status']}")
    print(f"  Date: {receipt.get('receipt_date', 'N/A')}")
    print(f"  Vendor: {receipt.get('vendor_normalized') or receipt.get('vendor_raw', 'N/A')}")
    print(f"  Total: ${receipt.get('total_amount', 0):.2f}")
    print(f"  Confidence: {receipt.get('ocr_confidence', 0):.2%}")
    print(f"  Needs Review: {'Yes' if receipt.get('needs_review') else 'No'}")

    return 0

def cli_stats():
    """CLI: Show processing statistics"""
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
    """Main CLI entry point"""
    import argparse

    parser = argparse.ArgumentParser(description="Receipt OCR Service")
    subparsers = parser.add_subparsers(dest='command', help='Commands')

    # Process command
    process_parser = subparsers.add_parser('process', help='Process a receipt image')
    process_parser.add_argument('image_path', help='Path to receipt image')
    process_parser.add_argument('--job-id', type=int, help='Associated job ID')

    # Stats command
    subparsers.add_parser('stats', help='Show processing statistics')

    # Serve command
    serve_parser = subparsers.add_parser('serve', help='Start API server')
    serve_parser.add_argument('--host', default='0.0.0.0', help='Host to bind to')
    serve_parser.add_argument('--port', type=int, default=8000, help='Port to bind to')

    args = parser.parse_args()

    if args.command == 'process':
        return cli_process(args.image_path, args.job_id)
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
