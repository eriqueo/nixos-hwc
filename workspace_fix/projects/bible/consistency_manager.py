#!/usr/bin/env python3
"""
Cross-Bible Consistency Manager
Ensures technical accuracy and coherence across all bible documentation files
by validating shared configurations, cross-references, and system-wide consistency.
"""

import json
import re
import sys
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Optional, Tuple, Any, Set
from dataclasses import dataclass
from enum import Enum
import yaml

# Configuration paths
BIBLE_CONFIG_PATH = Path("/etc/nixos/config/bible_categories.yaml")
BIBLES_DIR = Path("/etc/nixos/docs/bibles")
CONSISTENCY_LOG = Path("/etc/nixos/docs/consistency-validation.log")

class ImpactLevel(Enum):
    LOW = 1
    MODERATE = 2
    HIGH = 3
    CRITICAL = 4

class ConfidenceLevel(Enum):
    LOW = 1
    MEDIUM = 2
    HIGH = 3

@dataclass
class ConsistencyIssue:
    type: str
    source: str
    target: Optional[str]
    description: str
    severity: str
    auto_resolvable: bool = False
    confidence: ConfidenceLevel = ConfidenceLevel.MEDIUM

@dataclass
class Resolution:
    action: str
    target: Optional[str] = None
    old_value: Optional[str] = None
    new_value: Optional[str] = None
    confidence: ConfidenceLevel = ConfidenceLevel.MEDIUM
    applied: bool = False

@dataclass
class BibleValidationResult:
    bible_name: str
    status: str  # "pass", "warnings", "errors"
    consistency_score: float  # 0-100
    issues_found: List[ConsistencyIssue]
    resolutions_applied: List[Resolution]

@dataclass
class ConsistencyReport:
    validation_timestamp: datetime
    overall_status: str  # "pass", "issues_found", "critical_errors"  
    bible_results: Dict[str, BibleValidationResult]
    cross_reference_issues: List[ConsistencyIssue]
    automatic_resolutions: List[Resolution]
    manual_review_required: List[ConsistencyIssue]

