#!/usr/bin/env python3
"""
AI Bible Documentation Service
Self-documenting NixOS configuration analyzer and documentation generator

This service automatically:
- Scans NixOS configuration files
- Analyzes system structure and services
- Generates comprehensive documentation using local LLM
- Serves documentation via REST API
- Updates incrementally when system changes
"""

import os
import sys
import json
import yaml
import hashlib
import logging
import asyncio
import subprocess
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Optional, Any, Set
from dataclasses import dataclass, asdict
from collections import defaultdict

# FastAPI for web serving
from fastapi import FastAPI, HTTPException, BackgroundTasks
from fastapi.responses import JSONResponse, HTMLResponse
import uvicorn

# For LLM integration
import requests


#==============================================================================
# CONFIGURATION
#==============================================================================

@dataclass
class AiBibleConfig:
    """Configuration for AI Bible service"""
    port: int = 8888
    data_dir: Path = Path("/var/lib/ai-bible")
    codebase_root: Path = Path("/etc/nixos")
    exclude_paths: List[str] = None
    categories: List[str] = None
    llm_endpoint: str = "http://localhost:11434"
    llm_model: str = "llama3:8b"
    llm_enabled: bool = True

    def __post_init__(self):
        if self.exclude_paths is None:
            self.exclude_paths = [".git", "result", ".direnv", "__pycache__"]
        if self.categories is None:
            self.categories = [
                "system_architecture",
                "container_services",
                "hardware_gpu",
                "monitoring_observability",
                "storage_data",
                "networking",
                "backup"
            ]
        # Ensure paths are Path objects
        self.data_dir = Path(self.data_dir)
        self.codebase_root = Path(self.codebase_root)


#==============================================================================
# LOGGING SETUP
#==============================================================================

def setup_logging(log_dir: Path) -> logging.Logger:
    """Configure logging for AI Bible service"""
    log_dir.mkdir(parents=True, exist_ok=True)
    log_file = log_dir / f"ai-bible-{datetime.now().strftime('%Y%m%d')}.log"

    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
        handlers=[
            logging.FileHandler(log_file),
            logging.StreamHandler(sys.stdout)
        ]
    )

    return logging.getLogger("ai-bible")


#==============================================================================
# CODEBASE ANALYZER
#==============================================================================

@dataclass
class FileInfo:
    """Information about a scanned file"""
    path: Path
    relative_path: str
    content_hash: str
    size: int
    modified_time: float
    category: Optional[str] = None

    def to_dict(self) -> Dict:
        return {
            "path": str(self.path),
            "relative_path": self.relative_path,
            "content_hash": self.content_hash,
            "size": self.size,
            "modified_time": self.modified_time,
            "category": self.category
        }


