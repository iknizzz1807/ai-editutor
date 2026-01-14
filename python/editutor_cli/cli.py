"""
EduTutor CLI - Main entry point

Commands:
- index: Index a codebase for semantic search
- query: Search the indexed codebase
- status: Show indexing status
- clear: Clear the index
"""

import json
import sys
from pathlib import Path
from typing import Optional

import click
from rich.console import Console
from rich.table import Table
from rich.progress import Progress, SpinnerColumn, TextColumn

from editutor_cli import __version__
from editutor_cli.indexer import Indexer
from editutor_cli.search import Searcher

console = Console()


def get_default_db_path() -> Path:
    """Get default database path."""
    return Path.home() / ".editutor" / "vectors"


@click.group()
@click.version_option(version=__version__, prog_name="editutor-cli")
def main():
    """EduTutor CLI - RAG system for AI EduTutor.

    Index your codebase and perform semantic search to enhance
    AI EduTutor's understanding of your project.
    """
    pass


@main.command()
@click.argument("path", type=click.Path(exists=True, file_okay=False, dir_okay=True))
@click.option("--db-path", type=click.Path(), default=None, help="Database path")
@click.option("--force", is_flag=True, help="Force re-index all files")
@click.option("--exclude", multiple=True, help="Patterns to exclude (e.g., node_modules)")
@click.option("--include", multiple=True, help="File patterns to include (e.g., *.py)")
def index(
    path: str,
    db_path: Optional[str],
    force: bool,
    exclude: tuple,
    include: tuple,
):
    """Index a codebase for semantic search.

    PATH: Directory to index

    Examples:
        editutor-cli index /path/to/project
        editutor-cli index . --exclude node_modules --exclude .git
        editutor-cli index . --include "*.py" --include "*.js"
    """
    project_path = Path(path).resolve()
    db = Path(db_path) if db_path else get_default_db_path()

    console.print(f"[bold blue]Indexing:[/] {project_path}")
    console.print(f"[bold blue]Database:[/] {db}")

    # Default excludes
    default_excludes = [
        "node_modules", ".git", "__pycache__", ".venv", "venv",
        "dist", "build", ".next", ".nuxt", "target", ".idea",
        "*.min.js", "*.min.css", "*.map", "*.lock",
    ]
    all_excludes = list(exclude) + default_excludes

    try:
        indexer = Indexer(db_path=db)

        with Progress(
            SpinnerColumn(),
            TextColumn("[progress.description]{task.description}"),
            console=console,
        ) as progress:
            task = progress.add_task("Scanning files...", total=None)

            stats = indexer.index_directory(
                project_path,
                force=force,
                exclude_patterns=all_excludes,
                include_patterns=list(include) if include else None,
                progress_callback=lambda msg: progress.update(task, description=msg),
            )

        # Show results
        table = Table(title="Indexing Complete")
        table.add_column("Metric", style="cyan")
        table.add_column("Value", style="green")

        table.add_row("Files processed", str(stats.get("files_processed", 0)))
        table.add_row("Chunks created", str(stats.get("chunks_created", 0)))
        table.add_row("Files skipped", str(stats.get("files_skipped", 0)))
        table.add_row("Errors", str(stats.get("errors", 0)))

        console.print(table)

    except Exception as e:
        console.print(f"[bold red]Error:[/] {e}")
        sys.exit(1)


@main.command()
@click.argument("query")
@click.option("--db-path", type=click.Path(), default=None, help="Database path")
@click.option("--top-k", default=5, help="Number of results to return")
@click.option("--json", "as_json", is_flag=True, help="Output as JSON")
@click.option("--hybrid", is_flag=True, help="Use hybrid search (BM25 + vector)")
def query(
    query: str,
    db_path: Optional[str],
    top_k: int,
    as_json: bool,
    hybrid: bool,
):
    """Search the indexed codebase.

    QUERY: Natural language query

    Examples:
        editutor-cli query "How does authentication work?"
        editutor-cli query "database connection" --top-k 10
        editutor-cli query "error handling" --json
    """
    db = Path(db_path) if db_path else get_default_db_path()

    if not db.exists():
        console.print("[bold red]Error:[/] No index found. Run 'editutor-cli index' first.")
        sys.exit(1)

    try:
        searcher = Searcher(db_path=db)

        with Progress(
            SpinnerColumn(),
            TextColumn("[progress.description]{task.description}"),
            console=console,
            transient=True,
        ) as progress:
            progress.add_task("Searching...", total=None)
            results = searcher.search(query, top_k=top_k, hybrid=hybrid)

        if as_json:
            # Output JSON for Neovim integration
            output = {
                "query": query,
                "results": [
                    {
                        "filepath": r["filepath"],
                        "chunk": r["chunk"],
                        "score": r["score"],
                        "start_line": r.get("start_line"),
                        "end_line": r.get("end_line"),
                    }
                    for r in results
                ],
            }
            print(json.dumps(output))
        else:
            # Pretty output for terminal
            if not results:
                console.print("[yellow]No results found.[/]")
                return

            console.print(f"\n[bold]Found {len(results)} results for:[/] {query}\n")

            for i, result in enumerate(results, 1):
                console.print(f"[bold cyan]#{i}[/] {result['filepath']}")
                if result.get("start_line"):
                    console.print(f"    Lines {result['start_line']}-{result.get('end_line', '?')}")
                console.print(f"    Score: {result['score']:.4f}")

                # Show preview
                preview = result["chunk"][:200].replace("\n", " ")
                if len(result["chunk"]) > 200:
                    preview += "..."
                console.print(f"    [dim]{preview}[/]")
                console.print()

    except Exception as e:
        console.print(f"[bold red]Error:[/] {e}")
        sys.exit(1)


