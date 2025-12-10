#!/usr/bin/env python3
"""
Enhanced Obsidian Transcript Formatter with Progress Monitoring

Watches a folder for new transcript files, formats them with local Ollama (Qwen),
and provides detailed progress feedback with desktop notifications and GUI dialogs.

Features:
- Real-time file watching with watchdog
- Automatic formatting with Qwen/Ollama
- Desktop notifications for progress updates
- GUI file save dialog for output location
- Comprehensive logging with progress tracking
- Thread-safe processing queue

Exit Codes:
    0: Clean shutdown
    1: Configuration error
    2: Runtime error
"""

import argparse
import json
import logging
import os
import subprocess
import sys
import threading
import time
import tkinter as tk
from datetime import datetime
from pathlib import Path
from tkinter import filedialog, messagebox
from typing import Dict, List, Optional, Set

import requests
from watchdog.events import FileSystemEventHandler
from watchdog.observers import Observer

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Constants
DEFAULT_WATCH_FOLDER = "~/99-vaults/06-contractor/raw"
DEFAULT_PROMPT_FILE = "./formatting_prompt.txt"
DEFAULT_LOG_DIR = "~/logs/transcript-formatter"
DEFAULT_OLLAMA_HOST = "http://localhost:11434"
DEFAULT_OLLAMA_MODEL = "qwen2.5:7b"
DEFAULT_OLLAMA_TIMEOUT = 500  # seconds
DEFAULT_FILE_WAIT_TIME = 2  # seconds to wait for file to be fully written
DEFAULT_TEMPERATURE = 0.7
DEFAULT_TOP_P = 0.9


class Config:
    """Configuration for transcript formatter"""

    def __init__(self):
        """Initialize configuration from environment variables with defaults"""
        self.watch_folder = Path(os.getenv("WATCH_FOLDER", DEFAULT_WATCH_FOLDER)).expanduser()
        self.prompt_file = Path(os.getenv("PROMPT_FILE", DEFAULT_PROMPT_FILE))
        self.log_dir = Path(os.getenv("LOG_DIR", DEFAULT_LOG_DIR)).expanduser()
        self.ollama_host = os.getenv("OLLAMA_HOST", DEFAULT_OLLAMA_HOST)
        self.ollama_model = os.getenv("OLLAMA_MODEL", DEFAULT_OLLAMA_MODEL)
        self.ollama_timeout = int(os.getenv("OLLAMA_TIMEOUT", str(DEFAULT_OLLAMA_TIMEOUT)))
        self.file_wait_time = int(os.getenv("FILE_WAIT_TIME", str(DEFAULT_FILE_WAIT_TIME)))
        self.temperature = float(os.getenv("OLLAMA_TEMPERATURE", str(DEFAULT_TEMPERATURE)))
        self.top_p = float(os.getenv("OLLAMA_TOP_P", str(DEFAULT_TOP_P)))

        # Validate configuration
        self._validate()

    def _validate(self) -> None:
        """Validate configuration values"""
        if not self.prompt_file.exists():
            raise ValueError(f"Prompt file not found: {self.prompt_file}")

        if self.ollama_timeout <= 0:
            raise ValueError(f"OLLAMA_TIMEOUT must be positive, got: {self.ollama_timeout}")

        if self.file_wait_time < 0:
            raise ValueError(f"FILE_WAIT_TIME must be non-negative, got: {self.file_wait_time}")

        # Create directories if needed
        self.watch_folder.mkdir(parents=True, exist_ok=True)
        self.log_dir.mkdir(parents=True, exist_ok=True)


class ProgressLogger:
    """Handles logging and status file updates"""

    def __init__(self, log_file: Path):
        """
        Initialize progress logger.

        Args:
            log_file: Path to log file
        """
        self.log_file = log_file
        self.status_file = log_file.parent / "formatter_status.txt"

    def log(self, message: str, level: str = "INFO") -> None:
        """
        Log message to file, status file, and console.

        Args:
            message: Message to log
            level: Log level (INFO, WARNING, ERROR, etc.)
        """
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        log_entry = f"[{timestamp}] {level}: {message}"

        # Write to log file
        try:
            with open(self.log_file, 'a', encoding='utf-8') as file:
                file.write(log_entry + "\n")
        except OSError as error:
            logger.error(f"Failed to write to log file: {error}")

        # Update status file with latest message
        try:
            with open(self.status_file, 'w', encoding='utf-8') as file:
                file.write(f"Last Update: {timestamp}\n")
                file.write(f"Status: {message}\n")
        except OSError as error:
            logger.error(f"Failed to write to status file: {error}")

        # Print to console (will be picked up by logging framework)
        log_method = getattr(logger, level.lower(), logger.info)
        log_method(message)

    def update_progress(self, filename: str, stage: str, details: str = "") -> None:
        """
        Update progress for a specific file.

        Args:
            filename: Name of file being processed
            stage: Processing stage
            details: Optional additional details
        """
        message = f"{filename} - {stage}"
        if details:
            message += f" ({details})"
        self.log(message, "PROGRESS")


