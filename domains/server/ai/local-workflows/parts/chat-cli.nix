# domains/server/ai/local-workflows/parts/chat-cli.nix
#
# Interactive CLI chat interface with command execution tools

{ config, lib, pkgs, cfg }:

let
  chatScript = pkgs.writers.writePython3Bin "ai-chat" {
    libraries = with pkgs.python3Packages; [ requests pyyaml ];
  } ''
import json
import sqlite3
import readline
import atexit
import subprocess
import shlex
from pathlib import Path
from datetime import datetime
import requests


# Configuration
OLLAMA_ENDPOINT = "${cfg.ollamaEndpoint}"
DEFAULT_MODEL = "${cfg.chatCli.model}"
HISTORY_FILE = "${cfg.chatCli.historyFile}"
MAX_HISTORY = ${toString cfg.chatCli.maxHistoryLines}
SYSTEM_PROMPT = """${cfg.chatCli.systemPrompt}

You have access to tools to execute commands on the system.
When you need information, use the TOOL format:

TOOL: command args
Example: TOOL: podman ps
Example: TOOL: systemctl status ollama

After seeing results, respond naturally to the user.
Available tools: ls, tree, cat, head, tail, grep, find, pwd,
systemctl, journalctl, podman, df, free, uptime, who, mv
"""


