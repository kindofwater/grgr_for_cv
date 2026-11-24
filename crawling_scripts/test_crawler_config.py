import crawler_config


def test_environment_wins_over_legacy(monkeypatch):
    monkeypatch.setenv("SUPABASE_URL", "https://env.example")
    monkeypatch.setattr(crawler_config, "_user_environment", lambda name: None)
    monkeypatch.setattr(crawler_config, "_legacy_credential", lambda name: "legacy")
    assert crawler_config.get_value("SUPABASE_URL") == "https://env.example"


def test_windows_user_environment_is_supported(monkeypatch):
    monkeypatch.delenv("KOREA_PORTAL_ID", raising=False)
    monkeypatch.setattr(
        crawler_config,
        "_user_environment",
        lambda name: "portal-user" if name == "KOREA_PORTAL_ID" else None,
    )
    monkeypatch.setattr(crawler_config, "_legacy_credential", lambda name: None)
    assert crawler_config.get_value("KOREA_PORTAL_ID") == "portal-user"


def test_new_portal_names_fall_back_to_old_creds_names(monkeypatch):
    monkeypatch.delenv("KOREA_PORTAL_ID", raising=False)
    monkeypatch.delenv("KOREA_PORTAL_PASSWORD", raising=False)
    monkeypatch.delenv("SSC_ID", raising=False)
    monkeypatch.delenv("SSC_PW", raising=False)
    monkeypatch.setattr(crawler_config, "_user_environment", lambda name: None)
    values = {"SSC_ID": "legacy-id", "SSC_PW": "legacy-password"}
    monkeypatch.setattr(
        crawler_config,
        "_legacy_credential",
        lambda name: values.get(name),
    )
    assert crawler_config.get_portal_credentials() == (
        "legacy-id",
        "legacy-password",
    )