class DesktopNotifier:
    """Handles desktop notifications"""

    @staticmethod
    def notify(title: str, message: str, urgency: str = "normal") -> None:
        """
        Send desktop notification.

        Args:
            title: Notification title
            message: Notification message
            urgency: Urgency level ("low", "normal", "critical")
        """
        try:
            subprocess.run(
                [
                    "notify-send",
                    "--urgency", urgency,
                    "--app-name", "Transcript Formatter",
                    title,
                    message
                ],
                check=False,
                timeout=5
            )
        except FileNotFoundError:
            logger.debug("notify-send not available, skipping notification")
        except subprocess.TimeoutExpired:
            logger.warning("notify-send timed out")
        except Exception as error:
            logger.debug(f"Notification failed: {error}")


class OllamaFormatter:
    """Formats transcripts using Ollama API"""

    def __init__(
        self,
        host: str,
        model: str,
        prompt_template: str,
        temperature: float = DEFAULT_TEMPERATURE,
        top_p: float = DEFAULT_TOP_P,
        timeout: int = DEFAULT_OLLAMA_TIMEOUT
    ):
        """
        Initialize Ollama formatter.

        Args:
            host: Ollama host URL
            model: Model name to use
            prompt_template: Template for formatting prompts
            temperature: Sampling temperature
            top_p: Top-p sampling value
            timeout: Request timeout in seconds
        """
        self.host = host.rstrip("/")
        self.model = model
        self.prompt_template = prompt_template
        self.temperature = temperature
        self.top_p = top_p
        self.timeout = timeout

    def format_transcript(self, transcript_text: str) -> Optional[str]:
        """
        Format transcript text using Ollama.

        Args:
            transcript_text: Raw transcript text

        Returns:
            Optional[str]: Formatted text or None if formatting fails
        """
        # Insert transcript into prompt
        full_prompt = self.prompt_template.replace('{transcript}', transcript_text)

        url = f"{self.host}/api/generate"
        payload = {
            "model": self.model,
            "prompt": full_prompt,
            "stream": False,
            "options": {
                "temperature": self.temperature,
                "top_p": self.top_p
            }
        }

        try:
            response = requests.post(url, json=payload, timeout=self.timeout)
            response.raise_for_status()

            data = response.json()

            # Validate response structure
            if "response" not in data:
                logger.error(f"Invalid Ollama response: missing 'response' field")
                return None

            formatted_text = data["response"]
            if not formatted_text or not isinstance(formatted_text, str):
                logger.error(f"Invalid Ollama response: empty or non-string response")
                return None

            return formatted_text

        except requests.Timeout:
            logger.error(f"Ollama request timed out after {self.timeout}s")
            return None
        except requests.RequestException as error:
            logger.error(f"Ollama request failed: {error}")
            return None
        except (ValueError, KeyError) as error:
            logger.error(f"Invalid Ollama response structure: {error}")
            return None
        except Exception as error:
            logger.error(f"Unexpected error formatting transcript: {error}")
            return None


