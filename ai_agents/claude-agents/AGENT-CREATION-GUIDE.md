# Agent Creation Guide for HWC NixOS

This guide distills the patterns and best practices for creating effective Claude agents based on analysis of existing agents.

---

## What is an Agent?

An **agent** is a specialized Claude persona with:
- **Domain expertise** in a specific area (scripting, documentation, monitoring, etc.)
- **Structured workflows** for common tasks
- **Quality standards** and best practices
- **Interaction protocols** for effective collaboration
- **Templates and examples** for consistency

Agents are Markdown files that serve as comprehensive system prompts, transforming Claude into a domain expert.

---

## Agent Anatomy

### 1. Header Section

```markdown
# Agent Name

**Role:** [One sentence: What this agent specializes in]
**Mission:** [One sentence: What it aims to accomplish]
```

**Purpose:** Immediately establishes the agent's identity and purpose.

**Examples:**
- Role: "Expert code quality engineer specializing in shell scripting and Python"
- Mission: "Write new scripts and refactor existing ones to be production-grade"

---

### 2. Core Competencies

```markdown
## CORE COMPETENCIES

### 1. [Skill Area Name]
- **[Specific Skill]:** [Description and standards]
- **[Specific Skill]:** [Description and standards]

### 2. [Skill Area Name]
- **[Specific Skill]:** [Description and standards]

### 3. Universal Principles
- **[Principle]:** [Description]
```

**Purpose:** Defines the agent's knowledge base and quality standards.

**Best Practices:**
- Group related skills into categories
- Include specific, actionable standards (not vague guidelines)
- Add "Universal Principles" section for cross-cutting concerns
- Use concrete examples where possible

**Example:**
```markdown
### 1. Shell Scripting
- **Error Handling:** Always use `set -euo pipefail`
- **Quoting:** Proper variable quoting: `"$var"` not `$var`
- **Path Resolution:** Use `$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)`
```

---

### 3. Workflow Modes

```markdown
## WORKFLOW MODES

### MODE A: [Primary Workflow]
[Description of when to use this mode]

#### Checklist
- [ ] Step 1
- [ ] Step 2

#### Template
[Code or process template]

### MODE B: [Secondary Workflow]
[Description of when to use this mode]

#### Step 1: [Phase]
[Instructions]
```

**Purpose:** Provides structured processes for common tasks.

**Best Practices:**
- Define 2-4 distinct modes for different scenarios
- Include checklists for systematic execution
- Provide templates or examples for each mode
- Make steps actionable and specific

**Example Modes:**
- "New Script Creation" vs "Refactoring Existing Scripts"
- "Analysis Phase" vs "Implementation Phase"
- "Quick Check" vs "Deep Audit"

---

### 4. Interaction Protocol

```markdown
## INTERACTION PROTOCOL

### When User Asks to [Action]:

1. **Clarify Requirements:**
   - "[Question 1]"
   - "[Question 2]"

2. **[Next Step]:**
   - [Instructions]

3. **Provide [Deliverable]:**
   - [What to deliver]
```

**Purpose:** Defines how the agent should interact with users.

**Best Practices:**
- Cover common user requests
- Include clarifying questions to ask
- Define what to deliver and in what format
- Specify when to ask permission vs. proceed
- Include decision trees for complex scenarios

**Example:**
```markdown
### When User Asks to Refactor Existing Script:

1. **Request Code:**
   - "Please share the script you'd like me to refactor"

2. **Provide Analysis:**
   - Grade current quality (A+ to F)
   - List all issues (categorized by severity)

3. **Ask Permission:**
   - "Would you like me to: a) Fix everything b) Fix critical only c) Show issues"
```

---

### 5. Special Considerations

```markdown
## SPECIAL CONSIDERATIONS

### [Special Case]
[When this applies and what to do]
- [Consideration]
- [Consideration]
```

**Purpose:** Handles edge cases and domain-specific concerns.

**Best Practices:**
- Cover security-sensitive scenarios
- Address performance considerations
- Include system integration concerns
- Note any NixOS-specific requirements

**Examples:**
- Security-Sensitive Scripts
- Performance-Critical Code
- System Integration Requirements
- Data Processing at Scale

---

### 6. Quality Checklist

```markdown
## QUALITY CHECKLIST

Before delivering any output, verify:

### All Outputs
- [ ] [Universal criterion]

### [Specific Type]
- [ ] [Specific criterion]
```

**Purpose:** Ensures consistent quality in agent outputs.

**Best Practices:**
- Include universal criteria for all outputs
- Add type-specific criteria for different deliverables
- Make criteria objective and verifiable
- Order by importance (critical first)

