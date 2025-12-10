"""
Basic transcript cleaner - Fast, non-LLM cleaning.

Features:
- Remove consecutive duplicate lines
- Remove filler words (um, uh, like, etc.)
- Sentence segmentation via spaCy (with regex fallback)
- Paragraph grouping
- Simple keyword-based header detection
"""

import re
import logging
from typing import List

# Try to load spaCy once at module level for performance
try:
    import spacy
    nlp = spacy.load("en_core_web_sm", disable=["ner", "textcat"])
    nlp.max_length = 2000000  # Allow very long texts
    SPACY_AVAILABLE = True
except Exception as e:
    nlp = None
    SPACY_AVAILABLE = False
    logging.warning(f"spaCy not available, using fallback sentence detection: {e}")

# Common filler words to remove
FILLERS = {
    "um", "uh", "you know", "like", "sort of", "kind of",
    "i mean", "right", "okay", "well"
}


class BasicTranscriptCleaner:
    """Fast, deterministic transcript cleaner without LLM."""

    def __init__(self):
        self.logger = logging.getLogger(__name__)
        if SPACY_AVAILABLE:
            self.logger.info("BasicTranscriptCleaner initialized with spaCy")
        else:
            self.logger.info("BasicTranscriptCleaner initialized with regex fallback")

    def dedupe_lines(self, lines: List[str]) -> List[str]:
        """Remove consecutive duplicate lines."""
        deduped = []
        prev = None

        for line in lines:
            s = line.strip()
            if not s:
                continue
            if prev is None or s != prev:
                deduped.append(s)
                prev = s

        return deduped

    def remove_fillers(self, text: str) -> str:
        """Remove filler words and clean up spacing."""
        # Build regex pattern for filler words
        pattern = r'\b(' + '|'.join(re.escape(w) for w in FILLERS) + r')\b[\s,]*'
        text = re.sub(pattern, ' ', text, flags=re.IGNORECASE)

        # Remove multiple spaces
        text = re.sub(r'\s+', ' ', text)

        return text.strip()

    def split_into_sentences(self, text: str) -> List[str]:
        """Split text into sentences using spaCy or regex fallback."""
        if SPACY_AVAILABLE and nlp:
            try:
                doc = nlp(text)
                sentences = [sent.text.strip() for sent in doc.sents if sent.text.strip()]
                return sentences
            except Exception as e:
                self.logger.warning(f"spaCy sentence detection failed, using fallback: {e}")

        # Fallback: simple regex-based sentence splitting
        sentences = re.split(r'(?<=[.!?])\s+', text)
        return [s.strip() for s in sentences if s.strip()]

    def add_headers(self, paragraphs: List[str]) -> List[str]:
        """Add markdown headers based on keyword detection."""
        # Header detection patterns (pattern, markdown prefix)
        header_patterns = [
            (r'^(number \w+|first|second|third|fourth|fifth)', '## '),
            (r'^(next|another|finally|in conclusion|summary)', '## '),
            (r'^(let\'s|now|so)', '### ')
        ]

        formatted = []
        for para in paragraphs:
            prefix = ""
            lower = para.lower()[:80]  # Check first 80 chars

            for pattern, hdr in header_patterns:
                if re.search(pattern, lower):
                    prefix = hdr
                    break

            if prefix:
                formatted.append(f"{prefix}{para}")
            else:
                formatted.append(para)

        return formatted

    def clean(self, raw_text: str, title: str, sentences_per_para: int = 4) -> str:
        """
        Clean a raw YouTube transcript.

        Args:
            raw_text: Raw transcript text with duplicates and poor formatting
            title: Video title for the markdown header
            sentences_per_para: Number of sentences to group per paragraph

        Returns:
            Cleaned markdown text
        """
        self.logger.info(f"Starting basic cleaning for: {title}")

        # 1. Deduplicate consecutive lines
        lines = raw_text.splitlines()
        lines = self.dedupe_lines(lines)
        text = ' '.join(lines)

        # 2. Remove filler words
        text = self.remove_fillers(text)

        # 3. Split into sentences
        sentences = self.split_into_sentences(text)
        self.logger.debug(f"Split into {len(sentences)} sentences")

        # 4. Group into paragraphs
        paragraphs = []
        for i in range(0, len(sentences), sentences_per_para):
            para = ' '.join(sentences[i:i+sentences_per_para])
            paragraphs.append(para)

        # 5. Add headers
        formatted = self.add_headers(paragraphs)

        # 6. Assemble final markdown
        output = [f"# {title}\n"]
        output.extend(formatted)

        result = '\n\n'.join(output)
        self.logger.info(f"Basic cleaning complete: {len(paragraphs)} paragraphs")

        return result
