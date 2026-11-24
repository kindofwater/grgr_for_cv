import datetime

from upsert_worksites import decide_posting_update, MACHINE_COLS, CONTENT_COLS


def test_machine_cols_always_updated():
    existing = {"manual_override": False}
    parsed = {"recruit_until": "2026-07-24", "is_active": True, "hourly_wage": 9860}
    upd = decide_posting_update(existing, parsed)
    assert upd["recruit_until"] == "2026-07-24"
    assert upd["is_active"] is True

def test_content_updated_when_no_override():
    upd = decide_posting_update({"manual_override": False}, {"hourly_wage": 9860})
    assert upd["hourly_wage"] == 9860

def test_content_skipped_when_override():
    upd = decide_posting_update({"manual_override": True},
                                {"hourly_wage": 9860, "recruit_until": "2026-07-24"})
    assert "hourly_wage" not in upd          # 사람 수정 보호
    assert "recruit_until" not in upd        # 사람이 확정한 마감도 크롤러가 되돌리지 않음


def test_human_confirmed_deadline_stays_closed_while_content_can_refresh():
    upd = decide_posting_update(
        {"manual_override": False, "deadline_basis": "human_confirmed"},
        {
            "recruit_until": "2026-08-20",
            "deadline_basis": "posted_window",
            "is_active": True,
            "hourly_wage": 10400,
        },
    )
    assert "recruit_until" not in upd
    assert "is_active" not in upd
    assert upd["hourly_wage"] == 10400

def test_none_values_not_written():
    upd = decide_posting_update({"manual_override": False}, {"hourly_wage": None})
    assert "hourly_wage" not in upd

def test_col_sets_disjoint():
    assert MACHINE_COLS.isdisjoint(CONTENT_COLS)

def test_or3_preserves_zero_maps_none():
    from upsert_worksites import _or3
    assert _or3(0) == 0        # 학부만/재학만(falsy)이 3으로 뭉개지면 안 됨
    assert _or3(None) == 3     # 파싱 미상 → 3
    assert _or3(2) == 2


from upsert_worksites import kupid_external_id


def test_kupid_external_id_stable_and_short():
    a = kupid_external_id("[물리학과] 근로", "물리학과", "2026-03-01")
    b = kupid_external_id("[물리학과] 근로", "물리학과", "2026-03-01")
    c = kupid_external_id("[물리학과] 근로", "물리학과", "2026-03-02")
    assert a == b and a != c
    assert len(a) == 16 and a.isalnum()


def test_kupid_external_id_survives_strong_closed_title_marker():
    open_id = kupid_external_id("[학사팀] 근로장학생 모집", "학사팀", "2026-07-01")
    closed_id = kupid_external_id(
        "[학사팀] 근로장학생 모집 (마감)", "학사팀", "2026-07-01"
    )
    assert open_id == closed_id

def test_eligible_pair_mapping():
    from upsert_worksites import eligible_pair
    assert eligible_pair("O", "O") == 2   # 둘 다
    assert eligible_pair("O", "X") == 0   # 앞만(학부/재학)
    assert eligible_pair("X", "O") == 1   # 뒤만(대학원/휴학)
    assert eligible_pair("", "") == 3     # 미상


def test_kupid_canonical_prefers_sonnet_work_department():
    from upsert_worksites import _kupid_row_to_canonical
    row = _kupid_row(
        제목="[이과대학 물리학과] 근로장학생 모집",
        부서명="이과대학행정팀",
        근무부서="물리학과",
    )
    canonical = _kupid_row_to_canonical(row)
    assert canonical["worksite_name"] == "물리학과"
    # 외부 공고 키는 목록 부서명을 계속 사용해 기존 적재 행을 찾아 갱신한다.
    assert canonical["external_id"] == kupid_external_id(
        "[이과대학 물리학과] 근로장학생 모집", "이과대학행정팀", "2026-05-01"
    )


def test_kupid_canonical_falls_back_to_posting_department_when_sonnet_blank():
    from upsert_worksites import _kupid_row_to_canonical
    canonical = _kupid_row_to_canonical(_kupid_row(근무부서=""))
    assert canonical["worksite_name"] == "중앙도서관 학술정보서비스팀"


def test_kupid_physics_title_corrects_old_posting_department_cache_value():
    from upsert_worksites import resolve_kupid_worksite_name
    assert resolve_kupid_worksite_name(
        "[물리학과] 근로장학생 모집", "이과대학행정팀", "이과대학행정팀"
    ) == "물리학과"


def test_kupid_library_titles_keep_the_library_as_worksite():
    from upsert_worksites import resolve_kupid_worksite_name
    assert resolve_kupid_worksite_name(
        "[중앙도서관] 학술정보개발팀 근로장학생 모집", "학술정보개발팀", "중앙도서관"
    ) == "학술정보개발팀"
    assert resolve_kupid_worksite_name(
        "[과학도서관] 학술정보큐레이션팀 근로장학생 모집", "학술정보큐레이션팀", "도서관"
    ) == "과학도서관 학술정보큐레이션팀"