class EnhancedTranscriptHandler(FileSystemEventHandler):
    """Handles file system events for transcript processing"""

    def __init__(self, config: Config):
        """
        Initialize transcript handler.

        Args:
            config: Configuration instance
        """
        self.config = config

        # Setup logging and notifications
        log_file = config.log_dir / "formatter.log"
        self.logger = ProgressLogger(log_file)
        self.notifier = DesktopNotifier()

        # Load formatting prompt
        with open(config.prompt_file, 'r', encoding='utf-8') as file:
            prompt_template = file.read()

        # Initialize Ollama formatter
        self.formatter = OllamaFormatter(
            host=config.ollama_host,
            model=config.ollama_model,
            prompt_template=prompt_template,
            temperature=config.temperature,
            top_p=config.top_p,
            timeout=config.ollama_timeout
        )

        # Track processing state (thread-safe)
        self._processing_lock = threading.Lock()
        self._processing_queue: Set[str] = set()
        self.completed_count = 0

        self.logger.log(f"🚀 Transcript Formatter Started")
        self.logger.log(f"👀 Watching: {config.watch_folder}")
        self.logger.log(f"📝 Using prompt: {config.prompt_file}")
        self.logger.log(f"🤖 Using model: {config.ollama_model}")

        # Desktop notification
        self.notifier.notify(
            "Transcript Formatter Started",
            f"Watching {config.watch_folder.name} folder"
        )

    def on_created(self, event) -> None:
        """
        Handle file creation events.

        Args:
            event: File system event
        """
        if event.is_directory:
            return

        file_path = Path(event.src_path)

        # Only process .md files
        if file_path.suffix.lower() != '.md':
            return

        self.logger.log(f"📁 NEW FILE DETECTED: {file_path.name}")

        # Add to processing queue
        with self._processing_lock:
            if file_path.name in self._processing_queue:
                self.logger.log(f"⚠️ File already in queue: {file_path.name}")
                return
            self._processing_queue.add(file_path.name)

        # Desktop notification
        self.notifier.notify(
            "New Transcript Detected",
            f"Processing: {file_path.name}"
        )

        # Process in separate thread
        thread = threading.Thread(
            target=self.process_transcript,
            args=(file_path,),
            daemon=True
        )
        thread.start()

    def process_transcript(self, file_path: Path) -> None:
        """
        Process a transcript file.

        Args:
            file_path: Path to transcript file
        """
        filename = file_path.name

        try:
            # Update progress
            self.logger.update_progress(filename, "STARTING", "Reading file...")

            # Wait for file to be fully written
            time.sleep(self.config.file_wait_time)

            # Read transcript content
            try:
                with open(file_path, 'r', encoding='utf-8') as file:
                    transcript_text = file.read().strip()
            except OSError as error:
                self.logger.log(f"❌ ERROR reading {filename}: {error}")
                self.notifier.notify("Error", f"Failed to read {filename}", "critical")
                return

            if not transcript_text:
                self.logger.log(f"⚠️ WARNING: {filename} is empty, skipping...")
                self.notifier.notify("Warning", f"{filename} is empty", "low")
                return

            word_count = len(transcript_text.split())
            self.logger.update_progress(filename, "PROCESSING", f"{word_count} words, sending to Qwen...")

            # Format with Qwen
            formatted_text = self.formatter.format_transcript(transcript_text)

            if formatted_text:
                self.logger.update_progress(filename, "COMPLETED", "Ready for saving")

                # Desktop notification
                self.notifier.notify(
                    "Transcript Ready",
                    f"{filename} formatted successfully!"
                )

                # Prompt user for save location
                self.prompt_save_location(formatted_text, file_path.stem)

                with self._processing_lock:
                    self.completed_count += 1

                self.logger.log(f"✅ TOTAL COMPLETED: {self.completed_count}")

            else:
                self.logger.log(f"❌ ERROR: Failed to format {filename}")
                self.notifier.notify("Error", f"Failed to format {filename}", "critical")

        except Exception as error:
            self.logger.log(f"❌ ERROR processing {filename}: {error}")
            self.notifier.notify("Error", f"Error processing {filename}", "critical")

        finally:
            # Remove from queue
            with self._processing_lock:
                self._processing_queue.discard(filename)

    def prompt_save_location(self, formatted_text: str, original_filename: str) -> None:
        """
        Show file picker dialog for save location.

        Args:
            formatted_text: Formatted transcript text
            original_filename: Original filename (without extension)
        """
        def save_dialog() -> None:
            root = tk.Tk()
            root.withdraw()
            root.lift()
            root.attributes('-topmost', True)

            suggested_name = f"{original_filename}_formatted.md"
            initial_dir = str(Path.home() / "99-vaults" / "06-contractor")

            file_path = filedialog.asksaveasfilename(
                title="Save Formatted Transcript",
                defaultextension=".md",
                filetypes=[("Markdown files", "*.md"), ("All files", "*.*")],
                initialfile=suggested_name,
                initialdir=initial_dir
            )

            if file_path:
                try:
                    with open(file_path, 'w', encoding='utf-8') as file:
                        file.write(formatted_text)

                    self.logger.log(f"💾 SAVED: {original_filename} → {file_path}")

                    messagebox.showinfo(
                        "Success",
                        f"Formatted transcript saved to:\n{file_path}"
                    )

                    # Success notification
                    self.notifier.notify(
                        "File Saved",
                        f"Saved: {Path(file_path).name}"
                    )

                except OSError as error:
                    self.logger.log(f"❌ SAVE ERROR: {error}")
                    messagebox.showerror("Error", f"Failed to save file:\n{error}")
            else:
                self.logger.log(f"❌ SAVE CANCELLED: {original_filename}")

            root.destroy()

        save_dialog()

    def get_status(self) -> Dict:
        """
        Return current status for monitoring.

        Returns:
            Dict: Status information
        """
        with self._processing_lock:
            return {
                "queue_length": len(self._processing_queue),
                "processing_files": list(self._processing_queue),
                "completed_count": self.completed_count,
                "watching": str(self.config.watch_folder)
            }


