"""
PDF Report Generation Service

Uses WeasyPrint to generate professional PDF reports from HTML templates.
"""
import os
from datetime import datetime
from pathlib import Path
from typing import Dict, Any, Optional
from uuid import UUID

from jinja2 import Environment, FileSystemLoader
from weasyprint import HTML, CSS
import asyncpg


class PDFService:
    """Service for generating PDF reports"""

    def __init__(self, templates_dir: Optional[str] = None, output_dir: Optional[str] = None):
        """
        Initialize PDF service.

        Args:
            templates_dir: Path to Jinja2 templates (defaults to app/templates)
            output_dir: Path to save PDFs (defaults to /app/pdfs)
        """
        # Set up template directory
        if templates_dir is None:
            app_dir = Path(__file__).parent.parent
            templates_dir = app_dir / "templates"

        self.templates_dir = Path(templates_dir)

        # Set up Jinja2 environment
        self.jinja_env = Environment(
            loader=FileSystemLoader(str(self.templates_dir)),
            autoescape=True
        )

        # Set up output directory
        if output_dir is None:
            output_dir = Path("/app/pdfs")
        else:
            output_dir = Path(output_dir)

        self.output_dir = output_dir
        self.output_dir.mkdir(parents=True, exist_ok=True)

    async def generate_bathroom_report(
        self,
        conn: asyncpg.Connection,
        project_id: UUID
    ) -> Dict[str, str]:
        """
        Generate a bathroom remodel report PDF.

        Args:
            conn: Database connection
            project_id: UUID of the project

        Returns:
            Dictionary with pdf_path and pdf_url

        Raises:
            ValueError: If project not found or estimate not calculated
        """
        # Fetch project data
        project_data = await self._fetch_project_data(conn, project_id)

        if not project_data:
            raise ValueError(f"Project {project_id} not found")

        if not project_data.get('estimated_total_min'):
            raise ValueError("Estimate not yet calculated for this project")

        # Fetch client data
        client_data = await conn.fetchrow(
            "SELECT name, email, phone FROM clients WHERE id = $1",
            project_data['client_id']
        )

        # Fetch answers
        answers = await self._fetch_answers(conn, project_id)

        # Fetch cost modules
        modules = await self._fetch_cost_modules(conn, project_id)

        # Prepare template context
        context = self._prepare_context(project_data, client_data, answers, modules)

        # Render HTML
        html_content = self._render_template('bathroom_report.html', context)

        # Generate PDF
        pdf_filename = f"bathroom_remodel_{project_id}_{datetime.now().strftime('%Y%m%d')}.pdf"
        pdf_path = self.output_dir / pdf_filename

        HTML(string=html_content).write_pdf(str(pdf_path))

        # Update project record with PDF info
        await conn.execute(
            "UPDATE projects SET pdf_generated_at = NOW(), pdf_url = $2 WHERE id = $1",
            project_id,
            f"/pdfs/{pdf_filename}"
        )

        return {
            "pdf_path": str(pdf_path),
            "pdf_url": f"/pdfs/{pdf_filename}",
            "filename": pdf_filename
        }

    async def _fetch_project_data(
        self,
        conn: asyncpg.Connection,
        project_id: UUID
    ) -> Optional[Dict[str, Any]]:
        """Fetch project data from database"""
        row = await conn.fetchrow(
            """
            SELECT
                id, client_id, project_type, bathroom_type,
                size_sqft_band, budget_band, timeline_readiness,
                estimated_total_min, estimated_total_max,
                estimated_labor_min, estimated_labor_max,
                estimated_materials_min, estimated_materials_max,
                complexity_score, complexity_band,
                created_at
            FROM projects
            WHERE id = $1
            """,
            project_id
        )

        return dict(row) if row else None

    async def _fetch_answers(
        self,
        conn: asyncpg.Connection,
        project_id: UUID
    ) -> Dict[str, Any]:
        """Fetch all project answers"""
        rows = await conn.fetch(
            "SELECT question_key, value_json FROM project_answers WHERE project_id = $1",
            project_id
        )

        return {row['question_key']: row['value_json'] for row in rows}

    async def _fetch_cost_modules(
        self,
        conn: asyncpg.Connection,
        project_id: UUID
    ) -> list:
        """Fetch cost breakdown modules"""
        rows = await conn.fetch(
            """
            SELECT
                module_key, label,
                labor_min, labor_max,
                materials_min, materials_max,
                total_min, total_max
            FROM project_cost_items
            WHERE project_id = $1
            ORDER BY total_max DESC
            """,
            project_id
        )

        return [dict(row) for row in rows]

    def _prepare_context(
        self,
        project_data: Dict[str, Any],
        client_data: Dict[str, Any],
        answers: Dict[str, Any],
        modules: list
    ) -> Dict[str, Any]:
        """Prepare template context from data"""

        # Build scope description
        goals = answers.get('goals', [])
        scope_parts = []

        if 'convert_tub_to_shower' in goals:
            scope_parts.append("converting the tub to a shower")
        if 'replace_wall_tile' in goals:
            scope_parts.append("replacing wall tile")
        if 'replace_flooring' in goals:
            scope_parts.append("new flooring")
        if 'update_fixtures' in goals:
            scope_parts.append("updating fixtures")

        bathroom_type = project_data.get('bathroom_type', 'bathroom')
        scope_text = f"This {bathroom_type} remodel includes {', '.join(scope_parts) if scope_parts else 'various improvements'}."

        # Build cost drivers list
        cost_drivers = []

        # Top 3 modules by cost
        for module in modules[:3]:
            cost_drivers.append(
                f"{module['label']}: ${module['total_min']:,.0f}-${module['total_max']:,.0f}"
            )

        # Specific expensive choices
        tile_level = answers.get('tile_level')
        if tile_level == 'natural_stone':
            cost_drivers.append("Natural stone tile adds significant material and labor costs")

        extras = answers.get('extras', [])
        if 'frameless_glass' in extras:
            cost_drivers.append("Frameless glass shower doors are custom-fabricated")
        if 'heated_floor' in extras:
            cost_drivers.append("Heated floor systems require electrical work and specialized installation")

        plumbing_changes = answers.get('plumbing_changes')
        if plumbing_changes in ['moving_toilet', 'multiple_fixtures_moved']:
            cost_drivers.append("Plumbing relocation is labor-intensive and requires permits")

        # Contractor questions
        contractor_questions = [
            "Are you licensed and insured for bathroom remodels in this area?",
            "Can you provide references from recent similar projects?",
            "What is your estimated timeline for this scope of work?",
            "How do you handle change orders and unexpected issues?",
            "What warranties do you offer on labor and materials?",
            "Will you pull all necessary permits, or is that my responsibility?",
            "What is your payment schedule?",
            "Do you carry workers' compensation insurance?",
            "Will you be doing the work yourself or using subcontractors?",
            "How do you handle cleanup and debris removal?"
        ]

        # Build complete context
        context = {
            # Client info
            'client_name': client_data.get('name', 'Valued Client'),
            'client_email': client_data.get('email', ''),
            'client_phone': client_data.get('phone', ''),

            # Project details
            'bathroom_type': project_data.get('bathroom_type', 'bathroom'),
            'complexity_band': project_data.get('complexity_band', 'medium'),
            'timeline_readiness': project_data.get('timeline_readiness', 'planning'),

            # Scope
            'scope_text': scope_text,
            'goals': [g.replace('_', ' ').title() for g in goals],

            # Costs
            'cost_total_min': float(project_data['estimated_total_min']),
            'cost_total_max': float(project_data['estimated_total_max']),
            'cost_labor_min': float(project_data['estimated_labor_min']),
            'cost_labor_max': float(project_data['estimated_labor_max']),
            'cost_materials_min': float(project_data['estimated_materials_min']),
            'cost_materials_max': float(project_data['estimated_materials_max']),

            # Modules
            'modules': modules,

            # Education
            'cost_drivers': cost_drivers,
            'contractor_questions': contractor_questions,

            # Metadata
            'generated_date': datetime.now().strftime('%B %d, %Y'),
            'current_year': datetime.now().year,
        }

        return context

    def _render_template(self, template_name: str, context: Dict[str, Any]) -> str:
        """Render Jinja2 template with context"""
        template = self.jinja_env.get_template(template_name)
        return template.render(**context)


# Singleton instance (can be configured at startup)
_pdf_service: Optional[PDFService] = None


def get_pdf_service(
    templates_dir: Optional[str] = None,
    output_dir: Optional[str] = None
) -> PDFService:
    """
    Get or create the PDF service singleton.

    Args:
        templates_dir: Path to templates (only used on first call)
        output_dir: Path to save PDFs (only used on first call)

    Returns:
        PDFService instance
    """
    global _pdf_service

    if _pdf_service is None:
        _pdf_service = PDFService(
            templates_dir=templates_dir,
            output_dir=output_dir
        )

    return _pdf_service
