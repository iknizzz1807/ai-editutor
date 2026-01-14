"""
Codebase indexer using LanceDB for vector storage.

Indexes code files, generates embeddings, and stores them for semantic search.
"""

import fnmatch
import hashlib
import json
import time
from datetime import datetime
from pathlib import Path
from typing import Callable, Dict, List, Optional

import lancedb
import pyarrow as pa

from editutor_cli.chunker import Chunker, CodeChunk
from editutor_cli.embedder import Embedder


class Indexer:
    """Index codebase into LanceDB for semantic search."""

    def __init__(
        self,
        db_path: Path,
        embedder: Optional[Embedder] = None,
        chunker: Optional[Chunker] = None,
    ):
        """
        Initialize indexer.

        Args:
            db_path: Path to LanceDB database
            embedder: Embedder instance (creates default if None)
            chunker: Chunker instance (creates default if None)
        """
        self.db_path = Path(db_path)
        self.db_path.parent.mkdir(parents=True, exist_ok=True)

        self.embedder = embedder or Embedder()
        self.chunker = chunker or Chunker()

        self._db = None
        self._table = None
        self._meta_table = None

    @property
    def db(self):
        """Lazy load database connection."""
        if self._db is None:
            self._db = lancedb.connect(str(self.db_path))
        return self._db

    def _get_or_create_table(self):
        """Get or create the chunks table."""
        if self._table is not None:
            return self._table

        table_name = "chunks"

        if table_name in self.db.table_names():
            self._table = self.db.open_table(table_name)
        else:
            # Create with schema
            schema = pa.schema([
                pa.field("id", pa.string()),
                pa.field("filepath", pa.string()),
                pa.field("content", pa.string()),
                pa.field("language", pa.string()),
                pa.field("start_line", pa.int32()),
                pa.field("end_line", pa.int32()),
                pa.field("chunk_type", pa.string()),
                pa.field("name", pa.string()),
                pa.field("file_hash", pa.string()),
                pa.field("vector", pa.list_(pa.float32(), self.embedder.embedding_dim)),
            ])

            self._table = self.db.create_table(table_name, schema=schema)

        return self._table

    def _get_or_create_meta_table(self):
        """Get or create metadata table."""
        if self._meta_table is not None:
            return self._meta_table

        table_name = "metadata"

        if table_name in self.db.table_names():
            self._meta_table = self.db.open_table(table_name)
        else:
            schema = pa.schema([
                pa.field("filepath", pa.string()),
                pa.field("file_hash", pa.string()),
                pa.field("indexed_at", pa.string()),
            ])
            self._meta_table = self.db.create_table(table_name, schema=schema)

        return self._meta_table

    def _get_file_hash(self, filepath: Path) -> str:
        """Get hash of file content."""
        content = filepath.read_bytes()
        return hashlib.md5(content).hexdigest()

    def _should_index_file(self, filepath: Path, force: bool = False) -> bool:
        """Check if file needs to be indexed."""
        if force:
            return True

        meta_table = self._get_or_create_meta_table()
        current_hash = self._get_file_hash(filepath)

        # Check if file was indexed with same hash
        try:
            results = meta_table.search().where(
                f"filepath = '{str(filepath)}'"
            ).limit(1).to_list()

            if results and results[0]["file_hash"] == current_hash:
                return False
        except Exception:
            pass

        return True

    def _find_files(
        self,
        directory: Path,
        exclude_patterns: Optional[List[str]] = None,
        include_patterns: Optional[List[str]] = None,
    ) -> List[Path]:
        """Find all indexable files in directory."""
        exclude_patterns = exclude_patterns or []
        files = []

        for path in directory.rglob("*"):
            if not path.is_file():
                continue

            # Check excludes
            relative = str(path.relative_to(directory))
            excluded = False
            for pattern in exclude_patterns:
                if fnmatch.fnmatch(relative, pattern) or fnmatch.fnmatch(path.name, pattern):
                    excluded = True
                    break
                # Check if any parent matches
                for parent in path.relative_to(directory).parents:
                    if fnmatch.fnmatch(str(parent), pattern):
                        excluded = True
                        break

            if excluded:
                continue

            # Check includes
            if include_patterns:
                included = False
                for pattern in include_patterns:
                    if fnmatch.fnmatch(path.name, pattern):
                        included = True
                        break
                if not included:
                    continue

            # Check if we can chunk this file type
            if self.chunker.get_language(path) is not None:
                files.append(path)

        return files

    def index_directory(
        self,
        directory: Path,
        force: bool = False,
        exclude_patterns: Optional[List[str]] = None,
        include_patterns: Optional[List[str]] = None,
        progress_callback: Optional[Callable[[str], None]] = None,
    ) -> Dict:
        """
        Index all files in a directory.

        Args:
            directory: Directory to index
            force: Force re-index all files
            exclude_patterns: Glob patterns to exclude
            include_patterns: Glob patterns to include (None = all)
            progress_callback: Callback for progress updates

        Returns:
            Dict with indexing statistics
        """
        stats = {
            "files_processed": 0,
            "files_skipped": 0,
            "chunks_created": 0,
            "errors": 0,
        }

        directory = Path(directory).resolve()

        # Find files
        if progress_callback:
            progress_callback("Finding files...")

        files = self._find_files(directory, exclude_patterns, include_patterns)

        if progress_callback:
            progress_callback(f"Found {len(files)} files")

        # Process files
        table = self._get_or_create_table()
        meta_table = self._get_or_create_meta_table()

        for i, filepath in enumerate(files):
            if progress_callback:
                progress_callback(f"Processing {i+1}/{len(files)}: {filepath.name}")

            try:
                if not self._should_index_file(filepath, force):
                    stats["files_skipped"] += 1
                    continue

                # Remove old chunks for this file
                try:
                    table.delete(f"filepath = '{str(filepath)}'")
                except Exception:
                    pass

                # Chunk file
                chunks = list(self.chunker.chunk_file(filepath))

                if not chunks:
                    stats["files_skipped"] += 1
                    continue

                # Generate embeddings
                contents = [chunk.content for chunk in chunks]
                embeddings = self.embedder.embed(contents)

                # Prepare records
                file_hash = self._get_file_hash(filepath)
                records = []

                for chunk, embedding in zip(chunks, embeddings):
                    chunk_id = f"{filepath}:{chunk.start_line}:{chunk.end_line}"
                    records.append({
                        "id": chunk_id,
                        "filepath": str(filepath),
                        "content": chunk.content,
                        "language": chunk.language,
                        "start_line": chunk.start_line,
                        "end_line": chunk.end_line,
                        "chunk_type": chunk.chunk_type,
                        "name": chunk.name or "",
                        "file_hash": file_hash,
                        "vector": embedding.tolist(),
                    })

                # Insert into database
                if records:
                    table.add(records)
                    stats["chunks_created"] += len(records)

                # Update metadata
                try:
                    meta_table.delete(f"filepath = '{str(filepath)}'")
                except Exception:
                    pass

                meta_table.add([{
                    "filepath": str(filepath),
                    "file_hash": file_hash,
                    "indexed_at": datetime.now().isoformat(),
                }])

                stats["files_processed"] += 1

            except Exception as e:
                stats["errors"] += 1
                if progress_callback:
                    progress_callback(f"Error processing {filepath.name}: {e}")

        return stats

    def index_file(self, filepath: Path, force: bool = False) -> bool:
        """
        Index a single file.

        Args:
            filepath: File to index
            force: Force re-index

        Returns:
            True if file was indexed
        """
        stats = self.index_directory(
            filepath.parent,
            force=force,
            include_patterns=[filepath.name],
        )
        return stats["files_processed"] > 0
