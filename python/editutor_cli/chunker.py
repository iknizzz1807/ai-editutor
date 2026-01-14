"""
AST-based code chunking using Tree-sitter.

Chunks code at semantic boundaries (functions, classes, methods)
while respecting max token limits.
"""

from dataclasses import dataclass
from pathlib import Path
from typing import Iterator, Optional

try:
    import tree_sitter_languages
    TREE_SITTER_AVAILABLE = True
except ImportError:
    TREE_SITTER_AVAILABLE = False


@dataclass
class CodeChunk:
    """Represents a chunk of code."""
    content: str
    filepath: str
    language: str
    start_line: int
    end_line: int
    chunk_type: str  # "function", "class", "method", "module", "block"
    name: Optional[str] = None  # Function/class name if applicable


# Language to Tree-sitter parser mapping
LANGUAGE_MAP = {
    ".py": "python",
    ".js": "javascript",
    ".ts": "typescript",
    ".tsx": "tsx",
    ".jsx": "javascript",
    ".go": "go",
    ".rs": "rust",
    ".c": "c",
    ".cpp": "cpp",
    ".h": "c",
    ".hpp": "cpp",
    ".java": "java",
    ".rb": "ruby",
    ".lua": "lua",
    ".php": "php",
    ".cs": "c_sharp",
    ".swift": "swift",
    ".kt": "kotlin",
    ".scala": "scala",
    ".hs": "haskell",
    ".ex": "elixir",
    ".exs": "elixir",
    ".erl": "erlang",
    ".ml": "ocaml",
    ".vim": "vim",
    ".sh": "bash",
    ".bash": "bash",
    ".zsh": "bash",
    ".yaml": "yaml",
    ".yml": "yaml",
    ".json": "json",
    ".toml": "toml",
    ".html": "html",
    ".css": "css",
    ".sql": "sql",
}

# Node types that represent semantic boundaries
CHUNK_NODE_TYPES = {
    "python": ["function_definition", "class_definition", "decorated_definition"],
    "javascript": ["function_declaration", "class_declaration", "method_definition",
                   "arrow_function", "function_expression"],
    "typescript": ["function_declaration", "class_declaration", "method_definition",
                   "arrow_function", "interface_declaration", "type_alias_declaration"],
    "go": ["function_declaration", "method_declaration", "type_declaration"],
    "rust": ["function_item", "impl_item", "struct_item", "enum_item", "trait_item"],
    "java": ["class_declaration", "method_declaration", "interface_declaration"],
    "lua": ["function_declaration", "function_definition", "local_function"],
    "c": ["function_definition", "struct_specifier"],
    "cpp": ["function_definition", "class_specifier", "struct_specifier"],
}