class Colors:
    BLUE = '\033[94m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    RED = '\033[91m'
    CYAN = '\033[96m'
    MAGENTA = '\033[95m'
    ENDC = '\033[0m'
    BOLD = '\033[1m'


class CommandExecutor:
    """Safe command execution with whitelist"""

    # Whitelisted commands (read-only + mv)
    SAFE_COMMANDS = {
        'ls', 'tree', 'cat', 'head', 'tail', 'grep',
        'find', 'pwd', 'df', 'free', 'uptime', 'who',
        'systemctl', 'journalctl', 'podman', 'mv'
    }

    # Commands that need subcommand validation
    SUBCOMMAND_RULES = {
        'systemctl': ['status', 'list-units', 'is-active',
                      'is-enabled', 'show'],
        'podman': ['ps', 'logs', 'inspect', 'stats', 'images'],
    }

    # Dangerous flags to block
    BLOCKED_FLAGS = {
        '--force', '-f', '--delete', '-d', '--remove', '-r',
        '--rm', '--kill', '-k', '--stop', '--restart'
    }

    def __init__(self, working_dir="/"):
        self.working_dir = Path(working_dir)

    def validate_command(self, cmd_parts):
        """Validate command against whitelist"""
        if not cmd_parts:
            return False, "Empty command"

        base_cmd = cmd_parts[0]

        # Check if command is whitelisted
        if base_cmd not in self.SAFE_COMMANDS:
            return False, f"Command not allowed: {base_cmd}"

        # Validate subcommands
        if base_cmd in self.SUBCOMMAND_RULES:
            if len(cmd_parts) < 2:
                return False, f"{base_cmd} requires subcommand"

            subcmd = cmd_parts[1]
            allowed = self.SUBCOMMAND_RULES[base_cmd]

            if subcmd not in allowed:
                return False, (
                    f"Subcommand not allowed: {base_cmd} {subcmd}"
                )

        # Check for dangerous flags
        for part in cmd_parts:
            if part in self.BLOCKED_FLAGS:
                return False, f"Dangerous flag blocked: {part}"

        # Block shell operators
        dangerous = ['|', '>', '<', ';', '&', '$', '`']
        for part in cmd_parts:
            if any(op in part for op in dangerous):
                return False, "Shell operators not allowed"

        return True, "OK"

    def execute(self, command_str):
        """Execute a safe command and return output"""
        try:
            # Parse command
            cmd_parts = shlex.split(command_str)

            # Validate
            valid, msg = self.validate_command(cmd_parts)
            if not valid:
                return {
                    "success": False,
                    "error": msg,
                    "output": ""
                }

            # Execute with timeout
            result = subprocess.run(
                cmd_parts,
                capture_output=True,
                text=True,
                timeout=30,
                cwd=str(self.working_dir)
            )

            # Limit output size
            stdout = result.stdout[:5000]
            stderr = result.stderr[:1000]

            if len(result.stdout) > 5000:
                stdout += "\n... (output truncated)"

            return {
                "success": result.returncode == 0,
                "output": stdout,
                "error": stderr,
                "returncode": result.returncode
            }

        except subprocess.TimeoutExpired:
            return {
                "success": False,
                "error": "Command timeout (30s)",
                "output": ""
            }
        except Exception as e:
            return {
                "success": False,
                "error": str(e),
                "output": ""
            }


class ChatSession:
    def __init__(self):
        self.model = DEFAULT_MODEL
        self.context = []
        self.executor = CommandExecutor()
        self.setup_database()
        self.setup_readline()

    def setup_database(self):
        """Initialize SQLite database for chat history"""
        db_path = Path(HISTORY_FILE)
        db_path.parent.mkdir(parents=True, exist_ok=True)

        self.conn = sqlite3.connect(db_path)
        self.cursor = self.conn.cursor()

        # Create conversations table
        self.cursor.execute("""
            CREATE TABLE IF NOT EXISTS conversations (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                started_at TEXT,
                model TEXT,
                message_count INTEGER DEFAULT 0
            )
        """)

        # Create messages table
        self.cursor.execute("""
            CREATE TABLE IF NOT EXISTS messages (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                conversation_id INTEGER,
                timestamp TEXT,
                role TEXT,
                content TEXT,
                FOREIGN KEY (conversation_id)
                    REFERENCES conversations (id)
            )
        """)

        self.conn.commit()

        # Start new conversation
        self.cursor.execute(
            'INSERT INTO conversations (started_at, model) '
            'VALUES (?, ?)',
            (datetime.now().isoformat(), self.model)
        )
        self.conn.commit()
        self.conversation_id = self.cursor.lastrowid

    def setup_readline(self):
        """Setup readline for command history"""
        history_path = Path.home() / '.ai_chat_readline_history'
        try:
            readline.read_history_file(history_path)
        except FileNotFoundError:
            pass
        atexit.register(readline.write_history_file, history_path)

    def save_message(self, role, content):
        """Save message to database"""
        self.cursor.execute(
            'INSERT INTO messages '
            '(conversation_id, timestamp, role, content) '
            'VALUES (?, ?, ?, ?)',
            (self.conversation_id, datetime.now().isoformat(),
             role, content)
        )
        self.cursor.execute(
            'UPDATE conversations SET message_count = '
            'message_count + 1 WHERE id = ?',
            (self.conversation_id,)
        )
        self.conn.commit()

    def parse_tool_calls(self, text):
        """Extract TOOL: commands from AI response"""
        tools = []
        lines = text.split('\n')

        for line in lines:
            if line.strip().startswith('TOOL:'):
                cmd = line.strip()[5:].strip()
                if cmd:
                    tools.append(cmd)

        return tools

    def execute_tools(self, tool_calls):
        """Execute tool calls and return results"""
        results = []

        for cmd in tool_calls:
            print(
                f"{Colors.CYAN}> Executing: {cmd}{Colors.ENDC}"
            )
            result = self.executor.execute(cmd)

            if result['success']:
                output = result['output'].strip()
                if output:
                    print(
                        f"{Colors.YELLOW}{output}{Colors.ENDC}\n"
                    )
                    results.append({
                        'command': cmd,
                        'output': output
                    })
                else:
                    print(
                        f"{Colors.YELLOW}(no output){Colors.ENDC}\n"
                    )
            else:
                error_msg = result['error']
                print(f"{Colors.RED}Error: {error_msg}{Colors.ENDC}\n")
                results.append({
                    'command': cmd,
                    'error': error_msg
                })

        return results

    def query_ollama(self, prompt, stream=True):
        """Query Ollama API with streaming"""
        try:
            response = requests.post(
                f"{OLLAMA_ENDPOINT}/api/chat",
                json={
                    "model": self.model,
                    "messages": self.context + [
                        {"role": "user", "content": prompt}
                    ],
                    "stream": stream,
                    "options": {"temperature": 0.7}
                },
                stream=stream,
                timeout=300
            )
            response.raise_for_status()

            full_response = ""
            if stream:
                for line in response.iter_lines():
                    if line:
                        chunk = json.loads(line)
                        if "message" in chunk:
                            content = chunk["message"].get(
                                "content", ""
                            )
                            full_response += content
            else:
                result = response.json()
                full_response = result["message"]["content"]

            return full_response

        except Exception as e:
            print(f"{Colors.RED}Error: {e}{Colors.ENDC}")
            return None

    def chat(self, message):
        """Process a chat message with tool execution"""
        self.save_message("user", message)
        self.context.append({"role": "user", "content": message})

        # Get initial AI response (non-streaming for tool detection)
        response = self.query_ollama(message, stream=False)

        if not response:
            return

        # Check for tool calls
        tool_calls = self.parse_tool_calls(response)

        if tool_calls:
            # Execute tools
            tool_results = self.execute_tools(tool_calls)

            # Build results message for AI
            results_text = "Command results:\n"
            for r in tool_results:
                cmd = r['command']
                if 'output' in r:
                    results_text += (
                        f"\n$ {cmd}\n{r['output'][:500]}\n"
                    )
                else:
                    results_text += (
                        f"\n$ {cmd}\nError: {r['error']}\n"
                    )

            # Add to context
            self.context.append({
                "role": "assistant",
                "content": response
            })
            self.context.append({
                "role": "user",
                "content": results_text
            })

            # Get final response with results
            print(
                f"{Colors.GREEN}{Colors.BOLD}Assistant:"
                f"{Colors.ENDC} ",
                end="", flush=True
            )
            final_response = self.query_ollama(
                results_text,
                stream=True
            )
            print()

            if final_response:
                self.save_message("assistant", final_response)
                self.context.append({
                    "role": "assistant",
                    "content": final_response
                })
        else:
            # No tools, just display response
            print(
                f"{Colors.GREEN}{Colors.BOLD}Assistant:"
                f"{Colors.ENDC} {response}"
            )
            self.save_message("assistant", response)
            self.context.append({
                "role": "assistant",
                "content": response
            })

        # Trim context
        if len(self.context) > 20:
            self.context = self.context[-20:]

    def list_models(self):
        """List available Ollama models"""
        try:
            response = requests.get(f"{OLLAMA_ENDPOINT}/api/tags")
            response.raise_for_status()
            models = response.json().get("models", [])

            print(
                f"\n{Colors.CYAN}{Colors.BOLD}Available Models:"
                f"{Colors.ENDC}"
            )
            for model in models:
                name = model.get("name", "unknown")
                size = model.get("size", 0) / (1024**3)
                current = " (current)" if name == self.model else ""
                print(f"  * {name} ({size:.1f} GB){current}")

        except Exception as e:
            print(f"{Colors.RED}Error listing models: {e}{Colors.ENDC}")

    def switch_model(self, model_name):
        """Switch to a different model"""
        try:
            response = requests.get(f"{OLLAMA_ENDPOINT}/api/tags")
            response.raise_for_status()
            models = [
                m["name"]
                for m in response.json().get("models", [])
            ]

            if model_name in models:
                self.model = model_name
                self.context = []
                print(
                    f"{Colors.GREEN}Switched to model: "
                    f"{model_name}{Colors.ENDC}"
                )
            else:
                print(
                    f"{Colors.RED}Model not found: "
                    f"{model_name}{Colors.ENDC}"
                )
                print(
                    f"{Colors.YELLOW}Available: "
                    f"{', '.join(models)}{Colors.ENDC}"
                )

        except Exception as e:
            print(f"{Colors.RED}Error: {e}{Colors.ENDC}")

    def show_help(self):
        """Display help information"""
        help_text = f"""
{Colors.CYAN}{Colors.BOLD}AI Chat Commands:{Colors.ENDC}

{Colors.YELLOW}Chat:{Colors.ENDC}
  Type your message and press Enter
  AI can execute safe commands to answer questions

{Colors.YELLOW}Commands:{Colors.ENDC}
  /help              Show this help
  /models            List available models
  /model <name>      Switch model
  /clear             Clear context
  /history [n]       Show last n messages (default: 10)
  /export            Export conversation
  /quit or /exit     Exit

{Colors.YELLOW}Tool Capabilities:{Colors.ENDC}
  AI can run: ls, tree, cat, systemctl, podman, df, etc.
  Ask questions like "What containers are running?"

{Colors.YELLOW}Current:{Colors.ENDC}
  Model: {self.model}
  Endpoint: {OLLAMA_ENDPOINT}
"""
        print(help_text)

    def show_history(self, n=10):
        """Show recent chat history"""
        self.cursor.execute(
            "SELECT role, content, timestamp FROM messages "
            "WHERE conversation_id = ? ORDER BY id DESC LIMIT ?",
            (self.conversation_id, n)
        )

        messages = self.cursor.fetchall()

        if not messages:
            print(f"{Colors.YELLOW}No messages{Colors.ENDC}")
            return

        print(
            f"\n{Colors.CYAN}{Colors.BOLD}Last "
            f"{len(messages)} Messages:{Colors.ENDC}\n"
        )
        for role, content, timestamp in reversed(messages):
            color = Colors.BLUE if role == "user" else Colors.GREEN
            preview = (
                content[:100] + "..."
                if len(content) > 100 else content
            )
            print(
                f"{color}{role.capitalize()}:{Colors.ENDC} "
                f"{preview}"
            )

    def export_conversation(self):
        """Export conversation to markdown"""
        self.cursor.execute(
            "SELECT role, content, timestamp FROM messages "
            "WHERE conversation_id = ? ORDER BY id ASC",
            (self.conversation_id,)
        )

        messages = self.cursor.fetchall()

        if not messages:
            print(f"{Colors.YELLOW}No messages to export{Colors.ENDC}")
            return

        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = f"chat_export_{timestamp}.md"

        with open(filename, 'w') as f:
            f.write("# AI Chat Export\\n\\n")
            f.write(f"**Model**: {self.model}\\n")
            f.write(
                f"**Exported**: "
                f"{datetime.now().isoformat()}\\n\\n"
            )
            f.write("---\\n\\n")

            for role, content, ts in messages:
                f.write(f"### {role.capitalize()} ({ts})\\n\\n")
                f.write(f"{content}\\n\\n")

        print(f"{Colors.GREEN}Exported to: {filename}{Colors.ENDC}")

    def run(self):
        """Main chat loop"""
        print(
            f"{Colors.BOLD}{Colors.BLUE}AI Chat Interface "
            f"(Tool-Enabled){Colors.ENDC}"
        )
        print(f"{Colors.CYAN}Model: {self.model}{Colors.ENDC}")
        print(
            f"{Colors.CYAN}Type /help for commands, "
            f"/quit to exit{Colors.ENDC}\\n"
        )

        if SYSTEM_PROMPT:
            self.context.append({
                "role": "system",
                "content": SYSTEM_PROMPT
            })

        while True:
            try:
                user_input = input(
                    f"{Colors.BLUE}{Colors.BOLD}You:{Colors.ENDC} "
                ).strip()

                if not user_input:
                    continue

                if user_input.startswith('/'):
                    cmd_parts = user_input[1:].split()
                    cmd = cmd_parts[0].lower()

                    if cmd in ['quit', 'exit', 'q']:
                        print(f"{Colors.YELLOW}Goodbye!{Colors.ENDC}")
                        break
                    elif cmd == 'help':
                        self.show_help()
                    elif cmd == 'models':
                        self.list_models()
                    elif cmd == 'model' and len(cmd_parts) > 1:
                        self.switch_model(cmd_parts[1])
                    elif cmd == 'clear':
                        self.context = []
                        if SYSTEM_PROMPT:
                            self.context.append({
                                "role": "system",
                                "content": SYSTEM_PROMPT
                            })
                        print(
                            f"{Colors.GREEN}Context cleared"
                            f"{Colors.ENDC}"
                        )
                    elif cmd == 'history':
                        n = int(cmd_parts[1]) if len(
                            cmd_parts
                        ) > 1 else 10
                        self.show_history(n)
                    elif cmd == 'export':
                        self.export_conversation()
                    else:
                        print(
                            f"{Colors.RED}Unknown command: "
                            f"{cmd}{Colors.ENDC}"
                        )
                        print(
                            f"{Colors.YELLOW}Type /help for "
                            f"commands{Colors.ENDC}"
                        )

                    continue

                self.chat(user_input)

            except KeyboardInterrupt:
                print(
                    f"\\n{Colors.YELLOW}(Use /quit to exit)"
                    f"{Colors.ENDC}"
                )
            except EOFError:
                print(f"\\n{Colors.YELLOW}Goodbye!{Colors.ENDC}")
                break
            except Exception as e:
                print(f"{Colors.RED}Error: {e}{Colors.ENDC}")

        self.conn.close()


def main():
    """Entry point"""
    session = ChatSession()
    session.run()


if __name__ == "__main__":
    main()
  '';
in
{
  # Create history directory
  systemd.tmpfiles.rules = [
    "d ${builtins.dirOf cfg.chatCli.historyFile} 0755 eric users -"
  ];

  # Install chat CLI
  environment.systemPackages = [ chatScript ];
}
