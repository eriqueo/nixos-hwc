# Claude Agents for HWC NixOS

This directory contains specialized Claude agents for the HWC NixOS repository.

## Available Agents

### 1. Script Quality & Best Practices Agent

**Purpose:** Write new scripts and refactor existing ones to production-grade quality.

**Agent File:** `script-quality-agent.md`

**Use Cases:**
- Creating new shell or Python scripts from scratch
- Refactoring existing scripts for better quality
- Code reviews and quality audits
- Learning best practices

#### How to Use

##### Method 1: Via Claude Code CLI (Recommended)

When in the repository, you can invoke the agent by referencing it:

```bash
# Start a session with the script quality agent
claude --agent .claude/agents/script-quality-agent.md

# Or with a specific task
claude --agent .claude/agents/script-quality-agent.md "Refactor workspace/utilities/scripts/grebuild.sh"
```

##### Method 2: Copy-Paste the Agent Prompt

1. Open `.claude/agents/script-quality-agent.md`
2. Copy the entire contents
3. Paste into your Claude conversation
4. Then ask your question or share code

##### Method 3: Reference in Conversation

In any Claude conversation:
```
I'd like you to act as the Script Quality Agent defined in
.claude/agents/script-quality-agent.md. Please review this script:
[paste your script]
```

#### Example Interactions

##### Creating a New Script
```
User: I need a shell script that monitors a directory and sends
notifications when new files appear. It should support email and
desktop notifications.

Agent: I'll create a robust shell script for directory monitoring.
Let me clarify a few requirements:
1. Should this run as a daemon or one-time check?
2. What file extensions should trigger notifications?
3. Should it track file sizes or just existence?
[... creates complete, production-grade script ...]
```

##### Refactoring Existing Code
```
User: Please refactor this script:
[pastes grebuild.sh]

Agent: I've analyzed your script. Current grade: 40/100 (D)

Critical Issues Found:
1. Missing 'set -euo pipefail' - script continues on errors
2. Unquoted variables throughout
3. Hard-coded notification URL
4. No function organization

Would you like me to:
a) Fix everything in one pass
b) Fix critical issues only
c) Show issues and let you decide
d) Apply fixes incrementally with explanations

[... provides comprehensive refactoring ...]
```

##### Code Review
```
User: Review this Python script for quality:
[pastes script]

Agent: Quality Assessment: 75/100 (Grade B)

Strengths:
✓ Good use of pathlib
✓ Proper error handling
✓ Clear structure

Improvements Needed:
⚠️ Missing type hints on 3 functions
⚠️ No argparse CLI interface
⚠️ Hard-coded config path

Would you like me to implement these improvements?
```

#### Quick Reference: Quality Criteria

**Shell Scripts Must Have:**
- `#!/usr/bin/env bash`
- `set -euo pipefail`
- Quoted variables: `"$var"`
- `readonly` for constants
- `local` in functions
- Function organization
- Usage/help function
- Error handling

**Python Scripts Must Have:**
- Type hints
- pathlib for paths
- argparse for CLI
- Docstrings
- Error handling with specific exceptions
- Proper exit codes
- No `shell=True` or unsafe YAML loading

## Creating New Agents

To create a new specialized agent:

1. Create a new markdown file: `.claude/agents/your-agent-name.md`
2. Use this structure:
```markdown
# Agent Name

**Role:** [What this agent specializes in]
**Mission:** [What it aims to accomplish]

## CORE COMPETENCIES
[List key skills and knowledge]

## WORKFLOW MODES
[How the agent operates]

## INTERACTION PROTOCOL
[How to interact with this agent]

## EXAMPLES
[Concrete examples of agent behavior]
```

3. Add it to this README
4. Commit to repository

## Tips for Effective Agent Use

1. **Be Specific:** Provide context about what the script needs to do
2. **Share Constraints:** Mention any system requirements or limitations
3. **Ask Questions:** The agent will clarify requirements before coding
4. **Iterate:** Start with a working solution, then optimize
5. **Test:** Always test generated code in your environment

## Contributing

To improve these agents:
1. Use them and note what works/doesn't work
2. Update the agent markdown files
3. Add examples of good interactions
4. Share improvements via git commits

## Support

For issues or questions:
- Check the agent markdown file for detailed instructions
- Review the examples in this README
- Consult the main repository documentation