class Chunker:
    """AST-based code chunker using Tree-sitter."""

    def __init__(
        self,
        max_chunk_size: int = 500,  # tokens (approximate)
        min_chunk_size: int = 50,
        overlap: int = 20,
    ):
        self.max_chunk_size = max_chunk_size
        self.min_chunk_size = min_chunk_size
        self.overlap = overlap

    def get_language(self, filepath: Path) -> Optional[str]:
        """Get Tree-sitter language from file extension."""
        ext = filepath.suffix.lower()
        return LANGUAGE_MAP.get(ext)

    def chunk_file(self, filepath: Path) -> Iterator[CodeChunk]:
        """Chunk a single file using AST-based splitting."""
        language = self.get_language(filepath)

        if not language:
            # Fallback to line-based chunking for unknown languages
            yield from self._chunk_by_lines(filepath)
            return

        try:
            content = filepath.read_text(encoding="utf-8", errors="ignore")
        except Exception:
            return

        if not content.strip():
            return

        if TREE_SITTER_AVAILABLE:
            yield from self._chunk_with_ast(content, str(filepath), language)
        else:
            yield from self._chunk_by_lines(filepath)

    def _chunk_with_ast(
        self,
        content: str,
        filepath: str,
        language: str,
    ) -> Iterator[CodeChunk]:
        """Chunk using Tree-sitter AST."""
        try:
            parser = tree_sitter_languages.get_parser(language)
            tree = parser.parse(content.encode())
        except Exception:
            # Fallback to line-based chunking
            yield from self._chunk_content_by_lines(content, filepath, language)
            return

        root = tree.root_node
        chunk_types = CHUNK_NODE_TYPES.get(language, [])

        # Find all semantic boundary nodes
        semantic_nodes = []
        self._find_semantic_nodes(root, chunk_types, semantic_nodes)

        if not semantic_nodes:
            # No semantic boundaries found, chunk by size
            yield from self._chunk_content_by_lines(content, filepath, language)
            return

        lines = content.split("\n")

        for node in semantic_nodes:
            start_line = node.start_point[0]
            end_line = node.end_point[0]

            # Get node content
            chunk_content = "\n".join(lines[start_line:end_line + 1])

            # Check if chunk is too large
            if self._estimate_tokens(chunk_content) > self.max_chunk_size:
                # Split large chunks
                yield from self._split_large_chunk(
                    chunk_content, filepath, language, start_line, node.type
                )
            elif self._estimate_tokens(chunk_content) >= self.min_chunk_size:
                # Get name if available
                name = self._get_node_name(node, content)

                yield CodeChunk(
                    content=chunk_content,
                    filepath=filepath,
                    language=language,
                    start_line=start_line + 1,  # 1-indexed
                    end_line=end_line + 1,
                    chunk_type=node.type,
                    name=name,
                )

        # Also yield module-level code not in any semantic boundary
        yield from self._chunk_remaining_code(content, filepath, language, semantic_nodes)

    def _find_semantic_nodes(self, node, chunk_types, result):
        """Recursively find nodes that represent semantic boundaries."""
        if node.type in chunk_types:
            result.append(node)
            # Don't descend into nested functions/classes for now
            return

        for child in node.children:
            self._find_semantic_nodes(child, chunk_types, result)

    def _get_node_name(self, node, content: str) -> Optional[str]:
        """Extract name from a semantic node."""
        for child in node.children:
            if child.type in ["identifier", "name", "property_identifier"]:
                return content[child.start_byte:child.end_byte]
        return None

    def _estimate_tokens(self, text: str) -> int:
        """Estimate token count (rough approximation)."""
        # Average ~4 characters per token for code
        return len(text) // 4

    def _split_large_chunk(
        self,
        content: str,
        filepath: str,
        language: str,
        base_line: int,
        chunk_type: str,
    ) -> Iterator[CodeChunk]:
        """Split a large chunk into smaller pieces."""
        lines = content.split("\n")
        current_chunk = []
        current_start = 0

        for i, line in enumerate(lines):
            current_chunk.append(line)
            chunk_text = "\n".join(current_chunk)

            if self._estimate_tokens(chunk_text) >= self.max_chunk_size:
                # Emit chunk
                yield CodeChunk(
                    content=chunk_text,
                    filepath=filepath,
                    language=language,
                    start_line=base_line + current_start + 1,
                    end_line=base_line + i + 1,
                    chunk_type=chunk_type,
                )

                # Start new chunk with overlap
                overlap_start = max(0, len(current_chunk) - self.overlap)
                current_chunk = current_chunk[overlap_start:]
                current_start = i - len(current_chunk) + 1

        # Emit remaining
        if current_chunk and self._estimate_tokens("\n".join(current_chunk)) >= self.min_chunk_size:
            yield CodeChunk(
                content="\n".join(current_chunk),
                filepath=filepath,
                language=language,
                start_line=base_line + current_start + 1,
                end_line=base_line + len(lines),
                chunk_type=chunk_type,
            )

    def _chunk_remaining_code(
        self,
        content: str,
        filepath: str,
        language: str,
        semantic_nodes,
    ) -> Iterator[CodeChunk]:
        """Chunk code that's not inside any semantic boundary."""
        if not semantic_nodes:
            return

        lines = content.split("\n")
        covered = set()

        for node in semantic_nodes:
            for line in range(node.start_point[0], node.end_point[0] + 1):
                covered.add(line)

        # Find uncovered regions
        current_region = []
        region_start = None

        for i in range(len(lines)):
            if i not in covered:
                if region_start is None:
                    region_start = i
                current_region.append(lines[i])
            else:
                if current_region:
                    chunk_text = "\n".join(current_region)
                    if self._estimate_tokens(chunk_text) >= self.min_chunk_size:
                        yield CodeChunk(
                            content=chunk_text,
                            filepath=filepath,
                            language=language,
                            start_line=region_start + 1,
                            end_line=region_start + len(current_region),
                            chunk_type="module",
                        )
                    current_region = []
                    region_start = None

        # Handle remaining
        if current_region:
            chunk_text = "\n".join(current_region)
            if self._estimate_tokens(chunk_text) >= self.min_chunk_size:
                yield CodeChunk(
                    content=chunk_text,
                    filepath=filepath,
                    language=language,
                    start_line=region_start + 1,
                    end_line=region_start + len(current_region),
                    chunk_type="module",
                )

    def _chunk_by_lines(self, filepath: Path) -> Iterator[CodeChunk]:
        """Fallback: chunk file by lines."""
        try:
            content = filepath.read_text(encoding="utf-8", errors="ignore")
            language = self.get_language(filepath) or "text"
            yield from self._chunk_content_by_lines(content, str(filepath), language)
        except Exception:
            return

    def _chunk_content_by_lines(
        self,
        content: str,
        filepath: str,
        language: str,
    ) -> Iterator[CodeChunk]:
        """Chunk content by lines with overlap."""
        lines = content.split("\n")
        current_chunk = []
        current_start = 0

        for i, line in enumerate(lines):
            current_chunk.append(line)
            chunk_text = "\n".join(current_chunk)

            if self._estimate_tokens(chunk_text) >= self.max_chunk_size:
                yield CodeChunk(
                    content=chunk_text,
                    filepath=filepath,
                    language=language,
                    start_line=current_start + 1,
                    end_line=i + 1,
                    chunk_type="block",
                )

                # Overlap
                overlap_start = max(0, len(current_chunk) - self.overlap)
                current_chunk = current_chunk[overlap_start:]
                current_start = i - len(current_chunk) + 1

        # Remaining
        if current_chunk and self._estimate_tokens("\n".join(current_chunk)) >= self.min_chunk_size:
            yield CodeChunk(
                content="\n".join(current_chunk),
                filepath=filepath,
                language=language,
                start_line=current_start + 1,
                end_line=len(lines),
                chunk_type="block",
            )
