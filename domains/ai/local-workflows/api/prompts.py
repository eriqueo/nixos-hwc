"""
Prompt templates for Local Workflows
"""

SYSTEM_PROMPTS = {
    "chat": """You are a helpful AI assistant with access to the HWC server system.
You can help with:
- Code analysis and debugging
- System administration tasks
- Documentation generation
- File organization

Be concise and practical. When showing commands, use proper syntax.
""",

    "cleanup": """You are a file organization expert. Analyze files in the directory and suggest actions.

For each file, determine:
1. File type and purpose
2. Appropriate destination based on content/extension
3. Whether it should be renamed for clarity

Common destinations:
- Documents: ~/Documents/
- Downloads: Keep in ~/Downloads/ if recent, archive if old
- Media: /mnt/media/{music,photos,videos}/
- Code: ~/projects/
- Archives: ~/Archives/
- Temporary: Can be deleted if > 30 days old

Output format:
File: filename.ext
Action: move|rename|skip
Destination: /path/to/destination
Reason: Brief explanation
""",

    "journal": """You are a technical journal writer. Generate a concise daily journal entry.

Include:
1. **System Events**: Notable services started/stopped/failed
2. **Container Activity**: New deployments, restarts, errors
3. **Resource Usage**: CPU/memory/disk trends
4. **Notable Logs**: Errors, warnings, important events
5. **Summary**: Brief overview of system health

Style:
- Use markdown formatting
- Be concise (1-2 sentences per section)
- Focus on actionable information
- Include timestamps for key events
""",

    "autodoc": """You are a technical documentation expert. Generate comprehensive documentation.

Include:
1. **Overview**: What this code does
2. **Architecture**: How it's structured
3. **Key Components**: Main functions/classes/modules
4. **Configuration**: Options and settings
5. **Usage Examples**: Practical examples
6. **Dependencies**: What it requires

Style:
- Use markdown formatting
- Include code examples
- Be clear and practical
- Assume reader has basic technical knowledge
"""
}


def build_cleanup_prompt(directory: str, files: list) -> str:
    """Build prompt for file cleanup analysis"""
    files_list = "\n".join([f"- {f}" for f in files[:50]])  # Limit to 50 files
    if len(files) > 50:
        files_list += f"\n... and {len(files) - 50} more files"

    return f"""{SYSTEM_PROMPTS['cleanup']}

Directory: {directory}
Files to analyze:
{files_list}

Analyze each file and suggest appropriate actions.
"""


def build_journal_prompt(logs: dict, metrics: dict) -> str:
    """Build prompt for journal generation"""
    return f"""{SYSTEM_PROMPTS['journal']}

System Logs Summary:
{logs.get('summary', 'No logs available')}

Container Logs:
{logs.get('containers', 'No container logs')}

System Metrics:
- CPU: {metrics.get('cpu', 'N/A')}
- Memory: {metrics.get('memory', 'N/A')}
- Disk: {metrics.get('disk', 'N/A')}

Generate a journal entry for today.
"""


def build_autodoc_prompt(file_path: str, content: str, style: str) -> str:
    """Build prompt for documentation generation"""
    style_note = ""
    if style == "user-friendly":
        style_note = "\nUse simple language suitable for non-technical users."
    elif style == "technical":
        style_note = "\nUse technical terminology and be comprehensive."

    return f"""{SYSTEM_PROMPTS['autodoc']}
{style_note}

File: {file_path}

```
{content[:5000]}  # Limit content to prevent token overflow
```

Generate comprehensive documentation for this file.
"""
