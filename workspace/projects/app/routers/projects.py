"""
Projects API endpoints
"""
from uuid import UUID
from typing import Dict, Any
from fastapi import APIRouter, Depends, HTTPException
import asyncpg

from app.database import get_db_connection
from app.models import (
    ProjectCreate,
    ProjectResponse,
    EstimateRequest,
    EstimateResult,
    BathroomAnswers
)
from app.engines import BathroomCostEngine
from app.services.pdf_service import get_pdf_service

router = APIRouter(prefix="/api", tags=["projects"])


@router.post("/projects", response_model=ProjectResponse)
async def create_project(
    project_data: ProjectCreate,
    conn: asyncpg.Connection = Depends(get_db_connection)
):
    """
    Create a new project and client.

    Request body:
    ```json
    {
      "client": {
        "name": "Jane Doe",
        "email": "jane@example.com",
        "phone": "406-555-1234"
      },
      "project_type": "bathroom"
    }
    ```

    Returns:
        project_id and client_id
    """
    # Insert client
    client_query = """
        INSERT INTO clients (name, email, phone, lead_source)
        VALUES ($1, $2, $3, 'website_tool')
        RETURNING id
    """
    client_id = await conn.fetchval(
        client_query,
        project_data.client.name,
        project_data.client.email,
        project_data.client.phone
    )

    # Insert project
    project_query = """
        INSERT INTO projects (client_id, project_type)
        VALUES ($1, $2)
        RETURNING id
    """
    project_id = await conn.fetchval(
        project_query,
        client_id,
        project_data.project_type
    )

    return ProjectResponse(project_id=project_id, client_id=client_id)


@router.post("/projects/{project_id}/estimate", response_model=EstimateResult)
async def calculate_estimate(
    project_id: UUID,
    request: EstimateRequest,
    conn: asyncpg.Connection = Depends(get_db_connection)
):
    """
    Calculate cost estimate for a bathroom project.

    This endpoint:
    1. Stores the user's answers
    2. Runs the cost engine
    3. Saves cost results to the database
    4. Returns the complete estimate

    Request body contains all wizard answers - see BathroomAnswers model.

    Returns:
        Complete estimate with cost breakdown, modules, and education
    """
    answers = request.answers

    # Verify project exists
    project = await conn.fetchrow(
        "SELECT * FROM projects WHERE id = $1",
        project_id
    )

    if not project:
        raise HTTPException(status_code=404, detail="Project not found")

    # Store answers in project_answers table
    await _store_answers(conn, project_id, answers)

    # Update project with core fields
    await _update_project_fields(conn, project_id, answers)

    # Run cost engine
    engine = BathroomCostEngine(conn)
    result = await engine.calculate(project_id, answers)

    # Store cost results
    await _store_cost_results(conn, project_id, result)

    return result


async def _store_answers(
    conn: asyncpg.Connection,
    project_id: UUID,
    answers: BathroomAnswers
):
    """Store all answers as key-value pairs"""
    answers_dict = answers.model_dump()

    # Delete existing answers (for re-submission)
    await conn.execute(
        "DELETE FROM project_answers WHERE project_id = $1",
        project_id
    )

    # Insert new answers
    insert_query = """
        INSERT INTO project_answers (project_id, question_key, value_json)
        VALUES ($1, $2, $3)
    """

    for key, value in answers_dict.items():
        # Convert to JSON-compatible format
        if value is not None:
            await conn.execute(insert_query, project_id, key, value)


async def _update_project_fields(
    conn: asyncpg.Connection,
    project_id: UUID,
    answers: BathroomAnswers
):
    """Update project table with core answer fields"""
    query = """
        UPDATE projects
        SET
            bathroom_type = $2,
            size_sqft_band = $3,
            budget_band = $4,
            timeline_readiness = $5
        WHERE id = $1
    """

    await conn.execute(
        query,
        project_id,
        answers.bathroom_type,
        answers.size_sqft_band,
        answers.budget_band,
        answers.timeline_readiness
    )


