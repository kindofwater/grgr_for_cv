-- 목적: report_status_e에 실제 처리 결말 2종('blinded'·'moved') 추가 — 신고를 정확한 상태로 닫기 위해
-- 날짜: 2026-08-14 · 담당: 배경록
--
-- 왜: 기존 값은 pending/deleted/ignored 뿐인데, 지금까지 처리한 신고의 결말이 둘 다 여기 안 들어간다.
--   · 신고 2(리뷰 63) → 허위가 아니라 **근무지 오배정**이어서 재배정(6794→6823). 20260810141449가
--     "enum에 '이동 조치'에 맞는 값이 없다. 필요하면 별도 마이그레이션에서 enum 확장"이라 남겨둔 지점이다.
--   · 신고 3(리뷰 119) → 허위로 확정해 **블라인드**(+작성자 제재, 20260814071343). 리뷰를 지운 게 아니다.
--   'ignored'로 닫으면 "무시함"이 되어 사실과 정반대고, 'deleted'는 삭제한 적이 없으니 거짓이다.
--   상태값은 운영자가 큐를 훑을 때 "이건 어떻게 끝났나"를 바로 읽는 용도라, 뭉뚱그린 'resolved' 대신
--   두 결말을 그대로 남긴다(둘 다 이 저장소에서 재발하는 조치다 — 블라인드는 §③의 표준 수단,
--   재배정은 '미디어' 검색 오선택처럼 근무지 오배정이 원인일 때).
--
-- 값 의미 (확장 후 5종):
--   pending  = 미처리
--   deleted  = 신고가 타당해 리뷰를 삭제함
--   ignored  = 신고가 부당하거나 조치할 내용이 없어 무시함
--   blinded  = 신고가 타당해 리뷰를 블라인드 처리함(삭제 아님 — 목록엔 placeholder가 남는다)
--   moved    = 허위가 아니라 근무지 오배정이어서 리뷰를 올바른 근무지로 재배정함
--
-- ⚠️ **이 파일에 begin/commit을 넣지 말 것.** `ALTER TYPE ... ADD VALUE`로 추가한 값은
--   **같은 트랜잭션 안에서 사용할 수 없다**(Postgres 제약). 그래서 값 추가(이 파일)와
--   행 갱신(20260814081602)을 두 파일로 나눴다. 한 파일에 합치면 UPDATE가
--   "unsafe use of new value of enum type" 으로 실패한다.
-- ⚠️ Postgres는 enum 값을 **제거할 수 없다** — 되돌리려면 타입을 다시 만들어야 한다.
-- 멱등: IF NOT EXISTS라 재실행·reset 재생 모두 안전.

alter type public.report_status_e add value if not exists 'blinded';
alter type public.report_status_e add value if not exists 'moved';