class ConsistencyManager:
    def __init__(self):
        self.bible_config = self._load_bible_config()
        self.consistency_rules = self._load_consistency_rules()
        
    def _load_bible_config(self) -> Dict[str, Any]:
        """Load bible configuration from YAML file"""
        try:
            with open(BIBLE_CONFIG_PATH, 'r') as f:
                return yaml.safe_load(f)
        except Exception as e:
            raise Exception(f"Failed to load bible configuration: {e}")
    
    def _load_consistency_rules(self) -> Dict[str, Dict]:
        """Load consistency rules from bible configuration"""
        return self.bible_config.get("consistency_rules", {})
    
    def _log(self, message: str, level: str = "INFO"):
        """Log message with timestamp"""
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        log_message = f"[{timestamp}] {level}: {message}\n"
        
        with open(CONSISTENCY_LOG, 'a') as f:
            f.write(log_message)
        
        print(f"{level}: {message}")
    
    def _load_bible_content(self, bible_name: str) -> str:
        """Load content from a bible file"""
        bible_config = self.bible_config["bible_categories"].get(bible_name, {})
        filename = bible_config.get("filename", f"{bible_name}.md")
        bible_path = BIBLES_DIR / filename
        
        if not bible_path.exists():
            return ""
        
        try:
            with open(bible_path, 'r') as f:
                return f.read()
        except Exception as e:
            self._log(f"Failed to load bible {bible_name}: {e}", "ERROR")
            return ""
    
    def _extract_pattern_values(self, content: str, pattern: str) -> List[str]:
        """Extract values matching a regex pattern from content"""
        try:
            matches = re.findall(pattern, content, re.MULTILINE | re.IGNORECASE)
            return matches if isinstance(matches, list) else [matches] if matches else []
        except re.error as e:
            self._log(f"Invalid regex pattern '{pattern}': {e}", "ERROR")
            return []
    
    def _extract_cross_references(self, content: str) -> List[Dict[str, str]]:
        """Extract cross-references to other bibles from content"""
        cross_refs = []
        
        # Pattern to match cross-references like "See Hardware & GPU Bible" or "Container Services Bible"
        ref_patterns = [
            r"(?:see|refer to|check)\s+([A-Z][a-zA-Z\s&]+Bible)",
            r"([A-Z][a-zA-Z\s&]+Bible)\s+(?:for|contains|provides)",
            r"\[([A-Z][a-zA-Z\s&]+Bible)\]"
        ]
        
        for pattern in ref_patterns:
            matches = re.findall(pattern, content, re.IGNORECASE)
            for match in matches:
                bible_name = match.strip()
                cross_refs.append({
                    "target_bible": bible_name,
                    "reference_text": match
                })
        
        return cross_refs
    
    def _validate_cross_references(self, source_bible: str, content: str) -> List[ConsistencyIssue]:
        """Validate that cross-references between bibles are accurate"""
        issues = []
        cross_refs = self._extract_cross_references(content)
        
        # Map bible display names to internal names
        bible_name_map = {}
        for internal_name, config in self.bible_config["bible_categories"].items():
            display_name = config["name"]
            bible_name_map[display_name.lower()] = internal_name
        
        for ref in cross_refs:
            target_display_name = ref["target_bible"].lower()
            
            if target_display_name in bible_name_map:
                target_bible = bible_name_map[target_display_name]
                target_content = self._load_bible_content(target_bible)
                
                if not target_content:
                    issues.append(ConsistencyIssue(
                        type="broken_cross_reference",
                        source=source_bible,
                        target=target_bible,
                        description=f"Referenced bible '{ref['target_bible']}' is empty or missing",
                        severity="high"
                    ))
            else:
                issues.append(ConsistencyIssue(
                    type="invalid_cross_reference",
                    source=source_bible,
                    target=None,
                    description=f"Referenced bible '{ref['target_bible']}' does not exist",
                    severity="high"
                ))
        
        return issues
    
    def _validate_configuration_consistency(self, rule_name: str, rule_config: Dict) -> List[ConsistencyIssue]:
        """Validate configuration consistency according to a specific rule"""
        issues = []
        
        source_bible = rule_config["source_bible"]
        dependent_bibles = rule_config["dependent_bibles"]
        validation_rule = rule_config["validation"]
        
        source_content = self._load_bible_content(source_bible)
        if not source_content:
            issues.append(ConsistencyIssue(
                type="missing_source_bible",
                source=source_bible,
                target=None,
                description=f"Source bible '{source_bible}' for rule '{rule_name}' is missing",
                severity="critical"
            ))
            return issues
        
        # Extract authoritative values from source bible
        source_values = set()
        if "pattern" in rule_config:
            pattern_matches = self._extract_pattern_values(source_content, rule_config["pattern"])
            source_values.update(pattern_matches)
        
        # Check each dependent bible
        for dependent_bible in dependent_bibles:
            dependent_content = self._load_bible_content(dependent_bible)
            
            if not dependent_content:
                issues.append(ConsistencyIssue(
                    type="missing_dependent_bible",
                    source=source_bible,
                    target=dependent_bible,
                    description=f"Dependent bible '{dependent_bible}' is missing",
                    severity="medium"
                ))
                continue
            
            # Extract values from dependent bible
            dependent_values = set()
            if "pattern" in rule_config:
                pattern_matches = self._extract_pattern_values(dependent_content, rule_config["pattern"])
                dependent_values.update(pattern_matches)
            
            # Check for inconsistencies based on validation type
            if validation_rule == "GPU device paths and environment variables must match":
                missing_in_dependent = source_values - dependent_values
                for missing_value in missing_in_dependent:
                    issues.append(ConsistencyIssue(
                        type="configuration_mismatch",
                        source=source_bible,
                        target=dependent_bible,
                        description=f"GPU configuration '{missing_value}' missing from {dependent_bible}",
                        severity="high",
                        auto_resolvable=True
                    ))
            
            elif validation_rule == "Service names in monitoring and storage configs must match container definitions":
                # Check service name consistency
                source_services = {v for v in source_values if "podman-" in v}
                dependent_services = {v for v in dependent_values if "podman-" in v}
                
                inconsistent_services = source_services.symmetric_difference(dependent_services)
                for service in inconsistent_services:
                    issues.append(ConsistencyIssue(
                        type="service_name_mismatch",
                        source=source_bible,
                        target=dependent_bible,
                        description=f"Service name '{service}' inconsistent between bibles",
                        severity="medium",
                        auto_resolvable=True
                    ))
        
        return issues
    
    def _calculate_consistency_score(self, issues: List[ConsistencyIssue]) -> float:
        """Calculate overall consistency score based on issues found"""
        if not issues:
            return 100.0
        
        severity_weights = {
            "critical": 25,
            "high": 15,
            "medium": 10,
            "low": 5
        }
        
        total_penalty = sum(severity_weights.get(issue.severity, 5) for issue in issues)
        score = max(0, 100 - total_penalty)
        return score
    
    def _generate_automatic_resolutions(self, issues: List[ConsistencyIssue]) -> List[Resolution]:
        """Generate automatic resolutions for resolvable issues"""
        resolutions = []
        
        for issue in issues:
            if issue.auto_resolvable:
                if issue.type == "configuration_mismatch":
                    resolutions.append(Resolution(
                        action="update_dependent",
                        target=issue.target,
                        old_value="<missing>",
                        new_value=f"Add missing configuration from {issue.source}",
                        confidence=ConfidenceLevel.HIGH
                    ))
                elif issue.type == "service_name_mismatch":
                    resolutions.append(Resolution(
                        action="standardize_naming",
                        target=issue.target,
                        old_value="inconsistent",
                        new_value="standardized service naming",
                        confidence=ConfidenceLevel.MEDIUM
                    ))
        
        return resolutions
    
    def validate_bible_consistency(self, bible_name: str) -> BibleValidationResult:
        """Validate consistency for a specific bible"""
        self._log(f"Starting consistency validation for: {bible_name}")
        
        issues = []
        
        # Load bible content
        content = self._load_bible_content(bible_name)
        if not content:
            return BibleValidationResult(
                bible_name=bible_name,
                status="errors",
                consistency_score=0,
                issues_found=[ConsistencyIssue(
                    type="missing_bible",
                    source=bible_name,
                    target=None,
                    description=f"Bible file not found or empty",
                    severity="critical"
                )],
                resolutions_applied=[]
            )
        
        # Validate cross-references
        cross_ref_issues = self._validate_cross_references(bible_name, content)
        issues.extend(cross_ref_issues)
        
        # Validate against consistency rules
        for rule_name, rule_config in self.consistency_rules.items():
            if bible_name == rule_config["source_bible"] or bible_name in rule_config.get("dependent_bibles", []):
                rule_issues = self._validate_configuration_consistency(rule_name, rule_config)
                issues.extend(rule_issues)
        
        # Generate automatic resolutions
        resolutions = self._generate_automatic_resolutions(issues)
        
        # Calculate consistency score
        consistency_score = self._calculate_consistency_score(issues)
        
        # Determine overall status
        status = "pass"
        if any(issue.severity == "critical" for issue in issues):
            status = "errors"
        elif any(issue.severity in ["high", "medium"] for issue in issues):
            status = "warnings"
        
        self._log(f"Consistency validation complete for {bible_name}: {status} (score: {consistency_score})")
        
        return BibleValidationResult(
            bible_name=bible_name,
            status=status,
            consistency_score=consistency_score,
            issues_found=issues,
            resolutions_applied=resolutions
        )
    
    def validate_all_bibles(self) -> ConsistencyReport:
        """Validate consistency across all bibles"""
        self._log("Starting comprehensive consistency validation")
        
        bible_results = {}
        all_issues = []
        all_resolutions = []
        
        # Validate each bible individually
        for bible_name in self.bible_config["bible_categories"].keys():
            result = self.validate_bible_consistency(bible_name)
            bible_results[bible_name] = result
            all_issues.extend(result.issues_found)
            all_resolutions.extend(result.resolutions_applied)
        
        # Separate cross-reference issues and manual review items
        cross_reference_issues = [issue for issue in all_issues if "cross_reference" in issue.type]
        automatic_resolutions = [res for res in all_resolutions if res.confidence >= ConfidenceLevel.HIGH]
        manual_review_required = [issue for issue in all_issues 
                                if not issue.auto_resolvable and issue.severity in ["critical", "high"]]
        
        # Determine overall status
        overall_status = "pass"
        if any(result.status == "errors" for result in bible_results.values()):
            overall_status = "critical_errors"
        elif any(result.status == "warnings" for result in bible_results.values()):
            overall_status = "issues_found"
        
        report = ConsistencyReport(
            validation_timestamp=datetime.now(),
            overall_status=overall_status,
            bible_results=bible_results,
            cross_reference_issues=cross_reference_issues,
            automatic_resolutions=automatic_resolutions,
            manual_review_required=manual_review_required
        )
        
        self._log(f"Comprehensive validation complete: {overall_status}")
        return report
    
    def generate_consistency_report(self, report: ConsistencyReport) -> str:
        """Generate human-readable consistency report"""
        output = []
        output.append("# Bible Consistency Validation Report")
        output.append(f"**Generated**: {report.validation_timestamp.strftime('%Y-%m-%d %H:%M:%S')}")
        output.append(f"**Overall Status**: {report.overall_status.upper()}")
        output.append("")
        
        # Summary statistics
        total_issues = sum(len(result.issues_found) for result in report.bible_results.values())
        avg_score = sum(result.consistency_score for result in report.bible_results.values()) / len(report.bible_results)
        
        output.append("## Summary")
        output.append(f"- **Bibles Validated**: {len(report.bible_results)}")
        output.append(f"- **Total Issues Found**: {total_issues}")
        output.append(f"- **Average Consistency Score**: {avg_score:.1f}%")
        output.append(f"- **Automatic Resolutions**: {len(report.automatic_resolutions)}")
        output.append(f"- **Manual Review Required**: {len(report.manual_review_required)}")
        output.append("")
        
        # Bible-specific results
        output.append("## Bible Validation Results")
        for bible_name, result in report.bible_results.items():
            status_emoji = "✅" if result.status == "pass" else "⚠️" if result.status == "warnings" else "❌"
            output.append(f"### {status_emoji} {bible_name.replace('_', ' ').title()}")
            output.append(f"- **Status**: {result.status}")
            output.append(f"- **Consistency Score**: {result.consistency_score:.1f}%")
            output.append(f"- **Issues Found**: {len(result.issues_found)}")
            
            if result.issues_found:
                output.append("- **Issues**:")
                for issue in result.issues_found[:5]:  # Show first 5 issues
                    output.append(f"  - {issue.severity.upper()}: {issue.description}")
                if len(result.issues_found) > 5:
                    output.append(f"  - ... and {len(result.issues_found) - 5} more")
            output.append("")
        
        # Manual review items
        if report.manual_review_required:
            output.append("## Manual Review Required")
            for issue in report.manual_review_required:
                output.append(f"- **{issue.severity.upper()}**: {issue.description}")
                if issue.target:
                    output.append(f"  - Source: {issue.source}, Target: {issue.target}")
            output.append("")
        
        return "\n".join(output)

