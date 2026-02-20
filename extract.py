"""
extract.py — Backward-compatible wrapper for photo extraction.

All logic has moved to extractors/apple_photos.py. This module preserves the
original extract_photo_data() signature so main.py and other consumers work
without changes.
"""

from extractors.apple_photos import ApplePhotosExtractor


def extract_photo_data(db_path=None, debug_plists=False):
    """
    Extract geotagged photo data from the macOS Photos database.

    Args:
        db_path: Path to Photos.sqlite. Uses default if None.
        debug_plists: If True, print the structure of the first few plists
                      for schema investigation.

    Returns:
        pd.DataFrame with columns:
            latitude, longitude, date, year, month, filename,
            country, city, district, state
    """
    extractor = ApplePhotosExtractor(db_path=db_path)
    return extractor.extract(debug_plists=debug_plists)
