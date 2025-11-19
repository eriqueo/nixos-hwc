"""
LLM Normalizer Module
=====================

Uses local Ollama LLM to:
- Normalize vendor names
- Categorize expenses
- Clean up OCR errors
- Extract better structured data
"""

import json
import logging
from typing import Dict, Any, Optional

import httpx

logger = logging.getLogger(__name__)

class LLMNormalizer:
    """Normalize receipt data using LLM"""

    def __init__(self, config):
        self.config = config
        self.ollama_url = config.ollama_url
        self.model = config.ollama_model
        self.timeout = 30.0

    def health_check(self) -> Dict[str, str]:
        """Check if Ollama is available"""
        try:
            response = httpx.get(f"{self.ollama_url}/api/tags", timeout=5.0)
            if response.status_code == 200:
                return {"status": "operational", "url": self.ollama_url}
            else:
                return {"status": "error", "message": f"HTTP {response.status_code}"}
        except Exception as e:
            return {"status": "unreachable", "error": str(e)}

    def normalize_receipt(self, extracted_data: Dict[str, Any], raw_text: str) -> Dict[str, Any]:
        """
        Use LLM to normalize and enhance receipt data

        Args:
            extracted_data: Data from OCR extraction
            raw_text: Raw OCR text

        Returns:
            Enhanced/normalized data
        """
        logger.info("Normalizing receipt data with LLM")

        # Build prompt
        prompt = self._build_normalization_prompt(extracted_data, raw_text)

        # Call LLM
        try:
            response = self._call_ollama(prompt)

            # Parse response
            normalized = self._parse_llm_response(response)

            return normalized

        except Exception as e:
            logger.error(f"LLM normalization failed: {e}")
            raise

    def _build_normalization_prompt(self, extracted_data: Dict[str, Any], raw_text: str) -> str:
        """Build prompt for LLM normalization"""

        prompt = f"""You are a receipt data extraction assistant. Analyze the following receipt OCR data and improve it.

Raw OCR Text:
```
{raw_text[:1000]}  # Limit to first 1000 chars
```

Extracted Data (from OCR):
```json
{json.dumps(extracted_data, indent=2, default=str)}
```

Your task:
1. Normalize the vendor name (e.g., "WALMART #1234" -> "Walmart", "HOME DEPOT 5678" -> "Home Depot")
2. Categorize the expense (Materials, Labor, Tools, Office Supplies, Fuel, Permits & Fees, Subcontractors)
3. Improve item descriptions if provided
4. Verify the total, tax, and subtotal make sense
5. Fix any obvious OCR errors

Return ONLY a JSON object with this structure:
{{
  "vendor_normalized": "normalized vendor name",
  "category": "expense category",
  "items_improved": [
    {{
      "description": "cleaned description",
      "quantity": 1.0,
      "unit_price": 10.00,
      "total_price": 10.00
    }}
  ],
  "vendor_category": "hardware_store|lumber_yard|home_improvement|grocery|gas_station|office_supply|other",
  "confidence_notes": "any concerns or low-confidence areas"
}}

Be concise. Return only valid JSON.
"""

        return prompt

    def _call_ollama(self, prompt: str) -> str:
        """
        Call Ollama API

        Args:
            prompt: Prompt text

        Returns:
            LLM response text
        """
        payload = {
            "model": self.model,
            "prompt": prompt,
            "stream": False,
            "options": {
                "temperature": 0.1,  # Low temperature for factual extraction
                "top_p": 0.9,
            }
        }

        try:
            with httpx.Client(timeout=self.timeout) as client:
                response = client.post(
                    f"{self.ollama_url}/api/generate",
                    json=payload
                )

                response.raise_for_status()

                result = response.json()
                return result.get('response', '')

        except httpx.TimeoutException:
            raise Exception(f"LLM request timed out after {self.timeout}s")
        except httpx.HTTPStatusError as e:
            raise Exception(f"LLM HTTP error: {e.response.status_code}")
        except Exception as e:
            raise Exception(f"LLM request failed: {e}")

    def _parse_llm_response(self, response: str) -> Dict[str, Any]:
        """
        Parse LLM JSON response

        Args:
            response: Raw LLM response

        Returns:
            Parsed data dictionary
        """
        # Try to extract JSON from response
        # Sometimes LLM includes markdown code blocks

        # Remove markdown code blocks if present
        if '```json' in response:
            response = response.split('```json')[1].split('```')[0]
        elif '```' in response:
            response = response.split('```')[1].split('```')[0]

        # Parse JSON
        try:
            data = json.loads(response.strip())

            # Extract relevant fields
            normalized = {}

            if 'vendor_normalized' in data:
                normalized['vendor_normalized'] = data['vendor_normalized']

            if 'category' in data:
                normalized['category'] = data['category']

            if 'vendor_category' in data:
                if 'llm_metadata' not in normalized:
                    normalized['llm_metadata'] = {}
                normalized['llm_metadata']['vendor_category'] = data['vendor_category']

            if 'confidence_notes' in data:
                if 'llm_metadata' not in normalized:
                    normalized['llm_metadata'] = {}
                normalized['llm_metadata']['notes'] = data['confidence_notes']

            if 'items_improved' in data:
                normalized['items'] = data['items_improved']

            return normalized

        except json.JSONDecodeError as e:
            logger.warning(f"Failed to parse LLM JSON response: {e}")
            logger.debug(f"Response was: {response[:200]}")

            # Return empty dict if parsing fails
            return {}

    def categorize_vendor(self, vendor_name: str) -> str:
        """
        Categorize a vendor using LLM

        Args:
            vendor_name: Vendor name

        Returns:
            Category string
        """
        prompt = f"""Categorize this vendor for a remodeling/construction business.

Vendor: {vendor_name}

Categories:
- Materials (lumber, hardware, building materials)
- Tools (power tools, hand tools, equipment rental)
- Office Supplies
- Fuel (gas stations)
- Permits & Fees
- Subcontractors
- Other

Return ONLY the category name, nothing else."""

        try:
            response = self._call_ollama(prompt)
            category = response.strip()

            # Validate category
            valid_categories = ['Materials', 'Tools', 'Office Supplies', 'Fuel', 'Permits & Fees', 'Subcontractors', 'Other']
            if category in valid_categories:
                return category
            else:
                return 'Other'

        except Exception as e:
            logger.error(f"Failed to categorize vendor: {e}")
            return 'Other'
