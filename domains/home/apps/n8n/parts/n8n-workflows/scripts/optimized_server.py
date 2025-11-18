#!/usr/bin/env python3
"""
Optimized N8N Workflows Server
Error-free, fast, and reliable operation
"""

import os
import sys
import time
import sqlite3
import json
import hashlib
from datetime import datetime
from typing import Dict, List, Optional, Any
from fastapi import FastAPI, HTTPException, Query, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from fastapi.responses import JSONResponse, FileResponse
import uvicorn
import asyncio
from concurrent.futures import ThreadPoolExecutor

class OptimizedWorkflowServer:
    """Optimized server with error handling and performance optimization"""
    
    def __init__(self, db_path: str = "workflows.db"):
        """Initialize optimized server"""
        self.db_path = db_path
        self.app = FastAPI(
            title="N8N Workflows - Optimized API",
            description="High-performance, error-free n8n workflows API",
            version="2.1.0"
        )
        self.executor = ThreadPoolExecutor(max_workers=4)
        self._setup_middleware()
        self._setup_routes()
        self._ensure_database()
    
    def _setup_middleware(self):
        """Setup optimized middleware"""
        # CORS with optimized settings
        self.app.add_middleware(
            CORSMiddleware,
            allow_origins=["*"],
            allow_credentials=True,
            allow_methods=["GET", "POST", "PUT", "DELETE"],
            allow_headers=["*"],
        )
        
        # Gzip compression for better performance
        self.app.add_middleware(GZipMiddleware, minimum_size=1000)
    
    def _ensure_database(self):
        """Ensure database exists and is optimized"""
        if not os.path.exists(self.db_path):
            print("❌ Database not found. Please run 'python workflow_db.py --index' first.")
            return False
        
        # Optimize database for performance
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        # Enable WAL mode for better concurrency
        cursor.execute("PRAGMA journal_mode=WAL")
        
        # Optimize for performance
        cursor.execute("PRAGMA synchronous=NORMAL")
        cursor.execute("PRAGMA cache_size=10000")
        cursor.execute("PRAGMA temp_store=MEMORY")
        
        # Create indexes for faster queries
        try:
            cursor.execute("CREATE INDEX IF NOT EXISTS idx_workflows_active ON workflows(active)")
            cursor.execute("CREATE INDEX IF NOT EXISTS idx_workflows_trigger ON workflows(trigger_type)")
            cursor.execute("CREATE INDEX IF NOT EXISTS idx_workflows_complexity ON workflows(complexity)")
            cursor.execute("CREATE INDEX IF NOT EXISTS idx_workflows_integrations ON workflows(integrations)")
        except Exception as e:
            print(f"Warning: Could not create indexes: {e}")
        
        conn.commit()
        conn.close()
        return True
    
    def _setup_routes(self):
        """Setup optimized API routes"""
        
        @self.app.get("/")
        async def root():
            """Root endpoint with server info"""
            return {
                "message": "N8N Workflows - Optimized API",
                "version": "2.1.0",
                "status": "operational",
                "timestamp": datetime.now().isoformat(),
                "endpoints": {
                    "stats": "/api/stats",
                    "workflows": "/api/workflows",
                    "search": "/api/workflows/search",
                    "health": "/api/health",
                    "docs": "/docs"
                }
            }
        
        @self.app.get("/api/health")
        async def health_check():
            """Optimized health check with performance metrics"""
            start_time = time.time()
            
            try:
                # Test database connection
                conn = sqlite3.connect(self.db_path)
                cursor = conn.cursor()
                
                # Quick database test
                cursor.execute("SELECT COUNT(*) FROM workflows")
                total_workflows = cursor.fetchone()[0]
                
                # Test search performance
                search_start = time.time()
                cursor.execute("SELECT COUNT(*) FROM workflows WHERE active = 1")
                active_count = cursor.fetchone()[0]
                search_time = (time.time() - search_start) * 1000
                
                conn.close()
                
                total_time = (time.time() - start_time) * 1000
                
                return {
                    "status": "healthy",
                    "database": {
                        "connected": True,
                        "total_workflows": total_workflows,
                        "active_workflows": active_count
                    },
                    "performance": {
                        "response_time_ms": round(total_time, 2),
                        "search_time_ms": round(search_time, 2),
                        "status": "excellent" if total_time < 50 else "good" if total_time < 100 else "needs_optimization"
                    },
                    "timestamp": datetime.now().isoformat()
                }
                
            except Exception as e:
                return {
                    "status": "unhealthy",
                    "error": str(e),
                    "timestamp": datetime.now().isoformat()
                }
        
        @self.app.get("/api/stats")
        async def get_stats():
            """Get optimized platform statistics"""
            try:
                conn = sqlite3.connect(self.db_path)
                cursor = conn.cursor()
                
                # Get basic stats
                cursor.execute("SELECT COUNT(*) FROM workflows")
                total = cursor.fetchone()[0]
                
                cursor.execute("SELECT COUNT(*) FROM workflows WHERE active = 1")
                active = cursor.fetchone()[0]
                
                # Get trigger distribution
                cursor.execute("""
                    SELECT trigger_type, COUNT(*) 
                    FROM workflows 
                    GROUP BY trigger_type
                """)
                triggers = dict(cursor.fetchall())
                
                # Get complexity distribution
                cursor.execute("""
                    SELECT complexity, COUNT(*) 
                    FROM workflows 
                    GROUP BY complexity
                """)
                complexity = dict(cursor.fetchall())
                
                # Get total nodes
                cursor.execute("SELECT SUM(node_count) FROM workflows")
                total_nodes = cursor.fetchone()[0] or 0
                
                # Get unique integrations
                cursor.execute("SELECT COUNT(DISTINCT integrations) FROM workflows")
                unique_integrations = cursor.fetchone()[0]
                
                conn.close()
                
                return {
                    "total": total,
                    "active": active,
                    "inactive": total - active,
                    "triggers": triggers,
                    "complexity": complexity,
                    "total_nodes": total_nodes,
                    "unique_integrations": unique_integrations,
                    "last_indexed": datetime.now().isoformat()
                }
                
            except Exception as e:
                raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")
        
        @self.app.get("/api/workflows")
        async def get_workflows(
            search: Optional[str] = Query(None),
            category: Optional[str] = Query(None),
            trigger_type: Optional[str] = Query(None),
            complexity: Optional[str] = Query(None),
            active_only: bool = Query(False),
            limit: int = Query(20, le=100),
            offset: int = Query(0, ge=0)
        ):
            """Get workflows with optimized search"""
            try:
                conn = sqlite3.connect(self.db_path)
                cursor = conn.cursor()
                
                # Build optimized query
                query_parts = ["SELECT * FROM workflows"]
                conditions = []
                params = []
                
                # Apply filters
                if search:
                    conditions.append("(name LIKE ? OR description LIKE ? OR integrations LIKE ?)")
                    search_term = f"%{search}%"
                    params.extend([search_term, search_term, search_term])
                
                if category:
                    conditions.append("category = ?")
                    params.append(category)
                
                if trigger_type:
                    conditions.append("trigger_type = ?")
                    params.append(trigger_type)
                
                if complexity:
                    conditions.append("complexity = ?")
                    params.append(complexity)
                
                if active_only:
                    conditions.append("active = 1")
                
                # Add conditions
                if conditions:
                    query_parts.append("WHERE " + " AND ".join(conditions))
                
                # Add ordering and pagination
                query_parts.append("ORDER BY name LIMIT ? OFFSET ?")
                params.extend([limit, offset])
                
                # Execute query
                query = " ".join(query_parts)
                cursor.execute(query, params)
                
                workflows = []
                for row in cursor.fetchall():
                    workflows.append({
                        "id": row[0],
                        "filename": row[1],
                        "name": row[2],
                        "workflow_id": row[3],
                        "active": bool(row[4]),
                        "description": row[5],
                        "trigger_type": row[6],
                        "complexity": row[7],
                        "node_count": row[8],
                        "integrations": json.loads(row[9]) if row[9] else [],
                        "tags": json.loads(row[10]) if row[10] else [],
                        "created_at": row[11],
                        "updated_at": row[12]
                    })
                
                # Get total count for pagination
                count_query = "SELECT COUNT(*) FROM workflows"
                if conditions:
                    count_query += " WHERE " + " AND ".join(conditions)
                    cursor.execute(count_query, params[:-2])  # Remove limit and offset
                else:
                    cursor.execute(count_query)
                
                total = cursor.fetchone()[0]
                
                conn.close()
                
                return {
                    "workflows": workflows,
                    "total": total,
                    "page": (offset // limit) + 1,
                    "per_page": limit,
                    "pages": (total + limit - 1) // limit,
                    "query": search or "",
                    "filters": {
                        "trigger": trigger_type or "all",
                        "complexity": complexity or "all",
                        "active_only": active_only
                    }
                }
                
            except Exception as e:
                raise HTTPException(status_code=500, detail=f"Search error: {str(e)}")
        
        @self.app.get("/api/workflows/{filename}")
        async def get_workflow(filename: str):
            """Get specific workflow details"""
            try:
                conn = sqlite3.connect(self.db_path)
                cursor = conn.cursor()
                
                cursor.execute("SELECT * FROM workflows WHERE filename = ?", (filename,))
                row = cursor.fetchone()
                
                if not row:
                    raise HTTPException(status_code=404, detail="Workflow not found")
                
                conn.close()
                
                return {
                    "id": row[0],
                    "filename": row[1],
                    "name": row[2],
                    "workflow_id": row[3],
                    "active": bool(row[4]),
                    "description": row[5],
                    "trigger_type": row[6],
                    "complexity": row[7],
                    "node_count": row[8],
                    "integrations": json.loads(row[9]) if row[9] else [],
                    "tags": json.loads(row[10]) if row[10] else [],
                    "created_at": row[11],
                    "updated_at": row[12],
                    "file_hash": row[13],
                    "file_size": row[14],
                    "analyzed_at": row[15]
                }
                
            except HTTPException:
                raise
            except Exception as e:
                raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")
        
        @self.app.get("/api/workflows/{filename}/download")
        async def download_workflow(filename: str):
            """Download workflow file"""
            try:
                # Find the workflow file
                workflow_path = None
                for root, dirs, files in os.walk("workflows"):
                    if filename in files:
                        workflow_path = os.path.join(root, filename)
                        break
                
                if not workflow_path or not os.path.exists(workflow_path):
                    raise HTTPException(status_code=404, detail="Workflow file not found")
                
                return FileResponse(
                    workflow_path,
                    media_type="application/json",
                    filename=filename
                )
                
            except HTTPException:
                raise
            except Exception as e:
                raise HTTPException(status_code=500, detail=f"Download error: {str(e)}")
        
        @self.app.get("/api/categories")
        async def get_categories():
            """Get workflow categories"""
            try:
                conn = sqlite3.connect(self.db_path)
                cursor = conn.cursor()
                
                cursor.execute("""
                    SELECT category, COUNT(*) 
                    FROM workflows 
                    WHERE category IS NOT NULL AND category != ''
                    GROUP BY category 
                    ORDER BY COUNT(*) DESC
                """)
                
                categories = [{"name": row[0], "count": row[1]} for row in cursor.fetchall()]
                
                conn.close()
                
                return {"categories": categories}
                
            except Exception as e:
                raise HTTPException(status_code=500, detail=f"Categories error: {str(e)}")
    
    def run(self, host: str = "127.0.0.1", port: int = 8000, workers: int = 1):
        """Run optimized server"""
        print("🚀 Starting Optimized N8N Workflows Server...")
        print(f"📊 Database: {self.db_path}")
        print(f"🌐 Server: http://{host}:{port}")
        print(f"📚 Documentation: http://{host}:{port}/docs")
        print("⚡ Optimized for speed and reliability")
        
        uvicorn.run(
            self.app,
            host=host,
            port=port,
            workers=workers,
            log_level="info",
            access_log=True
        )

if __name__ == "__main__":
    server = OptimizedWorkflowServer()
    server.run()