class CodebaseAnalyzer:
    """Analyzes NixOS codebase structure and changes"""

    def __init__(self, config: AiBibleConfig, logger: logging.Logger):
        self.config = config
        self.logger = logger
        self.scan_cache_file = config.data_dir / "scan_cache.json"
        self.previous_scan: Dict[str, FileInfo] = {}
        self.current_scan: Dict[str, FileInfo] = {}

    def load_previous_scan(self) -> Dict[str, FileInfo]:
        """Load previous scan results from cache"""
        if not self.scan_cache_file.exists():
            return {}

        try:
            with open(self.scan_cache_file, 'r') as f:
                data = json.load(f)

            result = {}
            for path_str, info in data.items():
                result[path_str] = FileInfo(
                    path=Path(info['path']),
                    relative_path=info['relative_path'],
                    content_hash=info['content_hash'],
                    size=info['size'],
                    modified_time=info['modified_time'],
                    category=info.get('category')
                )

            self.logger.info(f"Loaded previous scan: {len(result)} files")
            return result

        except Exception as e:
            self.logger.error(f"Failed to load previous scan: {e}")
            return {}

    def save_current_scan(self):
        """Save current scan results to cache"""
        try:
            data = {
                path: info.to_dict()
                for path, info in self.current_scan.items()
            }

            with open(self.scan_cache_file, 'w') as f:
                json.dump(data, f, indent=2)

            self.logger.info(f"Saved scan cache: {len(data)} files")

        except Exception as e:
            self.logger.error(f"Failed to save scan cache: {e}")

    def should_exclude(self, path: Path) -> bool:
        """Check if path should be excluded from scanning"""
        path_str = str(path)

        for exclude in self.config.exclude_paths:
            if exclude in path_str:
                return True

        return False

    def compute_file_hash(self, file_path: Path) -> str:
        """Compute SHA256 hash of file content"""
        try:
            hasher = hashlib.sha256()
            with open(file_path, 'rb') as f:
                for chunk in iter(lambda: f.read(4096), b""):
                    hasher.update(chunk)
            return hasher.hexdigest()
        except Exception as e:
            self.logger.warning(f"Failed to hash {file_path}: {e}")
            return ""

    def categorize_file(self, relative_path: str) -> Optional[str]:
        """Determine which documentation category a file belongs to"""
        path_lower = relative_path.lower()

        # Category mapping based on path patterns
        category_patterns = {
            "system_architecture": ["modules/system", "flake.nix", "charter"],
            "container_services": ["domains/server/containers", "podman"],
            "hardware_gpu": ["hardware/gpu", "nvidia", "cuda"],
            "monitoring_observability": ["monitoring", "grafana", "prometheus"],
            "storage_data": ["storage", "backup", "zfs", "disk"],
            "networking": ["network", "firewall", "vpn", "tailscale"],
            "backup": ["backup", "restic", "borg"]
        }

        for category, patterns in category_patterns.items():
            for pattern in patterns:
                if pattern in path_lower:
                    return category

        return None

    def scan_codebase(self) -> Dict[str, List[FileInfo]]:
        """Scan codebase and detect changes"""
        self.logger.info(f"Scanning codebase: {self.config.codebase_root}")

        self.previous_scan = self.load_previous_scan()
        self.current_scan = {}

        changes_by_category = defaultdict(list)

        # Scan for .nix files
        for nix_file in self.config.codebase_root.rglob("*.nix"):
            if self.should_exclude(nix_file):
                continue

            try:
                relative_path = str(nix_file.relative_to(self.config.codebase_root))
                stat = nix_file.stat()

                file_info = FileInfo(
                    path=nix_file,
                    relative_path=relative_path,
                    content_hash=self.compute_file_hash(nix_file),
                    size=stat.st_size,
                    modified_time=stat.st_mtime,
                    category=self.categorize_file(relative_path)
                )

                self.current_scan[relative_path] = file_info

                # Check if file changed
                if relative_path in self.previous_scan:
                    prev_info = self.previous_scan[relative_path]
                    if prev_info.content_hash != file_info.content_hash:
                        if file_info.category:
                            changes_by_category[file_info.category].append(file_info)
                            self.logger.debug(f"Changed: {relative_path}")
                else:
                    # New file
                    if file_info.category:
                        changes_by_category[file_info.category].append(file_info)
                        self.logger.debug(f"New: {relative_path}")

            except Exception as e:
                self.logger.warning(f"Failed to process {nix_file}: {e}")

        # Also scan markdown docs
        for md_file in self.config.codebase_root.rglob("*.md"):
            if self.should_exclude(md_file):
                continue

            try:
                relative_path = str(md_file.relative_to(self.config.codebase_root))
                stat = md_file.stat()

                file_info = FileInfo(
                    path=md_file,
                    relative_path=relative_path,
                    content_hash=self.compute_file_hash(md_file),
                    size=stat.st_size,
                    modified_time=stat.st_mtime,
                    category=self.categorize_file(relative_path)
                )

                self.current_scan[relative_path] = file_info

            except Exception as e:
                self.logger.warning(f"Failed to process {md_file}: {e}")

        self.save_current_scan()

        self.logger.info(f"Scan complete: {len(self.current_scan)} files, "
                        f"{sum(len(v) for v in changes_by_category.values())} changes")

        return dict(changes_by_category)


#==============================================================================
# LLM INTEGRATION
#==============================================================================

