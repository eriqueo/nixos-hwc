"""
LLM-based transcript polisher using Ollama.

Features:
- Chunks long transcripts to fit model context
- Uses subprocess for robust Ollama invocation
- Simple paragraph deduplication for stitching
- Fallback to basic cleaning on errors
"""

import subprocess
import logging
from typing import List


class LLMTranscriptPolisher:
    """Polish transcripts using local Ollama LLM."""

    def __init__(self, model: str = "llama3:8b", temperature: float = 0.3):
        """
        Initialize LLM polisher.

        Args:
            model: Ollama model name (must be pulled on server)
            temperature: Generation temperature (0.0-1.0, lower = more consistent)
        """
        self.model = model
        self.temperature = temperature
        self.logger = logging.getLogger(__name__)

        # Chunking parameters
        self.chunk_size = 6000  # Characters per chunk
        self.chunk_overlap = 400  # Overlap to avoid losing context

    def chunk_text(self, text: str) -> List[str]:
        """
        Split text into overlapping chunks.

        Args:
            text: Text to chunk

        Returns:
            List of text chunks
        """
        chunks = []
        start = 0
        text_len = len(text)

        while start < text_len:
            end = min(start + self.chunk_size, text_len)
            chunk = text[start:end]
            chunks.append(chunk)

            # Move start forward, with overlap if not at end
            if end < text_len:
                start = end - self.chunk_overlap
            else:
                start = end

        self.logger.debug(f"Split text into {len(chunks)} chunks")
        return chunks

    def polish_chunk(self, chunk: str, title: str, chunk_num: int, total_chunks: int) -> str:
        """
        Polish one chunk using Ollama via subprocess.

        Args:
            chunk: Text chunk to polish
            title: Video title for context
            chunk_num: Current chunk number (1-indexed)
            total_chunks: Total number of chunks

        Returns:
            Polished markdown text

        Raises:
            RuntimeError: If Ollama subprocess fails
        """
        prompt = f"""You are a transcript editor. Clean this YouTube transcript chunk.

Rules:
1. Remove filler words (um, uh, like, you know)
2. Fix grammar and sentence structure
3. Add clear section headers (use ## for main sections)
4. Create logical paragraph breaks
5. Keep ALL technical content and examples
6. DO NOT summarize or remove information

Title: {title}
Chunk: {chunk_num}/{total_chunks}

Transcript chunk:
{chunk}

Return only the cleaned Markdown. Start with appropriate headers."""

        try:
            self.logger.debug(f"Polishing chunk {chunk_num}/{total_chunks}")

            # Use subprocess for robust Ollama invocation
            proc = subprocess.run(
                ["ollama", "run", self.model, "--temperature", str(self.temperature)],
                input=prompt,
                text=True,
                capture_output=True,
                timeout=120  # 2 minute timeout per chunk
            )

            if proc.returncode != 0:
                raise RuntimeError(f"Ollama failed: {proc.stderr.strip()}")

            return proc.stdout.strip()

        except subprocess.TimeoutExpired:
            self.logger.error(f"Timeout polishing chunk {chunk_num}")
            raise RuntimeError("Ollama timeout")
        except FileNotFoundError:
            self.logger.error("Ollama command not found - is it installed?")
            raise RuntimeError("Ollama not found in PATH")

    def dedupe_paragraphs(self, text: str) -> str:
        """
        Remove duplicate paragraphs (simple stitching strategy).

        Args:
            text: Text with potential duplicate paragraphs

        Returns:
            Text with duplicates removed
        """
        paragraphs = [p.strip() for p in text.split('\n\n') if p.strip()]

        seen = set()
        unique = []

        for para in paragraphs:
            if para not in seen:
                unique.append(para)
                seen.add(para)

        removed = len(paragraphs) - len(unique)
        if removed > 0:
            self.logger.debug(f"Removed {removed} duplicate paragraphs")

        return '\n\n'.join(unique)

    def polish(self, cleaned_text: str, title: str) -> str:
        """
        Polish cleaned transcript using Ollama.

        Args:
            cleaned_text: Pre-cleaned text (from basic cleaner)
            title: Video title

        Returns:
            Polished markdown text

        Raises:
            RuntimeError: If polishing fails
        """
        self.logger.info(f"Starting LLM polishing for: {title}")

        # Check if chunking needed
        chunks = self.chunk_text(cleaned_text)

        if len(chunks) == 1:
            # Small transcript - single pass
            self.logger.info("Small transcript, single pass polishing")
            result = self.polish_chunk(chunks[0], title, 1, 1)

            # Ensure title at top
            if not result.lstrip().startswith(f"# {title}"):
                result = f"# {title}\n\n{result}"

            return result

        # Large transcript - chunk, polish, stitch
        self.logger.info(f"Large transcript, polishing {len(chunks)} chunks")

        polished_chunks = []
        for i, chunk in enumerate(chunks, start=1):
            try:
                polished = self.polish_chunk(chunk, title, i, len(chunks))
                polished_chunks.append(polished)
            except Exception as e:
                self.logger.error(f"Failed to polish chunk {i}: {e}")
                raise

        # Stitch chunks together
        merged = '\n\n'.join(polished_chunks)

        # Deduplicate paragraphs (simple overlap handling)
        result = self.dedupe_paragraphs(merged)

        # Ensure title at top
        if not result.lstrip().startswith(f"# {title}"):
            result = f"# {title}\n\n{result}"

        self.logger.info("LLM polishing complete")
        return result
