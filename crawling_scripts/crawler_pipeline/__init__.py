"""School work-study crawler pipeline."""

from .similarity import DuplicateDecision, decide_duplicate
from .state import CrawlerState

__all__ = ["CrawlerState", "DuplicateDecision", "decide_duplicate"]
