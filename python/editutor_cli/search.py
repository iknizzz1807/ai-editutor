"""
Semantic and hybrid search for indexed codebase.

Supports:
- Pure vector (semantic) search
- BM25 keyword search
- Hybrid search (combining both)
"""

import re
from collections import Counter
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional

import lancedb

from editutor_cli.embedder import Embedder


class Searcher:
    """Search indexed codebase using vector and keyword search."""

    def __init__(
        self,
        db_path: Path,
        embedder: Optional[Embedder] = None,
    ):
        """
        Initialize searcher.

        Args:
            db_path: Path to LanceDB database
            embedder: Embedder instance (must match indexing embedder)
        """
        self.db_path = Path(db_path)
        self.embedder = embedder or Embedder()
        self._db = None

    @property
    def db(self):
        """Lazy load database connection."""
        if self._db is None:
            self._db = lancedb.connect(str(self.db_path))
        return self._db

    def search(
        self,
        query: str,
        top_k: int = 5,
        hybrid: bool = False,
        language: Optional[str] = None,
        filepath_pattern: Optional[str] = None,
    ) -> List[Dict]:
        """
        Search the indexed codebase.

        Args:
            query: Natural language query
            top_k: Number of results to return
            hybrid: Use hybrid search (vector + BM25)
            language: Filter by language
            filepath_pattern: Filter by filepath pattern

        Returns:
            List of search results with score, filepath, content, etc.
        """
        if "chunks" not in self.db.table_names():
            return []

        table = self.db.open_table("chunks")

        # Generate query embedding
        query_embedding = self.embedder.embed_single(query)

        # Build filter
        filters = []
        if language:
            filters.append(f"language = '{language}'")
        if filepath_pattern:
            filters.append(f"filepath LIKE '%{filepath_pattern}%'")

        where_clause = " AND ".join(filters) if filters else None

        # Vector search
        search_builder = table.search(query_embedding)

        if where_clause:
            search_builder = search_builder.where(where_clause)

        # Get more results for hybrid reranking
        fetch_k = top_k * 3 if hybrid else top_k
        vector_results = search_builder.limit(fetch_k).to_list()

        if not hybrid:
            return self._format_results(vector_results[:top_k])

        # Hybrid search: combine with BM25
        bm25_results = self._bm25_search(query, table, where_clause, fetch_k)

        # Combine and rerank using Reciprocal Rank Fusion
        combined = self._reciprocal_rank_fusion(vector_results, bm25_results)

        return combined[:top_k]

    def _bm25_search(
        self,
        query: str,
        table,
        where_clause: Optional[str],
        top_k: int,
    ) -> List[Dict]:
        """Simple BM25-style keyword search."""
        # Tokenize query
        query_tokens = set(self._tokenize(query.lower()))

        if not query_tokens:
            return []

        # Get all documents (for small codebases this is fine)
        # For large codebases, would use proper inverted index
        try:
            all_docs = table.to_pandas()
        except Exception:
            return []

        scores = []
        for idx, row in all_docs.iterrows():
            content = row["content"].lower()
            doc_tokens = Counter(self._tokenize(content))

            # Simple TF score
            score = sum(doc_tokens.get(token, 0) for token in query_tokens)

            if score > 0:
                scores.append((score, row.to_dict()))

        # Sort by score
        scores.sort(key=lambda x: -x[0])

        return [
            {**doc, "_distance": 1.0 / (score + 1)}
            for score, doc in scores[:top_k]
        ]

    def _tokenize(self, text: str) -> List[str]:
        """Simple tokenization for BM25."""
        # Split on non-alphanumeric, lowercase
        tokens = re.findall(r"\w+", text.lower())
        # Filter short tokens
        return [t for t in tokens if len(t) > 2]

    def _reciprocal_rank_fusion(
        self,
        vector_results: List[Dict],
        bm25_results: List[Dict],
        k: int = 60,
    ) -> List[Dict]:
        """
        Combine results using Reciprocal Rank Fusion.

        RRF score = sum(1 / (k + rank_i)) for each ranking
        """
        scores = {}
        doc_data = {}

        # Score vector results
        for rank, doc in enumerate(vector_results):
            doc_id = doc.get("id", doc.get("filepath", str(rank)))
            scores[doc_id] = scores.get(doc_id, 0) + 1.0 / (k + rank + 1)
            doc_data[doc_id] = doc

        # Score BM25 results
        for rank, doc in enumerate(bm25_results):
            doc_id = doc.get("id", doc.get("filepath", str(rank)))
            scores[doc_id] = scores.get(doc_id, 0) + 1.0 / (k + rank + 1)
            if doc_id not in doc_data:
                doc_data[doc_id] = doc

        # Sort by combined score
        sorted_ids = sorted(scores.keys(), key=lambda x: -scores[x])

        results = []
        for doc_id in sorted_ids:
            doc = doc_data[doc_id].copy()
            doc["_rrf_score"] = scores[doc_id]
            results.append(doc)

        return self._format_results(results)

    def _format_results(self, results: List[Dict]) -> List[Dict]:
        """Format results for output."""
        formatted = []
        for doc in results:
            # Calculate score (lower distance = better)
            distance = doc.get("_distance", 0)
            rrf_score = doc.get("_rrf_score")

            if rrf_score is not None:
                score = rrf_score
            else:
                score = 1.0 / (1.0 + distance)

            formatted.append({
                "filepath": doc.get("filepath", ""),
                "chunk": doc.get("content", ""),
                "language": doc.get("language", ""),
                "start_line": doc.get("start_line"),
                "end_line": doc.get("end_line"),
                "chunk_type": doc.get("chunk_type", ""),
                "name": doc.get("name", ""),
                "score": score,
            })

        return formatted

    def get_stats(self) -> Dict:
        """Get index statistics."""
        stats = {
            "total_chunks": 0,
            "total_files": 0,
            "by_language": {},
            "db_size": "Unknown",
            "last_updated": "Unknown",
        }

        if "chunks" not in self.db.table_names():
            return stats

        try:
            table = self.db.open_table("chunks")
            df = table.to_pandas()

            stats["total_chunks"] = len(df)
            stats["total_files"] = df["filepath"].nunique()
            stats["by_language"] = df["language"].value_counts().to_dict()

            # Database size
            if self.db_path.exists():
                size = sum(f.stat().st_size for f in self.db_path.rglob("*") if f.is_file())
                if size > 1024 * 1024:
                    stats["db_size"] = f"{size / (1024 * 1024):.1f} MB"
                else:
                    stats["db_size"] = f"{size / 1024:.1f} KB"

            # Last updated
            if "metadata" in self.db.table_names():
                meta_table = self.db.open_table("metadata")
                meta_df = meta_table.to_pandas()
                if not meta_df.empty:
                    stats["last_updated"] = meta_df["indexed_at"].max()

        except Exception:
            pass

        return stats