@main.command()
@click.option("--db-path", type=click.Path(), default=None, help="Database path")
def status(db_path: Optional[str]):
    """Show indexing status and statistics."""
    db = Path(db_path) if db_path else get_default_db_path()

    if not db.exists():
        console.print("[yellow]No index found.[/] Run 'editutor-cli index' first.")
        return

    try:
        searcher = Searcher(db_path=db)
        stats = searcher.get_stats()

        table = Table(title="Index Status")
        table.add_column("Metric", style="cyan")
        table.add_column("Value", style="green")

        table.add_row("Total chunks", str(stats.get("total_chunks", 0)))
        table.add_row("Total files", str(stats.get("total_files", 0)))
        table.add_row("Database size", stats.get("db_size", "Unknown"))
        table.add_row("Last updated", stats.get("last_updated", "Unknown"))

        console.print(table)

        # Show file type distribution
        if stats.get("by_language"):
            lang_table = Table(title="By Language")
            lang_table.add_column("Language", style="cyan")
            lang_table.add_column("Chunks", style="green")

            for lang, count in sorted(stats["by_language"].items(), key=lambda x: -x[1]):
                lang_table.add_row(lang, str(count))

            console.print(lang_table)

    except Exception as e:
        console.print(f"[bold red]Error:[/] {e}")
        sys.exit(1)


@main.command()
@click.option("--db-path", type=click.Path(), default=None, help="Database path")
@click.confirmation_option(prompt="Are you sure you want to clear the index?")
def clear(db_path: Optional[str]):
    """Clear the index database."""
    db = Path(db_path) if db_path else get_default_db_path()

    if not db.exists():
        console.print("[yellow]No index found.[/]")
        return

    try:
        import shutil
        shutil.rmtree(db)
        console.print("[green]Index cleared successfully.[/]")
    except Exception as e:
        console.print(f"[bold red]Error:[/] {e}")
        sys.exit(1)


@main.command("index-file")
@click.argument("filepath", type=click.Path(exists=True, file_okay=True, dir_okay=False))
@click.option("--db-path", type=click.Path(), default=None, help="Database path")
def index_file(filepath: str, db_path: Optional[str]):
    """Index or re-index a single file.

    FILEPATH: Path to the file to index

    This command is used for incremental indexing when files are saved.
    It only re-indexes if the file has changed (based on hash).

    Examples:
        editutor-cli index-file /path/to/file.py
        editutor-cli index-file ./src/main.rs
    """
    file_path = Path(filepath).resolve()
    db = Path(db_path) if db_path else get_default_db_path()

    if not db.exists():
        # Output JSON for Neovim
        print(json.dumps({"success": False, "error": "No index found. Run 'editutor-cli index' first."}))
        return

    try:
        indexer = Indexer(db_path=db)
        indexed = indexer.index_file(file_path, force=False)

        # Output JSON for Neovim integration
        print(json.dumps({
            "success": True,
            "indexed": indexed,
            "filepath": str(file_path),
        }))

    except Exception as e:
        print(json.dumps({"success": False, "error": str(e)}))
        sys.exit(1)


@main.command("check-file")
@click.argument("filepath", type=click.Path(exists=True, file_okay=True, dir_okay=False))
@click.option("--db-path", type=click.Path(), default=None, help="Database path")
def check_file(filepath: str, db_path: Optional[str]):
    """Check if a file is in an indexed project.

    FILEPATH: Path to the file to check

    Returns JSON indicating if the file is part of an indexed codebase.

    Examples:
        editutor-cli check-file /path/to/file.py
    """
    file_path = Path(filepath).resolve()
    db = Path(db_path) if db_path else get_default_db_path()

    if not db.exists():
        print(json.dumps({"indexed": False, "project_root": None}))
        return

    try:
        searcher = Searcher(db_path=db)

        # Check if file is in the index
        if "metadata" in searcher.db.table_names():
            meta_table = searcher.db.open_table("metadata")
            results = meta_table.search().where(
                f"filepath = '{str(file_path)}'"
            ).limit(1).to_list()

            if results:
                # Find project root (common ancestor of indexed files)
                all_meta = meta_table.to_pandas()
                paths = [Path(p) for p in all_meta["filepath"].tolist()]
                if paths:
                    # Simple heuristic: find common prefix
                    project_root = str(Path(*Path(paths[0]).parts[:3]))
                    print(json.dumps({"indexed": True, "project_root": project_root}))
                    return

        print(json.dumps({"indexed": False, "project_root": None}))

    except Exception as e:
        print(json.dumps({"indexed": False, "project_root": None, "error": str(e)}))


if __name__ == "__main__":
    main()
