# domains/server/ai/local-workflows/parts/chat-cli.nix
#
# Interactive CLI chat interface for local AI models

{ config, lib, pkgs, cfg }:

let
  chatScript = pkgs.writers.writePython3Bin "ai-chat" {
    libraries = with pkgs.python3Packages; [ requests pyyaml ];
  } ''
import json
import sqlite3
import readline
import atexit
from pathlib import Path
from datetime import datetime
import requests


# Configuration
OLLAMA_ENDPOINT = "${cfg.ollamaEndpoint}"
DEFAULT_MODEL = "${cfg.chatCli.model}"
HISTORY_FILE = "${cfg.chatCli.historyFile}"
MAX_HISTORY = ${toString cfg.chatCli.maxHistoryLines}
SYSTEM_PROMPT = """${cfg.chatCli.systemPrompt}"""


class Colors:
    BLUE = '\033[94m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    RED = '\033[91m'
    CYAN = '\033[96m'
    MAGENTA = '\033[95m'
    ENDC = '\033[0m'
    BOLD = '\033[1m'


class ChatSession:
    def __init__(self):
        self.model = DEFAULT_MODEL
        self.context = []
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
                print(
                    f"{Colors.GREEN}{Colors.BOLD}Assistant:"
                    f"{Colors.ENDC} ",
                    end="", flush=True
                )
                for line in response.iter_lines():
                    if line:
                        chunk = json.loads(line)
                        if "message" in chunk:
                            content = chunk["message"].get(
                                "content", ""
                            )
                            print(content, end="", flush=True)
                            full_response += content
                print()
            else:
                result = response.json()
                full_response = result["message"]["content"]
                print(
                    f"{Colors.GREEN}{Colors.BOLD}Assistant:"
                    f"{Colors.ENDC} {full_response}"
                )

            return full_response

        except Exception as e:
            print(f"{Colors.RED}Error: {e}{Colors.ENDC}")
            return None

    def chat(self, message):
        """Process a chat message"""
        self.save_message("user", message)
        self.context.append({"role": "user", "content": message})

        response = self.query_ollama(message)

        if response:
            self.save_message("assistant", response)
            self.context.append({
                "role": "assistant",
                "content": response
            })

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

{Colors.YELLOW}Commands:{Colors.ENDC}
  /help              Show this help
  /models            List available models
  /model <name>      Switch model
  /clear             Clear context
  /history [n]       Show last n messages (default: 10)
  /export            Export conversation
  /quit or /exit     Exit

{Colors.YELLOW}Tips:{Colors.ENDC}
  * Ctrl+C to interrupt generation
  * Ctrl+D to exit
  * Arrow keys for command history

{Colors.YELLOW}Current:{Colors.ENDC}
  Model: {self.model}
  Endpoint: {OLLAMA_ENDPOINT}
  History: {HISTORY_FILE}
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
            preview = content[:100] + "..." if len(content) > 100 else content
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
            f"{Colors.BOLD}{Colors.BLUE}AI Chat Interface"
            f"{Colors.ENDC}"
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
