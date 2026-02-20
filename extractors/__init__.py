"""
extractors — Pluggable photo extraction backends.

Each extractor reads photo metadata from a specific source (macOS Photos.sqlite,
iOS PhotoKit, Google Takeout, etc.) and returns a standardized pandas DataFrame.
"""

from extractors.base import PhotoExtractor, PhotoRecord
from extractors.apple_photos import ApplePhotosExtractor

__all__ = ["PhotoExtractor", "PhotoRecord", "ApplePhotosExtractor"]
