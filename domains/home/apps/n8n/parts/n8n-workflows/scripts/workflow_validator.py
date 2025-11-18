#!/usr/bin/env python3
"""
Workflow Validation and Testing System
Comprehensive validation of n8n workflows for quality, security, and best practices
"""

import json
import os
from pathlib import Path
from typing import Dict, List, Any, Tuple
import re
from collections import defaultdict

class WorkflowValidator:
    def __init__(self, workflows_dir="workflows"):
        self.workflows_dir = Path(workflows_dir)
        self.validation_results = defaultdict(list)
        self.quality_scores = {}
        self.security_issues = []
        self.best_practice_violations = []
        
    def validate_workflow_structure(self, workflow_data: Dict) -> List[str]:
        """Validate basic workflow structure"""
        issues = []
        
        # Check required fields
        required_fields = ['name', 'nodes', 'connections']
        for field in required_fields:
            if field not in workflow_data:
                issues.append(f"Missing required field: {field}")
        
        # Validate nodes structure
        if 'nodes' in workflow_data:
            nodes = workflow_data['nodes']
            if not isinstance(nodes, list):
                issues.append("Nodes must be a list")
            else:
                for i, node in enumerate(nodes):
                    if not isinstance(node, dict):
                        issues.append(f"Node {i} is not a dictionary")
                        continue
                    
                    # Check node required fields
                    node_required = ['id', 'name', 'type']
                    for field in node_required:
                        if field not in node:
                            issues.append(f"Node {i} missing required field: {field}")
        
        # Validate connections structure
        if 'connections' in workflow_data:
            connections = workflow_data['connections']
            if not isinstance(connections, dict):
                issues.append("Connections must be a dictionary")
        
        return issues
    
    def validate_node_configuration(self, node: Dict) -> List[str]:
        """Validate individual node configuration"""
        issues = []
        
        # Check for sensitive data in parameters
        parameters = node.get('parameters', {})
        sensitive_patterns = [
            r'password', r'token', r'key', r'secret', r'credential',
            r'api_key', r'access_token', r'refresh_token'
        ]
        
        def check_sensitive_data(obj, path=""):
            if isinstance(obj, dict):
                for key, value in obj.items():
                    current_path = f"{path}.{key}" if path else key
                    if any(pattern in key.lower() for pattern in sensitive_patterns):
                        if value and str(value).strip() and value != "":
                            issues.append(f"Sensitive data found in {current_path}")
                    check_sensitive_data(value, current_path)
            elif isinstance(obj, list):
                for i, item in enumerate(obj):
                    check_sensitive_data(item, f"{path}[{i}]")
        
        check_sensitive_data(parameters)
        
        # Check for hardcoded URLs (potential security issue)
        def check_hardcoded_urls(obj, path=""):
            if isinstance(obj, str):
                url_pattern = r'https?://[^\s]+'
                if re.search(url_pattern, obj):
                    if not any(placeholder in obj for placeholder in ['{{', '${', 'YOUR_', 'PLACEHOLDER']):
                        issues.append(f"Hardcoded URL found in {path}")
            elif isinstance(obj, dict):
                for key, value in obj.items():
                    current_path = f"{path}.{key}" if path else key
                    check_hardcoded_urls(value, current_path)
            elif isinstance(obj, list):
                for i, item in enumerate(obj):
                    check_hardcoded_urls(item, f"{path}[{i}]")
        
        check_hardcoded_urls(parameters)
        
        return issues
    
    def validate_error_handling(self, workflow_data: Dict) -> List[str]:
        """Check for proper error handling"""
        issues = []
        
        nodes = workflow_data.get('nodes', [])
        has_error_handling = False
        
        for node in nodes:
            node_type = node.get('type', '').lower()
            if any(error_type in node_type for error_type in ['error', 'catch', 'stop']):
                has_error_handling = True
                break
        
        if not has_error_handling:
            # Check if workflow has critical operations that need error handling
            critical_operations = ['httprequest', 'webhook', 'database', 'api']
            has_critical_ops = False
            
            for node in nodes:
                node_type = node.get('type', '').lower()
                if any(op in node_type for op in critical_operations):
                    has_critical_ops = True
                    break
            
            if has_critical_ops:
                issues.append("Workflow has critical operations but no error handling")
        
        return issues
    
    def validate_naming_conventions(self, workflow_data: Dict) -> List[str]:
        """Validate workflow and node naming conventions"""
        issues = []
        
        # Check workflow name
        workflow_name = workflow_data.get('name', '')
        if not workflow_name:
            issues.append("Workflow has no name")
        elif len(workflow_name) < 5:
            issues.append("Workflow name is too short")
        elif len(workflow_name) > 100:
            issues.append("Workflow name is too long")
        
        # Check node names
        nodes = workflow_data.get('nodes', [])
        node_names = []
        
        for node in nodes:
            node_name = node.get('name', '')
            if not node_name:
                issues.append(f"Node {node.get('id', 'unknown')} has no name")
            elif len(node_name) < 3:
                issues.append(f"Node '{node_name}' name is too short")
            elif node_name in node_names:
                issues.append(f"Duplicate node name: '{node_name}'")
            else:
                node_names.append(node_name)
        
        return issues
    
    def validate_workflow_complexity(self, workflow_data: Dict) -> List[str]:
        """Validate workflow complexity and suggest optimizations"""
        issues = []
        
        nodes = workflow_data.get('nodes', [])
        node_count = len(nodes)
        
        # Complexity warnings
        if node_count > 50:
            issues.append(f"Workflow is very complex ({node_count} nodes). Consider breaking into smaller workflows")
        elif node_count > 20:
            issues.append(f"Workflow is complex ({node_count} nodes). Consider optimization")
        
        # Check for deeply nested conditions
        connections = workflow_data.get('connections', {})
        max_depth = self.calculate_workflow_depth(connections, nodes)
        
        if max_depth > 10:
            issues.append(f"Workflow has high nesting depth ({max_depth}). Consider simplification")
        
        return issues
    
    def calculate_workflow_depth(self, connections: Dict, nodes: List[Dict]) -> int:
        """Calculate the maximum depth of the workflow"""
        # Find trigger nodes (nodes with no incoming connections)
        node_ids = {node['id'] for node in nodes}
        
        def get_depth(node_id, visited=None):
            if visited is None:
                visited = set()
            
            if node_id in visited:
                return 0  # Circular reference
            
            visited.add(node_id)
            max_child_depth = 0
            
            if node_id in connections:
                for output_connections in connections[node_id].values():
                    if isinstance(output_connections, list):
                        for connection in output_connections:
                            if isinstance(connection, dict) and 'node' in connection:
                                child_depth = get_depth(connection['node'], visited.copy())
                                max_child_depth = max(max_child_depth, child_depth)
            
            return max_child_depth + 1
        
        # Find trigger nodes and calculate max depth
        trigger_nodes = []
        for node in nodes:
            node_id = node['id']
            is_trigger = True
            for source_connections in connections.values():
                for output_connections in source_connections.values():
                    if isinstance(output_connections, list):
                        for connection in output_connections:
                            if isinstance(connection, dict) and connection.get('node') == node_id:
                                is_trigger = False
                                break
            if is_trigger:
                trigger_nodes.append(node_id)
        
        max_depth = 0
        for trigger in trigger_nodes:
            depth = get_depth(trigger)
            max_depth = max(max_depth, depth)
        
        return max_depth
    
    def calculate_quality_score(self, workflow_data: Dict, issues: List[str]) -> int:
        """Calculate quality score for workflow (0-100)"""
        base_score = 100
        
        # Deduct points for issues
        for issue in issues:
            if "Missing required field" in issue:
                base_score -= 20
            elif "Sensitive data found" in issue:
                base_score -= 15
            elif "Hardcoded URL found" in issue:
                base_score -= 10
            elif "no error handling" in issue:
                base_score -= 10
            elif "too complex" in issue or "too long" in issue:
                base_score -= 5
            elif "too short" in issue or "Duplicate" in issue:
                base_score -= 3
            else:
                base_score -= 2
        
        return max(0, base_score)
    
    def validate_single_workflow(self, workflow_path: Path) -> Dict[str, Any]:
        """Validate a single workflow file"""
        try:
            with open(workflow_path, 'r', encoding='utf-8') as f:
                workflow_data = json.load(f)
            
            issues = []
            
            # Run all validation checks
            issues.extend(self.validate_workflow_structure(workflow_data))
            
            # Validate each node
            for node in workflow_data.get('nodes', []):
                issues.extend(self.validate_node_configuration(node))
            
            issues.extend(self.validate_error_handling(workflow_data))
            issues.extend(self.validate_naming_conventions(workflow_data))
            issues.extend(self.validate_workflow_complexity(workflow_data))
            
            # Calculate quality score
            quality_score = self.calculate_quality_score(workflow_data, issues)
            
            return {
                'filename': workflow_path.name,
                'issues': issues,
                'quality_score': quality_score,
                'node_count': len(workflow_data.get('nodes', [])),
                'has_error_handling': any('error' in node.get('type', '').lower() for node in workflow_data.get('nodes', [])),
                'workflow_name': workflow_data.get('name', 'Unnamed')
            }
            
        except json.JSONDecodeError as e:
            return {
                'filename': workflow_path.name,
                'issues': [f"Invalid JSON: {str(e)}"],
                'quality_score': 0,
                'node_count': 0,
                'has_error_handling': False,
                'workflow_name': 'Invalid'
            }
        except Exception as e:
            return {
                'filename': workflow_path.name,
                'issues': [f"Validation error: {str(e)}"],
                'quality_score': 0,
                'node_count': 0,
                'has_error_handling': False,
                'workflow_name': 'Error'
            }
    
    def validate_all_workflows(self) -> Dict[str, Any]:
        """Validate all workflows in the repository"""
        print("🔍 Validating all workflows...")
        
        validation_results = []
        total_workflows = 0
        valid_workflows = 0
        high_quality_workflows = 0
        
        for category_dir in self.workflows_dir.iterdir():
            if category_dir.is_dir():
                for workflow_file in category_dir.glob('*.json'):
                    total_workflows += 1
                    result = self.validate_single_workflow(workflow_file)
                    validation_results.append(result)
                    
                    if not result['issues']:
                        valid_workflows += 1
                    
                    if result['quality_score'] >= 80:
                        high_quality_workflows += 1
        
        # Generate summary
        summary = {
            'total_workflows': total_workflows,
            'valid_workflows': valid_workflows,
            'high_quality_workflows': high_quality_workflows,
            'validation_rate': (valid_workflows / total_workflows * 100) if total_workflows > 0 else 0,
            'quality_rate': (high_quality_workflows / total_workflows * 100) if total_workflows > 0 else 0,
            'results': validation_results
        }
        
        print(f"✅ Validated {total_workflows} workflows")
        print(f"📊 {valid_workflows} workflows passed validation ({summary['validation_rate']:.1f}%)")
        print(f"⭐ {high_quality_workflows} workflows are high quality ({summary['quality_rate']:.1f}%)")
        
        return summary
    
    def generate_validation_report(self, summary: Dict[str, Any]):
        """Generate comprehensive validation report"""
        print("\n" + "="*60)
        print("📋 WORKFLOW VALIDATION REPORT")
        print("="*60)
        
        print(f"\n📊 OVERALL STATISTICS:")
        print(f"   Total Workflows: {summary['total_workflows']}")
        print(f"   Valid Workflows: {summary['valid_workflows']} ({summary['validation_rate']:.1f}%)")
        print(f"   High Quality: {summary['high_quality_workflows']} ({summary['quality_rate']:.1f}%)")
        
        # Issue analysis
        issue_counts = defaultdict(int)
        for result in summary['results']:
            for issue in result['issues']:
                issue_type = issue.split(':')[0] if ':' in issue else issue
                issue_counts[issue_type] += 1
        
        print(f"\n⚠️  MOST COMMON ISSUES:")
        for issue_type, count in sorted(issue_counts.items(), key=lambda x: x[1], reverse=True)[:10]:
            print(f"   {issue_type}: {count} workflows")
        
        # Quality distribution
        quality_ranges = {'Excellent (90-100)': 0, 'Good (80-89)': 0, 'Fair (70-79)': 0, 'Poor (<70)': 0}
        for result in summary['results']:
            score = result['quality_score']
            if score >= 90:
                quality_ranges['Excellent (90-100)'] += 1
            elif score >= 80:
                quality_ranges['Good (80-89)'] += 1
            elif score >= 70:
                quality_ranges['Fair (70-79)'] += 1
            else:
                quality_ranges['Poor (<70)'] += 1
        
        print(f"\n⭐ QUALITY DISTRIBUTION:")
        for range_name, count in quality_ranges.items():
            percentage = (count / summary['total_workflows'] * 100) if summary['total_workflows'] > 0 else 0
            print(f"   {range_name}: {count} workflows ({percentage:.1f}%)")
        
        # Error handling analysis
        error_handling_count = sum(1 for result in summary['results'] if result['has_error_handling'])
        print(f"\n🛡️ ERROR HANDLING:")
        print(f"   Workflows with error handling: {error_handling_count} ({error_handling_count/summary['total_workflows']*100:.1f}%)")
        
        # Save detailed report
        with open("workflow_validation_report.json", "w") as f:
            json.dump(summary, f, indent=2)
        
        print(f"\n📄 Detailed report saved to: workflow_validation_report.json")

def main():
    """Main validation function"""
    validator = WorkflowValidator()
    
    # Run validation
    summary = validator.validate_all_workflows()
    
    # Generate report
    validator.generate_validation_report(summary)
    
    print(f"\n🎉 Workflow validation complete!")

if __name__ == "__main__":
    main()
