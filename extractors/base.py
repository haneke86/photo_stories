"""
base.py — Shared types and protocol for photo extractors.

Any extractor that reads photo metadata (from macOS Photos.sqlite, iOS PhotoKit,
Google Takeout, etc.) should implement the PhotoExtractor protocol. All extractors
produce a DataFrame with the same columns defined by PhotoRecord.
"""

from typing import Protocol, TypedDict

import pandas as pd


class PhotoRecord(TypedDict):
    """Schema for a single photo record. DataFrame columns match these keys."""
    latitude: float
    longitude: float
    date: object       # datetime (UTC)
    year: int
    month: str         # "YYYY-MM"
    filename: str
    country: str
    city: str          # metro-level (normalized)
    district: str      # district/neighborhood level
    state: str


# Canonical column order for all extractor DataFrames
PHOTO_COLUMNS = list(PhotoRecord.__annotations__.keys())


class PhotoExtractor(Protocol):
    """
    Protocol for photo metadata extractors.

    Implementors must provide:
      - source_name: human-readable name (e.g. "Apple Photos (macOS)")
      - extract(**kwargs) -> DataFrame with PHOTO_COLUMNS
      - is_available() -> bool indicating whether the source is accessible
    """

    source_name: str

    def extract(self, **kwargs) -> pd.DataFrame:
        """Extract photo metadata and return a DataFrame with PHOTO_COLUMNS."""
        ...

    def is_available(self) -> bool:
        """Check whether this extraction source is accessible."""
        ...
