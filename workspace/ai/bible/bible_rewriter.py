#!/usr/bin/env python3
"""
AI Bible Rewriting Engine
Intelligently updates bible documentation files by integrating accumulated changes
while preserving critical technical content and maintaining accuracy.
"""

import json
import re
import sys
import shutil
import subprocess
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Optional, Tuple, Any
import requests
import yaml
import importlib.util

# Configuration
BIBLE_CONFIG_PATH = Path("/etc/nixos/config/bible_categories.yaml")
BIBLES_DIR = Path("/etc/nixos/docs/bibles")
PROMPTS_DIR = Path("/etc/nixos/prompts/bible_prompts")
BACKUPS_DIR = Path("/etc/nixos/docs/bibles/backups")
LOG_FILE = Path("/etc/nixos/docs/bible-rewriter.log")

class BibleRewritingError(Exception):
    """Custom exception for bible rewriting failures"""
    pass

class ContentPreservationError(Exception):
    """Exception for content preservation failures"""
    pass

class ValidationError(Exception):
    """Exception for content validation failures"""
    pass

class BibleRewriter:
    def __init__(self):
        self.ollama_url = "http://localhost:11434/api/generate"
        self.model = "llama3.2:3b"
        self.bible_config = self._load_bible_config()
        self.backups_dir = BACKUPS_DIR
        self.backups_dir.mkdir(exist_ok=True)
        
    def _load_bible_config(self) -> Dict[str, Any]:
        """Load bible configuration from YAML file"""
        try:
            with open(BIBLE_CONFIG_PATH, 'r') as f:
                return yaml.safe_load(f)
        except Exception as e:
            raise BibleRewritingError(f"Failed to load bible configuration: {e}")
    
    def _log(self, message: str, level: str = "INFO"):
        """Log message with timestamp"""
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        log_message = f"[{timestamp}] {level}: {message}\n"
        
        with open(LOG_FILE, 'a') as f:
            f.write(log_message)
        
        print(f"{level}: {message}")
    
    def _load_prompt_templates(self, bible_type: str) -> Dict[str, str]:
        """Load AI prompt templates for specific bible type"""
        prompt_file = PROMPTS_DIR / f"{bible_type}_prompts.py"
        
        if not prompt_file.exists():
            raise BibleRewritingError(f"Prompt templates not found for bible type: {bible_type}")
        
        try:
            spec = importlib.util.spec_from_file_location("prompt_templates", prompt_file)
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            return module.PROMPT_TEMPLATES
        except Exception as e:
            raise BibleRewritingError(f"Failed to load prompt templates for {bible_type}: {e}")
    
    def _call_ollama(self, prompt: str, system_prompt: str = None) -> str:
        """Call local Ollama API for AI analysis"""
        payload = {
            "model": self.model,
            "prompt": prompt,
            "stream": False,
            "options": {
                "temperature": 0.2,  # Low temperature for consistent technical writing
                "top_p": 0.9,
                "num_ctx": 4096,  # Max context for llama3.2:3b
                "stop": ["```\n\n\n", "---\n\n"]  # Prevent runaway generation
            }
        }
        
        if system_prompt:
            payload["system"] = system_prompt
            
        try:
            self._log(f"Calling Ollama with model {self.model}...")
            response = requests.post(self.ollama_url, json=payload, timeout=300)  # 5 minute timeout
            response.raise_for_status()
            result = response.json()["response"].strip()
            self._log(f"AI analysis complete ({len(result)} chars)")
            return result
        except requests.exceptions.Timeout:
            raise BibleRewritingError("AI model request timed out")
        except requests.exceptions.ConnectionError:
            raise BibleRewritingError("Cannot connect to Ollama service")
        except Exception as e:
            raise BibleRewritingError(f"Ollama API call failed: {e}")
    
    def _test_ollama_connection(self) -> bool:
        """Test if Ollama is accessible and model is available"""
        try:
            # Test basic connectivity
            response = requests.get("http://localhost:11434/api/tags", timeout=10)
            response.raise_for_status()
            
            # Check if our model is available
            models = response.json()
            available_models = [model["name"] for model in models.get("models", [])]
            
            if self.model not in available_models:
                raise BibleRewritingError(f"Model {self.model} not available. Available: {available_models}")
            
            self._log("Ollama connection test successful")
            return True
            
        except Exception as e:
            raise BibleRewritingError(f"Ollama connection test failed: {e}")
    
    def _extract_critical_content(self, content: str, bible_type: str) -> Dict[str, List[str]]:
        """Extract critical content that must be preserved during rewriting"""
        preservation_patterns = {
            "exact_commands": [
                r"```bash\n.*?\n```",
                r"`[^`]+`",
                r"sudo [^\n]+"
            ],
            "configuration_blocks": [
                r"```(?:yaml|json|toml|nix).*?```",
                r"```\n(?:.*?=.*?\n)+```"
            ],
            "technical_specifications": [
                r"- \*\*[^*]+\*\*: [^\n]+",
                r"\| [^|]+ \| [^|]+ \|",
                r"NVIDIA.*?P1000.*?Pascal"
            ],
            "file_paths": [
                r"/[a-zA-Z0-9/_.-]+",
                r"`/[^`]+`"
            ],
            "service_names": [
                r"podman-[a-zA-Z0-9-]+\.service",
                r"systemd.*?\.service"
            ]
        }
        
        # Bible-specific critical patterns
        if bible_type == "hardware_gpu":
            preservation_patterns["gpu_specific"] = [
                r"/dev/nvidia[^\\s]*",
                r"NVIDIA_[A-Z_]+",
                r"Pascal.*?architecture",
                r"Compute Capability 6\.1",
                r"4GB VRAM"
            ]
        elif bible_type == "container_services":
            preservation_patterns["container_specific"] = [
                r"podman run.*?--[^\n]*",
                r"systemctl.*?podman-[^\s]*",
                r"--network[=\s][^\s]*",
                r"--device[=\s][^\s]*"
            ]
        
        extracted_content = {}
        
        for category, patterns in preservation_patterns.items():
            extracted_content[category] = []
            for pattern in patterns:
                matches = re.findall(pattern, content, re.DOTALL | re.IGNORECASE)
                extracted_content[category].extend(matches)
        
        self._log(f"Extracted {sum(len(v) for v in extracted_content.values())} critical content items")
        return extracted_content
    
    def _analyze_change_impact(self, changes: List[Dict], bible_type: str) -> Dict[str, Any]:
        """Analyze the impact and significance of accumulated changes"""
        impact_analysis = {
            "total_changes": len(changes),
            "significance_score": 0.0,
            "change_types": set(),
            "affected_sections": set(),
            "requires_validation": False
        }
        
        for change in changes:
            # Accumulate significance scores
            impact_analysis["significance_score"] += change.get("significance", 0.0)
            
            # Track change types
            impact_analysis["change_types"].add(change.get("change_type", "unknown"))
            
            # Track affected sections
            if "sections" in change:
                impact_analysis["affected_sections"].update(change["sections"])
            
            # Determine if changes require cross-bible validation
            if change.get("change_type") in ["service_add", "network_change", "security_update"]:
                impact_analysis["requires_validation"] = True
        
        # Convert sets to lists for JSON serialization
        impact_analysis["change_types"] = list(impact_analysis["change_types"])
        impact_analysis["affected_sections"] = list(impact_analysis["affected_sections"])
        
        self._log(f"Change impact analysis: {impact_analysis['total_changes']} changes, "
                 f"significance {impact_analysis['significance_score']:.2f}")
        
        return impact_analysis
    
    def _determine_integration_strategy(self, impact_analysis: Dict[str, Any]) -> str:
        """Determine the best strategy for integrating changes"""
        if impact_analysis["significance_score"] > 50:
            return "comprehensive_rewrite"
        elif impact_analysis["total_changes"] > 10:
            return "section_updates"
        elif "config_change" in impact_analysis["change_types"]:
            return "targeted_updates"
        else:
            return "incremental_updates"
    
    def _create_bible_backup(self, bible_name: str) -> Path:
        """Create timestamped backup of bible before rewriting"""
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        backup_filename = f"{bible_name}_{timestamp}.md"
        backup_path = self.backups_dir / backup_filename
        
        bible_path = BIBLES_DIR / f"{bible_name}.md"
        
        if bible_path.exists():
            shutil.copy2(bible_path, backup_path)
            self._log(f"Created backup: {backup_path}")
        else:
            # Create empty backup for new bibles
            backup_path.touch()
            self._log(f"Created empty backup for new bible: {backup_path}")
        
        return backup_path
    
    def _restore_from_backup(self, bible_name: str, backup_path: Path):
        """Restore bible from backup in case of rewriting failure"""
        bible_path = BIBLES_DIR / f"{bible_name}.md"
        
        if backup_path.exists():
            shutil.copy2(backup_path, bible_path)
            self._log(f"Restored {bible_name} from backup: {backup_path}")
        else:
            self._log(f"Warning: Backup {backup_path} not found for restore")
    
    def _validate_technical_accuracy(self, content: str, bible_type: str) -> Dict[str, Any]:
        """Validate technical accuracy of rewritten content"""
        validation_results = {
            "passed": True,
            "accuracy_score": 100,
            "issues": []
        }
        
        # Bible-specific validation checks
        if bible_type == "hardware_gpu":
            # Check for required GPU technical details
            if "Pascal" not in content:
                validation_results["issues"].append("Missing Pascal architecture reference")
            if "4GB VRAM" not in content:
                validation_results["issues"].append("Missing VRAM specification")
            if "/dev/nvidia" not in content:
                validation_results["issues"].append("Missing GPU device paths")
                
        elif bible_type == "container_services":
            # Check for required container technical details
            if "podman" not in content.lower():
                validation_results["issues"].append("Missing Podman references")
            if "systemd" not in content.lower():
                validation_results["issues"].append("Missing systemd integration")
                
        elif bible_type == "storage_data":
            # Check for required storage technical details
            if "/mnt/hot" not in content:
                validation_results["issues"].append("Missing hot storage path")
            if "/mnt/media" not in content:
                validation_results["issues"].append("Missing cold storage path")
        
        # General validation checks
        if len(content) < 1000:
            validation_results["issues"].append("Content too short - may be incomplete")
        
        if "TODO" in content or "FIXME" in content:
            validation_results["issues"].append("Content contains TODO/FIXME markers")
        
        # Calculate accuracy score based on issues
        if validation_results["issues"]:
            validation_results["passed"] = False
            validation_results["accuracy_score"] = max(0, 100 - len(validation_results["issues"]) * 20)
        
        return validation_results
    
    def _apply_ai_rewriting(self, bible_type: str, existing_content: str, 
                          accumulated_changes: List[Dict], preserved_content: Dict,
                          integration_strategy: str) -> str:
        """Apply AI rewriting with specified strategy"""
        
        prompt_templates = self._load_prompt_templates(bible_type)
        
        # Format changes for the prompt
        changes_text = json.dumps(accumulated_changes, indent=2)
        
        # Use the appropriate rewrite prompt
        prompt = prompt_templates["rewrite_prompt"].format(
            accumulated_changes=changes_text,
            existing_content=existing_content[:3000]  # Limit context size
        )
        
        system_prompt = prompt_templates["system_prompt"]
        
        try:
            updated_content = self._call_ollama(prompt, system_prompt)
            
            # Validate that critical content is preserved
            self._validate_content_preservation(updated_content, preserved_content)
            
            return updated_content
            
        except Exception as e:
            raise BibleRewritingError(f"AI rewriting failed: {e}")
    
    def _validate_content_preservation(self, updated_content: str, preserved_content: Dict):
        """Validate that critical content was preserved in the update"""
        missing_content = []
        
        for category, content_items in preserved_content.items():
            for item in content_items:
                if item not in updated_content:
                    missing_content.append(f"{category}: {item[:50]}...")
        
        if missing_content:
            raise ContentPreservationError(
                f"Critical content missing from update: {missing_content}"
            )
    
    def rewrite_bible(self, bible_name: str, accumulated_changes: List[Dict]) -> Dict[str, Any]:
        """
        Main method to rewrite a bible with accumulated changes
        Returns update results and metrics
        """
        start_time = datetime.now()
        
        try:
            self._log(f"Starting bible rewrite: {bible_name}")
            
            # Test Ollama connection
            self._test_ollama_connection()
            
            # Load bible configuration
            bible_config = self.bible_config["bible_categories"].get(bible_name)
            if not bible_config:
                raise BibleRewritingError(f"No configuration found for bible: {bible_name}")
            
            # Create backup
            backup_path = self._create_bible_backup(bible_name)
            
            # Load existing content
            bible_path = BIBLES_DIR / f"{bible_config['filename']}"
            existing_content = ""
            if bible_path.exists():
                with open(bible_path, 'r') as f:
                    existing_content = f.read()
            
            # Extract critical content to preserve
            preserved_content = self._extract_critical_content(existing_content, bible_name)
            
            # Analyze change impact
            change_analysis = self._analyze_change_impact(accumulated_changes, bible_name)
            
            # Determine integration strategy
            integration_strategy = self._determine_integration_strategy(change_analysis)
            
            self._log(f"Using integration strategy: {integration_strategy}")
            
            # Apply AI rewriting
            updated_content = self._apply_ai_rewriting(
                bible_name, existing_content, accumulated_changes, 
                preserved_content, integration_strategy
            )
            
            # Validate technical accuracy
            validation_results = self._validate_technical_accuracy(updated_content, bible_name)
            
            if not validation_results["passed"]:
                raise ValidationError(f"Validation failed: {validation_results['issues']}")
            
            # Write updated content
            BIBLES_DIR.mkdir(exist_ok=True)
            with open(bible_path, 'w') as f:
                f.write(updated_content)
            
            duration = (datetime.now() - start_time).total_seconds()
            
            result = {
                "bible_name": bible_name,
                "update_success": True,
                "changes_integrated": len(accumulated_changes),
                "content_preserved": len(sum(preserved_content.values(), [])),
                "validation_results": validation_results,
                "backup_path": str(backup_path),
                "update_duration": duration,
                "integration_strategy": integration_strategy
            }
            
            self._log(f"Bible rewrite completed successfully: {bible_name} ({duration:.2f}s)")
            return result
            
        except Exception as e:
            # Restore from backup on failure
            self._restore_from_backup(bible_name, backup_path)
            
            duration = (datetime.now() - start_time).total_seconds()
            
            result = {
                "bible_name": bible_name,
                "update_success": False,
                "error": str(e),
                "backup_path": str(backup_path),
                "update_duration": duration
            }
            
            self._log(f"Bible rewrite failed: {bible_name} - {e}", "ERROR")
            return result
    
    def rewrite_multiple_bibles(self, bible_changes: Dict[str, List[Dict]]) -> List[Dict[str, Any]]:
        """Rewrite multiple bibles with their respective accumulated changes"""
        results = []
        
        for bible_name, changes in bible_changes.items():
            if changes:  # Only rewrite if there are changes
                result = self.rewrite_bible(bible_name, changes)
                results.append(result)
        
        return results

def main():
    """CLI interface for bible rewriting"""
    import argparse
    
    parser = argparse.ArgumentParser(description="AI Bible Rewriting Engine")
    parser.add_argument("--bible", required=True, help="Bible name to rewrite")
    parser.add_argument("--changes", required=True, help="JSON file with accumulated changes")
    parser.add_argument("--test", action="store_true", help="Test mode - don't write changes")
    
    args = parser.parse_args()
    
    try:
        # Load accumulated changes
        with open(args.changes, 'r') as f:
            changes = json.load(f)
        
        rewriter = BibleRewriter()
        
        if args.test:
            print("Test mode - validating configuration...")
            rewriter._test_ollama_connection()
            print("Configuration valid")
        else:
            result = rewriter.rewrite_bible(args.bible, changes)
            print(json.dumps(result, indent=2))
            
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()