#!/usr/bin/env python3
"""
Obsidian Transcript Formatter
Watches ~/99-vaults/06-contractor/raw/ for new transcript files,
formats them with local Qwen, and prompts user for save location.
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

class ObsidianTranscriptHandler(FileSystemEventHandler):
    def __init__(self, watch_folder, prompt_file):
        self.watch_folder = Path(watch_folder).expanduser()
        self.prompt_file = Path(prompt_file)
        
        # Ensure watch folder exists
        self.watch_folder.mkdir(parents=True, exist_ok=True)
        
        # Load formatting prompt
        if self.prompt_file.exists():
            with open(self.prompt_file, 'r') as f:
                self.prompt_template = f.read()
        else:
            raise FileNotFoundError(f"Prompt file not found: {self.prompt_file}")
        
        print(f"👀 Watching: {self.watch_folder}")
        print(f"📝 Using prompt: {self.prompt_file}")
    
    def on_created(self, event):
        if event.is_directory:
            return
            
        file_path = Path(event.src_path)
        
        # Only process .md files
        if file_path.suffix.lower() == '.md':
            print(f"📁 New transcript detected: {file_path.name}")
            # Process in separate thread to avoid blocking file watcher
            threading.Thread(target=self.process_transcript, args=(file_path,), daemon=True).start()
    
    def process_transcript(self, file_path):
        try:
            # Wait a moment for file to be fully written
            time.sleep(2)
            
            # Read transcript content
            with open(file_path, 'r', encoding='utf-8') as f:
                transcript_text = f.read().strip()
            
            if not transcript_text:
                self.show_message("Warning", f"File {file_path.name} is empty, skipping...")
                return
            
            print(f"🔄 Processing {file_path.name}...")
            self.show_message("Processing", f"Formatting {file_path.name}...\nThis may take a moment.")
            
            # Format with Qwen
            formatted_text = self.format_with_qwen(transcript_text, file_path.stem)
            
            if formatted_text:
                # Prompt user for save location
                self.prompt_save_location(formatted_text, file_path.stem)
            else:
                self.show_message("Error", f"Failed to format {file_path.name}")
                
        except Exception as e:
            self.show_message("Error", f"Error processing {file_path.name}: {str(e)}")
            print(f"❌ Error processing {file_path.name}: {str(e)}")
    
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
            print("🤖 Sending to Qwen for formatting...")
            response = requests.post(url, json=payload, timeout=300)  # 5 minute timeout
            if response.status_code == 200:
                result = response.json()
                print("✅ Formatting complete!")
                return result['response']
            else:
                print(f"API Error: {response.status_code} - {response.text}")
                return None
                
        except Exception as e:
            print(f"Request Error: {str(e)}")
            return None
    
    def prompt_save_location(self, formatted_text, original_filename):
        """Show file picker dialog for save location"""
        def save_dialog():
            root = tk.Tk()
            root.withdraw()  # Hide main window
            root.lift()
            root.attributes('-topmost', True)
            
            # Suggest filename
            suggested_name = f"{original_filename}_formatted.md"
            
            # Show save dialog
            file_path = filedialog.asksaveasfilename(
                title="Save Formatted Transcript",
                defaultextension=".md",
                filetypes=[("Markdown files", "*.md"), ("All files", "*.*")],
                initialfile=suggested_name,
                initialdir=str(Path.home() / "99-vaults" / "06-contractor")
            )
            
            if file_path:
                try:
                    # Save the formatted transcript
                    with open(file_path, 'w', encoding='utf-8') as f:
                        f.write(formatted_text)
                    
                    print(f"✅ Saved formatted transcript: {file_path}")
                    
                    # Show success message
                    messagebox.showinfo(
                        "Success", 
                        f"Formatted transcript saved to:\n{file_path}"
                    )
                    
                except Exception as e:
                    messagebox.showerror("Error", f"Failed to save file:\n{str(e)}")
                    print(f"❌ Save error: {str(e)}")
            else:
                print("❌ Save cancelled by user")
            
            root.destroy()
        
        # Run dialog in main thread
        save_dialog()
    
    def show_message(self, title, message):
        """Show a message dialog"""
        def show():
            root = tk.Tk()
            root.withdraw()
            root.lift()
            root.attributes('-topmost', True)
            
            if title == "Error":
                messagebox.showerror(title, message)
            elif title == "Warning":
                messagebox.showwarning(title, message)
            else:
                messagebox.showinfo(title, message)
            
            root.destroy()
        
        # Run in main thread
        threading.Thread(target=show, daemon=True).start()

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
    
    print("🚀 Obsidian Transcript Formatter")
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
    print("📁 Drop .md transcript files into the raw folder to auto-format them!")
    print("💾 You'll be prompted where to save each formatted transcript.")
    print("🛑 Press Ctrl+C to stop...")
    print()
    
    # Set up file monitoring
    try:
        event_handler = ObsidianTranscriptHandler(WATCH_FOLDER, PROMPT_FILE)
        observer = Observer()
        observer.schedule(event_handler, str(event_handler.watch_folder), recursive=False)
        
        # Start monitoring
        observer.start()
        
        try:
            while True:
                time.sleep(1)
        except KeyboardInterrupt:
            print("\n🛑 Stopping transcript formatter...")
            observer.stop()
        
        observer.join()
        print("✅ Transcript formatter stopped.")
        
    except Exception as e:
        print(f"❌ Error starting formatter: {str(e)}")

if __name__ == "__main__":
    main()