def check_qwen_connection(config: Config) -> bool:
    """
    Check if Qwen is running and accessible.

    Args:
        config: Configuration instance

    Returns:
        bool: True if Qwen is accessible
    """
    try:
        response = requests.get(f"{config.ollama_host}/api/tags", timeout=5)
        response.raise_for_status()

        data = response.json()
        models = data.get('models', [])
        qwen_models = [m for m in models if 'qwen' in m.get('name', '').lower()]

        if qwen_models:
            logger.info(f"✅ Qwen is running. Available models: {[m['name'] for m in qwen_models]}")
            return True
        else:
            logger.error("❌ Qwen models not found. Run: ollama pull qwen2.5:7b")
            return False

    except requests.Timeout:
        logger.error("❌ Timeout connecting to Qwen/Ollama")
        return False
    except requests.RequestException as error:
        logger.error(f"❌ Cannot connect to Qwen: {error}")
        logger.info("Make sure Ollama is running: ollama serve")
        return False
    except Exception as error:
        logger.error(f"❌ Unexpected error checking Qwen connection: {error}")
        return False


def main() -> int:
    """
    Main entry point.

    Returns:
        int: Exit code
    """
    parser = argparse.ArgumentParser(
        prog="obsidian-transcript-formatter",
        description="Watch folder for transcripts and format them with Qwen/Ollama",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Environment Variables:
  WATCH_FOLDER          Folder to watch (default: ~/99-vaults/06-contractor/raw)
  PROMPT_FILE           Prompt template file (default: ./formatting_prompt.txt)
  LOG_DIR               Log directory (default: ~/logs/transcript-formatter)
  OLLAMA_HOST           Ollama host URL (default: http://localhost:11434)
  OLLAMA_MODEL          Model to use (default: qwen2.5:7b)
  OLLAMA_TIMEOUT        Request timeout in seconds (default: 500)
  FILE_WAIT_TIME        Seconds to wait for file write (default: 2)
  OLLAMA_TEMPERATURE    Sampling temperature (default: 0.7)
  OLLAMA_TOP_P          Top-p sampling (default: 0.9)

Examples:
  obsidian-transcript-formatter.py
  obsidian-transcript-formatter.py --verbose
  OLLAMA_MODEL=llama3 obsidian-transcript-formatter.py
        """
    )

    parser.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="Enable verbose logging"
    )

    args = parser.parse_args()

    # Configure logging
    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)
        logger.setLevel(logging.DEBUG)

    logger.info("🚀 Enhanced Obsidian Transcript Formatter")
    logger.info("=" * 50)

    try:
        # Load configuration
        config = Config()

        # Check if Qwen is running
        if not check_qwen_connection(config):
            logger.error("\n❌ Please start Qwen first:")
            logger.error("   ollama serve")
            logger.error("   ollama pull qwen2.5:7b")
            return 1

        logger.info(f"👀 Monitoring: {config.watch_folder}")
        logger.info(f"📊 Progress logs: {config.log_dir}/")
        logger.info(f"📱 Desktop notifications enabled")
        logger.info(f"📁 Drop .md transcript files into the watched folder to auto-format them!")
        logger.info(f"💾 You'll be prompted where to save each formatted transcript.")
        logger.info(f"🛑 Press Ctrl+C to stop...")
        logger.info("")

        # Set up file monitoring
        event_handler = EnhancedTranscriptHandler(config)
        observer = Observer()
        observer.schedule(event_handler, str(config.watch_folder), recursive=False)

        # Start monitoring
        observer.start()

        try:
            while True:
                time.sleep(1)
        except KeyboardInterrupt:
            logger.info("\n🛑 Stopping transcript formatter...")
            event_handler.logger.log("🛑 Transcript Formatter Stopped")
            observer.stop()

        observer.join()
        logger.info("✅ Transcript formatter stopped.")

        return 0

    except ValueError as error:
        logger.error(f"Configuration error: {error}")
        return 1
    except Exception as error:
        logger.error(f"Error starting formatter: {error}")
        return 2


if __name__ == "__main__":
    sys.exit(main())
