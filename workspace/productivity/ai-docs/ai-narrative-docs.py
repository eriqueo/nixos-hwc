#!/usr/bin/env python3
# AI-Enhanced Documentation Generator for NixOS
# Uses local Ollama for intelligent commit analysis

import json
import re
import subprocess
from pathlib import Path
from datetime import datetime
import requests

class AIDocumentationGenerator:
    def __init__(self):
        self.changelog_path = Path("/etc/nixos/docs/SYSTEM_CHANGELOG.md")
        self.docs_path = Path("/etc/nixos/docs")
        self.ollama_url = "http://localhost:11434/api/generate"
        self.model = "llama3.2:3b"  # Fast local model for hwc-server
        
    def call_ollama(self, prompt, system_prompt=None):
        """Call local Ollama API for AI analysis"""
        payload = {
            "model": self.model,
            "prompt": prompt,
            "stream": False,
            "options": {
                "temperature": 0.3,  # Low temperature for consistent technical writing
                "top_p": 0.9,
                "num_ctx": 4096  # Larger context for code analysis
            }
        }
        
        if system_prompt:
            payload["system"] = system_prompt
            
        try:
            print(f"🤖 Calling Ollama with model {self.model}...")
            response = requests.post(self.ollama_url, json=payload, timeout=60)
            response.raise_for_status()
            result = response.json()["response"].strip()
            print(f"✅ AI analysis complete ({len(result)} chars)")
            return result
        except Exception as e:
            print(f"⚠️ Ollama call failed: {e}")
            return None
    
    def test_ollama_connection(self):
        """Test if Ollama is accessible and model is available"""
        try:
            # Test basic connectivity
            test_response = requests.get("http://localhost:11434/api/tags", timeout=10)
            test_response.raise_for_status()
            
            models = test_response.json().get("models", [])
            available_models = [m["name"] for m in models]
            
            print(f"📡 Ollama connected. Available models: {available_models}")
            
            if self.model not in available_models:
                print(f"⚠️ Model {self.model} not found. Using first available model.")
                if available_models:
                    self.model = available_models[0]
                else:
                    print("❌ No models available in Ollama")
                    return False
            
            # Test actual generation
            test_result = self.call_ollama("Say 'test successful' if you can read this.")
            return test_result is not None
            
        except Exception as e:
            print(f"❌ Ollama connection test failed: {e}")
            return False
    
    def analyze_commit_with_ai(self, commit):
        """Use AI to analyze what a commit actually does"""
        
        system_prompt = """You are a technical documentation expert for NixOS systems. 
        Analyze git commits and explain what they accomplish in clear, concise language.
        Focus on:
        - What services/containers were added/removed/modified
        - What capabilities were enhanced (GPU, storage, networking, etc.)
        - What problems were likely solved
        - Impact on system functionality
        
        Be specific and technical but readable. No emojis. Maximum 2 sentences."""
        
        commit_prompt = f"""
        Analyze this NixOS git commit:
        
        **Commit Message:** {commit['message']}
        **Files Modified:** {', '.join(commit['changes']['files_modified'][:5])}
        
        **Key Changes in Diff:**
        {self.extract_key_changes(commit['diff'])}
        
        Provide a concise technical summary of what this commit accomplishes.
        """
        
        analysis = self.call_ollama(commit_prompt, system_prompt)
        return analysis or f"Modified {', '.join(commit['changes']['files_modified'][:3])}"
    
    def extract_key_changes(self, diff_content):
        """Extract most important lines from diff for AI analysis"""
        lines = diff_content.split('\n')
        key_lines = []
        
        for line in lines:
            # Include important additions/removals
            if line.startswith('+') or line.startswith('-'):
                # Skip file headers and minor changes
                if not any(skip in line for skip in ['+++', '---', '@@', 'index ']):
                    stripped = line[1:].strip()
                    if len(stripped) > 10:  # Ignore very short lines
                        key_lines.append(line)
                        
                if len(key_lines) >= 20:  # Limit to most important changes
                    break
        
        return '\n'.join(key_lines)
    
    def generate_system_evolution_narrative(self, commits):
        """Generate a narrative about system evolution"""
        
        system_prompt = """You are documenting the evolution of a NixOS homeserver system.
        Create a narrative summary showing how the system has grown and improved.
        Focus on major capabilities, architectural decisions, and system maturity.
        Write in a technical but engaging style. Maximum 4 sentences."""
        
        # Prepare commit summaries
        commit_summaries = []
        for commit in commits[:8]:  # Last 8 commits for context
            summary = f"- {commit['message']} (modified: {', '.join(commit['changes']['files_modified'][:2])})"
            commit_summaries.append(summary)
        
        evolution_prompt = f"""
        Based on these recent NixOS commits, write a narrative about how this homeserver system has evolved:
        
        {chr(10).join(commit_summaries)}
        
        Highlight key improvements in capabilities like containerization, GPU acceleration, monitoring, or storage management.
        """
        
        narrative = self.call_ollama(evolution_prompt, system_prompt)
        return narrative or "System continues to evolve with ongoing improvements to containerization and service management."
    
    def generate_technical_summary(self, commits):
        """Generate technical summary for system primer"""
        
        # Analyze changes by category
        categories = {
            'containers': [],
            'gpu': [],
            'monitoring': [],
            'storage': [],
            'security': [],
            'services': []
        }
        
        for commit in commits:
            changes = commit['changes']
            if changes['containers_added']:
                categories['containers'].extend(changes['containers_added'])
            if changes['gpu_changes']:
                categories['gpu'].append(commit['message'])
            if changes['monitoring_changes']:
                categories['monitoring'].append(commit['message'])
            if changes['storage_changes']:
                categories['storage'].append(commit['message'])
            if changes['security_changes']:
                categories['security'].append(commit['message'])
            if changes['services_added']:
                categories['services'].extend(changes['services_added'])
        
        system_prompt = """You are a NixOS system administrator creating status updates.
        Generate concise bullet points about recent system improvements.
        Be specific about technical capabilities added. Use appropriate emojis for categories.
        Maximum 6 bullet points."""
        
        summary_prompt = f"""
        Generate bullet points summarizing recent NixOS system improvements:
        
        **Containers Added:** {', '.join(set(categories['containers'])) or 'None'}
        **Services Added:** {', '.join(set(categories['services'])) or 'None'}
        **GPU Updates:** {len(categories['gpu'])} commits
        **Monitoring Updates:** {len(categories['monitoring'])} commits
        **Storage Updates:** {len(categories['storage'])} commits
        **Security Updates:** {len(categories['security'])} commits
        
        Format as markdown bullet points with emojis.
        """
        
        summary = self.call_ollama(summary_prompt, system_prompt)
        return summary or "- ✅ System continues operating with recent configuration updates"
    
    def update_documentation_with_ai(self, commits):
        """Update multiple documentation files with AI insights"""
        
        if not commits:
            print("No commits to analyze")
            return
            
        print(f"🤖 Analyzing {len(commits)} commits with Ollama AI...")
        
        # Test Ollama connection first
        if not self.test_ollama_connection():
            print("❌ Cannot connect to Ollama. Skipping AI analysis.")
            return
        
        # Generate AI-powered content
        evolution_narrative = self.generate_system_evolution_narrative(commits)
        technical_summary = self.generate_technical_summary(commits)
        
        # Update CLAUDE_CODE_SYSTEM_PRIMER.md
        self.update_system_primer(commits, evolution_narrative, technical_summary)
        
        # Update SYSTEM_CONCEPTS_AND_ARCHITECTURE.md
        self.update_architecture_docs(commits)
        
        print("✅ AI-enhanced documentation updated!")
    
    def update_system_primer(self, commits, evolution_narrative, technical_summary):
        """Update system primer with AI-generated content"""
        primer_path = self.docs_path / "CLAUDE_CODE_SYSTEM_PRIMER.md"
        if not primer_path.exists():
            print(f"⚠️ {primer_path} not found")
            return
            
        content = primer_path.read_text()
        timestamp = datetime.now().strftime('%Y-%m-%d %H:%M')
        
        # AI-generated recently completed section
        new_section = f"""### **Recently Completed** ✅ (AI-Generated: {timestamp})

**System Evolution Summary:**
{evolution_narrative}

**Recent Technical Improvements:**
{technical_summary}

**Latest Commits** (Last 7 days):
{self.format_commit_summaries(commits[:5])}"""
        
        # Replace the existing section
        pattern = r'### \*\*Recently Completed\*\* ✅.*?(?=### \*\*Known Issues\*\*|\Z)'
        content = re.sub(pattern, new_section + '\n\n', content, flags=re.DOTALL)
        
        primer_path.write_text(content)
        print(f"📝 Updated {primer_path.name} with AI insights")
    
    def format_commit_summaries(self, commits):
        """Format commits with AI analysis"""
        if not commits:
            return "- No recent changes"
            
        summaries = []
        for commit in commits:
            short_hash = commit['hash'][:8] if commit['hash'] else 'unknown'
            
            # Get AI analysis for this commit (with fallback)
            print(f"  🔍 Analyzing commit {short_hash}...")
            ai_summary = self.analyze_commit_with_ai(commit)
            
            summaries.append(f"- **{short_hash}**: {ai_summary}")
            
        return '\n'.join(summaries)
    
    def update_architecture_docs(self, commits):
        """Update architecture documentation with AI insights"""
        arch_path = self.docs_path / "SYSTEM_CONCEPTS_AND_ARCHITECTURE.md"
        if not arch_path.exists():
            print(f"⚠️ {arch_path} not found")
            return
            
        # Generate architectural insights
        system_prompt = """You are a systems architect documenting NixOS infrastructure.
        Analyze recent commits to identify architectural patterns and improvements.
        Maximum 3 sentences, focus on containerization, GPU integration, or service orchestration."""
        
        arch_prompt = f"""
        Based on these recent commits to a NixOS homeserver, identify significant architectural changes:
        
        {self.format_commits_for_analysis(commits[:5])}
        
        Write about architectural evolution, focusing on infrastructure improvements.
        """
        
        arch_insights = self.call_ollama(arch_prompt, system_prompt)
        
        if arch_insights:
            content = arch_path.read_text()
            timestamp = datetime.now().strftime('%Y-%m-%d')
            
            # Add AI insights to the overview
            ai_section = f"""
## Recent Architectural Evolution (AI-Generated: {timestamp})

{arch_insights}

---
"""
            
            # Insert after the overview section
            content = content.replace("## Table of Contents", ai_section + "## Table of Contents")
            arch_path.write_text(content)
            print(f"🏗️ Updated {arch_path.name} with architectural insights")
    
    def format_commits_for_analysis(self, commits):
        """Format commits for AI analysis"""
        formatted = []
        for commit in commits:
            formatted.append(f"- {commit['message']} (files: {', '.join(commit['changes']['files_modified'][:3])})")
        return '\n'.join(formatted)
    
    def parse_recent_changes(self, days=7):
        """Parse recent commits from changelog"""
        commits = []
        
        if not self.changelog_path.exists():
            print(f"⚠️ Changelog not found at {self.changelog_path}")
            return commits
            
        content = self.changelog_path.read_text()
        commit_sections = re.split(r'^## Commit:', content, flags=re.MULTILINE)[1:]
        
        for section in commit_sections[-10:]:  # Last 10 commits
            commit = self.parse_commit_section(section)
            if commit:
                commits.append(commit)
                
        print(f"📊 Parsed {len(commits)} commits from changelog")
        return commits
    
    def parse_commit_section(self, section):
        """Extract meaningful info from a commit section"""
        lines = section.split('\n')
        commit_hash = lines[0].strip()
        date_match = re.search(r'\*\*Date:\*\* (.+)', section)
        msg_match = re.search(r'\*\*Message:\*\* (.+)', section)
        diff_match = re.search(r'```diff\n(.*?)\n```', section, re.DOTALL)
        diff_content = diff_match.group(1) if diff_match else ""
        
        return {
            'hash': commit_hash,
            'date': date_match.group(1) if date_match else None,
            'message': msg_match.group(1) if msg_match else None,
            'diff': diff_content,
            'changes': self.analyze_diff(diff_content)
        }
    
    def analyze_diff(self, diff_content):
        """Analyze diff to understand what changed"""
        changes = {
            'files_modified': [],
            'services_added': [],
            'services_removed': [],
            'containers_added': [],
            'containers_removed': [],
            'gpu_changes': False,
            'monitoring_changes': False,
            'storage_changes': False,
            'security_changes': False
        }
        
        lines = diff_content.split('\n')
        current_file = None
        
        for line in lines:
            if line.startswith('+++') or line.startswith('---'):
                file_match = re.search(r'[+-]{3} [ab]/(.+)', line)
                if file_match:
                    current_file = file_match.group(1)
                    if current_file not in changes['files_modified']:
                        changes['files_modified'].append(current_file)
            
            if line.startswith('+'):
                self.detect_additions(line, changes, current_file)
            elif line.startswith('-'):
                self.detect_removals(line, changes, current_file)
                
        return changes
    
    def detect_additions(self, line, changes, current_file):
        """Detect what was added"""
        content = line[1:].strip()
        
        if 'virtualisation.oci-containers.containers' in content:
            container_match = re.search(r'containers\.(\w+)', content)
            if container_match:
                changes['containers_added'].append(container_match.group(1))
        elif 'services.' in content and 'enable = true' in content:
            service_match = re.search(r'services\.(\w+)', content)
            if service_match:
                changes['services_added'].append(service_match.group(1))
        elif any(gpu_term in content.lower() for gpu_term in ['nvidia', 'cuda', 'gpu', 'tensorrt']):
            changes['gpu_changes'] = True
        elif any(storage_term in content for storage_term in ['/mnt/hot', '/mnt/media', 'fileSystems']):
            changes['storage_changes'] = True
        elif any(sec_term in content for sec_term in ['sops.secrets', 'firewall', 'tailscale']):
            changes['security_changes'] = True
        elif any(mon_term in content for mon_term in ['prometheus', 'grafana', 'alertmanager']):
            changes['monitoring_changes'] = True
    
    def detect_removals(self, line, changes, current_file):
        """Detect what was removed"""
        content = line[1:].strip()
        if 'enable = true' in content and 'services.' in content:
            service_match = re.search(r'services\.(\w+)', content)
            if service_match:
                changes['services_removed'].append(service_match.group(1))

if __name__ == "__main__":
    generator = AIDocumentationGenerator()
    recent_commits = generator.parse_recent_changes(days=7)
    generator.update_documentation_with_ai(recent_commits)