"""
Forms and configuration API endpoints
"""
from typing import Dict, Any
from fastapi import APIRouter, HTTPException
import yaml
import os

router = APIRouter(prefix="/api/forms", tags=["forms"])


@router.get("/bathroom")
async def get_bathroom_form() -> Dict[str, Any]:
    """
    Get the bathroom wizard question tree configuration.

    This serves the parsed YAML config so the frontend can:
    - Render the wizard steps dynamically
    - Display educational content
    - Show conditional questions
    - Load image URLs

    Returns:
        Parsed question tree configuration
    """
    config_path = os.path.join(
        os.path.dirname(os.path.dirname(os.path.dirname(__file__))),
        "config",
        "bathroom_questions.yaml"
    )

    try:
        with open(config_path, 'r') as f:
            config = yaml.safe_load(f)
        return config
    except FileNotFoundError:
        raise HTTPException(
            status_code=500,
            detail="Question tree configuration not found"
        )
    except yaml.YAMLError as e:
        raise HTTPException(
            status_code=500,
            detail=f"Error parsing configuration: {str(e)}"
        )


@router.get("/bathroom/version")
async def get_form_version() -> Dict[str, str]:
    """
    Get the version of the bathroom form configuration.
    Useful for frontend caching and tracking which version was used.
    """
    config_path = os.path.join(
        os.path.dirname(os.path.dirname(os.path.dirname(__file__))),
        "config",
        "bathroom_questions.yaml"
    )

    try:
        with open(config_path, 'r') as f:
            config = yaml.safe_load(f)
        return {
            "version": config.get("version", "unknown"),
            "project_type": config.get("project_type", "bathroom")
        }
    except FileNotFoundError:
        raise HTTPException(
            status_code=500,
            detail="Question tree configuration not found"
        )