class LLMClient:
    """Client for interacting with local LLM (Ollama)"""

    def __init__(self, config: AiBibleConfig, logger: logging.Logger):
        self.config = config
        self.logger = logger
        self.endpoint = f"{config.llm_endpoint}/api/generate"
        self.model = config.llm_model

    def test_connection(self) -> bool:
        """Test if LLM is accessible"""
        try:
            response = requests.get(
                f"{self.config.llm_endpoint}/api/tags",
                timeout=5
            )
            response.raise_for_status()

            models = response.json().get("models", [])
            model_names = [m["name"] for m in models]

            if self.model in model_names:
                self.logger.info(f"LLM connection OK: {self.model}")
                return True
            else:
                self.logger.warning(f"Model {self.model} not found. Available: {model_names}")
                return False

        except Exception as e:
            self.logger.error(f"LLM connection failed: {e}")
            return False

    def generate(self, prompt: str, system_prompt: Optional[str] = None,
                 max_tokens: int = 4096) -> Optional[str]:
        """Generate text using LLM"""
        if not self.config.llm_enabled:
            return None

        payload = {
            "model": self.model,
            "prompt": prompt,
            "stream": False,
            "options": {
                "temperature": 0.3,
                "top_p": 0.9,
                "num_ctx": max_tokens
            }
        }

        if system_prompt:
            payload["system"] = system_prompt

        try:
            self.logger.debug(f"Generating with LLM (prompt length: {len(prompt)})")

            response = requests.post(
                self.endpoint,
                json=payload,
                timeout=120
            )
            response.raise_for_status()

            result = response.json()["response"].strip()
            self.logger.debug(f"Generated {len(result)} characters")

            return result

        except Exception as e:
            self.logger.error(f"LLM generation failed: {e}")
            return None


#==============================================================================
# DOCUMENTATION GENERATOR
#==============================================================================

class DocumentationGenerator:
    """Generates documentation for different categories"""

    def __init__(self, config: AiBibleConfig, llm_client: LLMClient,
                 logger: logging.Logger):
        self.config = config
        self.llm = llm_client
        self.logger = logger
        self.docs_dir = config.data_dir / "documentation"
        self.docs_dir.mkdir(parents=True, exist_ok=True)

    def read_file_content(self, file_path: Path, max_lines: int = 500) -> str:
        """Read file content safely"""
        try:
            with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
                lines = f.readlines()[:max_lines]
                return ''.join(lines)
        except Exception as e:
            self.logger.warning(f"Failed to read {file_path}: {e}")
            return ""

    def generate_category_prompt(self, category: str,
                                 files: List[FileInfo]) -> str:
        """Generate prompt for documenting a category"""

        # Collect file contents
        file_contents = []
        for file_info in files[:20]:  # Limit to 20 files to avoid token limits
            content = self.read_file_content(file_info.path, max_lines=200)
            if content:
                file_contents.append(f"### File: {file_info.relative_path}\n```\n{content}\n```\n")

        combined_content = "\n".join(file_contents)

        prompt = f"""Analyze the following NixOS configuration files for the {category} category and generate comprehensive technical documentation.

Files to analyze:
{combined_content}

Please create documentation that includes:
1. **Overview**: What this category covers in this NixOS system
2. **Key Components**: List main modules, services, or configurations
3. **Configuration Details**: Important settings and their purposes
4. **Dependencies**: What other parts of the system this relies on
5. **Usage**: How to interact with or modify this configuration

Format the response as clean markdown suitable for technical documentation.
Focus on facts from the code - don't speculate."""

        return prompt

    def generate_category_doc(self, category: str,
                             changed_files: List[FileInfo]) -> Optional[str]:
        """Generate documentation for a category"""
        self.logger.info(f"Generating documentation for: {category}")

        # Get all files in this category (not just changed)
        all_category_files = []
        for file_info in self.config.data_dir.glob("**/*"):
            # This would need to query the analyzer's current_scan
            # For now, use changed files
            pass

        prompt = self.generate_category_prompt(category, changed_files)

        system_prompt = """You are a technical documentation expert specializing in NixOS configurations.
Generate clear, accurate, factual documentation based on the provided configuration files.
Use markdown formatting. Be concise but comprehensive."""

        doc_content = self.llm.generate(prompt, system_prompt)

        if doc_content:
            # Save to file
            doc_file = self.docs_dir / f"{category}.md"

            header = f"""# {category.replace('_', ' ').title()}

**Generated**: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
**Files Analyzed**: {len(changed_files)}
**Auto-generated by AI Bible System**

---

"""

            full_content = header + doc_content

            try:
                with open(doc_file, 'w') as f:
                    f.write(full_content)

                self.logger.info(f"Saved documentation: {doc_file}")
                return full_content

            except Exception as e:
                self.logger.error(f"Failed to save documentation: {e}")
                return None

        return None

    def get_category_doc(self, category: str) -> Optional[str]:
        """Retrieve existing documentation for a category"""
        doc_file = self.docs_dir / f"{category}.md"

        if not doc_file.exists():
            return None

        try:
            with open(doc_file, 'r') as f:
                return f.read()
        except Exception as e:
            self.logger.error(f"Failed to read {doc_file}: {e}")
            return None

    def list_categories(self) -> List[Dict[str, Any]]:
        """List all documented categories with metadata"""
        categories = []

        for doc_file in self.docs_dir.glob("*.md"):
            try:
                stat = doc_file.stat()
                category_name = doc_file.stem

                categories.append({
                    "name": category_name,
                    "display_name": category_name.replace('_', ' ').title(),
                    "file": str(doc_file),
                    "size": stat.st_size,
                    "modified": datetime.fromtimestamp(stat.st_mtime).isoformat()
                })
            except Exception as e:
                self.logger.warning(f"Failed to process {doc_file}: {e}")

        return sorted(categories, key=lambda x: x['name'])


