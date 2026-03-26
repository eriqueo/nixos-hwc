#!/usr/bin/env python3
"""
Transcript Formatter with Ollama Integration

Batch processes raw transcript files using local Ollama LLM to:
- Remove filler words and improve readability
- Add logical heading structure
- Format as clean markdown
- Preserve all technical content

Features:
- Smart chunking for large transcripts
- Automatic merge of multi-chunk results
- Retry logic with exponential backoff
- Metadata tracking for processed files
- Skip-if-exists behavior with --force override

Exit Codes:
    0: Success
    1: Error occurred (with details logged)
"""

import argparse
import json
import logging
import os
import re
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import List, Optional, Tuple

import requests

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Constants
DEFAULT_INPUT_DIR = "input_transcripts"
DEFAULT_OUTPUT_DIR = "cleaned_transcripts"
DEFAULT_PATTERN = "*.md"
DEFAULT_MODEL = "llama3"
DEFAULT_HOST = "http://127.0.0.1:11434"
DEFAULT_TEMPERATURE = 0.2
DEFAULT_TOP_P = 0.9

# Chunking parameters
TARGET_CHUNK_SIZE = 12000  # characters
HARD_CHUNK_LIMIT = 16000  # characters

# Retry configuration
MAX_RETRIES = 3
INITIAL_BACKOFF = 1.0  # seconds
MAX_BACKOFF = 8.0  # seconds
REQUEST_TIMEOUT = 60.0  # seconds

# Regex patterns
FILLER_WORDS_PATTERN = re.compile(
    r"\b(?:um+|uh+|ah+|er+|hmm+|you know|like|sort of|kind of|i mean|well,|so,|basically|literally|right\?|okay|ok)\b",
    re.IGNORECASE
)
MULTISPACE_PATTERN = re.compile(r"[ \t]{2,}")
TRAILING_SPACE_PATTERN = re.compile(r"[ \t]+$", re.MULTILINE)
CODE_FENCE_PATTERN = re.compile(r"(^```[\s\S]*?^```)", re.MULTILINE)

# Ollama prompts
SYSTEM_PROMPT = """You are a meticulous technical writer. Rewrite the USER transcript into clean Markdown with a clear structure:
- Add logical H1/H2/H3 headings.
- Use concise paragraphs, bullet/numbered lists where helpful.
- Bold important technical terms the speaker actually used.
- Preserve code blocks and commands verbatim; never invent code.
- Do not add new facts. If something is unclear, keep it terse and neutral.
- Remove chit-chat and filler; keep only the instructional/technical essence.
- Keep URLs and paths unchanged.
- Use American English, consistent terminology, and parallel list structure.
Output valid Markdown only, no preamble or commentary."""

CHUNK_USER_INSTRUCTION = "Restructure this transcript chunk. Keep ALL real technical content."

MERGE_USER_INSTRUCTION = """You will receive multiple already-structured Markdown chunks from the same transcript. Merge them into a single cohesive Markdown document:
- Keep existing headings where appropriate; adjust levels for a consistent outline.
- Remove duplicates and repeated intros/outros.
- Ensure section ordering is logical and non-repetitive.
- Do not add new content.
Output final Markdown only."""


