"""
OCR Processor Module
====================

Handles image preprocessing and OCR using Tesseract.
Extracts structured receipt data from OCR text.
"""

import re
import logging
from datetime import datetime
from pathlib import Path
from typing import Dict, Any, List, Optional
from decimal import Decimal

import cv2
import numpy as np
from PIL import Image
import pytesseract
from pdf2image import convert_from_path

logger = logging.getLogger(__name__)

class OCRProcessor:
    """Process images with OCR and extract receipt data"""

    def __init__(self, config):
        self.config = config
        self.tesseract_config = '--oem 3 --psm 6'  # LSTM OCR, assume uniform block of text

    def process_image(self, image_path: Path) -> Dict[str, Any]:
        """
        Process an image with OCR

        Args:
            image_path: Path to image file

        Returns:
            Dictionary with OCR results
        """
        logger.info(f"Processing image: {image_path}")

        # Convert PDF to image if needed
        if image_path.suffix.lower() == '.pdf':
            images = convert_from_path(str(image_path), first_page=1, last_page=1)
            if not images:
                raise ValueError("Could not convert PDF to image")
            img = np.array(images[0])
        else:
            # Load image
            img = cv2.imread(str(image_path))
            if img is None:
                raise ValueError(f"Could not load image: {image_path}")

        # Preprocess image
        preprocessed = self.preprocess_image(img)

        # Run OCR
        text = pytesseract.image_to_string(preprocessed, config=self.tesseract_config)

        # Get detailed OCR data
        data = pytesseract.image_to_data(
            preprocessed,
            config=self.tesseract_config,
            output_type=pytesseract.Output.DICT
        )

        # Calculate average confidence
        confidences = [int(conf) for conf in data['conf'] if conf != '-1']
        avg_confidence = sum(confidences) / len(confidences) / 100 if confidences else 0

        return {
            'text': text,
            'confidence': avg_confidence,
            'detailed_data': data,
            'preprocessed_shape': preprocessed.shape
        }

    def preprocess_image(self, img: np.ndarray) -> np.ndarray:
        """
        Preprocess image for better OCR results

        Steps:
        1. Convert to grayscale
        2. Resize if too small
        3. Denoise
        4. Deskew
        5. Threshold
        6. Enhance contrast

        Args:
            img: Input image

        Returns:
            Preprocessed image
        """
        # Convert to grayscale
        if len(img.shape) == 3:
            gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        else:
            gray = img

        # Resize if image is too small
        height, width = gray.shape
        if height < 1000:
            scale = 1000 / height
            new_width = int(width * scale)
            gray = cv2.resize(gray, (new_width, 1000), interpolation=cv2.INTER_CUBIC)

        # Denoise
        denoised = cv2.fastNlMeansDenoising(gray, None, 10, 7, 21)

        # Deskew
        deskewed = self.deskew_image(denoised)

        # Adaptive threshold
        thresh = cv2.adaptiveThreshold(
            deskewed, 255,
            cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
            cv2.THRESH_BINARY,
            11, 2
        )

        # Enhance contrast
        clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
        enhanced = clahe.apply(thresh)

        return enhanced

    def deskew_image(self, img: np.ndarray) -> np.ndarray:
        """
        Deskew (rotate) image to correct orientation

        Args:
            img: Input grayscale image

        Returns:
            Deskewed image
        """
        # Detect edges
        edges = cv2.Canny(img, 50, 150, apertureSize=3)

        # Detect lines using Hough transform
        lines = cv2.HoughLines(edges, 1, np.pi / 180, 200)

        if lines is None:
            return img

        # Calculate dominant angle
        angles = []
        for rho, theta in lines[:, 0]:
            angle = np.rad2deg(theta) - 90
            angles.append(angle)

        # Get median angle
        median_angle = np.median(angles)

        # Only rotate if angle is significant
        if abs(median_angle) > 0.5:
            # Rotate image
            (h, w) = img.shape
            center = (w // 2, h // 2)
            M = cv2.getRotationMatrix2D(center, median_angle, 1.0)
            rotated = cv2.warpAffine(
                img, M, (w, h),
                flags=cv2.INTER_CUBIC,
                borderMode=cv2.BORDER_REPLICATE
            )
            return rotated

        return img

    def extract_receipt_data(self, ocr_result: Dict[str, Any]) -> Dict[str, Any]:
        """
        Extract structured receipt data from OCR text

        Args:
            ocr_result: OCR result dictionary

        Returns:
            Structured receipt data
        """
        text = ocr_result['text']

        extracted = {
            'confidence': ocr_result['confidence'],
            'date': self.extract_date(text),
            'vendor_raw': self.extract_vendor(text),
            'total': self.extract_total(text),
            'tax': self.extract_tax(text),
            'subtotal': self.extract_subtotal(text),
            'items': self.extract_items(text)
        }

        return extracted

    def extract_date(self, text: str) -> Optional[str]:
        """Extract date from receipt text"""
        # Common date patterns
        patterns = [
            r'(\d{1,2}[/-]\d{1,2}[/-]\d{2,4})',  # MM/DD/YYYY or DD/MM/YYYY
            r'(\d{4}[/-]\d{1,2}[/-]\d{1,2})',  # YYYY-MM-DD
            r'(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+\d{1,2},?\s+\d{4}',  # Month DD, YYYY
            r'\d{1,2}\s+(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+\d{4}',  # DD Month YYYY
        ]

        for pattern in patterns:
            match = re.search(pattern, text, re.IGNORECASE)
            if match:
                date_str = match.group(0)
                # Try to parse and standardize
                try:
                    # Try various date formats
                    for fmt in ['%m/%d/%Y', '%m/%d/%y', '%Y-%m-%d', '%d/%m/%Y', '%B %d, %Y', '%d %B %Y']:
                        try:
                            dt = datetime.strptime(date_str, fmt)
                            return dt.strftime('%Y-%m-%d')
                        except ValueError:
                            continue
                except Exception as e:
                    logger.debug(f"Failed to parse date {date_str}: {e}")

        return None

    def extract_vendor(self, text: str) -> Optional[str]:
        """
        Extract vendor name from receipt

        Usually at the top of the receipt
        """
        lines = text.split('\n')

        # Look at first few non-empty lines
        for line in lines[:5]:
            line = line.strip()
            if len(line) > 3 and not re.match(r'^[\d\s\-/]+$', line):
                # Skip lines that are just dates or numbers
                if not re.search(r'\d{1,2}[/-]\d{1,2}[/-]\d{2,4}', line):
                    return line

        return None

    def extract_total(self, text: str) -> Optional[float]:
        """Extract total amount from receipt"""
        patterns = [
            r'total[:\s]+\$?(\d+\.\d{2})',
            r'amount[:\s]+\$?(\d+\.\d{2})',
            r'balance[:\s]+\$?(\d+\.\d{2})',
        ]

        # Look for patterns
        for pattern in patterns:
            match = re.search(pattern, text, re.IGNORECASE)
            if match:
                try:
                    return float(match.group(1))
                except ValueError:
                    pass

        # Fallback: find largest dollar amount
        amounts = re.findall(r'\$?(\d+\.\d{2})', text)
        if amounts:
            try:
                return max([float(a) for a in amounts])
            except ValueError:
                pass

        return None

    def extract_tax(self, text: str) -> Optional[float]:
        """Extract tax amount from receipt"""
        patterns = [
            r'tax[:\s]+\$?(\d+\.\d{2})',
            r'sales tax[:\s]+\$?(\d+\.\d{2})',
            r'hst[:\s]+\$?(\d+\.\d{2})',
            r'gst[:\s]+\$?(\d+\.\d{2})',
        ]

        for pattern in patterns:
            match = re.search(pattern, text, re.IGNORECASE)
            if match:
                try:
                    return float(match.group(1))
                except ValueError:
                    pass

        return None

    def extract_subtotal(self, text: str) -> Optional[float]:
        """Extract subtotal amount from receipt"""
        patterns = [
            r'subtotal[:\s]+\$?(\d+\.\d{2})',
            r'sub total[:\s]+\$?(\d+\.\d{2})',
            r'sub-total[:\s]+\$?(\d+\.\d{2})',
        ]

        for pattern in patterns:
            match = re.search(pattern, text, re.IGNORECASE)
            if match:
                try:
                    return float(match.group(1))
                except ValueError:
                    pass

        return None

    def extract_items(self, text: str) -> List[Dict[str, Any]]:
        """
        Extract line items from receipt

        This is a basic implementation. LLM normalization will improve accuracy.
        """
        items = []

        # Look for lines with item description and price
        # Pattern: description ... price
        lines = text.split('\n')

        for line in lines:
            # Skip short lines
            if len(line.strip()) < 5:
                continue

            # Look for price at end of line
            price_match = re.search(r'\$?(\d+\.\d{2})\s*$', line)
            if price_match:
                price = float(price_match.group(1))

                # Extract description (everything before price)
                description = line[:price_match.start()].strip()

                # Skip if description looks like a total/subtotal/tax
                skip_keywords = ['total', 'subtotal', 'tax', 'amount', 'balance', 'change']
                if any(keyword in description.lower() for keyword in skip_keywords):
                    continue

                # Look for quantity pattern like "2 @" or "2x"
                quantity = 1.0
                qty_match = re.search(r'(\d+\.?\d*)\s*[@x]', description, re.IGNORECASE)
                if qty_match:
                    quantity = float(qty_match.group(1))
                    # Remove quantity from description
                    description = re.sub(r'\d+\.?\d*\s*[@x]\s*', '', description, flags=re.IGNORECASE)

                items.append({
                    'description': description.strip(),
                    'quantity': quantity,
                    'total_price': price,
                    'unit_price': price / quantity if quantity > 0 else price
                })

        return items
