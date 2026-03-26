"""
Output formatters for dependency graph visualization.
"""

import json
from typing import Dict, Set, List

# Handle imports whether run as script or module
try:
    from scanner import Module
    from graph import DependencyGraph
except ImportError:
    from .scanner import Module
    from .graph import DependencyGraph


class TextFormatter:
    """Format graph output as human-readable text."""

    @staticmethod
    def format_module_tree(module: Module, graph: DependencyGraph, show_reverse: bool = False) -> str:
        """
        Format a module and its dependencies as a tree.

        Example:
          hwc.server.jellyfin
            ├─ requires → hwc.infrastructure.hardware.gpu
            ├─ requires → hwc.services.reverseProxy
            └─ provides → media-server:8096:/media
        """
        lines = []

        # Module header
        header = f"{module.name}"
        if module.description:
            header += f" - {module.description}"
        lines.append(header)

        # Requirements
        if module.requires:
            req_list = sorted(module.requires)
            for i, req in enumerate(req_list):
                prefix = "├─" if i < len(req_list) - 1 or module.required_by else "└─"
                lines.append(f"  {prefix} requires → {req}")

        # Required by (if showing reverse deps)
        if show_reverse and module.required_by:
            req_by_list = sorted(module.required_by)
            for i, req_by in enumerate(req_by_list):
                prefix = "└─" if i == len(req_by_list) - 1 else "├─"
                lines.append(f"  {prefix} required by → {req_by}")

        return "\n".join(lines)

    @staticmethod
    def format_impact_analysis(module_name: str, impact: Dict[str, Set[str]],
                                graph: DependencyGraph) -> str:
        """Format impact analysis output."""
        lines = []

        lines.append(f"Impact Analysis: {module_name}")
        lines.append("=" * 80)

        direct = sorted(impact['direct'])
        transitive = sorted(impact['transitive'] - impact['direct'])

        if not direct and not transitive:
            lines.append("\nNo modules depend on this one.")
            lines.append("✅ Safe to disable/modify")
            return "\n".join(lines)

        # Direct impact
        if direct:
            lines.append(f"\nDirect Dependents ({len(direct)}):")
            lines.append("These will IMMEDIATELY break if you disable this module:\n")
            for dep in direct:
                module = graph.modules.get(dep)
                kind = f"[{module.kind}]" if module else ""
                lines.append(f"  ❌ {dep} {kind}")

        # Transitive impact
        if transitive:
            lines.append(f"\nTransitive Dependents ({len(transitive)}):")
            lines.append("These will break indirectly:\n")

            # Group by depth
            by_depth: Dict[int, List[str]] = {}
            for mod in transitive:
                depth = impact['depth'].get(mod, 0)
                if depth not in by_depth:
                    by_depth[depth] = []
                by_depth[depth].append(mod)

            for depth in sorted(by_depth.keys()):
                mods = sorted(by_depth[depth])
                lines.append(f"  Depth {depth}:")
                for mod in mods:
                    module = graph.modules.get(mod)
                    kind = f"[{module.kind}]" if module else ""
                    lines.append(f"    ⚠️  {mod} {kind}")

        # Summary
        total_impact = len(direct) + len(transitive)
        lines.append(f"\n{'='*80}")
        lines.append(f"Total Impact: {total_impact} module(s) will be affected")

        if total_impact > 0:
            lines.append("⚠️  Disabling this module requires careful consideration")
        else:
            lines.append("✅ Safe to disable/modify")

        return "\n".join(lines)

    @staticmethod
    def format_requirements_analysis(module_name: str, requirements: Dict[str, Set[str]],
                                     graph: DependencyGraph) -> str:
        """Format requirements analysis output."""
        lines = []

        lines.append(f"Requirements Analysis: {module_name}")
        lines.append("=" * 80)

        direct = sorted(requirements['direct'])
        transitive = sorted(requirements['transitive'] - requirements['direct'])

        if not direct and not transitive:
            lines.append("\nThis module has no dependencies.")
            lines.append("✅ Standalone module")
            return "\n".join(lines)

        # Direct requirements
        if direct:
            lines.append(f"\nDirect Dependencies ({len(direct)}):")
            lines.append("These MUST be enabled for this module to work:\n")
            for req in direct:
                module = graph.modules.get(req)
                kind = f"[{module.kind}]" if module else ""
                lines.append(f"  ✓ {req} {kind}")

        # Transitive requirements
        if transitive:
            lines.append(f"\nTransitive Dependencies ({len(transitive)}):")
            lines.append("These are also needed (indirectly):\n")

            # Group by depth
            by_depth: Dict[int, List[str]] = {}
            for mod in transitive:
                depth = requirements['depth'].get(mod, 0)
                if depth not in by_depth:
                    by_depth[depth] = []
                by_depth[depth].append(mod)

            for depth in sorted(by_depth.keys()):
                mods = sorted(by_depth[depth])
                lines.append(f"  Depth {depth}:")
                for mod in mods:
                    module = graph.modules.get(mod)
                    kind = f"[{module.kind}]" if module else ""
                    lines.append(f"    → {mod} {kind}")

        # Summary
        total_reqs = len(direct) + len(transitive)
        lines.append(f"\n{'='*80}")
        lines.append(f"Total Requirements: {total_reqs} module(s) must be enabled")

        return "\n".join(lines)

    @staticmethod
    def format_module_list(modules: Dict[str, Module], graph: DependencyGraph) -> str:
        """Format a compact list of all modules."""
        lines = []

        # Group by domain
        by_domain: Dict[str, List[Module]] = {}
        for module in modules.values():
            if module.domain not in by_domain:
                by_domain[module.domain] = []
            by_domain[module.domain].append(module)

        for domain in sorted(by_domain.keys()):
            mods = sorted(by_domain[domain], key=lambda m: m.name)
            lines.append(f"\n{domain.upper()} ({len(mods)} modules)")
            lines.append("-" * 80)

            for mod in mods:
                # Format: name [kind] (X deps, Y dependents)
                deps_count = len(mod.requires)
                dependents_count = len(mod.required_by)

                info = f"[{mod.kind}]"
                if deps_count > 0 or dependents_count > 0:
                    info += f" ({deps_count} deps, {dependents_count} dependents)"

                lines.append(f"  {mod.name} {info}")

                # Show direct dependencies inline
                if mod.requires:
                    deps = sorted(list(mod.requires)[:3])  # Show first 3
                    deps_str = ", ".join(deps)
                    if len(mod.requires) > 3:
                        deps_str += f" + {len(mod.requires) - 3} more"
                    lines.append(f"    ↳ requires: {deps_str}")

        return "\n".join(lines)


