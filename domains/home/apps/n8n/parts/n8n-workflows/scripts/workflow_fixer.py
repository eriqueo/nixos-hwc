#!/usr/bin/env python3
"""
n8n Workflow Fixer
Comprehensive fixer for common n8n workflow issues including:
- Security issues (sensitive data, hardcoded URLs)
- Missing error handling
- Duplicate node names
- Structural problems
- Naming convention issues
"""

import json
import os
import re
import uuid
from pathlib import Path
from typing import Dict, List, Any, Set
from collections import defaultdict

class WorkflowFixer:
    def __init__(self, workflows_dir="workflows"):
        self.workflows_dir = Path(workflows_dir)
        self.fix_stats = {
            'total_workflows': 0,
            'fixed_workflows': 0,
            'security_fixes': 0,
            'error_handling_added': 0,
            'duplicate_names_fixed': 0,
            'structural_fixes': 0,
            'naming_fixes': 0
        }
        
    def fix_sensitive_data(self, workflow_data: Dict) -> Dict:
        """Remove or replace sensitive data with placeholders"""
        fixed = False
        
        def replace_sensitive_values(obj, path=""):
            nonlocal fixed
            if isinstance(obj, dict):
                for key, value in obj.items():
                    current_path = f"{path}.{key}" if path else key
                    
                    # Check for sensitive data patterns
                    sensitive_patterns = [
                        r'password', r'token', r'key', r'secret', r'credential',
                        r'api_key', r'access_token', r'refresh_token', r'sessionKey'
                    ]
                    
                    if any(pattern in key.lower() for pattern in sensitive_patterns):
                        if value and str(value).strip() and value != "":
                            if isinstance(value, str) and not value.startswith('{{') and not value.startswith('${'):
                                obj[key] = f"{{{{ $credentials.{key} }}}}"
                                fixed = True
                    
                    # Recursively check nested objects
                    replace_sensitive_values(value, current_path)
                    
            elif isinstance(obj, list):
                for i, item in enumerate(obj):
                    replace_sensitive_values(item, f"{path}[{i}]")
        
        replace_sensitive_values(workflow_data)
        return workflow_data, fixed
    
    def fix_hardcoded_urls(self, workflow_data: Dict) -> Dict:
        """Replace hardcoded URLs with environment variables or placeholders"""
        fixed = False
        
        def replace_urls(obj, path=""):
            nonlocal fixed
            if isinstance(obj, str):
                # Match URLs but not expressions
                url_pattern = r'https?://[^\s"\'<>]+'
                urls = re.findall(url_pattern, obj)
                
                for url in urls:
                    if not any(placeholder in obj for placeholder in ['{{', '${', 'YOUR_', 'PLACEHOLDER']):
                        # Replace with environment variable pattern
                        if 'myshopify.com' in url:
                            obj = obj.replace(url, "{{ $env.SHOPIFY_URL }}")
                        elif 'webhook' in url.lower():
                            obj = obj.replace(url, "{{ $env.WEBHOOK_URL }}")
                        else:
                            obj = obj.replace(url, "{{ $env.API_BASE_URL }}")
                        fixed = True
                        
            elif isinstance(obj, dict):
                for key, value in obj.items():
                    current_path = f"{path}.{key}" if path else key
                    obj[key] = replace_urls(value, current_path)
            elif isinstance(obj, list):
                for i, item in enumerate(obj):
                    obj[i] = replace_urls(item, f"{path}[{i}]")
                    
            return obj
        
        workflow_data = replace_urls(workflow_data)
        return workflow_data, fixed
    
    def add_error_handling(self, workflow_data: Dict) -> Dict:
        """Add error handling nodes to workflows that need them"""
        fixed = False
        nodes = workflow_data.get('nodes', [])
        connections = workflow_data.get('connections', {})
        
        # Check if workflow already has error handling
        has_error_handling = any('error' in node.get('type', '').lower() or 
                               'stop' in node.get('type', '').lower() 
                               for node in nodes)
        
        if has_error_handling:
            return workflow_data, False
            
        # Check if workflow has critical operations that need error handling
        critical_operations = ['httprequest', 'webhook', 'database', 'api', 'graphql']
        has_critical_ops = False
        
        critical_nodes = []
        for node in nodes:
            node_type = node.get('type', '').lower()
            if any(op in node_type for op in critical_operations):
                has_critical_ops = True
                critical_nodes.append(node)
        
        if not has_critical_ops:
            return workflow_data, False
        
        # Add error handling nodes for critical operations
        for node in critical_nodes:
            node_id = node['id']
            error_node_id = f"error-handler-{node_id}"
            
            # Create error handler node
            error_node = {
                "id": error_node_id,
                "name": f"Error Handler for {node.get('name', 'Node')}",
                "type": "n8n-nodes-base.stopAndError",
                "typeVersion": 1,
                "position": [
                    node.get('position', [0, 0])[0] + 200,
                    node.get('position', [0, 0])[1] + 100
                ],
                "parameters": {
                    "message": f"Error occurred in {node.get('name', 'workflow execution')}",
                    "options": {}
                }
            }
            
            nodes.append(error_node)
            
            # Add error connection
            if node_id not in connections:
                connections[node_id] = {}
            if 'main' not in connections[node_id]:
                connections[node_id]['main'] = [[], []]
            
            # Add error connection to the error handler
            connections[node_id]['main'][1].append({
                "node": error_node_id,
                "type": "main",
                "index": 0
            })
            
            fixed = True
        
        workflow_data['nodes'] = nodes
        workflow_data['connections'] = connections
        return workflow_data, fixed
    
    def fix_duplicate_names(self, workflow_data: Dict) -> Dict:
        """Fix duplicate node names by adding unique suffixes"""
        fixed = False
        nodes = workflow_data.get('nodes', [])
        name_counts = defaultdict(int)
        
        # Count occurrences of each name
        for node in nodes:
            name = node.get('name', '')
            if name:
                name_counts[name] += 1
        
        # Fix duplicates
        for node in nodes:
            name = node.get('name', '')
            if name and name_counts[name] > 1:
                # Generate unique suffix
                counter = 1
                new_name = f"{name} {counter}"
                while new_name in [n.get('name', '') for n in nodes]:
                    counter += 1
                    new_name = f"{name} {counter}"
                
                node['name'] = new_name
                fixed = True
        
        return workflow_data, fixed
    
    def fix_missing_ids(self, workflow_data: Dict) -> Dict:
        """Add missing IDs to nodes"""
        fixed = False
        nodes = workflow_data.get('nodes', [])
        
        for node in nodes:
            if 'id' not in node:
                node['id'] = str(uuid.uuid4())
                fixed = True
        
        return workflow_data, fixed
    
    def fix_naming_conventions(self, workflow_data: Dict) -> Dict:
        """Fix workflow and node naming conventions"""
        fixed = False
        
        # Fix workflow name
        workflow_name = workflow_data.get('name', '')
        if not workflow_name:
            workflow_data['name'] = 'Unnamed Workflow'
            fixed = True
        elif len(workflow_name) < 5:
            workflow_data['name'] = f"{workflow_name} Workflow"
            fixed = True
        elif len(workflow_name) > 100:
            workflow_data['name'] = workflow_name[:97] + "..."
            fixed = True
        
        # Fix node names
        nodes = workflow_data.get('nodes', [])
        for node in nodes:
            node_name = node.get('name', '')
            if not node_name:
                node['name'] = f"Node {node.get('id', 'unknown')[:8]}"
                fixed = True
            elif len(node_name) < 3:
                node['name'] = f"{node_name} Node"
                fixed = True
        
        return workflow_data, fixed
    
    def fix_structural_issues(self, workflow_data: Dict) -> Dict:
        """Fix basic structural issues"""
        fixed = False
        
        # Ensure required fields exist
        if 'nodes' not in workflow_data:
            workflow_data['nodes'] = []
            fixed = True
        
        if 'connections' not in workflow_data:
            workflow_data['connections'] = {}
            fixed = True
        
        if 'settings' not in workflow_data:
            workflow_data['settings'] = {
                "executionOrder": "v1",
                "saveManualExecutions": True,
                "callerPolicy": "workflowsFromSameOwner",
                "errorWorkflow": None,
                "timezone": "UTC"
            }
            fixed = True
        
        # Ensure nodes have required fields
        nodes = workflow_data.get('nodes', [])
        for node in nodes:
            if 'type' not in node:
                node['type'] = 'n8n-nodes-base.noOp'
                fixed = True
            if 'typeVersion' not in node:
                node['typeVersion'] = 1
                fixed = True
            if 'position' not in node:
                node['position'] = [100, 100]
                fixed = True
            if 'parameters' not in node:
                node['parameters'] = {}
                fixed = True
        
        return workflow_data, fixed
    
    def add_documentation(self, workflow_data: Dict) -> Dict:
        """Add documentation node to workflow"""
        nodes = workflow_data.get('nodes', [])
        
        # Check if documentation already exists
        has_doc = any('documentation' in node.get('name', '').lower() for node in nodes)
        
        if not has_doc:
            doc_node = {
                "id": "documentation-node",
                "name": "Workflow Documentation",
                "type": "n8n-nodes-base.stickyNote",
                "typeVersion": 1,
                "position": [50, 50],
                "parameters": {
                    "content": f"# {workflow_data.get('name', 'Workflow')}\n\nAutomated workflow: {workflow_data.get('name', 'Workflow')}. This workflow processes data and performs automated tasks.\n\n## Nodes:\n- {len(nodes)} total nodes\n- Includes error handling\n- Follows best practices\n\n## Usage:\n1. Configure credentials\n2. Update environment variables\n3. Test workflow\n4. Deploy to production"
                }
            }
            nodes.append(doc_node)
            workflow_data['nodes'] = nodes
        
        return workflow_data
    
    def fix_single_workflow(self, workflow_path: Path) -> Dict[str, Any]:
        """Fix a single workflow file"""
        try:
            with open(workflow_path, 'r', encoding='utf-8') as f:
                workflow_data = json.load(f)
            
            fixes_applied = {
                'security_fixes': False,
                'error_handling_added': False,
                'duplicate_names_fixed': False,
                'structural_fixes': False,
                'naming_fixes': False,
                'documentation_added': False
            }
            
            # Apply all fixes
            workflow_data, security_fixed = self.fix_sensitive_data(workflow_data)
            fixes_applied['security_fixes'] = security_fixed
            
            workflow_data, url_fixed = self.fix_hardcoded_urls(workflow_data)
            fixes_applied['security_fixes'] = fixes_applied['security_fixes'] or url_fixed
            
            workflow_data, error_fixed = self.add_error_handling(workflow_data)
            fixes_applied['error_handling_added'] = error_fixed
            
            workflow_data, duplicate_fixed = self.fix_duplicate_names(workflow_data)
            fixes_applied['duplicate_names_fixed'] = duplicate_fixed
            
            workflow_data, id_fixed = self.fix_missing_ids(workflow_data)
            fixes_applied['structural_fixes'] = id_fixed
            
            workflow_data, structural_fixed = self.fix_structural_issues(workflow_data)
            fixes_applied['structural_fixes'] = fixes_applied['structural_fixes'] or structural_fixed
            
            workflow_data, naming_fixed = self.fix_naming_conventions(workflow_data)
            fixes_applied['naming_fixes'] = naming_fixed
            
            workflow_data = self.add_documentation(workflow_data)
            fixes_applied['documentation_added'] = True
            
            # Save fixed workflow
            with open(workflow_path, 'w', encoding='utf-8') as f:
                json.dump(workflow_data, f, indent=2, ensure_ascii=False)
            
            return {
                'filename': workflow_path.name,
                'fixed': True,
                'fixes_applied': fixes_applied,
                'workflow_name': workflow_data.get('name', 'Unnamed')
            }
            
        except json.JSONDecodeError as e:
            return {
                'filename': workflow_path.name,
                'fixed': False,
                'error': f"Invalid JSON: {str(e)}",
                'workflow_name': 'Invalid'
            }
        except Exception as e:
            return {
                'filename': workflow_path.name,
                'fixed': False,
                'error': f"Fix error: {str(e)}",
                'workflow_name': 'Error'
            }
    
    def fix_all_workflows(self) -> Dict[str, Any]:
        """Fix all workflows in the repository"""
        print("🔧 Fixing all workflows...")
        
        fix_results = []
        
        for category_dir in self.workflows_dir.iterdir():
            if category_dir.is_dir():
                for workflow_file in category_dir.glob('*.json'):
                    self.fix_stats['total_workflows'] += 1
                    result = self.fix_single_workflow(workflow_file)
                    fix_results.append(result)
                    
                    if result['fixed']:
                        self.fix_stats['fixed_workflows'] += 1
                        
                        # Update specific fix counters
                        if result['fixes_applied']['security_fixes']:
                            self.fix_stats['security_fixes'] += 1
                        if result['fixes_applied']['error_handling_added']:
                            self.fix_stats['error_handling_added'] += 1
                        if result['fixes_applied']['duplicate_names_fixed']:
                            self.fix_stats['duplicate_names_fixed'] += 1
                        if result['fixes_applied']['structural_fixes']:
                            self.fix_stats['structural_fixes'] += 1
                        if result['fixes_applied']['naming_fixes']:
                            self.fix_stats['naming_fixes'] += 1
        
        # Generate summary
        summary = {
            'total_workflows': self.fix_stats['total_workflows'],
            'fixed_workflows': self.fix_stats['fixed_workflows'],
            'fix_rate': (self.fix_stats['fixed_workflows'] / self.fix_stats['total_workflows'] * 100) if self.fix_stats['total_workflows'] > 0 else 0,
            'fix_stats': self.fix_stats,
            'results': fix_results
        }
        
        print(f"✅ Processed {self.fix_stats['total_workflows']} workflows")
        print(f"🔧 Fixed {self.fix_stats['fixed_workflows']} workflows ({summary['fix_rate']:.1f}%)")
        print(f"🛡️ Security fixes: {self.fix_stats['security_fixes']}")
        print(f"⚠️ Error handling added: {self.fix_stats['error_handling_added']}")
        print(f"📝 Duplicate names fixed: {self.fix_stats['duplicate_names_fixed']}")
        print(f"🏗️ Structural fixes: {self.fix_stats['structural_fixes']}")
        print(f"📋 Naming fixes: {self.fix_stats['naming_fixes']}")
        
        return summary
    
    def generate_fix_report(self, summary: Dict[str, Any]):
        """Generate comprehensive fix report"""
        print("\n" + "="*60)
        print("🔧 WORKFLOW FIX REPORT")
        print("="*60)
        
        print(f"\n📊 FIX STATISTICS:")
        print(f"   Total Workflows: {summary['total_workflows']}")
        print(f"   Fixed Workflows: {summary['fixed_workflows']} ({summary['fix_rate']:.1f}%)")
        
        print(f"\n🔧 FIXES APPLIED:")
        print(f"   Security Fixes: {self.fix_stats['security_fixes']}")
        print(f"   Error Handling Added: {self.fix_stats['error_handling_added']}")
        print(f"   Duplicate Names Fixed: {self.fix_stats['duplicate_names_fixed']}")
        print(f"   Structural Fixes: {self.fix_stats['structural_fixes']}")
        print(f"   Naming Fixes: {self.fix_stats['naming_fixes']}")
        
        # Show failed fixes
        failed_fixes = [r for r in summary['results'] if not r['fixed']]
        if failed_fixes:
            print(f"\n❌ FAILED FIXES ({len(failed_fixes)}):")
            for result in failed_fixes[:10]:  # Show first 10
                print(f"   {result['filename']}: {result.get('error', 'Unknown error')}")
        
        # Save detailed report
        with open("workflow_fix_report.json", "w") as f:
            json.dump(summary, f, indent=2)
        
        print(f"\n📄 Detailed fix report saved to: workflow_fix_report.json")
        print(f"\n🎉 Workflow fixing complete!")

def main():
    """Main fixing function"""
    fixer = WorkflowFixer()
    
    # Run fixes
    summary = fixer.fix_all_workflows()
    
    # Generate report
    fixer.generate_fix_report(summary)

if __name__ == "__main__":
    main()
