"""
Graph traversal and analysis for module dependencies.
"""

from typing import Dict, Set, List, Tuple
from collections import deque

# Handle imports whether run as script or module
try:
    from scanner import Module
except ImportError:
    from .scanner import Module


class DependencyGraph:
    """Analyzes and traverses module dependency graph."""

    def __init__(self, modules: Dict[str, Module]):
        self.modules = modules

    def get_impact(self, module_name: str) -> Dict[str, Set[str]]:
        """
        Get the impact of disabling/changing a module.

        Returns:
            Dict with:
              - 'direct': modules that directly depend on this
              - 'transitive': all modules affected (directly + indirectly)
              - 'depth': dict mapping module -> distance from source
        """
        module = self._find_module(module_name)
        if not module:
            return {'direct': set(), 'transitive': set(), 'depth': {}}

        # Direct dependents
        direct = set(module.required_by)

        # Transitive dependents (BFS)
        transitive = set()
        depth_map = {}
        visited = set()
        queue = deque([(module_name, 0)])

        while queue:
            current_name, depth = queue.popleft()

            if current_name in visited:
                continue
            visited.add(current_name)

            current = self._find_module(current_name)
            if not current:
                continue

            # Add all dependents
            for dependent_name in current.required_by:
                if dependent_name not in visited:
                    transitive.add(dependent_name)
                    depth_map[dependent_name] = depth + 1
                    queue.append((dependent_name, depth + 1))

        return {
            'direct': direct,
            'transitive': transitive,
            'depth': depth_map
        }

    def get_requirements(self, module_name: str) -> Dict[str, Set[str]]:
        """
        Get all requirements for a module to function.

        Returns:
            Dict with:
              - 'direct': modules this directly depends on
              - 'transitive': all requirements (directly + indirectly)
              - 'depth': dict mapping module -> distance from source
        """
        module = self._find_module(module_name)
        if not module:
            return {'direct': set(), 'transitive': set(), 'depth': {}}

        # Direct requirements
        direct = set(module.requires)

        # Transitive requirements (BFS)
        transitive = set()
        depth_map = {}
        visited = set()
        queue = deque([(module_name, 0)])

        while queue:
            current_name, depth = queue.popleft()

            if current_name in visited:
                continue
            visited.add(current_name)

            current = self._find_module(current_name)
            if not current:
                continue

            # Add all requirements
            for req_name in current.requires:
                if req_name not in visited:
                    transitive.add(req_name)
                    depth_map[req_name] = depth + 1
                    queue.append((req_name, depth + 1))

        return {
            'direct': direct,
            'transitive': transitive,
            'depth': depth_map
        }

    def detect_cycles(self) -> List[List[str]]:
        """Detect circular dependencies in the graph."""
        cycles = []
        visited = set()
        rec_stack = []

        def dfs(module_name: str, path: List[str]) -> bool:
            """DFS to find cycles."""
            if module_name in rec_stack:
                # Found a cycle
                cycle_start = rec_stack.index(module_name)
                cycle = rec_stack[cycle_start:] + [module_name]
                cycles.append(cycle)
                return True

            if module_name in visited:
                return False

            visited.add(module_name)
            rec_stack.append(module_name)

            module = self._find_module(module_name)
            if module:
                for dep in module.requires:
                    dfs(dep, path + [module_name])

            rec_stack.remove(module_name)
            return False

        for module_name in self.modules:
            if module_name not in visited:
                dfs(module_name, [])

        return cycles

    def get_orphans(self) -> Set[str]:
        """Find modules that nothing depends on (potential cleanup candidates)."""
        orphans = set()

        for module_name, module in self.modules.items():
            # Orphan = nothing requires it, and it's not a top-level service
            if not module.required_by and module.kind in ['service', 'container']:
                orphans.add(module_name)

        return orphans

    def get_roots(self) -> Set[str]:
        """Find root modules (no dependencies)."""
        roots = set()

        for module_name, module in self.modules.items():
            if not module.requires:
                roots.add(module_name)

        return roots

    def get_modules_by_domain(self, domain: str) -> List[Module]:
        """Get all modules in a specific domain."""
        return [
            module for module in self.modules.values()
            if module.domain == domain
        ]

    def get_modules_by_kind(self, kind: str) -> List[Module]:
        """Get all modules of a specific kind."""
        return [
            module for module in self.modules.values()
            if module.kind == kind
        ]

    def _find_module(self, module_name: str) -> Module | None:
        """Find module by name, with fuzzy matching."""
        # Exact match
        if module_name in self.modules:
            return self.modules[module_name]

        # Partial match (find most specific)
        matches = [
            (name, module)
            for name, module in self.modules.items()
            if module_name in name or name in module_name
        ]

        if matches:
            # Prefer exact prefix matches
            exact = [(n, m) for n, m in matches if n.startswith(module_name)]
            if exact:
                return exact[0][1]

            # Otherwise return closest match
            return matches[0][1]

        return None

    def get_dependency_chain(self, from_module: str, to_module: str) -> List[List[str]]:
        """
        Find all dependency chains from one module to another.

        Returns list of paths (each path is a list of module names).
        """
        paths = []
        visited = set()

        def dfs(current: str, target: str, path: List[str]):
            if current == target:
                paths.append(path + [current])
                return

            if current in visited:
                return

            visited.add(current)

            module = self._find_module(current)
            if module:
                for dep in module.requires:
                    dfs(dep, target, path + [current])

            visited.remove(current)

        dfs(from_module, to_module, [])
        return paths

    def get_stats(self) -> Dict:
        """Get graph statistics."""
        total = len(self.modules)

        by_domain = {}
        by_kind = {}

        for module in self.modules.values():
            by_domain[module.domain] = by_domain.get(module.domain, 0) + 1
            by_kind[module.kind] = by_kind.get(module.kind, 0) + 1

        # Dependency statistics
        dep_counts = [len(m.requires) for m in self.modules.values()]
        avg_deps = sum(dep_counts) / len(dep_counts) if dep_counts else 0

        dependent_counts = [len(m.required_by) for m in self.modules.values()]
        avg_dependents = sum(dependent_counts) / len(dependent_counts) if dependent_counts else 0

        return {
            'total_modules': total,
            'by_domain': by_domain,
            'by_kind': by_kind,
            'avg_dependencies': round(avg_deps, 2),
            'avg_dependents': round(avg_dependents, 2),
            'roots': len(self.get_roots()),
            'orphans': len(self.get_orphans()),
        }
