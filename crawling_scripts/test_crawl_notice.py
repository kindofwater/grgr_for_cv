import datetime

from upsert_worksites import (
    CRAWL_NOTICE_TITLE,
    UNIVERSITY_ID,
    crawl_notice_content,
    crawl_notice_title,
    crawl_notice_week,
    upsert_crawl_notice,
)


class _Response:
    def __init__(self, data):
        self.data = data


class _NoticeQuery:
    def __init__(self, client, action="select", payload=None):
        self.client = client
        self.action = action
        self.payload = payload
        self.filters = []

    def select(self, *_args):
        return self

    def eq(self, key, value):
        self.filters.append((key, value))
        return self

    def limit(self, _value):
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
                rows = [row for row in rows if row.get(key) == value]
            return _Response(rows)
        if self.action == "insert":
            self.client.inserted.append(self.payload)
            return _Response([self.payload])
        if self.action == "update":
            self.client.updated.append((self.filters, self.payload))
            return _Response([self.payload])
        raise AssertionError(f"unknown action: {self.action}")


class _FakeClient:
    def __init__(self, rows=()):
        self.rows = list(rows)
        self.inserted = []
        self.updated = []

    def table(self, name):
        assert name == "notices"
        return _NoticeQuery(self)


def test_crawl_notice_content_has_week_range_titles_and_insert_count():
    assert crawl_notice_content(
        datetime.date(2026, 7, 23),
        4,
        posting_titles=[
            "이과대학행정팀 근로장학생 모집",
            "공과대학원행정팀 근로장학생 모집",
            "이과대학행정팀 근로장학생 모집",
        ],
    ) == (
        "2026년 7월 20일~26일\n"
        "• [이과대학행정팀 근로장학생 모집]\n"
        "• [공과대학원행정팀 근로장학생 모집]\n"
        "총 4건 업데이트 완료되었습니다."
    )


def test_crawl_notice_week_is_monday_through_sunday():
    today = datetime.date(2026, 8, 4)
    assert crawl_notice_week(today) == (
        datetime.date(2026, 8, 3), datetime.date(2026, 8, 9)
    )
    assert crawl_notice_title(today) == "근로장학 공고 업데이트 (8월 3일~9일)"


def test_no_notice_when_the_run_inserted_no_postings():
    client = _FakeClient()
    assert upsert_crawl_notice(client, 0, datetime.date(2026, 7, 23)) is None
    assert client.inserted == [] and client.updated == []


def test_first_notice_is_inserted_for_ku_only():
    client = _FakeClient()
    result = upsert_crawl_notice(
        client,
        2,
        datetime.date(2026, 7, 23),
        posting_titles=["이과대학행정팀 근로장학생 모집", "공과대학원행정팀 근로장학생 모집"],
    )
    assert result == "inserted"
    assert client.inserted == [{
        "title": crawl_notice_title(datetime.date(2026, 7, 23)),
        "content": (
            "2026년 7월 20일~26일\n"
            "• [이과대학행정팀 근로장학생 모집]\n"
            "• [공과대학원행정팀 근로장학생 모집]\n"
            "총 2건 업데이트 완료되었습니다."
        ),
        "university_id": UNIVERSITY_ID,
    }]


def test_existing_notice_is_updated_instead_of_duplicated():
    client = _FakeClient([{
        "id": 99,
        "title": crawl_notice_title(datetime.date(2026, 7, 24)),
        "content": (
            "2026년 7월 20일~26일\n"
            "• [이과대학행정팀 근로장학생 모집]\n"
            "총 2건 업데이트 완료되었습니다."
        ),
        "university_id": UNIVERSITY_ID,
    }])
    result = upsert_crawl_notice(
        client,
        3,
        datetime.date(2026, 7, 24),
        posting_titles=["학생지원팀 근로장학생 모집"],
    )
    assert result == "updated"
    assert client.inserted == []
    assert client.updated[0][0] == [("id", 99)]
    assert client.updated[0][1]["content"] == (
        "2026년 7월 20일~26일\n"
        "• [이과대학행정팀 근로장학생 모집]\n"
        "• [학생지원팀 근로장학생 모집]\n"
        "총 5건 업데이트 완료되었습니다."
    )
    assert "updated_at" in client.updated[0][1]


def test_next_week_creates_a_new_notice():
    client = _FakeClient([{
        "id": 99,
        "title": crawl_notice_title(datetime.date(2026, 7, 24)),
        "university_id": UNIVERSITY_ID,
    }])
    result = upsert_crawl_notice(
        client,
        1,
        datetime.date(2026, 7, 27),
        posting_titles=["학생지원팀 근로장학생 모집"],
    )
    assert result == "inserted"
    assert client.inserted[0]["title"] == "근로장학 공고 업데이트 (7월 27일~8월 2일)"