def test_posting_is_active_future_deadline():
    import datetime
    from upsert_worksites import _posting_fields
    f = _posting_fields({"source": "ssc", "external_id": "1", "recruit_until": "2999-01-01"}, datetime.date(2026, 1, 1))
    assert f["is_active"] is True


def test_posting_fields_preserve_attachment_names():
    import datetime
    from upsert_worksites import _posting_fields
    fields = _posting_fields({
        "source": "ssc", "external_id": "1", "attachment_names": ["지원서.hwp"]
    }, datetime.date(2026, 1, 1))
    assert fields["attachment_names"] == ["지원서.hwp"]

def test_posting_is_active_past_deadline():
    import datetime
    from upsert_worksites import _posting_fields
    f = _posting_fields({"source": "ssc", "external_id": "1", "recruit_until": "2020-01-01"}, datetime.date(2026, 1, 1))
    assert f["is_active"] is False


def test_source_closed_posting_is_inactive_even_with_future_deadline():
    from upsert_worksites import _posting_fields
    fields = _posting_fields({
        "source": "kupid",
        "external_id": "closed",
        "recruit_until": "2026-08-20",
        "source_closed_at": "2026-07-29",
        "source_closed_reason": "title_marker",
    }, datetime.date(2026, 7, 29))
    assert fields["is_active"] is False


def test_posting_is_active_fallback_when_no_deadline():
    import datetime
    from upsert_worksites import _posting_fields
    f = _posting_fields({"source": "ssc", "external_id": "1", "recruit_until": ""}, datetime.date(2026, 1, 1))
    assert f["recruit_until"] is None and f["is_active"] is True   # 판정불가→폴백 True(무조건 False 금지)

def test_posting_recruit_until_estimated_threaded():
    import datetime
    from upsert_worksites import _posting_fields
    est = _posting_fields({
        "source": "kupid", "external_id": "1",
        "recruit_until": "2026-05-01", "recruit_until_estimated": True,
        "posted_at": "2026-04-11",
    }, datetime.date(2026, 1, 1))
    assert est["recruit_until_estimated"] is True
    assert est["recruit_until"] == "2026-05-01"
    default = _posting_fields({"source": "ssc", "external_id": "2", "recruit_until": "2026-05-01"}, datetime.date(2026, 1, 1))
    assert default["recruit_until_estimated"] is False


def test_posting_without_source_date_uses_stable_first_seen_date():
    from upsert_worksites import _posting_fields
    fields = _posting_fields(
        {"source": "everytime_manual", "external_id": "1"},
        datetime.date(2026, 7, 29),
        first_seen_at="2026-07-10T15:00:00+00:00",
    )
    assert fields["recruit_until"] == "2026-07-31"
    assert fields["deadline_basis"] == "first_seen_window"

def test_posting_clamps_bad_duration_and_eligible():
    import datetime
    from upsert_worksites import _posting_fields
    f = _posting_fields({"source": "ssc", "external_id": "1", "recruit_until": "2026-05-01", "work_duration_type": "weird", "eligible_degree": 9}, datetime.date(2026, 1, 1))
    assert f["work_duration_type"] == "unknown" and f["eligible_degree"] == 3


def test_posting_clears_copied_recruitment_period():
    from upsert_worksites import _posting_fields
    f = _posting_fields({
        "source": "ssc", "external_id": "1", "recruit_until": "2026-08-02",
        "period_text": "2026.07.21 00:00~2026.08.02 00:00",
        "work_period_text": "2026.07.21 ~ 2026.08.02 (모집기간)",
        "work_duration_type": "long",
    }, datetime.date(2026, 7, 23))
    assert f["work_period_text"] is None
    assert f["work_duration_type"] == "unknown"


def test_posting_keeps_real_work_period():
    from upsert_worksites import _posting_fields
    f = _posting_fields({
        "source": "ssc", "external_id": "1", "recruit_until": "2026-07-24",
        "period_text": "2026.07.20 00:00~2026.07.24 12:00",
        "work_period_text": "2026년 7월 27일(월) ~ 2027년 2월 말",
        "work_duration_type": "long",
    }, datetime.date(2026, 7, 23))
    assert f["work_period_text"] == "2026년 7월 27일(월) ~ 2027년 2월 말"
    assert f["work_duration_type"] == "long"

def test_duration_from_flag():
    from upsert_worksites import _duration
    assert _duration("O") == "short" and _duration("X") == "long" and _duration("") == "unknown"


from upsert_worksites import _kupid_row_to_canonical


def _kupid_row(**over):
    r = {
        "제목": "[중앙도서관] 근로장학생 모집", "부서명": "중앙도서관",
        "등록일": datetime.date(2026, 5, 1), "모집마감일(계산)": datetime.date(2026, 5, 20),
        "시급": 10400, "모집인원": "2명", "마감추정": "X",
        "학부생가능": "O", "대학원생가능": "X", "재학생가능": "O", "휴학생가능": "O",
        "직무내용": "자료정리", "우대조건": "", "기타특이사항": "", "근무기간": "",
        "단기여부": "X", "지원마감일": "", "출처URL": "", "본문(원본)": "본문",
    }
    r.update(over)
    return r


