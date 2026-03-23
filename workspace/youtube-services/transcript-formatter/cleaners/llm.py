"""
LLM-based transcript polisher using Ollama.

Features:
- Chunks long transcripts to fit model context
- Async HTTP API for non-blocking Ollama invocation
- Parallel chunk processing with semaphore limits
- Sentence-level deduplication for better stitching
- LLM output validation to prevent hallucination
- Fallback to basic cleaning on errors
"""

import asyncio
import logging
import os
import re
from typing import List, Set

import httpx


class LLMTranscriptPolisher:
    """Polish transcripts using local Ollama LLM."""

    def __init__(self, model: str = "llama3:8b", temperature: float = 0.3, max_concurrent: int = 2):
        """
        Initialize LLM polisher.

        Args:
            model: Ollama model name (must be pulled on server)
            temperature: Generation temperature (0.0-1.0, lower = more consistent)
            max_concurrent: Max concurrent Ollama HTTP requests
        """
        self.model = model
        self.temperature = temperature
        self.max_concurrent = max_concurrent
        self.logger = logging.getLogger(__name__)

        # Get Ollama host from environment
        self.ollama_host = os.getenv("OLLAMA_HOST", "http://127.0.0.1:11434")

        # Chunking parameters
        self.chunk_size = 6000  # Characters per chunk
        self.chunk_overlap = 400  # Overlap to avoid losing context

        # Semaphore for rate limiting concurrent Ollama calls
        self._semaphore = asyncio.Semaphore(max_concurrent)

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

    async def is_available(self) -> bool:
        """Check if Ollama is available and has the required model."""
        try:
            async with httpx.AsyncClient(timeout=5.0) as client:
                # Check Ollama is running
                response = await client.get(f"{self.ollama_host}/api/tags")
                response.raise_for_status()

                # Check model is available
                tags = response.json()
                models = [m["name"] for m in tags.get("models", [])]

                # Model name might include tag (e.g., "llama3.2:3b" vs "llama3.2")
                model_base = self.model.split(":")[0]
                available = any(model_base in m for m in models)

                if not available:
                    self.logger.warning(f"Model {self.model} not found in Ollama")

                return available
        except Exception as e:
            self.logger.warning(f"Ollama not available: {e}")
            return False

    async def polish_chunk(self, chunk: str, title: str, chunk_num: int, total_chunks: int) -> str:
        """
        Polish one chunk using Ollama via HTTP API.

        Args:
            chunk: Text chunk to polish
            title: Video title for context
            chunk_num: Current chunk number (1-indexed)
            total_chunks: Total number of chunks

        Returns:
            Polished markdown text

        Raises:
            RuntimeError: If Ollama HTTP request fails
        """
        prompt = f"""You are a transcript editor. Your task is to clean and format this YouTube transcript segment while preserving ALL information.

CRITICAL RULES:
1. DO NOT summarize - keep all details, examples, and explanations
2. DO NOT add your own commentary or introductions
3. DO NOT start with phrases like "Here is the cleaned transcript"
4. Fix grammar and remove filler words (um, uh, like, you know)
5. Create clear section headers using ## when topic changes
6. Format code examples in ```language blocks
7. Preserve all URLs, product names, and technical terms exactly
8. Create logical paragraph breaks

Video: {title}
Segment {chunk_num} of {total_chunks}

{chunk}

Return ONLY the cleaned markdown, starting immediately with the content:"""

        async with self._semaphore:  # Rate limit concurrent calls
            try:
                self.logger.debug(f"Polishing chunk {chunk_num}/{total_chunks}")

                # Use HTTP API for non-blocking execution
                async with httpx.AsyncClient(timeout=180.0) as client:
                    response = await client.post(
                        f"{self.ollama_host}/api/generate",
                        json={
                            "model": self.model,
                            "prompt": prompt,
                            "stream": False,
                            "options": {
                                "temperature": self.temperature,
                            }
                        }
                    )
                    response.raise_for_status()
                    result = response.json()
                    output = result["response"].strip()

                # Validate output length (shouldn't be drastically shorter)
                if len(output) < len(chunk) * 0.5:
                    self.logger.warning(f"Chunk {chunk_num} output suspiciously short ({len(output)} vs {len(chunk)})")

                return output

            except httpx.TimeoutException:
                self.logger.error(f"Timeout polishing chunk {chunk_num}")
                raise RuntimeError("Ollama request timed out")
            except httpx.HTTPError as e:
                self.logger.error(f"Ollama HTTP request failed: {e}")
                raise RuntimeError(f"Ollama API error: {e}")

    def dedupe_paragraphs(self, text: str) -> str:
        """
        Remove duplicate content using sentence-level deduplication.

        This handles chunk boundaries better than paragraph-level dedup
        by tracking recent sentences and removing overlaps.

        Args:
            text: Text with potential duplicate paragraphs

        Returns:
            Text with duplicates removed
        """
        paragraphs = [p.strip() for p in text.split('\n\n') if p.strip()]

        result = []
        prev_sentences: Set[str] = set()

        for para in paragraphs:
            # Split into sentences
            sentences = re.split(r'(?<=[.!?])\s+', para)
            new_sentences = []

            for sent in sentences:
                sent_clean = sent.strip().lower()
                # Only add if not seen in previous paragraph
                if sent_clean and sent_clean not in prev_sentences:
                    new_sentences.append(sent)

            if new_sentences:
                result.append(' '.join(new_sentences))
                # Update prev_sentences to last 3 sentences for next iteration
                prev_sentences = {s.strip().lower() for s in new_sentences[-3:]}

        removed = len(paragraphs) - len(result)
        if removed > 0:
            self.logger.debug(f"Removed {removed} paragraphs with duplicate content")

        return '\n\n'.join(result)

    def validate_llm_output(self, original: str, polished: str, title: str) -> str:
        """
        Validate LLM output to prevent hallucination/summarization.

        Args:
            original: Original cleaned text
            polished: LLM polished output
            title: Video title

        Returns:
            Validated polished text (or original if validation fails)
        """
        # Check length ratio (polished shouldn't be < 70% of original)
        if len(polished) < len(original) * 0.7:
            self.logger.warning(
                f"LLM output too short ({len(polished)} vs {len(original)}), "
                f"possible summarization - using original"
            )
            return original

        # Check for hallucination markers (meta-commentary)
        hallucination_phrases = [
            "here is the cleaned transcript",
            "here's the cleaned version",
            "i have cleaned",
            "i've cleaned",
            "summary:",
            "this transcript",
        ]

        lower_polished = polished.lower()
        found_markers = [p for p in hallucination_phrases if p in lower_polished]

        if found_markers:
            self.logger.warning(f"LLM added meta-commentary: {found_markers}, stripping...")
            # Try to extract just the content
            lines = polished.split('\n')
            cleaned_lines = [
                l for l in lines
                if not any(p in l.lower() for p in hallucination_phrases)
            ]
            polished = '\n'.join(cleaned_lines)

            # Re-check length after stripping
            if len(polished) < len(original) * 0.7:
                self.logger.warning("After stripping meta-commentary, output too short - using original")
                return original

        return polished

    async def polish(self, cleaned_text: str, title: str) -> str:
        """
        Polish cleaned transcript using Ollama (async, non-blocking).

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
            result = await self.polish_chunk(chunks[0], title, 1, 1)

            # Validate output
            result = self.validate_llm_output(chunks[0], result, title)

            # Ensure title at top
            if not result.lstrip().startswith(f"# {title}"):
                result = f"# {title}\n\n{result}"

            return result

        # Large transcript - chunk, polish in parallel, stitch
        self.logger.info(f"Large transcript, polishing {len(chunks)} chunks in parallel (max {self.max_concurrent} concurrent)")

        # Process chunks in parallel with semaphore limiting
        tasks = [
            self.polish_chunk(chunk, title, i, len(chunks))
            for i, chunk in enumerate(chunks, start=1)
        ]

        try:
            polished_chunks = await asyncio.gather(*tasks)
        except Exception as e:
            self.logger.error(f"Failed to polish chunks: {e}")
            raise

        # Stitch chunks together
        merged = '\n\n'.join(polished_chunks)

        # Deduplicate paragraphs (sentence-level overlap handling)
        result = self.dedupe_paragraphs(merged)

        # Validate overall output
        result = self.validate_llm_output(cleaned_text, result, title)

        # Ensure title at top
        if not result.lstrip().startswith(f"# {title}"):
            result = f"# {title}\n\n{result}"

        self.logger.info("LLM polishing complete")
        return result
