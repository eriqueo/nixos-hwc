#!/usr/bin/env python3
"""
Comprehensive Workflow Pattern Analysis
Analyze n8n workflows to identify common patterns, best practices, and optimization opportunities.
"""

import json
import os
from pathlib import Path
from collections import defaultdict, Counter
import re

class WorkflowPatternAnalyzer:
    def __init__(self, workflows_dir="workflows"):
        self.workflows_dir = Path(workflows_dir)
        self.patterns = defaultdict(int)
        self.node_types = Counter()
        self.integrations = Counter()
        self.trigger_patterns = Counter()
        self.complexity_distribution = Counter()
        self.error_handling_patterns = Counter()
        self.data_flow_patterns = defaultdict(list)
        
    def analyze_workflow(self, workflow_path):
        """Analyze a single workflow file"""
        try:
            with open(workflow_path, 'r', encoding='utf-8') as f:
                data = json.load(f)
            
            nodes = data.get('nodes', [])
            connections = data.get('connections', {})
            
            # Basic metrics
            node_count = len(nodes)
            self.complexity_distribution[self.get_complexity_level(node_count)] += 1
            
            # Analyze nodes
            node_types = []
            integrations = set()
            triggers = []
            
            for node in nodes:
                node_type = node.get('type', '')
                node_name = node.get('name', '')
                
                # Extract integration from node type
                if '.' in node_type:
                    integration = node_type.split('.')[-1]
                    integrations.add(integration)
                
                node_types.append(node_type)
                self.node_types[node_type] += 1
                
                # Identify trigger nodes
                if any(t in node_type.lower() for t in ['trigger', 'webhook', 'cron', 'schedule']):
                    triggers.append(node_type)
                    self.trigger_patterns[node_type] += 1
                
                # Check for error handling
                if any(e in node_type.lower() for e in ['error', 'catch']):
                    self.error_handling_patterns[node_type] += 1
            
            # Analyze data flow patterns
            self.analyze_data_flow(nodes, connections)
            
            # Store integration info
            for integration in integrations:
                self.integrations[integration] += 1
            
            return {
                'filename': workflow_path.name,
                'node_count': node_count,
                'node_types': node_types,
                'integrations': list(integrations),
                'triggers': triggers,
                'has_error_handling': any('error' in nt.lower() for nt in node_types)
            }
            
        except Exception as e:
            print(f"Error analyzing {workflow_path}: {e}")
            return None
    
    def get_complexity_level(self, node_count):
        """Determine workflow complexity level"""
        if node_count <= 5:
            return 'Simple'
        elif node_count <= 15:
            return 'Medium'
        else:
            return 'Complex'
    
    def analyze_data_flow(self, nodes, connections):
        """Analyze data flow patterns in workflows"""
        # Count connection patterns
        connection_count = 0
        for source, targets in connections.items():
            if isinstance(targets, dict) and 'main' in targets:
                connection_count += len(targets['main'])
        
        self.data_flow_patterns['total_connections'].append(connection_count)
        
        # Identify common patterns
        node_names = [node.get('name', '') for node in nodes]
        
        # HTTP -> Process -> Store pattern
        if any('http' in name.lower() for name in node_names) and \
           any('process' in name.lower() or 'transform' in name.lower() for name in node_names):
            self.patterns['http_process_store'] += 1
        
        # Trigger -> Filter -> Action pattern
        if any('trigger' in name.lower() for name in node_names) and \
           any('filter' in name.lower() for name in node_names):
            self.patterns['trigger_filter_action'] += 1
        
        # Loop patterns
        if any('loop' in name.lower() or 'batch' in name.lower() for name in node_names):
            self.patterns['loop_processing'] += 1
    
    def analyze_all_workflows(self):
        """Analyze all workflows in the repository"""
        print("🔍 Analyzing workflow patterns...")
        
        analyzed_count = 0
        for category_dir in self.workflows_dir.iterdir():
            if category_dir.is_dir():
                for workflow_file in category_dir.glob('*.json'):
                    result = self.analyze_workflow(workflow_file)
                    if result:
                        analyzed_count += 1
        
        print(f"✅ Analyzed {analyzed_count} workflows")
        return analyzed_count
    
    def generate_report(self):
        """Generate comprehensive analysis report"""
        print("\n" + "="*60)
        print("📊 N8N WORKFLOW PATTERN ANALYSIS REPORT")
        print("="*60)
        
        # Complexity Distribution
        print(f"\n🎯 COMPLEXITY DISTRIBUTION:")
        for complexity, count in self.complexity_distribution.most_common():
            percentage = (count / sum(self.complexity_distribution.values())) * 100
            print(f"   {complexity}: {count} workflows ({percentage:.1f}%)")
        
        # Top Node Types
        print(f"\n🔧 TOP 15 NODE TYPES:")
        for node_type, count in self.node_types.most_common(15):
            print(f"   {node_type}: {count} uses")
        
        # Top Integrations
        print(f"\n🔌 TOP 15 INTEGRATIONS:")
        for integration, count in self.integrations.most_common(15):
            print(f"   {integration}: {count} workflows")
        
        # Trigger Patterns
        print(f"\n⚡ TRIGGER PATTERNS:")
        for trigger, count in self.trigger_patterns.most_common(10):
            print(f"   {trigger}: {count} workflows")
        
        # Common Patterns
        print(f"\n🔄 COMMON WORKFLOW PATTERNS:")
        for pattern, count in self.patterns.items():
            print(f"   {pattern}: {count} workflows")
        
        # Error Handling
        print(f"\n🛡️ ERROR HANDLING PATTERNS:")
        total_workflows = sum(self.complexity_distribution.values())
        error_workflows = sum(self.error_handling_patterns.values())
        print(f"   Workflows with error handling: {error_workflows} ({error_workflows/total_workflows*100:.1f}%)")
        for error_type, count in self.error_handling_patterns.most_common():
            print(f"   {error_type}: {count} uses")
        
        # Data Flow Analysis
        if self.data_flow_patterns['total_connections']:
            avg_connections = sum(self.data_flow_patterns['total_connections']) / len(self.data_flow_patterns['total_connections'])
            print(f"\n📈 DATA FLOW ANALYSIS:")
            print(f"   Average connections per workflow: {avg_connections:.1f}")
            print(f"   Max connections: {max(self.data_flow_patterns['total_connections'])}")
            print(f"   Min connections: {min(self.data_flow_patterns['total_connections'])}")
    
    def generate_recommendations(self):
        """Generate optimization recommendations"""
        print(f"\n💡 OPTIMIZATION RECOMMENDATIONS:")
        print("="*60)
        
        total_workflows = sum(self.complexity_distribution.values())
        error_workflows = sum(self.error_handling_patterns.values())
        
        # Error Handling
        if error_workflows / total_workflows < 0.3:
            print("⚠️  ERROR HANDLING:")
            print("   - Only {:.1f}% of workflows have error handling".format(error_workflows/total_workflows*100))
            print("   - Consider adding error handling nodes to improve reliability")
            print("   - Use 'Stop and Error' or 'Error Trigger' nodes for better debugging")
        
        # Complexity
        complex_workflows = self.complexity_distribution.get('Complex', 0)
        if complex_workflows / total_workflows > 0.3:
            print(f"\n⚠️  COMPLEXITY:")
            print(f"   - {complex_workflows} workflows ({complex_workflows/total_workflows*100:.1f}%) are complex")
            print("   - Consider breaking down complex workflows into smaller, reusable components")
            print("   - Use sub-workflows or function nodes for better maintainability")
        
        # Popular Patterns
        print(f"\n✅ BEST PRACTICES:")
        print("   - Most common pattern: HTTP -> Process -> Store")
        print("   - Use descriptive node names for better documentation")
        print("   - Implement proper error handling and logging")
        print("   - Consider using webhooks for real-time processing")
        print("   - Use filters to reduce unnecessary processing")

def main():
    """Main analysis function"""
    analyzer = WorkflowPatternAnalyzer()
    
    # Run analysis
    count = analyzer.analyze_all_workflows()
    
    if count > 0:
        # Generate reports
        analyzer.generate_report()
        analyzer.generate_recommendations()
        
        print(f"\n🎉 Analysis complete! Processed {count} workflows.")
    else:
        print("❌ No workflows found to analyze.")

if __name__ == "__main__":
    main()
