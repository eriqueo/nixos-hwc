#!/usr/bin/env python3
"""
Demo script for Final Excellence Upgrader
Demonstrates the capabilities of the final excellence upgrader
"""

import json
from pathlib import Path
from final_excellence_upgrader import FinalExcellenceUpgrader

def demo_workflow_analysis():
    """Demonstrate workflow analysis capabilities"""
    print("🔍 DEMO: Workflow Analysis Capabilities")
    print("=" * 50)
    
    upgrader = FinalExcellenceUpgrader()
    
    # Find a sample workflow to analyze
    sample_workflow = None
    for category_dir in upgrader.workflows_dir.iterdir():
        if category_dir.is_dir():
            workflow_files = list(category_dir.glob('*.json'))
            if workflow_files:
                sample_workflow = workflow_files[0]
                break
    
    if sample_workflow:
        print(f"📄 Analyzing sample workflow: {sample_workflow.name}")
        
        with open(sample_workflow, 'r', encoding='utf-8') as f:
            workflow_data = json.load(f)
        
        # Calculate quality
        quality = upgrader.calculate_workflow_quality(workflow_data)
        
        print(f"\n📊 Quality Analysis Results:")
        print(f"   Score: {quality.score:.1f}/100")
        print(f"   Category: {quality.category.title()}")
        print(f"   Complexity: {quality.complexity.title()}")
        
        if quality.issues:
            print(f"\n⚠️  Issues Found ({len(quality.issues)}):")
            for issue in quality.issues:
                print(f"   - {issue}")
        
        if quality.strengths:
            print(f"\n✅ Strengths ({len(quality.strengths)}):")
            for strength in quality.strengths:
                print(f"   - {strength}")
        
        if quality.recommendations:
            print(f"\n💡 Recommendations ({len(quality.recommendations)}):")
            for rec in quality.recommendations:
                print(f"   - {rec}")
    else:
        print("❌ No sample workflow found for analysis")

def demo_single_workflow_upgrade():
    """Demonstrate upgrading a single workflow"""
    print("\n🔧 DEMO: Single Workflow Upgrade")
    print("=" * 50)
    
    upgrader = FinalExcellenceUpgrader()
    
    # Find a sample workflow to upgrade
    sample_workflow = None
    for category_dir in upgrader.workflows_dir.iterdir():
        if category_dir.is_dir():
            workflow_files = list(category_dir.glob('*.json'))
            if workflow_files:
                sample_workflow = workflow_files[0]
                break
    
    if sample_workflow:
        print(f"📄 Upgrading sample workflow: {sample_workflow.name}")
        
        # Show before upgrade
        with open(sample_workflow, 'r', encoding='utf-8') as f:
            original_data = json.load(f)
        
        original_quality = upgrader.calculate_workflow_quality(original_data)
        print(f"   Initial Score: {original_quality.score:.1f}/100")
        print(f"   Initial Category: {original_quality.category.title()}")
        
        # Perform upgrade
        result = upgrader.upgrade_single_workflow(sample_workflow)
        
        if result['success']:
            print(f"\n✅ Upgrade Successful!")
            print(f"   Final Score: {result['final_score']:.1f}/100")
            print(f"   Improvement: +{result['improvement']:.1f} points")
            print(f"   Quality Category: {result['quality_category'].title()}")
            print(f"   Fixes Applied: {', '.join(result['fixes_applied'])}")
        else:
            print(f"\n❌ Upgrade Failed: {result.get('error', 'Unknown error')}")
    else:
        print("❌ No sample workflow found for upgrade")

def demo_workflow_statistics():
    """Demonstrate workflow statistics and patterns"""
    print("\n📈 DEMO: Workflow Statistics")
    print("=" * 50)
    
    upgrader = FinalExcellenceUpgrader()
    
    # Count workflows by category
    category_counts = {}
    total_workflows = 0
    
    for category_dir in upgrader.workflows_dir.iterdir():
        if category_dir.is_dir():
            workflow_count = len(list(category_dir.glob('*.json')))
            category_counts[category_dir.name] = workflow_count
            total_workflows += workflow_count
    
    print(f"📊 Workflow Statistics:")
    print(f"   Total Workflows: {total_workflows}")
    print(f"   Categories: {len(category_counts)}")
    
    print(f"\n📁 Top Categories:")
    sorted_categories = sorted(category_counts.items(), key=lambda x: x[1], reverse=True)
    for category, count in sorted_categories[:10]:
        print(f"   {category}: {count} workflows")

def main():
    """Run all demonstrations"""
    print("🎯 Final Excellence Upgrader - Demo Mode")
    print("=" * 60)
    
    try:
        # Demo 1: Workflow Analysis
        demo_workflow_analysis()
        
        # Demo 2: Single Workflow Upgrade
        demo_single_workflow_upgrade()
        
        # Demo 3: Workflow Statistics
        demo_workflow_statistics()
        
        print(f"\n🎉 Demo completed successfully!")
        print(f"💡 To run the full upgrade, use: python final_excellence_upgrader.py")
        
    except Exception as e:
        print(f"❌ Demo failed: {e}")
        print(f"💡 Make sure you have workflow files in the 'workflows' directory")

if __name__ == "__main__":
    main()