class OllamaClient:
    """Client for interacting with Ollama API"""

    def __init__(
        self,
        host: str,
        model: str,
        temperature: float = DEFAULT_TEMPERATURE,
        top_p: float = DEFAULT_TOP_P
    ):
        """
        Initialize Ollama client.

        Args:
            host: Ollama host URL
            model: Model name to use
            temperature: Sampling temperature (0.0-1.0)
            top_p: Top-p sampling value (0.0-1.0)
        """
        self.host = host.rstrip("/")
        self.model = model
        self.temperature = temperature
        self.top_p = top_p

    def chat(
        self,
        system_prompt: str,
        user_message: str,
        retries: int = MAX_RETRIES,
        timeout: float = REQUEST_TIMEOUT
    ) -> str:
        """
        Send chat request to Ollama with retry logic.

        Args:
            system_prompt: System prompt for context
            user_message: User message/query
            retries: Number of retry attempts
            timeout: Request timeout in seconds

        Returns:
            str: Response content from Ollama

        Raises:
            RuntimeError: If all retries fail
        """
        url = f"{self.host}/api/chat"
        payload = {
            "model": self.model,
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_message}
            ],
            "options": {
                "temperature": self.temperature,
                "top_p": self.top_p
            },
            "stream": False
        }

        backoff = INITIAL_BACKOFF
        last_error: Optional[Exception] = None

        for attempt in range(1, retries + 1):
            try:
                logger.debug(f"Ollama request attempt {attempt}/{retries}")
                response = requests.post(url, json=payload, timeout=timeout)
                response.raise_for_status()

                data = response.json()

                # Validate response structure
                if "message" not in data:
                    raise ValueError(f"Invalid Ollama response: missing 'message' field")
                if "content" not in data["message"]:
                    raise ValueError(f"Invalid Ollama response: missing 'content' field in message")

                content = data["message"]["content"]
                if not content or not isinstance(content, str):
                    raise ValueError(f"Invalid Ollama response: empty or non-string content")

                return content

            except requests.Timeout as error:
                last_error = error
                logger.warning(f"Ollama request timed out (attempt {attempt}/{retries})")

            except requests.RequestException as error:
                last_error = error
                logger.warning(f"Ollama request failed: {error} (attempt {attempt}/{retries})")

            except (ValueError, KeyError) as error:
                last_error = error
                logger.error(f"Invalid Ollama response structure: {error}")
                # Don't retry on validation errors
                break

            # Wait before retry (except on last attempt)
            if attempt < retries:
                time.sleep(backoff)
                backoff = min(backoff * 2, MAX_BACKOFF)

        # All retries exhausted
        raise RuntimeError(f"Ollama chat failed after {retries} attempts: {last_error}")


class TranscriptCleaner:
    """Cleans and formats transcript text"""

    @staticmethod
    def strip_filler_words(text: str) -> str:
        """
        Remove filler words and improve text formatting.

        Args:
            text: Raw transcript text

        Returns:
            str: Cleaned text with fillers removed
        """
        # Stash code blocks to protect them from modification
        code_blocks: List[str] = []

        def stash_code_block(match: re.Match) -> str:
            code_blocks.append(match.group(1))
            return f"@@FENCE{len(code_blocks) - 1}@@"

        masked_text = CODE_FENCE_PATTERN.sub(stash_code_block, text)

        # Remove filler words
        masked_text = FILLER_WORDS_PATTERN.sub("", masked_text)

        # Clean up whitespace
        masked_text = MULTISPACE_PATTERN.sub(" ", masked_text)
        masked_text = TRAILING_SPACE_PATTERN.sub("", masked_text)

        # Process line by line
        lines = masked_text.splitlines()
        processed_lines: List[str] = []

        for line in lines:
            # Keep empty lines
            if not line.strip():
                processed_lines.append(line)
                continue

            # Keep markdown special lines as-is
            if line.lstrip().startswith(("-", "*", ">", "```", "    ", "\t")):
                processed_lines.append(line)
                continue

            # Process regular lines
            stripped = line.strip()
            if stripped:
                # Capitalize first character
                if re.match(r"[a-z]", stripped[0]):
                    stripped = stripped[0].upper() + stripped[1:]

                # Ensure sentence ends with punctuation
                if re.search(r"[A-Za-z0-9)]$", stripped):
                    stripped += "."

                # Preserve original indentation
                leading_spaces = len(line) - len(line.lstrip(" "))
                processed_lines.append(" " * leading_spaces + stripped)
            else:
                processed_lines.append(line)

        masked_text = "\n".join(processed_lines)

        # Restore code blocks
        def restore_code_block(match: re.Match) -> str:
            index = int(match.group(0)[8:-2])
            return code_blocks[index]

        return re.sub(r"@@FENCE(\d+)@@", restore_code_block, masked_text).strip()

    @staticmethod
    def split_into_chunks(
        text: str,
        target_size: int = TARGET_CHUNK_SIZE,
        hard_limit: int = HARD_CHUNK_LIMIT
    ) -> List[str]:
        """
        Split text into chunks based on paragraph boundaries.

        Args:
            text: Text to split
            target_size: Target chunk size in characters
            hard_limit: Hard maximum chunk size

        Returns:
            List of text chunks
        """
        paragraphs = text.split("\n\n")
        chunks: List[str] = []
        current_buffer: List[str] = []
        current_size = 0

        for paragraph in paragraphs:
            # Check if adding this paragraph would exceed target
            candidate = "\n\n".join(current_buffer + [paragraph]).strip()
            candidate_size = len(candidate)

            if candidate_size <= target_size:
                # Fits in current chunk
                current_buffer.append(paragraph)
                current_size = candidate_size
            else:
                # Would exceed target
                if current_buffer:
                    # Save current buffer as chunk
                    chunks.append("\n\n".join(current_buffer).strip())
                    current_buffer = [paragraph]
                    current_size = len(paragraph)
                else:
                    # Single paragraph too large, need to hard split
                    remaining = paragraph
                    while len(remaining) > hard_limit:
                        chunks.append(remaining[:hard_limit])
                        remaining = remaining[hard_limit:]

                    current_buffer = [remaining]
                    current_size = len(remaining)

        # Add final buffer
        if current_buffer:
            chunks.append("\n\n".join(current_buffer).strip())

        return chunks if chunks else [text]


