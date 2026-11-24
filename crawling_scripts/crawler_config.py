"""Central crawler configuration with Windows user-env support.

Secrets are never read from the frontend Vite environment. On Windows the
HKCU\\Environment fallback makes newly configured values available to an
already-running Task Scheduler service without waiting for a new login.
"""
from __future__ import annotations

import os


def _user_environment(name: str) -> str | None:
    if os.name != "nt":
        return None
    try:
        import winreg

        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, "Environment") as key:
            value, _ = winreg.QueryValueEx(key, name)
    except (FileNotFoundError, OSError):
        return None
    return str(value).strip() or None


def _legacy_credential(name: str) -> str | None:
    try:
        import creds
    except ModuleNotFoundError:
        return None
    return str(getattr(creds, name, "") or "").strip() or None


def get_value(name: str, *, aliases: tuple[str, ...] = (),
              legacy_name: str | None = None) -> str | None:
    for candidate in (name, *aliases):
        value = os.environ.get(candidate) or _user_environment(candidate)
        if value:
            return value.strip()
    return _legacy_credential(legacy_name or name)


def require_value(name: str, *, aliases: tuple[str, ...] = (),
                  legacy_name: str | None = None) -> str:
    value = get_value(name, aliases=aliases, legacy_name=legacy_name)
    if not value:
        raise RuntimeError(f"missing crawler configuration: {name}")
    return value


def get_anthropic_api_key() -> str | None:
    return get_value("ANTHROPIC_API_KEY")


def get_supabase_credentials() -> tuple[str, str]:
    return (
        require_value("SUPABASE_URL"),
        require_value("SUPABASE_SERVICE_ROLE_KEY"),
    )


def get_portal_credentials() -> tuple[str, str]:
    return (
        require_value(
            "KOREA_PORTAL_ID",
            aliases=("SSC_ID",),
            legacy_name="SSC_ID",
        ),
        require_value(
            "KOREA_PORTAL_PASSWORD",
            aliases=("SSC_PW",),
            legacy_name="SSC_PW",
        ),
    )
