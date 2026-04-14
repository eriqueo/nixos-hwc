#!/usr/bin/env python3
"""
hwc-graph: Dependency graph analysis tool for NixOS HWC configuration.

Usage:
    hwc-graph list                    List all modules
    hwc-graph show <module>           Show details for a specific module
    hwc-graph impact <module>         Show what depends on this module
    hwc-graph requirements <module>   Show what this module requires
    hwc-graph export [--format=json]  Export graph data
    hwc-graph stats                   Show graph statistics
"""

import sys
import argparse
from pathlib import Path

from scanner import scan_repository
from graph import DependencyGraph
from formatters import TextFormatter, JSONFormatter


def find_repo_root() -> Path:
    """Find the repository root (contains flake.nix)."""
    current = Path.cwd()

    # Try current directory and parents
    for path in [current] + list(current.parents):
        if (path / "flake.nix").exists():
            return path

    # Fallback: assume we're in workspace/nixos/graph
    # and go up to repo root
    script_dir = Path(__file__).parent
    if script_dir.name == "graph":
        repo_root = script_dir.parent.parent.parent
        if (repo_root / "flake.nix").exists():
            return repo_root

    print("Error: Could not find repository root (no flake.nix found)")
    print(f"Current directory: {current}")
    sys.exit(1)


def cmd_list(args, modules, graph):
    """List all modules."""
    output = TextFormatter.format_module_list(modules, graph)
    print(output)

    # Print summary
    stats = graph.get_stats()
    print(f"\n{'='*80}")
    print(f"Total: {stats['total_modules']} modules across {len(stats['by_domain'])} domains")


def cmd_show(args, modules, graph):
    """Show details for a specific module."""
    module_name = args.module

    # Find module (with fuzzy matching)
    module = None
    if module_name in modules:
        module = modules[module_name]
    else:
        # Try partial match
        matches = [m for name, m in modules.items() if module_name in name]
        if len(matches) == 1:
            module = matches[0]
        elif len(matches) > 1:
            print(f"Ambiguous module name '{module_name}'. Matches:")
            for m in matches[:10]:
                print(f"  - {m.name}")
            sys.exit(1)

    if not module:
        print(f"Error: Module '{module_name}' not found")
        print(f"\nTry: hwc-graph list")
        sys.exit(1)

    # Show module details
    output = TextFormatter.format_module_tree(module, graph, show_reverse=True)
    print(output)

    # Additional metadata
    print(f"\nDomain: {module.domain}")
    print(f"Kind: {module.kind}")
    print(f"Path: {module.path}")

    if module.ports:
        print(f"Ports: {', '.join(map(str, module.ports))}")


def cmd_impact(args, modules, graph):
    """Show impact analysis for a module."""
    module_name = args.module

    # Find module (allow partial matches)
    if module_name not in modules:
        matches = [name for name in modules if module_name in name]
        if len(matches) == 1:
            module_name = matches[0]
        elif len(matches) > 1:
            print(f"Ambiguous module name '{module_name}'. Did you mean:")
            for m in matches[:10]:
                print(f"  - {m}")
            sys.exit(1)
        else:
            print(f"Error: Module '{module_name}' not found")
            sys.exit(1)

    impact = graph.get_impact(module_name)

    if args.format == 'json':
        output = JSONFormatter.format_impact(module_name, impact)
    else:
        output = TextFormatter.format_impact_analysis(module_name, impact, graph)

    print(output)


def cmd_requirements(args, modules, graph):
    """Show requirements analysis for a module."""
    module_name = args.module

    # Find module (allow partial matches)
    if module_name not in modules:
        matches = [name for name in modules if module_name in name]
        if len(matches) == 1:
            module_name = matches[0]
        elif len(matches) > 1:
            print(f"Ambiguous module name '{module_name}'. Did you mean:")
            for m in matches[:10]:
                print(f"  - {m}")
            sys.exit(1)
        else:
            print(f"Error: Module '{module_name}' not found")
            sys.exit(1)

    requirements = graph.get_requirements(module_name)

    if args.format == 'json':
        output = JSONFormatter.format_requirements(module_name, requirements)
    else:
        output = TextFormatter.format_requirements_analysis(module_name, requirements, graph)

    print(output)


def cmd_export(args, modules, graph):
    """Export graph data."""
    if args.format == 'json':
        output = JSONFormatter.format_graph(modules)
        print(output)
    else:
        print("Error: Only JSON format is supported for export")
        sys.exit(1)


def cmd_stats(args, modules, graph):
    """Show graph statistics."""
    stats = graph.get_stats()

    print("Graph Statistics")
    print("=" * 80)
    print(f"\nTotal Modules: {stats['total_modules']}")

    print(f"\nBy Domain:")
    for domain, count in sorted(stats['by_domain'].items()):
        print(f"  {domain}: {count}")

    print(f"\nBy Kind:")
    for kind, count in sorted(stats['by_kind'].items()):
        print(f"  {kind}: {count}")

    print(f"\nDependency Stats:")
    print(f"  Average dependencies per module: {stats['avg_dependencies']}")
    print(f"  Average dependents per module: {stats['avg_dependents']}")
    print(f"  Root modules (no dependencies): {stats['roots']}")
    print(f"  Orphan modules (nothing depends on): {stats['orphans']}")

    # Check for cycles
    cycles = graph.detect_cycles()
    if cycles:
        print(f"\n⚠️  Circular Dependencies Detected: {len(cycles)}")
        for i, cycle in enumerate(cycles[:5], 1):
            print(f"  {i}. {' → '.join(cycle)}")
    else:
        print(f"\n✅ No circular dependencies detected")


def main():
    parser = argparse.ArgumentParser(
        description='Dependency graph analysis for NixOS HWC configuration',
        formatter_class=argparse.RawDescriptionHelpFormatter
    )

    subparsers = parser.add_subparsers(dest='command', help='Command to run')

    # list command
    subparsers.add_parser('list', help='List all modules')

    # show command
    show_parser = subparsers.add_parser('show', help='Show module details')
    show_parser.add_argument('module', help='Module name (supports partial match)')

    # impact command
    impact_parser = subparsers.add_parser('impact', help='Show impact analysis')
    impact_parser.add_argument('module', help='Module name')
    impact_parser.add_argument('--format', choices=['text', 'json'], default='text')

    # requirements command
    req_parser = subparsers.add_parser('requirements', help='Show requirements analysis')
    req_parser.add_argument('module', help='Module name')
    req_parser.add_argument('--format', choices=['text', 'json'], default='text')

    # export command
    export_parser = subparsers.add_parser('export', help='Export graph data')
    export_parser.add_argument('--format', choices=['json'], default='json')

    # stats command
    subparsers.add_parser('stats', help='Show graph statistics')

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        sys.exit(1)

    # Find repository root
    repo_root = find_repo_root()
    print(f"Repository: {repo_root}\n", file=sys.stderr)

    # Scan repository
    modules = scan_repository(repo_root)
    graph = DependencyGraph(modules)

    # Execute command
    commands = {
        'list': cmd_list,
        'show': cmd_show,
        'impact': cmd_impact,
        'requirements': cmd_requirements,
        'export': cmd_export,
        'stats': cmd_stats,
    }

    cmd_func = commands.get(args.command)
    if cmd_func:
        cmd_func(args, modules, graph)
    else:
        print(f"Unknown command: {args.command}")
        parser.print_help()
        sys.exit(1)


if __name__ == '__main__':
    main()