class TranscriptProcessor:
    """Processes transcript files using Ollama"""

    def __init__(
        self,
        ollama_client: OllamaClient,
        output_dir: Path,
        force: bool = False
    ):
        """
        Initialize transcript processor.

        Args:
            ollama_client: Ollama client instance
            output_dir: Output directory for processed files
            force: Force reprocessing of existing files
        """
        self.ollama_client = ollama_client
        self.output_dir = output_dir
        self.force = force
        self.cleaner = TranscriptCleaner()

    def process_file(self, source_path: Path) -> Path:
        """
        Process a single transcript file.

        Args:
            source_path: Path to source transcript file

        Returns:
            Path: Path to output file

        Raises:
            RuntimeError: If processing fails
        """
        output_path = self.output_dir / source_path.name
        metadata_path = output_path.with_suffix(".json")

        # Check if already processed
        if output_path.exists() and not self.force:
            logger.info(f"Skipping {source_path.name} (already processed, use --force to reprocess)")
            return output_path

        logger.info(f"Processing: {source_path.name}")

        try:
            # Read and clean source file
            raw_text = source_path.read_text(encoding="utf-8", errors="ignore")
            cleaned_text = self.cleaner.strip_filler_words(raw_text)

            # Split into chunks
            chunks = self.cleaner.split_into_chunks(cleaned_text)
            logger.debug(f"Split into {len(chunks)} chunk(s)")

            # Process each chunk
            structured_chunks: List[str] = []
            for i, chunk in enumerate(chunks, 1):
                logger.debug(f"Processing chunk {i}/{len(chunks)}")
                user_message = f"{CHUNK_USER_INSTRUCTION}\n\n{chunk}"

                chunk_result = self.ollama_client.chat(
                    system_prompt=SYSTEM_PROMPT,
                    user_message=user_message
                )
                structured_chunks.append(chunk_result.strip())

            # Merge chunks if multiple
            if len(structured_chunks) == 1:
                final_markdown = structured_chunks[0]
            else:
                logger.debug(f"Merging {len(structured_chunks)} chunks")
                merged_input = "\n\n---\n\n".join(structured_chunks)
                final_markdown = self.ollama_client.chat(
                    system_prompt=SYSTEM_PROMPT,
                    user_message=f"{MERGE_USER_INSTRUCTION}\n\n{merged_input}"
                )

            # Write output file
            output_path.write_text(final_markdown.strip() + "\n", encoding="utf-8")

            # Write metadata
            metadata = {
                "source": str(source_path),
                "output": str(output_path),
                "model": self.ollama_client.model,
                "host": self.ollama_client.host,
                "temperature": self.ollama_client.temperature,
                "top_p": self.ollama_client.top_p,
                "chunks": len(chunks),
                "timestamp": datetime.utcnow().isoformat() + "Z"
            }
            metadata_path.write_text(json.dumps(metadata, indent=2), encoding="utf-8")

            logger.info(f"✓ Saved: {output_path.name}")
            return output_path

        except OSError as error:
            raise RuntimeError(f"File I/O error processing {source_path.name}: {error}")
        except Exception as error:
            raise RuntimeError(f"Error processing {source_path.name}: {error}")