def test_kupid_canonical_preserves_posted_at():
    c = _kupid_row_to_canonical(_kupid_row())
    assert c["posted_at"] == "2026-05-01"          # 등록일 → 게시일자
    assert c["source"] == "kupid"
    assert c["worksite_name"] == "중앙도서관 학술정보서비스팀"
    assert c["hourly_wage"] == 10400


def test_kupid_canonical_external_id_stable():
    a = _kupid_row_to_canonical(_kupid_row())
    b = _kupid_row_to_canonical(_kupid_row())
    assert a["external_id"] == b["external_id"]     # 같은 입력 = 같은 키
    assert a["external_id"] == kupid_external_id("[중앙도서관] 근로장학생 모집", "중앙도서관", "2026-05-01")


def test_kupid_canonical_blank_dept_returns_none():
    assert _kupid_row_to_canonical(_kupid_row(부서명="")) is None


class _Resp:
    def __init__(self, data):
        self.data = data


class _FakePostingsQuery:
    def __init__(self, client, action="select", payload=None):
        self.client = client
        self.action = action
        self.payload = payload
        self.filters = []
        self._limit = None

    def select(self, *_args):
        return self

    def eq(self, key, value):
        self.filters.append((key, value))
        return self

    def limit(self, value):
        self._limit = value
        return self

    def delete(self):
        self.action = "delete"
        return self

    def insert(self, payload):
        self.action = "insert"
        self.payload = payload
        return self

    def update(self, payload):
        self.action = "update"
        self.payload = payload
        return self

    def execute(self):
        if self.action == "select":
            rows = self.client.rows
            for key, value in self.filters:
                rows = [r for r in rows if r.get(key) == value]
            if self._limit is not None:
                rows = rows[:self._limit]
            return _Resp(rows)
        if self.action == "insert":
            self.client.inserted.append(self.payload)
            return _Resp([self.payload])
        if self.action == "delete":
            self.client.deleted = True
            return _Resp([])
        if self.action == "update":
            self.client.updated.append(self.payload)
            return _Resp([self.payload])
        raise AssertionError(f"unknown action: {self.action}")


class _FakeClient:
    def __init__(self, rows):
        self.rows = rows
        self.inserted = []
        self.updated = []
        self.deleted = False

    def table(self, name):
        assert name == "postings"
        return _FakePostingsQuery(self)


def test_upsert_posting_skips_same_worksite_description_deadline_duplicate():
    from upsert_worksites import upsert_posting

    client = _FakeClient([{
        "id": 10,
        "source": "ssc",
        "external_id": "ssc-1",
        "worksite_id": 6755,
        "job_description": "ONE-STOP서비스센터 지원업무",
        "recruit_until": "2026-08-02",
        "is_placeholder": False,
    }])
    result = upsert_posting(client, 6755, {
        "source": "kupid",
        "external_id": "kupid-1",
        "recruit_until": "2026-08-02",
        "job_description": "ONE-STOP서비스센터   지원업무",
    }, datetime.date(2026, 7, 23))

    assert result == "skipped_duplicate"
    assert client.inserted == []
    assert client.deleted is False


def test_source_closure_closes_known_posting_without_reopening_logic():
    from upsert_worksites import apply_source_closures

    client = _FakeClient([{
        "id": 9,
        "source": "kupid",
        "external_id": "closed-1",
        "manual_override": False,
        "source_closed_at": None,
    }])
    changed = apply_source_closures(client, [{
        "source": "kupid",
        "external_id": "closed-1",
        "source_closed_at": "2026-07-29",
        "source_closed_reason": "title_marker",
    }])
    assert changed == 1
    assert client.updated == [{
        "source_closed_at": "2026-07-29",
        "source_closed_reason": "title_marker",
        "is_active": False,
    }]


def test_load_reviewed_never_inserts_pending_or_skipped_records(monkeypatch):
    import upsert_worksites

    resolutions = iter([
        {"status": "pending", "queue_id": 31},
        {"status": "matched", "worksite_id": 55},
        {"status": "skipped", "queue_id": 32},
    ])
    posted = []

    def resolver(_client, _record):
        return next(resolutions)

    def fake_upsert_posting(_client, worksite_id, record, _today):
        posted.append((worksite_id, record["external_id"]))
        return "inserted"

    monkeypatch.setattr(upsert_worksites, "upsert_posting", fake_upsert_posting)
    stats = upsert_worksites.load_reviewed(
        object(),
        [
            {"external_id": "pending"},
            {"external_id": "matched"},
            {"external_id": "skipped"},
        ],
        datetime.date(2026, 7, 28),
        resolver=resolver,
    )

    assert posted == [(55, "matched")]
    assert stats["postings_inserted"] == 1
    assert stats["pending"] == 1
    assert stats["skipped"] == 1
    assert stats["pending_queue_ids"] == [31]
