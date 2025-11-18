# domains/server/ai/local-workflows/parts/auto-doc.nix
#
# AI-powered code documentation generator (CLI tool)

{ config, lib, pkgs, cfg }:

let
  autoDocScript = pkgs.writeScriptBin "ai-doc" ''
    #!${pkgs.python3}/bin/python3
    import os
    import sys
    import argparse
    from pathlib import Path
    import requests

    # Configuration
    OLLAMA_ENDPOINT = "${cfg.ollamaEndpoint}"
    MODEL = "${cfg.autoDoc.model}"
    TEMPLATES_DIR = "${cfg.autoDoc.templates}"

    class Colors:
        BLUE = '\033[94m'
        GREEN = '\033[92m'
        YELLOW = '\033[93m'
        RED = '\033[91m'
        ENDC = '\033[0m'
        BOLD = '\033[1m'

    def print_colored(message, color=Colors.ENDC):
        """Print colored output"""
        print(f"{color}{message}{Colors.ENDC}")

    def query_ollama(prompt, max_tokens=2000):
        """Query Ollama API"""
        try:
            print_colored("🤖 Generating documentation...", Colors.BLUE)
            response = requests.post(
                f"{OLLAMA_ENDPOINT}/api/generate",
                json={
                    "model": MODEL,
                    "prompt": prompt,
                    "stream": False,
                    "options": {
                        "temperature": 0.2,
                        "num_predict": max_tokens,
                    }
                },
                timeout=120
            )
            response.raise_for_status()
            return response.json()["response"].strip()
        except Exception as e:
            print_colored(f"❌ Error querying Ollama: {e}", Colors.RED)
            return None

    def read_file(file_path):
        """Read file content"""
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                return f.read()
        except Exception as e:
            print_colored(f"❌ Error reading file: {e}", Colors.RED)
            return None

    def detect_language(file_path):
        """Detect programming language from extension"""
        ext_map = {
            '.py': 'Python',
            '.nix': 'Nix',
            '.sh': 'Bash',
            '.js': 'JavaScript',
            '.ts': 'TypeScript',
            '.rs': 'Rust',
            '.go': 'Go',
            '.c': 'C',
            '.cpp': 'C++',
            '.java': 'Java',
            '.rb': 'Ruby',
            '.php': 'PHP',
        }
        return ext_map.get(file_path.suffix.lower(), 'Unknown')

    def generate_function_docs(file_path, function_name=None):
        """Generate function documentation"""
        content = read_file(file_path)
        if not content:
            return

        language = detect_language(file_path)

        if function_name:
            prompt = f"""You are a technical documentation expert. Generate comprehensive documentation for the function '{function_name}' in this {language} file.

File: {file_path.name}

```{language.lower()}
{content}
```

Generate documentation in the appropriate format for {language}:
- For Python: Google-style or NumPy-style docstrings
- For Nix: Multi-line comments with parameter descriptions
- For Bash: Comment blocks with usage examples
- For others: Language-appropriate comment format

Include:
1. Brief description
2. Parameters with types and descriptions
3. Return value
4. Example usage
5. Any side effects or important notes

Only output the documentation, ready to paste into the code."""

        else:
            prompt = f"""You are a technical documentation expert. Generate comprehensive documentation for this {language} file.

File: {file_path.name}

```{language.lower()}
{content}
```

Generate a documentation comment block for the top of the file including:
1. File purpose and overview
2. Main functions/classes
3. Dependencies
4. Usage examples
5. Any important notes

Use the appropriate comment format for {language}."""

        doc = query_ollama(prompt, max_tokens=1500)

        if doc:
            print_colored("\n" + "="*80, Colors.GREEN)
            print_colored("Generated Documentation:", Colors.BOLD + Colors.GREEN)
            print_colored("="*80 + "\n", Colors.GREEN)
            print(doc)
            print_colored("\n" + "="*80 + "\n", Colors.GREEN)

            # Ask if user wants to save
            save = input(f"Save to file? (y/N): ").strip().lower()
            if save == 'y':
                output_file = file_path.parent / f"{file_path.stem}_docs{file_path.suffix}.md"
                with open(output_file, 'w') as f:
                    f.write(f"# Documentation for {file_path.name}\n\n")
                    f.write(f"```{language.lower()}\n")
                    f.write(doc)
                    f.write("\n```\n")
                print_colored(f"✅ Saved to: {output_file}", Colors.GREEN)

    def generate_readme(directory):
        """Generate README for a directory"""
        dir_path = Path(directory)
        if not dir_path.exists():
            print_colored(f"❌ Directory not found: {directory}", Colors.RED)
            return

        # Collect information about directory
        files = []
        for file_path in dir_path.iterdir():
            if file_path.is_file() and not file_path.name.startswith('.'):
                files.append({
                    'name': file_path.name,
                    'ext': file_path.suffix,
                    'size': file_path.stat().st_size,
                })

        subdirs = [d.name for d in dir_path.iterdir() if d.is_dir() and not d.name.startswith('.')]

        # Check for existing code files to analyze
        code_files = [f for f in files if f['ext'] in ['.py', '.nix', '.sh', '.js', '.ts']]

        file_list = "\n".join([f"- {f['name']} ({f['size']} bytes)" for f in files[:20]])
        subdir_list = "\n".join([f"- {d}/" for d in subdirs[:10]])

        prompt = f"""You are a technical documentation expert. Generate a comprehensive README.md for this directory.

Directory: {dir_path.name}
Path: {dir_path}

Files ({len(files)} total):
{file_list}

Subdirectories ({len(subdirs)} total):
{subdir_list}

Generate a README.md with:
1. Project/directory title
2. Purpose and overview
3. Directory structure explanation
4. Key files and their purposes
5. Usage instructions (if applicable)
6. Dependencies or requirements
7. Any other relevant information

Format in proper Markdown. Be concise but informative."""

        readme = query_ollama(prompt, max_tokens=2000)

        if readme:
            print_colored("\n" + "="*80, Colors.GREEN)
            print_colored("Generated README:", Colors.BOLD + Colors.GREEN)
            print_colored("="*80 + "\n", Colors.GREEN)
            print(readme)
            print_colored("\n" + "="*80 + "\n", Colors.GREEN)

            # Ask if user wants to save
            save = input(f"Save to README.md? (y/N): ").strip().lower()
            if save == 'y':
                readme_file = dir_path / "README.md"
                with open(readme_file, 'w') as f:
                    f.write(readme)
                print_colored(f"✅ Saved to: {readme_file}", Colors.GREEN)

    def generate_module_docs(file_path):
        """Generate module-level documentation for Nix modules"""
        content = read_file(file_path)
        if not content:
            return

        prompt = f"""You are a NixOS expert. Generate comprehensive documentation for this Nix module.

File: {file_path.name}

```nix
{content}
```

Generate documentation including:
1. Module purpose
2. All options with:
   - Type
   - Default value
   - Description
   - Example usage
3. Dependencies (upstream modules)
4. Used by (downstream consumers)
5. Example configuration

Format as a Markdown documentation block suitable for inclusion in the nixos-hwc documentation."""

        doc = query_ollama(prompt, max_tokens=2500)

        if doc:
            print_colored("\n" + "="*80, Colors.GREEN)
            print_colored("Generated Module Documentation:", Colors.BOLD + Colors.GREEN)
            print_colored("="*80 + "\n", Colors.GREEN)
            print(doc)
            print_colored("\n" + "="*80 + "\n", Colors.GREEN)

    def main():
        """Main entry point"""
        parser = argparse.ArgumentParser(
            description="AI-powered documentation generator",
            epilog="Examples:\n"
                   "  ai-doc file script.py              # Document entire file\n"
                   "  ai-doc file script.py -f main      # Document specific function\n"
                   "  ai-doc readme /path/to/dir         # Generate README\n"
                   "  ai-doc module options.nix          # Document Nix module",
            formatter_class=argparse.RawDescriptionHelpFormatter
        )

        subparsers = parser.add_subparsers(dest='command', help='Documentation type')

        # File documentation
        file_parser = subparsers.add_parser('file', help='Generate file/function documentation')
        file_parser.add_argument('path', type=str, help='Path to file')
        file_parser.add_argument('-f', '--function', type=str, help='Specific function name')

        # README generation
        readme_parser = subparsers.add_parser('readme', help='Generate README for directory')
        readme_parser.add_argument('directory', type=str, help='Directory path')

        # Nix module documentation
        module_parser = subparsers.add_parser('module', help='Generate Nix module documentation')
        module_parser.add_argument('path', type=str, help='Path to Nix module')

        args = parser.parse_args()

        if not args.command:
            parser.print_help()
            return

        print_colored(f"🚀 AI Documentation Generator (Model: {MODEL})", Colors.BOLD + Colors.BLUE)
        print_colored(f"📡 Ollama: {OLLAMA_ENDPOINT}\n", Colors.BLUE)

        if args.command == 'file':
            generate_function_docs(Path(args.path), args.function)
        elif args.command == 'readme':
            generate_readme(args.directory)
        elif args.command == 'module':
            generate_module_docs(Path(args.path))

    if __name__ == "__main__":
        main()
  '';
in
{
  # Create templates directory
  systemd.tmpfiles.rules = [
    "d ${cfg.autoDoc.templates} 0755 eric users -"
  ];

  # Install auto-doc script
  environment.systemPackages = [ autoDocScript ];
}
