"""
Configuration Module
====================

Handles configuration for the receipt OCR service.
Reads from environment variables and provides defaults.
"""

import os
from pathlib import Path
from typing import Optional

class Config:
    """Configuration for receipt OCR service"""

    def __init__(self):
        # Database configuration
        self.database_url = os.getenv(
            'DATABASE_URL',
            'postgresql://business_user:password@localhost:5432/heartwood_business'
        )

        # Ollama configuration
        self.ollama_enabled = os.getenv('OLLAMA_ENABLED', 'true').lower() == 'true'
        self.ollama_url = os.getenv('OLLAMA_URL', 'http://localhost:11434')
        self.ollama_model = os.getenv('OLLAMA_MODEL', 'llama3.2')

        # OCR configuration
        self.confidence_threshold = float(os.getenv('OCR_CONFIDENCE_THRESHOLD', '0.7'))

        # Storage paths
        self.storage_root = Path(os.getenv('STORAGE_ROOT', '/hot/receipts'))
        self.upload_path = self.storage_root / 'raw'
        self.processed_path = self.storage_root / 'processed'
        self.failed_path = self.storage_root / 'failed'

        # Ensure directories exist
        self.upload_path.mkdir(parents=True, exist_ok=True)
        self.processed_path.mkdir(parents=True, exist_ok=True)
        self.failed_path.mkdir(parents=True, exist_ok=True)

        # Service configuration
        self.api_host = os.getenv('API_HOST', '0.0.0.0')
        self.api_port = int(os.getenv('API_PORT', '8001'))

        # Notification configuration
        self.ntfy_enabled = os.getenv('NTFY_ENABLED', 'false').lower() == 'true'
        self.ntfy_url = os.getenv('NTFY_URL', 'https://ntfy.sh')
        self.ntfy_topic = os.getenv('NTFY_TOPIC', 'receipts')

    def get_upload_path(self) -> Path:
        """Get upload path with date-based subdirectory"""
        from datetime import datetime
        date_path = self.upload_path / datetime.now().strftime('%Y/%m')
        date_path.mkdir(parents=True, exist_ok=True)
        return date_path

    def get_processed_path(self) -> Path:
        """Get processed path with date-based subdirectory"""
        from datetime import datetime
        date_path = self.processed_path / datetime.now().strftime('%Y/%m')
        date_path.mkdir(parents=True, exist_ok=True)
        return date_path

    def get_failed_path(self) -> Path:
        """Get failed path with date-based subdirectory"""
        from datetime import datetime
        date_path = self.failed_path / datetime.now().strftime('%Y/%m')
        date_path.mkdir(parents=True, exist_ok=True)
        return date_path

    def __repr__(self):
        return f"""Config(
    database_url={self.database_url},
    ollama_enabled={self.ollama_enabled},
    ollama_url={self.ollama_url},
    storage_root={self.storage_root},
    api_port={self.api_port}
)"""
