"""
Embedding generation using sentence-transformers.

Supports multiple embedding models with automatic caching.
"""

from pathlib import Path
from typing import List, Optional

import numpy as np


class Embedder:
    """Generate embeddings for code chunks using sentence-transformers."""

    def __init__(
        self,
        model_name: str = "all-MiniLM-L6-v2",
        device: Optional[str] = None,
        cache_dir: Optional[Path] = None,
    ):
        """
        Initialize embedder.

        Args:
            model_name: Name of sentence-transformers model
            device: Device to use ("cpu", "cuda", "mps")
            cache_dir: Directory to cache model
        """
        self.model_name = model_name
        self.device = device
        self.cache_dir = cache_dir
        self._model = None

    @property
    def model(self):
        """Lazy load the model."""
        if self._model is None:
            from sentence_transformers import SentenceTransformer

            kwargs = {}
            if self.cache_dir:
                kwargs["cache_folder"] = str(self.cache_dir)
            if self.device:
                kwargs["device"] = self.device

            self._model = SentenceTransformer(self.model_name, **kwargs)

        return self._model

    def embed(self, texts: List[str], show_progress: bool = False) -> np.ndarray:
        """
        Generate embeddings for texts.

        Args:
            texts: List of text strings to embed
            show_progress: Show progress bar

        Returns:
            numpy array of shape (len(texts), embedding_dim)
        """
        if not texts:
            return np.array([])

        embeddings = self.model.encode(
            texts,
            show_progress_bar=show_progress,
            convert_to_numpy=True,
            normalize_embeddings=True,  # L2 normalize for cosine similarity
        )

        return embeddings

    def embed_single(self, text: str) -> np.ndarray:
        """
        Generate embedding for a single text.

        Args:
            text: Text to embed

        Returns:
            1D numpy array of embedding
        """
        return self.embed([text])[0]

    @property
    def embedding_dim(self) -> int:
        """Get embedding dimension."""
        return self.model.get_sentence_embedding_dimension()


# Model recommendations
RECOMMENDED_MODELS = {
    "fast": "all-MiniLM-L6-v2",  # 384 dims, fast, good quality
    "balanced": "all-mpnet-base-v2",  # 768 dims, balanced
    "quality": "all-MiniLM-L12-v2",  # 384 dims, better quality than L6
    "code": "microsoft/codebert-base",  # Specialized for code (requires transformers)
}


def get_embedder(
    quality: str = "fast",
    device: Optional[str] = None,
    cache_dir: Optional[Path] = None,
) -> Embedder:
    """
    Get an embedder with recommended settings.

    Args:
        quality: One of "fast", "balanced", "quality", "code"
        device: Device to use
        cache_dir: Cache directory

    Returns:
        Configured Embedder instance
    """
    model_name = RECOMMENDED_MODELS.get(quality, RECOMMENDED_MODELS["fast"])
    return Embedder(model_name=model_name, device=device, cache_dir=cache_dir)