def main() -> int:
    """
    Main entry point.

    Returns:
        int: Exit code
    """
    parser = argparse.ArgumentParser(
        prog="formatter",
        description="Format raw transcripts with Ollama LLM",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Environment Variables:
  TRANSCRIPTS_INPUT     Input directory (default: input_transcripts)
  TRANSCRIPTS_OUTPUT    Output directory (default: cleaned_transcripts)
  OLLAMA_MODEL          Model name (default: llama3)
  OLLAMA_HOST           Ollama host URL (default: http://127.0.0.1:11434)
  OLLAMA_TEMPERATURE    Sampling temperature (default: 0.2)
  OLLAMA_TOP_P          Top-p sampling (default: 0.9)

Examples:
  formatter.py --input raw/ --output cleaned/
  formatter.py --model qwen2.5:7b --force
  formatter.py --pattern "*.txt" --verbose
        """
    )

    parser.add_argument(
        "--input", "-i",
        default=os.environ.get("TRANSCRIPTS_INPUT", DEFAULT_INPUT_DIR),
        help=f"Input directory (default: {DEFAULT_INPUT_DIR})"
    )
    parser.add_argument(
        "--output", "-o",
        default=os.environ.get("TRANSCRIPTS_OUTPUT", DEFAULT_OUTPUT_DIR),
        help=f"Output directory (default: {DEFAULT_OUTPUT_DIR})"
    )
    parser.add_argument(
        "--pattern", "-p",
        default=DEFAULT_PATTERN,
        help=f"File pattern to match (default: {DEFAULT_PATTERN})"
    )
    parser.add_argument(
        "--model", "-m",
        default=os.environ.get("OLLAMA_MODEL", DEFAULT_MODEL),
        help=f"Ollama model name (default: {DEFAULT_MODEL})"
    )
    parser.add_argument(
        "--host",
        default=os.environ.get("OLLAMA_HOST", DEFAULT_HOST),
        help=f"Ollama host URL (default: {DEFAULT_HOST})"
    )
    parser.add_argument(
        "--force", "-f",
        action="store_true",
        help="Force reprocessing of existing files"
    )
    parser.add_argument(
        "--temperature",
        type=float,
        default=float(os.environ.get("OLLAMA_TEMPERATURE", str(DEFAULT_TEMPERATURE))),
        help=f"Sampling temperature 0.0-1.0 (default: {DEFAULT_TEMPERATURE})"
    )
    parser.add_argument(
        "--top_p",
        type=float,
        default=float(os.environ.get("OLLAMA_TOP_P", str(DEFAULT_TOP_P))),
        help=f"Top-p sampling 0.0-1.0 (default: {DEFAULT_TOP_P})"
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

    # Validate directories
    input_dir = Path(args.input)
    output_dir = Path(args.output)

    if not input_dir.exists():
        logger.error(f"Input directory does not exist: {input_dir}")
        return 1

    output_dir.mkdir(parents=True, exist_ok=True)

    # Find files to process
    files = sorted(input_dir.glob(args.pattern))
    if not files:
        logger.error(f"No files matching '{args.pattern}' in {input_dir}")
        return 1

    logger.info(f"Found {len(files)} file(s) to process")

    # Initialize Ollama client
    try:
        ollama_client = OllamaClient(
            host=args.host,
            model=args.model,
            temperature=args.temperature,
            top_p=args.top_p
        )
    except Exception as error:
        logger.error(f"Failed to initialize Ollama client: {error}")
        return 1

    # Initialize processor
    processor = TranscriptProcessor(
        ollama_client=ollama_client,
        output_dir=output_dir,
        force=args.force
    )

    # Process files
    error_count = 0
    success_count = 0

    for file_path in files:
        try:
            processor.process_file(file_path)
            success_count += 1
        except RuntimeError as error:
            error_count += 1
            logger.error(f"Failed to process {file_path.name}: {error}")
        except Exception as error:
            error_count += 1
            logger.error(f"Unexpected error processing {file_path.name}: {error}")

    # Summary
    logger.info(f"Processing complete: {success_count} succeeded, {error_count} failed")

    return 1 if error_count > 0 else 0


if __name__ == "__main__":
    sys.exit(main())
