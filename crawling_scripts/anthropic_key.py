"""Anthropic API key lookup for unattended crawler jobs."""
from __future__ import annotations

import sys

from crawler_config import get_anthropic_api_key


def main() -> int:
    if get_anthropic_api_key():
        print("[OK] ANTHROPIC_API_KEY found")
        return 0
    print("[FAIL] missing ANTHROPIC_API_KEY user environment variable")
    return 1


if __name__ == "__main__":
    sys.exit(main())
