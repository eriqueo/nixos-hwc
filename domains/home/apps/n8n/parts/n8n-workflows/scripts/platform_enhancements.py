#!/usr/bin/env python3
"""
Platform Enhancement Features
Add advanced features to the N8N Workflows platform
"""

import json
import os
from pathlib import Path
from typing import Dict, List, Any
import sqlite3
from datetime import datetime

class PlatformEnhancer:
    def __init__(self, db_path="workflows.db"):
        self.db_path = db_path
        self.workflows_dir = Path("workflows")
        
    def add_workflow_analytics(self):
        """Add analytics tracking to workflows"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        # Add analytics columns if they don't exist
        try:
            cursor.execute("ALTER TABLE workflows ADD COLUMN view_count INTEGER DEFAULT 0")
            cursor.execute("ALTER TABLE workflows ADD COLUMN download_count INTEGER DEFAULT 0")
            cursor.execute("ALTER TABLE workflows ADD COLUMN last_viewed TIMESTAMP")
            cursor.execute("ALTER TABLE workflows ADD COLUMN popularity_score REAL DEFAULT 0")
            print("✅ Added analytics columns to workflows table")
        except sqlite3.OperationalError as e:
            if "duplicate column name" in str(e):
                print("✅ Analytics columns already exist")
            else:
                print(f"❌ Error adding analytics columns: {e}")
        
        conn.commit()
        conn.close()
    
    def create_workflow_recommendations(self):
        """Create workflow recommendation system"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        # Create recommendations table
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS workflow_recommendations (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                source_workflow_id INTEGER,
                recommended_workflow_id INTEGER,
                similarity_score REAL,
                recommendation_reason TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (source_workflow_id) REFERENCES workflows (id),
                FOREIGN KEY (recommended_workflow_id) REFERENCES workflows (id)
            )
        """)
        
        # Create index for faster lookups
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_recommendations_source ON workflow_recommendations(source_workflow_id)")
        
        conn.commit()
        conn.close()
        print("✅ Created workflow recommendations table")
    
    def add_workflow_tags_system(self):
        """Enhanced tagging system for workflows"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        # Create tags table
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS workflow_tags (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT UNIQUE NOT NULL,
                category TEXT,
                description TEXT,
                usage_count INTEGER DEFAULT 0,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)
        
        # Create workflow-tag relationship table
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS workflow_tag_relationships (
                workflow_id INTEGER,
                tag_id INTEGER,
                PRIMARY KEY (workflow_id, tag_id),
                FOREIGN KEY (workflow_id) REFERENCES workflows (id),
                FOREIGN KEY (tag_id) REFERENCES workflow_tags (id)
            )
        """)
        
        conn.commit()
        conn.close()
        print("✅ Created enhanced tagging system")
    
    def create_workflow_versions_table(self):
        """Create version tracking for workflows"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS workflow_versions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                workflow_id INTEGER,
                version_number TEXT,
                changes_summary TEXT,
                file_hash TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (workflow_id) REFERENCES workflows (id)
            )
        """)
        
        conn.commit()
        conn.close()
        print("✅ Created workflow versions table")
    
    def add_performance_metrics(self):
        """Add performance tracking metrics"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        # Create performance metrics table
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS workflow_performance (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                workflow_id INTEGER,
                execution_time_ms INTEGER,
                success_rate REAL,
                error_count INTEGER DEFAULT 0,
                last_execution TIMESTAMP,
                avg_execution_time REAL,
                total_executions INTEGER DEFAULT 0,
                FOREIGN KEY (workflow_id) REFERENCES workflows (id)
            )
        """)
        
        conn.commit()
        conn.close()
        print("✅ Created performance metrics table")
    
    def create_user_feedback_system(self):
        """Create user feedback and rating system"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS workflow_feedback (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                workflow_id INTEGER,
                user_identifier TEXT,
                rating INTEGER CHECK (rating >= 1 AND rating <= 5),
                feedback_text TEXT,
                helpful_count INTEGER DEFAULT 0,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (workflow_id) REFERENCES workflows (id)
            )
        """)
        
        conn.commit()
        conn.close()
        print("✅ Created user feedback system")
    
    def generate_workflow_insights(self):
        """Generate insights and analytics for workflows"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        # Get workflow statistics
        cursor.execute("SELECT COUNT(*) FROM workflows")
        total_workflows = cursor.fetchone()[0]
        
        cursor.execute("SELECT COUNT(*) FROM workflows WHERE active = 1")
        active_workflows = cursor.fetchone()[0]
        
        # Get complexity distribution
        cursor.execute("""
            SELECT 
                CASE 
                    WHEN node_count <= 5 THEN 'Simple'
                    WHEN node_count <= 15 THEN 'Medium'
                    ELSE 'Complex'
                END as complexity,
                COUNT(*) as count
            FROM workflows 
            GROUP BY complexity
        """)
        complexity_stats = cursor.fetchall()
        
        # Get top integrations
        cursor.execute("""
            SELECT integrations, COUNT(*) as count
            FROM workflows
            WHERE integrations IS NOT NULL AND integrations != '[]'
            GROUP BY integrations
            ORDER BY count DESC
            LIMIT 10
        """)
        top_integrations = cursor.fetchall()
        
        insights = {
            "total_workflows": total_workflows,
            "active_workflows": active_workflows,
            "complexity_distribution": dict(complexity_stats),
            "top_integrations": [{"integration": row[0], "count": row[1]} for row in top_integrations],
            "generated_at": datetime.now().isoformat()
        }
        
        # Save insights to file
        with open("workflow_insights.json", "w") as f:
            json.dump(insights, f, indent=2)
        
        conn.close()
        print("✅ Generated workflow insights")
        return insights
    
    def create_workflow_templates(self):
        """Create common workflow templates"""
        templates = {
            "data_pipeline": {
                "name": "Data Pipeline Template",
                "description": "Standard pattern for data processing workflows",
                "nodes": [
                    {"type": "trigger", "name": "Data Source"},
                    {"type": "transform", "name": "Data Processing"},
                    {"type": "validate", "name": "Data Validation"},
                    {"type": "store", "name": "Data Storage"}
                ],
                "pattern": "trigger → process → validate → store"
            },
            "api_integration": {
                "name": "API Integration Template",
                "description": "Standard pattern for API integrations",
                "nodes": [
                    {"type": "webhook", "name": "API Trigger"},
                    {"type": "http", "name": "API Call"},
                    {"type": "transform", "name": "Response Processing"},
                    {"type": "action", "name": "Result Action"}
                ],
                "pattern": "webhook → api_call → process → action"
            },
            "monitoring": {
                "name": "Monitoring Template",
                "description": "Standard pattern for monitoring workflows",
                "nodes": [
                    {"type": "schedule", "name": "Check Trigger"},
                    {"type": "http", "name": "Health Check"},
                    {"type": "if", "name": "Status Check"},
                    {"type": "notification", "name": "Alert"}
                ],
                "pattern": "schedule → check → condition → alert"
            }
        }
        
        with open("workflow_templates.json", "w") as f:
            json.dump(templates, f, indent=2)
        
        print("✅ Created workflow templates")
        return templates
    
    def enhance_search_capabilities(self):
        """Enhance search capabilities with advanced features"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        # Add search history table
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS search_history (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                query TEXT NOT NULL,
                result_count INTEGER,
                user_identifier TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)
        
        # Add saved searches table
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS saved_searches (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                query TEXT NOT NULL,
                filters TEXT,
                user_identifier TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)
        
        conn.commit()
        conn.close()
        print("✅ Enhanced search capabilities")
    
    def create_workflow_comparison_tool(self):
        """Create workflow comparison and analysis tool"""
        comparison_features = {
            "node_comparison": "Compare node types and structures",
            "integration_comparison": "Compare integrations used",
            "complexity_comparison": "Compare workflow complexity",
            "pattern_comparison": "Compare workflow patterns",
            "performance_comparison": "Compare execution metrics"
        }
        
        with open("comparison_features.json", "w") as f:
            json.dump(comparison_features, f, indent=2)
        
        print("✅ Created workflow comparison tool")
        return comparison_features
    
    def setup_all_enhancements(self):
        """Setup all platform enhancements"""
        print("🚀 Setting up platform enhancements...")
        
        enhancements = [
            ("Analytics Tracking", self.add_workflow_analytics),
            ("Recommendation System", self.create_workflow_recommendations),
            ("Enhanced Tagging", self.add_workflow_tags_system),
            ("Version Tracking", self.create_workflow_versions_table),
            ("Performance Metrics", self.add_performance_metrics),
            ("User Feedback", self.create_user_feedback_system),
            ("Workflow Insights", self.generate_workflow_insights),
            ("Workflow Templates", self.create_workflow_templates),
            ("Enhanced Search", self.enhance_search_capabilities),
            ("Comparison Tool", self.create_workflow_comparison_tool)
        ]
        
        for name, func in enhancements:
            try:
                print(f"⚙️  Setting up {name}...")
                func()
                print(f"✅ {name} setup complete")
            except Exception as e:
                print(f"❌ Error setting up {name}: {e}")
        
        print("\n🎉 All platform enhancements setup complete!")

def main():
    """Main enhancement setup"""
    enhancer = PlatformEnhancer()
    enhancer.setup_all_enhancements()

if __name__ == "__main__":
    main()
