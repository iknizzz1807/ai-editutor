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
        """
        Optimized BM25-style keyword search.

        Uses SQL LIKE queries to pre-filter instead of loading all docs.
        Falls back to full scan only for very short queries.
        """
        # Tokenize query
        query_tokens = list(set(self._tokenize(query.lower())))

        if not query_tokens:
            return []

        try:
            # Strategy 1: Use LIKE queries to pre-filter (efficient for large codebases)
            # Only fetch docs that contain at least one query term
            if len(query_tokens) <= 5:
                # Build OR conditions for each token
                like_conditions = [f"content LIKE '%{token}%'" for token in query_tokens[:5]]
                combined_where = " OR ".join(like_conditions)

                if where_clause:
                    combined_where = f"({combined_where}) AND ({where_clause})"

                # Fetch filtered results
                try:
                    filtered_docs = table.search().where(combined_where).limit(top_k * 10).to_list()
                except Exception:
                    # Fallback if LIKE not supported
                    filtered_docs = self._fallback_keyword_search(table, query_tokens, where_clause, top_k)
            else:
                # Too many tokens, use fallback
                filtered_docs = self._fallback_keyword_search(table, query_tokens, where_clause, top_k)

            if not filtered_docs:
                return []

            # Score the filtered docs
            scores = []
            for doc in filtered_docs:
                content = doc.get("content", "").lower()
                doc_tokens = Counter(self._tokenize(content))

                # BM25-inspired scoring with TF and document length normalization
                doc_len = len(doc_tokens)
                avg_doc_len = 100  # Approximate average
                k1 = 1.2
                b = 0.75

                score = 0
                for token in query_tokens:
                    tf = doc_tokens.get(token, 0)
                    if tf > 0:
                        # Simplified BM25 TF component
                        normalized_tf = (tf * (k1 + 1)) / (tf + k1 * (1 - b + b * doc_len / avg_doc_len))
                        score += normalized_tf

                if score > 0:
                    scores.append((score, doc))

            # Sort by score
            scores.sort(key=lambda x: -x[0])

            return [
                {**doc, "_distance": 1.0 / (score + 1)}
                for score, doc in scores[:top_k]
            ]

        except Exception:
            return []

    def _fallback_keyword_search(
        self,
        table,
        query_tokens: List[str],
        where_clause: Optional[str],
        top_k: int,
    ) -> List[Dict]:
        """
        Fallback keyword search using batched iteration.

        More memory efficient than loading entire table.
        """
        try:
            # Get total count
            total = table.count_rows()

            if total == 0:
                return []

            # For small tables, just load all (faster)
            if total <= 1000:
                df = table.to_pandas()
                return df.to_dict('records')

            # For larger tables, batch process
            batch_size = 500
            matching_docs = []
            query_set = set(query_tokens)

            # Use scanner for efficient iteration
            scanner = table.to_lance().scanner(
                columns=["id", "filepath", "content", "language", "start_line", "end_line", "chunk_type", "name"],
                batch_size=batch_size,
            )

            for batch in scanner.to_batches():
                df_batch = batch.to_pandas()
                for _, row in df_batch.iterrows():
                    content_lower = row["content"].lower()
                    # Quick check if any query token is in content
                    if any(token in content_lower for token in query_set):
                        matching_docs.append(row.to_dict())

                        # Early exit if we have enough candidates
                        if len(matching_docs) >= top_k * 5:
                            break

                if len(matching_docs) >= top_k * 5:
                    break

            return matching_docs

        except Exception:
            # Ultimate fallback: load all
            try:
                return table.to_pandas().to_dict('records')
            except Exception:
                return []

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
