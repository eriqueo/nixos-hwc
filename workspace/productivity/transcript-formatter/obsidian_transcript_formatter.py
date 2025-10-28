#!/usr/bin/env python3
"""
Enhanced Obsidian Transcript Formatter with Progress Monitoring
Watches ~/99-vaults/06-contractor/raw/ for new transcript files,
formats them with local Qwen, and provides detailed progress feedback.
"""

import os
import time
import requests
import json
from pathlib import Path
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler
import tkinter as tk
from tkinter import filedialog, messagebox
import threading
from datetime import datetime
import subprocess

class ProgressLogger:
    def __init__(self, log_file):
        self.log_file = Path(log_file)
        self.status_file = self.log_file.parent / "formatter_status.txt"
        
    def log(self, message, level="INFO"):
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        log_entry = f"[{timestamp}] {level}: {message}"
        
        # Write to log file
        with open(self.log_file, 'a') as f:
            f.write(log_entry + "\n")
        
        # Update status file with latest message
        with open(self.status_file, 'w') as f:
            f.write(f"Last Update: {timestamp}\n")
            f.write(f"Status: {message}\n")
        
        # Print to console
        print(log_entry)
    
    def update_progress(self, filename, stage, details=""):
        message = f"{filename} - {stage}"
        if details:
            message += f" ({details})"
        self.log(message, "PROGRESS")

class DesktopNotifier:
    @staticmethod
    def notify(title, message, urgency="normal"):
        try:
            subprocess.run([
                "notify-send", 
                "--urgency", urgency,
                "--app-name", "Transcript Formatter",
                title, 
                message
            ], check=False)
        except:
            pass  # Fail silently if notify-send not available

class EnhancedTranscriptHandler(FileSystemEventHandler):
    def __init__(self, watch_folder, prompt_file):
        self.watch_folder = Path(watch_folder).expanduser()
        self.prompt_file = Path(prompt_file)
        
        # Setup logging and notifications
        log_dir = Path.home() / "logs" / "transcript-formatter"
        log_dir.mkdir(parents=True, exist_ok=True)
        
        self.logger = ProgressLogger(log_dir / "formatter.log")
        self.notifier = DesktopNotifier()
        
        # Ensure watch folder exists
        self.watch_folder.mkdir(parents=True, exist_ok=True)
        
        # Load formatting prompt
        if self.prompt_file.exists():
            with open(self.prompt_file, 'r') as f:
                self.prompt_template = f.read()
        else:
            raise FileNotFoundError(f"Prompt file not found: {self.prompt_file}")
        
        # Track processing queue
        self.processing_queue = []
        self.completed_count = 0
        
        self.logger.log(f"🚀 Transcript Formatter Started")
        self.logger.log(f"👀 Watching: {self.watch_folder}")
        self.logger.log(f"📝 Using prompt: {self.prompt_file}")
        
        # Desktop notification
        self.notifier.notify(
            "Transcript Formatter Started", 
            f"Watching {self.watch_folder.name} folder"
        )
    
    def on_created(self, event):
        if event.is_directory:
            return
            
        file_path = Path(event.src_path)
        
        # Only process .md files
        if file_path.suffix.lower() == '.md':
            self.logger.log(f"📁 NEW FILE DETECTED: {file_path.name}")
            self.processing_queue.append(file_path.name)
            
            # Desktop notification
            self.notifier.notify(
                "New Transcript Detected", 
                f"Processing: {file_path.name}"
            )
            
            # Process in separate thread
            threading.Thread(target=self.process_transcript, args=(file_path,), daemon=True).start()
    
    def process_transcript(self, file_path):
        filename = file_path.name
        
        try:
            # Update progress
            self.logger.update_progress(filename, "STARTING", "Reading file...")
            
            # Wait for file to be fully written
            time.sleep(2)
            
            # Read transcript content
            with open(file_path, 'r', encoding='utf-8') as f:
                transcript_text = f.read().strip()
            
            if not transcript_text:
                self.logger.log(f"⚠️  WARNING: {filename} is empty, skipping...")
                self.notifier.notify("Warning", f"{filename} is empty", "low")
                return
            
            word_count = len(transcript_text.split())
            self.logger.update_progress(filename, "PROCESSING", f"{word_count} words, sending to Qwen...")
            
            # Format with Qwen
            formatted_text = self.format_with_qwen(transcript_text, filename)
            
            if formatted_text:
                self.logger.update_progress(filename, "COMPLETED", "Ready for saving")
                
                # Desktop notification
                self.notifier.notify(
                    "Transcript Ready", 
                    f"{filename} formatted successfully!"
                )
                
                # Prompt user for save location
                self.prompt_save_location(formatted_text, file_path.stem)
                
                self.completed_count += 1
                self.logger.log(f"✅ TOTAL COMPLETED: {self.completed_count}")
                
            else:
                self.logger.log(f"❌ ERROR: Failed to format {filename}")
                self.notifier.notify("Error", f"Failed to format {filename}", "critical")
                
        except Exception as e:
            self.logger.log(f"❌ ERROR processing {filename}: {str(e)}")
            self.notifier.notify("Error", f"Error processing {filename}", "critical")
        
        finally:
            # Remove from queue
            if filename in self.processing_queue:
                self.processing_queue.remove(filename)
    
    def format_with_qwen(self, transcript_text, filename):
        # Insert transcript into prompt
        full_prompt = self.prompt_template.replace('{transcript}', transcript_text)
        
        url = "http://localhost:11434/api/generate"
        payload = {
            "model": "qwen2.5:7b",
            "prompt": full_prompt,
            "stream": False,
            "options": {
                "temperature": 0.7,
                "top_p": 0.9
            }
        }
        
        try:
            self.logger.update_progress(filename, "QWEN_PROCESSING", "AI formatting in progress...")
            
            response = requests.post(url, json=payload, timeout=500)
            if response.status_code == 200:
                result = response.json()
                self.logger.update_progress(filename, "QWEN_COMPLETE", "AI formatting finished")
                return result['response']
            else:
                self.logger.log(f"❌ API Error for {filename}: {response.status_code} - {response.text}")
                return None
                
        except Exception as e:
            self.logger.log(f"❌ Request Error for {filename}: {str(e)}")
            return None
    
    def prompt_save_location(self, formatted_text, original_filename):
        """Show file picker dialog for save location"""
        def save_dialog():
            root = tk.Tk()
            root.withdraw()
            root.lift()
            root.attributes('-topmost', True)
            
            suggested_name = f"{original_filename}_formatted.md"
            
            file_path = filedialog.asksaveasfilename(
                title="Save Formatted Transcript",
                defaultextension=".md",
                filetypes=[("Markdown files", "*.md"), ("All files", "*.*")],
                initialfile=suggested_name,
                initialdir=str(Path.home() / "99-vaults" / "06-contractor")
            )
            
            if file_path:
                try:
                    with open(file_path, 'w', encoding='utf-8') as f:
                        f.write(formatted_text)
                    
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
                    
                except Exception as e:
                    self.logger.log(f"❌ SAVE ERROR: {str(e)}")
                    messagebox.showerror("Error", f"Failed to save file:\n{str(e)}")
            else:
                self.logger.log(f"❌ SAVE CANCELLED: {original_filename}")
            
            root.destroy()
        
        save_dialog()
    
    def get_status(self):
        """Return current status for monitoring"""
        return {
            "queue_length": len(self.processing_queue),
            "processing_files": self.processing_queue.copy(),
            "completed_count": self.completed_count,
            "watching": str(self.watch_folder)
        }

