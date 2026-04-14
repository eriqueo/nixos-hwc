"""Main CLI entry point for estimate automation system."""

import typer
from rich.console import Console
from rich.table import Table

from src.config.database import init_db

app = typer.Typer(
    name="estimate",
    help="Estimate Automation System for Remodeling Business",
    add_completion=False,
)
console = Console()


@app.command()
def init() -> None:
    """Initialize the database and create tables."""
    try:
        console.print("[bold blue]Initializing database...[/bold blue]")
        init_db()
        console.print("[bold green]✓ Database initialized successfully![/bold green]")
    except Exception as e:
        console.print(f"[bold red]✗ Error: {e}[/bold red]")
        raise typer.Exit(code=1)


@app.command()
def version() -> None:
    """Show version information."""
    console.print("[bold]Estimate Automation System[/bold]")
    console.print("Version: 0.1.0")


# Materials commands
materials_app = typer.Typer(help="Manage materials")
app.add_typer(materials_app, name="materials")


@materials_app.command("list")
def list_materials(
    category: str = typer.Option(None, "--category", "-c", help="Filter by category"),
    active: bool = typer.Option(True, "--active/--all", help="Show only active materials"),
) -> None:
    """List all materials."""
    console.print("[yellow]Materials list (to be implemented)[/yellow]")


@materials_app.command("add")
def add_material() -> None:
    """Add a new material interactively."""
    console.print("[yellow]Add material (to be implemented)[/yellow]")


# Labor commands
labor_app = typer.Typer(help="Manage labor categories")
app.add_typer(labor_app, name="labor")


@labor_app.command("list")
def list_labor(
    trade: str = typer.Option(None, "--trade", "-t", help="Filter by trade"),
) -> None:
    """List all labor categories."""
    console.print("[yellow]Labor categories list (to be implemented)[/yellow]")


@labor_app.command("add")
def add_labor() -> None:
    """Add a new labor category interactively."""
    console.print("[yellow]Add labor category (to be implemented)[/yellow]")


# Project/Estimate commands
estimate_app = typer.Typer(help="Create and manage estimates")
app.add_typer(estimate_app, name="estimate")


@estimate_app.command("create")
def create_estimate(
    job_type: str = typer.Argument(..., help="Type of job (bathroom, deck, siding)"),
    client: str = typer.Option(..., "--client", "-c", help="Client name"),
) -> None:
    """Create a new estimate."""
    console.print(f"[yellow]Creating {job_type} estimate for {client} (to be implemented)[/yellow]")


@estimate_app.command("list")
def list_estimates() -> None:
    """List all estimates."""
    console.print("[yellow]Estimates list (to be implemented)[/yellow]")


@estimate_app.command("export")
def export_estimate(
    project_id: int = typer.Argument(..., help="Project ID to export"),
    format: str = typer.Option("jobtread", "--format", "-f", help="Export format"),
    output: str = typer.Option("./exports", "--output", "-o", help="Output directory"),
) -> None:
    """Export estimate to CSV."""
    console.print(
        f"[yellow]Exporting project {project_id} to {format} format (to be implemented)[/yellow]"
    )


# Data import commands
import_app = typer.Typer(help="Import data from CSV files")
app.add_typer(import_app, name="import")


@import_app.command("materials")
def import_materials(
    file: str = typer.Argument(..., help="Path to materials CSV file"),
) -> None:
    """Import materials from CSV file."""
    console.print(f"[yellow]Importing materials from {file} (to be implemented)[/yellow]")


@import_app.command("labor")
def import_labor(
    file: str = typer.Argument(..., help="Path to labor CSV file"),
) -> None:
    """Import labor categories from CSV file."""
    console.print(f"[yellow]Importing labor from {file} (to be implemented)[/yellow]")


if __name__ == "__main__":
    app()