async def _store_cost_results(
    conn: asyncpg.Connection,
    project_id: UUID,
    result: EstimateResult
):
    """Store cost calculation results"""
    # Update project totals
    update_project_query = """
        UPDATE projects
        SET
            estimated_total_min = $2,
            estimated_total_max = $3,
            estimated_labor_min = $4,
            estimated_labor_max = $5,
            estimated_materials_min = $6,
            estimated_materials_max = $7,
            complexity_score = $8,
            complexity_band = $9
        WHERE id = $1
    """

    await conn.execute(
        update_project_query,
        project_id,
        result.cost.total_min,
        result.cost.total_max,
        result.cost.labor_min,
        result.cost.labor_max,
        result.cost.materials_min,
        result.cost.materials_max,
        result.summary.complexity_score,
        result.summary.complexity_band
    )

    # Delete existing cost items (for re-calculation)
    await conn.execute(
        "DELETE FROM project_cost_items WHERE project_id = $1",
        project_id
    )

    # Insert cost modules
    insert_module_query = """
        INSERT INTO project_cost_items (
            project_id, module_key, label,
            labor_min, labor_max,
            materials_min, materials_max,
            total_min, total_max
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
    """

    for module in result.modules:
        await conn.execute(
            insert_module_query,
            project_id,
            module.module_key,
            module.label,
            module.labor_min or 0,
            module.labor_max or 0,
            module.materials_min or 0,
            module.materials_max or 0,
            module.total_min,
            module.total_max
        )


@router.get("/projects/{project_id}")
async def get_project(
    project_id: UUID,
    conn: asyncpg.Connection = Depends(get_db_connection)
):
    """Get project details"""
    project = await conn.fetchrow(
        "SELECT * FROM projects WHERE id = $1",
        project_id
    )

    if not project:
        raise HTTPException(status_code=404, detail="Project not found")

    return dict(project)


@router.get("/projects/{project_id}/answers")
async def get_project_answers(
    project_id: UUID,
    conn: asyncpg.Connection = Depends(get_db_connection)
) -> Dict[str, Any]:
    """
    Get all saved answers for a project.

    Useful for:
    - Pre-filling the wizard when user returns
    - Showing what they selected previously
    - Allowing edits to submitted projects

    Returns:
        Dictionary of question_key: value pairs
    """
    # Verify project exists
    project = await conn.fetchrow(
        "SELECT id FROM projects WHERE id = $1",
        project_id
    )

    if not project:
        raise HTTPException(status_code=404, detail="Project not found")

    # Fetch all answers
    answers_rows = await conn.fetch(
        "SELECT question_key, value_json FROM project_answers WHERE project_id = $1",
        project_id
    )

    # Convert to dictionary
    answers = {row['question_key']: row['value_json'] for row in answers_rows}

    return answers


@router.put("/projects/{project_id}/answers")
async def update_project_answers(
    project_id: UUID,
    answers: Dict[str, Any],
    conn: asyncpg.Connection = Depends(get_db_connection)
):
    """
    Update answers for a project (incremental or full).

    This allows:
    - Saving progress as user goes through wizard
    - Editing individual answers without re-submitting everything
    - "Save for later" functionality

    Only provided keys will be updated/inserted. Existing answers not
    mentioned will be preserved.

    Request body:
    ```json
    {
      "bathroom_type": "primary",
      "goals": ["convert_tub_to_shower"],
      "tile_level": "porcelain"
    }
    ```

    Returns:
        Updated answers count
    """
    # Verify project exists
    project = await conn.fetchrow(
        "SELECT id FROM projects WHERE id = $1",
        project_id
    )

    if not project:
        raise HTTPException(status_code=404, detail="Project not found")

    # Upsert each answer (insert or update)
    upsert_query = """
        INSERT INTO project_answers (project_id, question_key, value_json)
        VALUES ($1, $2, $3)
        ON CONFLICT (project_id, question_key)
        DO UPDATE SET value_json = EXCLUDED.value_json
    """

    count = 0
    for key, value in answers.items():
        if value is not None:  # Skip null values
            await conn.execute(upsert_query, project_id, key, value)
            count += 1

    return {"updated": count, "project_id": str(project_id)}


@router.post("/projects/{project_id}/report")
async def generate_report(
    project_id: UUID,
    conn: asyncpg.Connection = Depends(get_db_connection)
):
    """
    Generate PDF report for a project.

    This endpoint:
    1. Fetches project data, answers, and cost results
    2. Renders a professional HTML template
    3. Converts to PDF with WeasyPrint
    4. Saves to persistent storage
    5. Returns download URL

    Returns:
        JSON with pdf_url and filename for download
    """
    pdf_service = get_pdf_service()

    try:
        result = await pdf_service.generate_bathroom_report(conn, project_id)

        return {
            "project_id": str(project_id),
            "status": "success",
            "pdf_url": result['pdf_url'],
            "filename": result['filename'],
            "message": "PDF report generated successfully"
        }
    except ValueError as e:
        # Handle expected errors (project not found, estimate not calculated)
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        # Handle unexpected errors
        import traceback
        traceback.print_exc()
        raise HTTPException(
            status_code=500,
            detail=f"Failed to generate PDF: {str(e)}"
        )