#==============================================================================
# WEB API
#==============================================================================

class AiBibleAPI:
    """FastAPI application for AI Bible service"""

    def __init__(self, config: AiBibleConfig, analyzer: CodebaseAnalyzer,
                 generator: DocumentationGenerator, logger: logging.Logger):
        self.config = config
        self.analyzer = analyzer
        self.generator = generator
        self.logger = logger

        self.app = FastAPI(
            title="AI Bible Documentation API",
            description="Self-documenting NixOS configuration system",
            version="2.0.0"
        )

        self._setup_routes()

    def _setup_routes(self):
        """Setup API routes"""

        @self.app.get("/")
        async def root():
            """API root - return HTML documentation viewer"""
            return HTMLResponse(self._get_web_ui())

        @self.app.get("/api/categories")
        async def list_categories():
            """List all documentation categories"""
            categories = self.generator.list_categories()
            return JSONResponse({"categories": categories})

        @self.app.get("/api/category/{category_name}")
        async def get_category(category_name: str):
            """Get documentation for a specific category"""
            doc = self.generator.get_category_doc(category_name)

            if doc is None:
                raise HTTPException(status_code=404, detail="Category not found")

            return JSONResponse({
                "category": category_name,
                "content": doc
            })

        @self.app.post("/api/scan")
        async def trigger_scan(background_tasks: BackgroundTasks):
            """Trigger a codebase scan"""
            background_tasks.add_task(self._background_scan)
            return JSONResponse({"status": "scan_started"})

        @self.app.get("/api/status")
        async def get_status():
            """Get service status"""
            return JSONResponse({
                "status": "running",
                "config": {
                    "codebase_root": str(self.config.codebase_root),
                    "llm_enabled": self.config.llm_enabled,
                    "llm_model": self.config.llm_model
                },
                "stats": {
                    "categories": len(self.generator.list_categories()),
                    "data_dir": str(self.config.data_dir)
                }
            })

    def _background_scan(self):
        """Run codebase scan in background"""
        try:
            self.logger.info("Starting background scan")
            changes = self.analyzer.scan_codebase()

            # Generate docs for changed categories
            for category, files in changes.items():
                if category in self.config.categories:
                    self.generator.generate_category_doc(category, files)

            self.logger.info("Background scan complete")

        except Exception as e:
            self.logger.error(f"Background scan failed: {e}")

    def _get_web_ui(self) -> str:
        """Generate simple web UI for browsing documentation"""
        return """
<!DOCTYPE html>
<html>
<head>
    <title>AI Bible Documentation</title>
    <style>
        body { font-family: system-ui; max-width: 1200px; margin: 0 auto; padding: 20px; }
        h1 { color: #333; }
        .category { background: #f5f5f5; padding: 15px; margin: 10px 0; border-radius: 5px; cursor: pointer; }
        .category:hover { background: #e5e5e5; }
        .content { background: white; padding: 20px; border: 1px solid #ddd; margin: 10px 0; }
        pre { background: #f8f8f8; padding: 10px; overflow-x: auto; }
        .btn { background: #4CAF50; color: white; padding: 10px 20px; border: none; cursor: pointer; border-radius: 4px; }
        .btn:hover { background: #45a049; }
    </style>
</head>
<body>
    <h1>🔮 AI Bible Documentation</h1>
    <p>Self-documenting NixOS configuration system</p>

    <button class="btn" onclick="triggerScan()">Scan Now</button>
    <button class="btn" onclick="loadCategories()">Refresh</button>

    <div id="categories"></div>
    <div id="content"></div>

    <script>
        async function loadCategories() {
            const response = await fetch('/api/categories');
            const data = await response.json();

            const html = data.categories.map(cat =>
                `<div class="category" onclick="loadCategory('${cat.name}')">
                    <strong>${cat.display_name}</strong><br>
                    <small>Modified: ${new Date(cat.modified).toLocaleString()}</small>
                </div>`
            ).join('');

            document.getElementById('categories').innerHTML = html;
        }

        async function loadCategory(name) {
            const response = await fetch(`/api/category/${name}`);
            const data = await response.json();

            // Simple markdown rendering (would use marked.js in production)
            const content = data.content.replace(/```/g, '<pre>').replace(/```/g, '</pre>');

            document.getElementById('content').innerHTML =
                `<div class="content"><h2>${name}</h2>${content}</div>`;
        }

        async function triggerScan() {
            await fetch('/api/scan', { method: 'POST' });
            alert('Scan started! Refresh in a moment to see updates.');
        }

        // Load categories on page load
        loadCategories();
    </script>
</body>
</html>
        """


