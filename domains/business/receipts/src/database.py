"""
Database Module
===============

PostgreSQL operations for the receipts OCR pipeline.
Uses the shared heartwood_business database alongside estimates, leads, etc.
"""

import logging
from typing import Dict, Any, List, Optional
from contextlib import contextmanager

import psycopg2
from psycopg2.extras import RealDictCursor, Json
from psycopg2.pool import SimpleConnectionPool

logger = logging.getLogger(__name__)


class Database:
    """PostgreSQL interface for receipts in heartwood_business"""

    def __init__(self, connection_string: str, min_conn: int = 1, max_conn: int = 10):
        self.connection_string = connection_string
        self.pool = SimpleConnectionPool(min_conn, max_conn, connection_string)
        logger.info("Database connection pool initialized")

    @contextmanager
    def get_connection(self):
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
        try:
            with self.get_connection() as conn:
                with conn.cursor() as cur:
                    cur.execute("SELECT 1")
                    return True
        except Exception:
            return False

    def health_check(self) -> Dict[str, Any]:
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
            return {"status": "error", "error": str(e)}

    # ========================================================================
    # Receipt Operations
    # ========================================================================

    def create_receipt(
        self,
        image_path: str,
        filename: str,
        file_size: int,
        file_hash: Optional[str] = None,
        project_id: Optional[str] = None,
        notes: Optional[str] = None,
        status: str = 'pending'
    ) -> int:
        with self.get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute("""
                    INSERT INTO receipts (
                        image_path, image_filename, file_size_bytes,
                        file_hash, project_id, notes, status
                    ) VALUES (%s, %s, %s, %s, %s, %s, %s)
                    RETURNING id
                """, (image_path, filename, file_size, file_hash, project_id, notes, status))
                receipt_id = cur.fetchone()[0]
                logger.info(f"Created receipt {receipt_id}")
                return receipt_id

    def get_receipt(self, receipt_id: int) -> Optional[Dict[str, Any]]:
        with self.get_connection() as conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute("""
                    SELECT
                        r.*,
                        p.name          AS project_name,
                        p.jt_job_id,
                        p.jt_job_number,
                        v.name_normalized AS vendor_name,
                        ec.name         AS category_name
                    FROM receipts r
                    LEFT JOIN projects p ON r.project_id = p.id
                    LEFT JOIN vendors v ON r.vendor_id = v.id
                    LEFT JOIN expense_categories ec ON r.category_id = ec.id
                    WHERE r.id = %s
                """, (receipt_id,))

                receipt = cur.fetchone()
                if receipt:
                    cur.execute("""
                        SELECT * FROM receipt_items
                        WHERE receipt_id = %s ORDER BY line_number
                    """, (receipt_id,))
                    items = cur.fetchall()
                    receipt = dict(receipt)
                    receipt['items'] = [dict(item) for item in items]

                return receipt

    def update_receipt(self, receipt_id: int, data: Dict[str, Any]) -> None:
        if not data:
            return
        set_clause = ', '.join([f"{key} = %s" for key in data.keys()])
        values = list(data.values()) + [receipt_id]
        with self.get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(f"""
                    UPDATE receipts SET {set_clause} WHERE id = %s
                """, values)

    def get_receipts_by_project(self, project_id: str) -> List[Dict[str, Any]]:
        with self.get_connection() as conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute("""
                    SELECT
                        r.*,
                        v.name_normalized AS vendor_name,
                        ec.name AS category_name
                    FROM receipts r
                    LEFT JOIN vendors v ON r.vendor_id = v.id
                    LEFT JOIN expense_categories ec ON r.category_id = ec.id
                    WHERE r.project_id = %s
                    ORDER BY r.receipt_date DESC, r.upload_timestamp DESC
                """, (project_id,))
                return [dict(row) for row in cur.fetchall()]

    # ========================================================================
    # Receipt Items
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
    # Processing Log
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
    # Review Queue
    # ========================================================================

    def add_to_review_queue(self, receipt_id: int, reason: str,
                            priority: int = 0, assigned_to: Optional[str] = None) -> int:
        with self.get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute("""
                    INSERT INTO receipt_review_queue (
                        receipt_id, reason, priority, assigned_to
                    ) VALUES (%s, %s, %s, %s)
                    ON CONFLICT (receipt_id) DO UPDATE
                    SET priority = EXCLUDED.priority, reason = EXCLUDED.reason
                    RETURNING id
                """, (receipt_id, reason, priority, assigned_to))
                return cur.fetchone()[0]

    def get_pending_review(self, limit: int = 50) -> List[Dict[str, Any]]:
        with self.get_connection() as conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute("SELECT * FROM v_receipts_pending_review LIMIT %s", (limit,))
                return [dict(row) for row in cur.fetchall()]

    def complete_review_queue_item(self, receipt_id: int, reviewed_by: str) -> None:
        with self.get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute("""
                    UPDATE receipt_review_queue
                    SET status = 'completed', completed_at = NOW(),
                        resolution_notes = %s
                    WHERE receipt_id = %s
                """, (f"Reviewed by {reviewed_by}", receipt_id))

    # ========================================================================
    # Vendor Operations
    # ========================================================================

    def get_or_create_vendor(self, vendor_name: str) -> int:
        """Find vendor by normalized name / variants, or create a new one."""
        with self.get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute("""
                    SELECT id FROM vendors
                    WHERE name_normalized = %s OR %s = ANY(name_variants)
                """, (vendor_name, vendor_name))
                row = cur.fetchone()
                if row:
                    return row[0]

                cur.execute("""
                    INSERT INTO vendors (name_normalized)
                    VALUES (%s) RETURNING id
                """, (vendor_name,))
                return cur.fetchone()[0]

    # ========================================================================
    # Statistics
    # ========================================================================

    def get_processing_stats(self) -> Dict[str, Any]:
        with self.get_connection() as conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
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

                if stats['total_receipts'] > 0:
                    stats['success_rate'] = stats['completed'] / stats['total_receipts']
                else:
                    stats['success_rate'] = 0

                cur.execute("""
                    SELECT step, AVG(duration_ms) as avg_duration_ms, COUNT(*) as count
                    FROM receipt_processing_log
                    WHERE timestamp > NOW() - INTERVAL '24 hours'
                    GROUP BY step
                """)
                stats['recent_processing'] = [dict(row) for row in cur.fetchall()]

                return stats