---

### 7. Response Style

```markdown
## RESPONSE STYLE

### Be [Characteristic]
- [Guideline]
- [Guideline]
```

**Purpose:** Defines the agent's communication approach.

**Best Practices:**
- Define 3-4 key characteristics
- Provide specific guidelines for each
- Balance technical precision with accessibility
- Consider the target audience

**Example Characteristics:**
- Be Concise but Complete
- Be Educational
- Be Practical
- Be Specific

---

### 8. Examples

```markdown
## EXAMPLES

### Example 1: [Use Case]
[Code or interaction example]

**Explanation:** [Why this is good]
```

**Purpose:** Provides concrete demonstrations of agent behavior.

**Best Practices:**
- Include 3-5 diverse examples
- Show before/after comparisons
- Explain the reasoning behind each example
- Cover common use cases
- Include both simple and complex scenarios

---

### 9. Remember Section

```markdown
## REMEMBER

**Your goal is to [objective]:**
1. **[Quality]** - [Description]
2. **[Quality]** - [Description]

**Always ask yourself:**
- [Critical question]
- [Critical question]

**[Motivational closing]**
```

**Purpose:** Reinforces the agent's core mission and mindset.

**Best Practices:**
- Summarize key objectives (3-5 items)
- Include self-reflection questions
- End with motivational statement
- Make it memorable and actionable

---

## Agent Types for HWC NixOS

### 1. Script Quality Agent
**Focus:** Code quality, best practices, refactoring
**Use Cases:** Creating/improving automation scripts
**Key Workflows:** New script creation, refactoring, code review

### 2. Documentation Architect
**Focus:** Technical documentation, architecture guides
**Use Cases:** Creating comprehensive system documentation
**Key Workflows:** Codebase analysis, documentation structuring, writing

### 3. Monitoring Agent (Template)
**Focus:** System health checks, alerting, metrics
**Use Cases:** Creating monitoring scripts, health checks
**Key Workflows:** Metric collection, threshold checking, alerting

### 4. Security Audit Agent (Template)
**Focus:** Security scanning, vulnerability detection
**Use Cases:** Security audits, compliance checking
**Key Workflows:** Vulnerability scanning, configuration review, reporting

### 5. NixOS Module Agent (Template)
**Focus:** NixOS module creation, charter compliance
**Use Cases:** Creating new modules, refactoring existing ones
**Key Workflows:** Module scaffolding, validation, testing

---

## Creating a New Agent

### Step 1: Define the Domain
- What specific problem does this agent solve?
- What expertise is required?
- What are the common tasks in this domain?

### Step 2: Identify Workflows
- What are the 2-4 main workflows?
- What are the steps in each workflow?
- What decisions need to be made?

### Step 3: Establish Standards
- What are the quality criteria?
- What are the best practices?
- What are common mistakes to avoid?

### Step 4: Create Templates
- What code/process templates are needed?
- What examples demonstrate best practices?
- What checklists ensure completeness?

### Step 5: Define Interaction
- What questions should the agent ask?
- When should it ask permission vs. proceed?
- What format should outputs take?

### Step 6: Write the Agent
- Use `AGENT-TEMPLATE.md` as starting point
- Fill in each section with domain-specific content
- Include concrete examples
- Test with real scenarios

### Step 7: Document and Deploy
- Add to `.claude/agents/README.md`
- Create usage examples
- Test with actual use cases
- Iterate based on feedback

---

## Agent Best Practices

### DO:
✅ Be specific and actionable
✅ Include concrete examples
✅ Provide templates and checklists
✅ Define clear quality standards
✅ Cover common edge cases
✅ Make interaction protocols explicit
✅ Include both simple and complex examples
✅ Test the agent with real scenarios

### DON'T:
❌ Be vague or generic
❌ Skip examples
❌ Assume knowledge
❌ Leave quality criteria subjective
❌ Ignore edge cases
❌ Make users guess what to do
❌ Only show trivial examples
❌ Deploy untested agents

---

## Agent Invocation Methods

### Method 1: Claude Code CLI (Recommended)
```bash
claude --agent .claude/agents/agent-name.md "Task description"
```

### Method 2: Reference in Conversation
```
I'd like you to act as the [Agent Name] defined in
.claude/agents/agent-name.md. [Task description]
```

### Method 3: Copy-Paste
1. Copy agent file contents
2. Paste into Claude conversation
3. Provide task

---

## Testing Your Agent

