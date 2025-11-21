"""
Database Module
===============

Handles all PostgreSQL database operations for receipts.
"""

import logging
from datetime import datetime
from typing import Dict, Any, List, Optional
from contextlib import contextmanager

import psycopg2
from psycopg2.extras import RealDictCursor, Json
from psycopg2.pool import SimpleConnectionPool

logger = logging.getLogger(__name__)

class Database:
    """PostgreSQL database interface for receipts"""

    def __init__(self, connection_string: str, min_conn: int = 1, max_conn: int = 10):
        """
        Initialize database connection pool

        Args:
            connection_string: PostgreSQL connection string
            min_conn: Minimum pool connections
            max_conn: Maximum pool connections
        """
        self.connection_string = connection_string
        self.pool = SimpleConnectionPool(
            min_conn,
            max_conn,
            connection_string
        )
        logger.info("Database connection pool initialized")

    @contextmanager
    def get_connection(self):
        """Context manager for database connections"""
        conn = self.pool.getconn()
        try:
            yield conn
            conn.commit()
        except Exception:
            conn.rollback()
            raise
        finally:
            self.pool.putconn(conn)

    def is_connected(self) -> bool:
        """Check if database is accessible"""
        try:
            with self.get_connection() as conn:
                with conn.cursor() as cur:
                    cur.execute("SELECT 1")
                    return True
        except Exception:
            return False

    def health_check(self) -> Dict[str, Any]:
        """Detailed health check"""
        try:
            with self.get_connection() as conn:
                with conn.cursor() as cur:
                    cur.execute("SELECT version()")
                    version = cur.fetchone()[0]

                    cur.execute("SELECT COUNT(*) FROM receipts")
                    receipt_count = cur.fetchone()[0]

                    return {
                        "status": "connected",
                        "version": version,
                        "receipt_count": receipt_count
                    }
        except Exception as e:
            return {
                "status": "error",
                "error": str(e)
            }

    # ========================================================================
    # Receipt Operations
    # ========================================================================

    def create_receipt(
        self,
        image_path: str,
        filename: str,
        file_size: int,
        job_id: Optional[int] = None,
        notes: Optional[str] = None,
        status: str = 'pending'
    ) -> int:
        """
        Create a new receipt record

        Returns:
            Receipt ID
        """
        with self.get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute("""
                    INSERT INTO receipts (
                        image_path, image_filename, file_size_bytes,
                        job_id, notes, status
                    ) VALUES (%s, %s, %s, %s, %s, %s)
                    RETURNING id
                """, (image_path, filename, file_size, job_id, notes, status))

                receipt_id = cur.fetchone()[0]
                logger.info(f"Created receipt {receipt_id}")
                return receipt_id

    def get_receipt(self, receipt_id: int) -> Optional[Dict[str, Any]]:
        """Get receipt by ID"""
        with self.get_connection() as conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute("""
                    SELECT
                        r.*,
                        j.job_number,
                        j.job_name,
                        v.name_normalized as vendor_name,
                        ec.name as category_name
                    FROM receipts r
                    LEFT JOIN jobs j ON r.job_id = j.id
                    LEFT JOIN vendors v ON r.vendor_id = v.id
                    LEFT JOIN expense_categories ec ON r.category_id = ec.id
                    WHERE r.id = %s
                """, (receipt_id,))

                receipt = cur.fetchone()

                if receipt:
                    # Get items
                    cur.execute("""
                        SELECT * FROM receipt_items
                        WHERE receipt_id = %s
                        ORDER BY line_number
                    """, (receipt_id,))

                    items = cur.fetchall()
                    receipt = dict(receipt)
                    receipt['items'] = [dict(item) for item in items]

                return receipt

    def update_receipt(self, receipt_id: int, data: Dict[str, Any]) -> None:
        """Update receipt with new data"""
        if not data:
            return

        # Build UPDATE query dynamically
        set_clause = ', '.join([f"{key} = %s" for key in data.keys()])
        values = list(data.values()) + [receipt_id]

        with self.get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(f"""
                    UPDATE receipts
                    SET {set_clause}
                    WHERE id = %s
                """, values)

                logger.debug(f"Updated receipt {receipt_id}")

    def get_receipts_by_job(self, job_id: int) -> List[Dict[str, Any]]:
        """Get all receipts for a job"""
        with self.get_connection() as conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute("""
                    SELECT
                        r.*,
                        v.name_normalized as vendor_name,
                        ec.name as category_name
                    FROM receipts r
                    LEFT JOIN vendors v ON r.vendor_id = v.id
                    LEFT JOIN expense_categories ec ON r.category_id = ec.id
                    WHERE r.job_id = %s
                    ORDER BY r.receipt_date DESC, r.upload_timestamp DESC
                """, (job_id,))

                return [dict(row) for row in cur.fetchall()]

    # ========================================================================
    # Receipt Items Operations
    # ========================================================================

    def create_receipt_item(
        self,
        receipt_id: int,
        line_number: int,
        description: str,
        total_price: float,
        quantity: float = 1.0,
        unit_price: Optional[float] = None
    ) -> int:
        """Create a receipt line item"""
        with self.get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute("""
                    INSERT INTO receipt_items (
                        receipt_id, line_number, description,
                        quantity, unit_price, total_price
                    ) VALUES (%s, %s, %s, %s, %s, %s)
                    RETURNING id
                """, (receipt_id, line_number, description, quantity, unit_price, total_price))

                return cur.fetchone()[0]

    # ========================================================================
    # Processing Log Operations
    # ========================================================================

    def log_processing_step(
        self,
        receipt_id: int,
        step: str,
        status: str,
        duration_ms: Optional[int] = None,
        error_message: Optional[str] = None,
        metadata: Optional[Dict[str, Any]] = None
    ) -> None:
        """Log a processing step"""
        with self.get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute("""
                    INSERT INTO receipt_processing_log (
                        receipt_id, step, status, duration_ms,
                        error_message, metadata
                    ) VALUES (%s, %s, %s, %s, %s, %s)
                """, (
                    receipt_id, step, status, duration_ms,
                    error_message, Json(metadata) if metadata else None
                ))

    # ========================================================================
    # Review Queue Operations
    # ========================================================================

    def add_to_review_queue(
        self,
        receipt_id: int,
        reason: str,
        priority: int = 0,
        assigned_to: Optional[str] = None
    ) -> int:
        """Add receipt to review queue"""
        with self.get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute("""
                    INSERT INTO receipt_review_queue (
                        receipt_id, reason, priority, assigned_to
                    ) VALUES (%s, %s, %s, %s)
                    ON CONFLICT (receipt_id) DO UPDATE
                    SET priority = EXCLUDED.priority,
                        reason = EXCLUDED.reason
                    RETURNING id
                """, (receipt_id, reason, priority, assigned_to))

                return cur.fetchone()[0]

    def get_pending_review(self, limit: int = 50) -> List[Dict[str, Any]]:
        """Get receipts pending review"""
        with self.get_connection() as conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute("""
                    SELECT * FROM v_receipts_pending_review
                    LIMIT %s
                """, (limit,))

                return [dict(row) for row in cur.fetchall()]

    def complete_review_queue_item(self, receipt_id: int, reviewed_by: str) -> None:
        """Mark review queue item as completed"""
        with self.get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute("""
                    UPDATE receipt_review_queue
                    SET status = 'completed',
                        completed_at = NOW(),
                        resolution_notes = %s
                    WHERE receipt_id = %s
                """, (f"Reviewed by {reviewed_by}", receipt_id))

    # ========================================================================
    # Statistics Operations
    # ========================================================================

    def get_processing_stats(self) -> Dict[str, Any]:
        """Get processing statistics"""
        with self.get_connection() as conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                # Overall counts
                cur.execute("""
                    SELECT
                        COUNT(*) as total_receipts,
                        COUNT(*) FILTER (WHERE status = 'completed') as completed,
                        COUNT(*) FILTER (WHERE status = 'failed') as failed,
                        COUNT(*) FILTER (WHERE status = 'pending') as pending,
                        COUNT(*) FILTER (WHERE needs_review = TRUE) as pending_review,
                        AVG(ocr_confidence) as avg_confidence,
                        SUM(total_amount) as total_amount
                    FROM receipts
                """)

                stats = dict(cur.fetchone())

                # Calculate success rate
                if stats['total_receipts'] > 0:
                    stats['success_rate'] = stats['completed'] / stats['total_receipts']
                else:
                    stats['success_rate'] = 0

                # Recent processing times
                cur.execute("""
                    SELECT
                        step,
                        AVG(duration_ms) as avg_duration_ms,
                        COUNT(*) as count
                    FROM receipt_processing_log
                    WHERE timestamp > NOW() - INTERVAL '24 hours'
                    GROUP BY step
                """)

                stats['recent_processing'] = [dict(row) for row in cur.fetchall()]

                return stats

    # ========================================================================
    # Job Operations
    # ========================================================================

    def create_job(
        self,
        job_number: str,
        job_name: str,
        client_name: Optional[str] = None,
        budget: Optional[float] = None
    ) -> int:
        """Create a new job"""
        with self.get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute("""
                    INSERT INTO jobs (job_number, job_name, client_name, budget)
                    VALUES (%s, %s, %s, %s)
                    RETURNING id
                """, (job_number, job_name, client_name, budget))

                return cur.fetchone()[0]

    def get_job(self, job_id: int) -> Optional[Dict[str, Any]]:
        """Get job by ID"""
        with self.get_connection() as conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute("""
                    SELECT * FROM v_job_cost_summary
                    WHERE id = %s
                """, (job_id,))

                row = cur.fetchone()
                return dict(row) if row else None

    # ========================================================================
    # Vendor Operations
    # ========================================================================

    def get_or_create_vendor(self, vendor_name: str) -> int:
        """Get vendor by normalized name or create if not exists"""
        with self.get_connection() as conn:
            with conn.cursor() as cur:
                # Try to find existing vendor
                cur.execute("""
                    SELECT id FROM vendors
                    WHERE name_normalized = %s
                    OR %s = ANY(name_variants)
                """, (vendor_name, vendor_name))

                row = cur.fetchone()
                if row:
                    return row[0]

                # Create new vendor
                cur.execute("""
                    INSERT INTO vendors (name_normalized)
                    VALUES (%s)
                    RETURNING id
                """, (vendor_name,))

                return cur.fetchone()[0]
