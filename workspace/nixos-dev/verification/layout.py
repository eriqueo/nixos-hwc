"""Parse Nix syntax to keep the flake as composition and tests out of modules."""
from pathlib import Path
import sys
from tree_sitter import Language, Parser
import tree_sitter_nix


def nodes(node):
    yield node
    for child in node.named_children:
        yield from nodes(child)


def inspect(root):
    parser = Parser(Language(tree_sitter_nix.language()))
    def parse(path):
        tree = parser.parse(path.read_bytes())
        if tree.root_node.has_error:
            raise ValueError(f'{path}: invalid Nix syntax')
        return tree.root_node
    tree = parse(root / 'flake.nix')
    bindings = [n for n in nodes(tree) if n.type == 'binding']
    checks = [n for n in bindings if n.named_children[0].text.startswith(b'checks.')]
    if len(checks) != 1 or checks[0].named_children[0].text != b'checks.${system}':
        raise ValueError('Checks must have one registered composition output')
    value = checks[0].child_by_field_name('expression')
    if value.type != 'select_expression' or value.text != b'verification.checks':
        raise ValueError('Inline or unregistered flake checks are forbidden')
    for path in (root / 'domains').rglob('*.nix'):
        relative = path.relative_to(root)
        if 'verification' in relative.parts:
            if path.name == 'index.nix':
                raise ValueError(f'{relative}: verification is not a module directory')
            continue
        for node in nodes(parse(path)):
            if node.type == 'path_expression' and b'/verification' in node.text:
                raise ValueError(f'{relative}: production module references verification')


if __name__ == '__main__':
    try:
        inspect(Path(sys.argv[1]))
    except (OSError, ValueError) as error:
        sys.exit(str(error))
