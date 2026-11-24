"""One-time migration from gitignored creds.py to Windows user variables.

Values are written directly to HKCU\\Environment and are never printed or
passed on a command line.
"""
from __future__ import annotations

import argparse
import ctypes
import getpass
import os
import sys

ENV_TO_LEGACY = {
    "ANTHROPIC_API_KEY": "ANTHROPIC_API_KEY",
    "SUPABASE_URL": "SUPABASE_URL",
    "SUPABASE_SERVICE_ROLE_KEY": "SUPABASE_SERVICE_ROLE_KEY",
    "KOREA_PORTAL_ID": "SSC_ID",
    "KOREA_PORTAL_PASSWORD": "SSC_PW",
}


def _write_user_environment(values: dict[str, str]) -> list[str]:
    if os.name != "nt":
        raise RuntimeError("this helper currently supports Windows only")
    import winreg

    with winreg.OpenKey(
        winreg.HKEY_CURRENT_USER,
        "Environment",
        0,
        winreg.KEY_SET_VALUE,
    ) as key:
        for name, value in values.items():
            winreg.SetValueEx(key, name, 0, winreg.REG_SZ, value)

    # Tell interactive applications that the user environment changed.
    HWND_BROADCAST = 0xFFFF
    WM_SETTINGCHANGE = 0x001A
    ctypes.windll.user32.SendMessageTimeoutW(
        HWND_BROADCAST,
        WM_SETTINGCHANGE,
        0,
        "Environment",
        0x0002,
        5000,
        None,
    )
    return sorted(values)


def migrate_from_creds() -> list[str]:
    import creds

    values = {}
    for environment_name, legacy_name in ENV_TO_LEGACY.items():
        value = str(getattr(creds, legacy_name, "") or "").strip()
        if not value:
            raise RuntimeError(f"creds.py has no value for {legacy_name}")
        values[environment_name] = value
    return _write_user_environment(values)


def configure_interactively() -> list[str]:
    print("Secret inputs are hidden and are not printed.")
    values = {
        "ANTHROPIC_API_KEY": getpass.getpass("Anthropic API key: ").strip(),
        "SUPABASE_URL": input("Supabase project URL: ").strip(),
        "SUPABASE_SERVICE_ROLE_KEY": getpass.getpass(
            "Supabase service-role key: "
        ).strip(),
        "KOREA_PORTAL_ID": input("Korea portal ID: ").strip(),
        "KOREA_PORTAL_PASSWORD": getpass.getpass(
            "Korea portal password: "
        ).strip(),
    }
    missing = [name for name, value in values.items() if not value]
    if missing:
        raise RuntimeError(f"empty values: {', '.join(missing)}")
    return _write_user_environment(values)


def main() -> int:
    parser = argparse.ArgumentParser(description="크롤러 비밀값을 Windows 사용자 환경변수로 이전")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--from-creds", action="store_true")
    mode.add_argument("--interactive", action="store_true")
    args = parser.parse_args()
    try:
        names = (
            migrate_from_creds()
            if args.from_creds
            else configure_interactively()
        )
    except Exception as exc:
        print(f"[FAIL] crawler environment migration failed: {exc}")
        return 1
    print("[OK] configured user environment variables:")
    for name in names:
        print(f"  - {name}")
    print("No secret values were printed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
