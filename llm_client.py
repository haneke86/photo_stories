"""
llm_client.py — Shared LLM infrastructure: client init, caching, model config.

Provides a cached Anthropic client, file-based response caching to avoid
redundant API calls, and model constants used across llm_enrich.py,
llm_stories.py, and chat.py.
"""

import hashlib
import json
import os

from dotenv import load_dotenv

# Load .env file from project root (contains ANTHROPIC_API_KEY)
load_dotenv(os.path.join(os.path.dirname(__file__), ".env"))

# Model constants — change these to switch models across the pipeline
DEFAULT_MODEL = "claude-sonnet-4-5-20250929"
NARRATIVE_MODEL = "claude-sonnet-4-5-20250929"
CHAT_MODEL = "claude-sonnet-4-5-20250929"

# Cache directory (relative to project root)
CACHE_DIR = os.path.join(os.path.dirname(__file__), ".llm_cache")


def get_client():
    """
    Initialize and return an Anthropic client.

    Raises EnvironmentError if ANTHROPIC_API_KEY is not set.
    """
    import anthropic

    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        raise EnvironmentError(
            "ANTHROPIC_API_KEY environment variable is not set.\n"
            "Set it with: export ANTHROPIC_API_KEY='your-key-here'\n"
            "Or run with --no-llm to skip LLM features."
        )
    return anthropic.Anthropic(api_key=api_key)


def compute_cache_key(data, prompt_version):
    """
    Compute a deterministic cache key from input data and prompt version.

    Args:
        data: Any JSON-serializable data (dict, list, str).
        prompt_version: String identifying the prompt version (e.g. "enrich-v1").

    Returns:
        SHA256 hex digest string.
    """
    payload = json.dumps({"data": data, "prompt_version": prompt_version},
                         sort_keys=True, ensure_ascii=False, default=str)
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def load_cached(cache_key, task):
    """
    Load a cached response if it exists.

    Args:
        cache_key: SHA256 hex digest from compute_cache_key().
        task: Task name used as subdirectory (e.g. "enrich", "stories").

    Returns:
        Parsed JSON data if cache hit, None if miss.
    """
    path = os.path.join(CACHE_DIR, task, f"{cache_key}.json")
    if os.path.exists(path):
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    return None


def save_cached(cache_key, task, data):
    """
    Save a response to the file cache.

    Args:
        cache_key: SHA256 hex digest from compute_cache_key().
        task: Task name used as subdirectory (e.g. "enrich", "stories").
        data: JSON-serializable data to cache.
    """
    task_dir = os.path.join(CACHE_DIR, task)
    os.makedirs(task_dir, exist_ok=True)
    path = os.path.join(task_dir, f"{cache_key}.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