def main():
    """CLI interface for consistency validation"""
    import argparse
    
    parser = argparse.ArgumentParser(description="Cross-Bible Consistency Manager")
    parser.add_argument("--bible", help="Validate specific bible only")
    parser.add_argument("--report", action="store_true", help="Generate detailed report")
    parser.add_argument("--json", action="store_true", help="Output results as JSON")
    
    args = parser.parse_args()
    
    try:
        manager = ConsistencyManager()
        
        if args.bible:
            # Validate specific bible
            result = manager.validate_bible_consistency(args.bible)
            
            if args.json:
                print(json.dumps({
                    "bible_name": result.bible_name,
                    "status": result.status,
                    "consistency_score": result.consistency_score,
                    "issues_count": len(result.issues_found),
                    "resolutions_count": len(result.resolutions_applied)
                }, indent=2))
            else:
                print(f"Bible: {result.bible_name}")
                print(f"Status: {result.status}")
                print(f"Consistency Score: {result.consistency_score:.1f}%")
                print(f"Issues Found: {len(result.issues_found)}")
        else:
            # Validate all bibles
            report = manager.validate_all_bibles()
            
            if args.json:
                # Convert report to JSON-serializable format
                json_report = {
                    "timestamp": report.validation_timestamp.isoformat(),
                    "overall_status": report.overall_status,
                    "bible_count": len(report.bible_results),
                    "total_issues": sum(len(r.issues_found) for r in report.bible_results.values()),
                    "automatic_resolutions": len(report.automatic_resolutions),
                    "manual_review_required": len(report.manual_review_required)
                }
                print(json.dumps(json_report, indent=2))
            elif args.report:
                print(manager.generate_consistency_report(report))
            else:
                print(f"Overall Status: {report.overall_status}")
                print(f"Bibles Validated: {len(report.bible_results)}")
                total_issues = sum(len(r.issues_found) for r in report.bible_results.values())
                print(f"Total Issues: {total_issues}")
                
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()