class JSONFormatter:
    """Format graph data as JSON."""

    @staticmethod
    def format_graph(modules: Dict[str, Module]) -> str:
        """Export entire graph as JSON."""
        data = {
            "modules": [],
            "edges": []
        }

        # Modules
        for module in modules.values():
            data["modules"].append({
                "name": module.name,
                "domain": module.domain,
                "kind": module.kind,
                "description": module.description,
                "ports": module.ports,
                "path": str(module.path.relative_to(module.path.parent.parent.parent)),
                "dependencies_count": len(module.requires),
                "dependents_count": len(module.required_by)
            })

        # Edges
        for module in modules.values():
            for dep in module.requires:
                data["edges"].append({
                    "from": module.name,
                    "to": dep,
                    "type": "requires"
                })

        return json.dumps(data, indent=2)

    @staticmethod
    def format_impact(module_name: str, impact: Dict[str, Set[str]]) -> str:
        """Export impact analysis as JSON."""
        data = {
            "module": module_name,
            "impact": {
                "direct": sorted(list(impact['direct'])),
                "transitive": sorted(list(impact['transitive'])),
                "total": len(impact['direct']) + len(impact['transitive']),
                "depth_map": {k: v for k, v in impact['depth'].items()}
            }
        }
        return json.dumps(data, indent=2)

    @staticmethod
    def format_requirements(module_name: str, requirements: Dict[str, Set[str]]) -> str:
        """Export requirements analysis as JSON."""
        data = {
            "module": module_name,
            "requirements": {
                "direct": sorted(list(requirements['direct'])),
                "transitive": sorted(list(requirements['transitive'])),
                "total": len(requirements['direct']) + len(requirements['transitive']),
                "depth_map": {k: v for k, v in requirements['depth'].items()}
            }
        }
        return json.dumps(data, indent=2)