#==============================================================================
# MAIN SERVICE
#==============================================================================

class AiBibleService:
    """Main AI Bible service coordinator"""

    def __init__(self, config: AiBibleConfig):
        self.config = config
        self.logger = setup_logging(config.data_dir / "logs")

        self.logger.info("=== AI Bible Service Starting ===")
        self.logger.info(f"Codebase: {config.codebase_root}")
        self.logger.info(f"Data Dir: {config.data_dir}")

        # Initialize components
        self.analyzer = CodebaseAnalyzer(config, self.logger)
        self.llm = LLMClient(config, self.logger)
        self.generator = DocumentationGenerator(config, self.llm, self.logger)
        self.api = AiBibleAPI(config, self.analyzer, self.generator, self.logger)

    def startup(self):
        """Service startup tasks"""
        self.logger.info("Running startup tasks...")

        # Test LLM connection if enabled
        if self.config.llm_enabled:
            if not self.llm.test_connection():
                self.logger.warning("LLM not available - documentation generation disabled")
                self.config.llm_enabled = False

        # Initial scan on startup
        try:
            changes = self.analyzer.scan_codebase()
            self.logger.info(f"Initial scan found {sum(len(v) for v in changes.values())} changes")

            # Generate docs for changed categories if LLM available
            if self.config.llm_enabled:
                for category, files in changes.items():
                    if category in self.config.categories and len(files) > 0:
                        self.generator.generate_category_doc(category, files)

        except Exception as e:
            self.logger.error(f"Startup scan failed: {e}")

    def run(self):
        """Run the web service"""
        self.startup()

        self.logger.info(f"Starting web server on port {self.config.port}")

        uvicorn.run(
            self.api.app,
            host="0.0.0.0",
            port=self.config.port,
            log_level="info"
        )


#==============================================================================
# ENTRY POINT
#==============================================================================

def main():
    """Main entry point"""

    # Load config from environment variables
    config = AiBibleConfig(
        port=int(os.getenv("BIBLE_PORT", "8888")),
        data_dir=Path(os.getenv("BIBLE_DATA_DIR", "/var/lib/ai-bible")),
        codebase_root=Path(os.getenv("BIBLE_CODEBASE_ROOT", "/etc/nixos")),
        llm_endpoint=os.getenv("BIBLE_LLM_ENDPOINT", "http://localhost:11434"),
        llm_model=os.getenv("BIBLE_LLM_MODEL", "llama3:8b"),
        llm_enabled=os.getenv("BIBLE_LLM_ENABLED", "true").lower() == "true"
    )

    # Parse categories from env
    categories_str = os.getenv("BIBLE_CATEGORIES", "")
    if categories_str:
        config.categories = [c.strip() for c in categories_str.split(",")]

    # Create service and run
    service = AiBibleService(config)

    try:
        service.run()
    except KeyboardInterrupt:
        service.logger.info("Service stopped by user")
    except Exception as e:
        service.logger.error(f"Service failed: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