def check_qwen_connection():
    """Check if Qwen is running and accessible"""
    try:
        response = requests.get("http://localhost:11434/api/tags", timeout=5)
        if response.status_code == 200:
            models = response.json().get('models', [])
            qwen_models = [m for m in models if 'qwen' in m.get('name', '').lower()]
            if qwen_models:
                print(f"✅ Qwen is running. Available models: {[m['name'] for m in qwen_models]}")
                return True
            else:
                print("❌ Qwen models not found. Run: ollama pull qwen2.5:7b")
                return False
        else:
            print("❌ Ollama API not responding")
            return False
    except Exception as e:
        print(f"❌ Cannot connect to Qwen: {str(e)}")
        print("Make sure Ollama is running: ollama serve")
        return False

def main():
    # Configuration
    WATCH_FOLDER = "~/99-vaults/06-contractor/raw"
    PROMPT_FILE = "./formatting_prompt.txt"
    
    print("🚀 Enhanced Obsidian Transcript Formatter")
    print("=" * 50)
    
    # Check if Qwen is running
    if not check_qwen_connection():
        print("\n❌ Please start Qwen first:")
        print("   ollama serve")
        print("   ollama pull qwen2.5:7b")
        return
    
    # Check if prompt file exists
    if not Path(PROMPT_FILE).exists():
        print(f"❌ Prompt file not found: {PROMPT_FILE}")
        print("Please create the formatting_prompt.txt file first.")
        return
    
    print(f"👀 Monitoring: {Path(WATCH_FOLDER).expanduser()}")
    print(f"📊 Progress logs: ~/logs/transcript-formatter/")
    print(f"📱 Desktop notifications enabled")
    print("📁 Drop .md transcript files into the raw folder to auto-format them!")
    print("💾 You'll be prompted where to save each formatted transcript.")
    print("🛑 Press Ctrl+C to stop...")
    print()
    
    # Set up file monitoring
    try:
        event_handler = EnhancedTranscriptHandler(WATCH_FOLDER, PROMPT_FILE)
        observer = Observer()
        observer.schedule(event_handler, str(event_handler.watch_folder), recursive=False)
        
        # Start monitoring
        observer.start()
        
        try:
            while True:
                time.sleep(1)
        except KeyboardInterrupt:
            print("\n🛑 Stopping transcript formatter...")
            event_handler.logger.log("🛑 Transcript Formatter Stopped")
            observer.stop()
        
        observer.join()
        print("✅ Transcript formatter stopped.")
        
    except Exception as e:
        print(f"❌ Error starting formatter: {str(e)}")

if __name__ == "__main__":
    main()