### 1. Simple Task Test
Give the agent a straightforward task in its domain.
- Does it ask appropriate clarifying questions?
- Does it follow its defined workflow?
- Is the output high quality?

### 2. Complex Task Test
Give the agent a challenging, multi-step task.
- Does it break down the problem correctly?
- Does it handle edge cases?
- Does it maintain quality under complexity?

### 3. Edge Case Test
Give the agent an unusual or boundary case.
- Does it recognize the special case?
- Does it apply appropriate considerations?
- Does it ask for guidance when uncertain?

### 4. Interaction Test
Simulate different user interaction styles.
- Does it handle unclear requests well?
- Does it ask good clarifying questions?
- Does it provide helpful guidance?

---

## Maintaining Agents

### When to Update an Agent:
- New best practices emerge in the domain
- Common issues are discovered through use
- User feedback suggests improvements
- Standards or tools change
- New workflows are identified

### How to Update:
1. Document the issue or improvement
2. Update the relevant section
3. Add examples if needed
4. Test the updated agent
5. Commit with clear description

### Version Control:
- Commit agent changes with descriptive messages
- Reference specific improvements
- Link to issues or discussions if applicable

---

## Examples of Good Agents

### Script Quality Agent
**Strengths:**
- Comprehensive templates for bash and Python
- Clear quality criteria with grading scale
- Multiple workflow modes (create vs. refactor)
- Extensive examples with explanations
- Specific interaction protocols

### Documentation Architect
**Strengths:**
- Clear process phases (Discovery, Structuring, Writing)
- Defined output characteristics
- Comprehensive section list
- Best practices for technical writing
- Specific output format requirements

---

## Agent Creation Checklist

Before finalizing a new agent:

- [ ] Header clearly defines role and mission
- [ ] Core competencies are specific and actionable
- [ ] 2-4 workflow modes are defined
- [ ] Interaction protocols cover common scenarios
- [ ] Special considerations address edge cases
- [ ] Quality checklist is comprehensive
- [ ] Response style is clearly defined
- [ ] 3-5 concrete examples are included
- [ ] "Remember" section reinforces key points
- [ ] Agent has been tested with real tasks
- [ ] Documentation is added to README
- [ ] Usage examples are provided

---

## Advanced Agent Patterns

### Multi-Mode Agents
Agents that switch between different operating modes based on task type.
**Example:** Script Quality Agent (Create vs. Refactor modes)

### Phased Agents
Agents that work through distinct phases sequentially.
**Example:** Documentation Architect (Discovery → Structuring → Writing)

### Interactive Agents
Agents that heavily rely on back-and-forth with users.
**Example:** Agents that need to clarify requirements before proceeding

### Autonomous Agents
Agents that can complete tasks with minimal user interaction.
**Example:** Monitoring agents that run checks and report findings

---

## Integration with HWC NixOS

### Repository Structure
```
.claude/
├── agents/
│   ├── README.md                    # Agent catalog and usage
│   ├── AGENT-TEMPLATE.md           # Template for new agents
│   ├── AGENT-CREATION-GUIDE.md     # This guide
│   ├── QUICK-REFERENCE.md          # Quick reference cards
│   ├── script-quality-agent.md     # Script quality expert
│   ├── docs-architect.md           # Documentation expert
│   └── [your-agent].md             # Your custom agents
```

### Naming Conventions
- Use lowercase-with-hyphens for filenames
- End with `-agent.md` for agent files
- Use descriptive names: `monitoring-agent.md` not `agent1.md`

### Documentation Requirements
- Add entry to `.claude/agents/README.md`
- Include usage examples
- Document key use cases
- Provide invocation commands

---

## Resources

- **Existing Agents:** See `.claude/agents/` for examples
- **Template:** Use `AGENT-TEMPLATE.md` as starting point
- **Quick Reference:** See `QUICK-REFERENCE.md` for patterns
- **Repository Guidelines:** See root `AGENTS.md` for repo standards

---

## Summary

**An effective agent has:**
1. **Clear identity** - Role and mission
2. **Domain expertise** - Core competencies and standards
3. **Structured workflows** - Modes and processes
4. **Interaction guidance** - How to work with users
5. **Quality standards** - Checklists and criteria
6. **Concrete examples** - Demonstrations of best practices
7. **Edge case handling** - Special considerations
8. **Consistent style** - Response characteristics

**Creating an agent is about:**
- Codifying expertise into a reusable system prompt
- Providing structure for common tasks
- Ensuring consistent quality
- Making domain knowledge accessible
- Enabling effective human-AI collaboration

**Start simple, iterate based on use, and always include concrete examples.**
