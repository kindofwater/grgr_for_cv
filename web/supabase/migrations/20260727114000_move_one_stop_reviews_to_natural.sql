-- 목적: 기존 일반 ONE-STOP서비스센터 리뷰를 자연계 ONE-STOP서비스센터로 옮긴다.
-- 날짜: 2026-07-27 · 담당: 배경록
--
-- 현재 리뷰는 제목에 'ONE-STOP서비스센터(자연계)'가 명시된 KUPID 공고의 근무 경험이다.
-- 본문의 인문사회계 표기는 지원 대상이므로, 리뷰의 실제 근무지는 자연계 창구로 본다.

update public.reviews r
set worksite_id = target.id,
    updated_at = now()
from public.worksites current_worksite
join public.worksites target
  on target.university_id = 1
 and target.type = 'school'
 and target.workplace_name = '자연계 ONE-STOP서비스센터'
 and target.deleted_at is null
where r.worksite_id = current_worksite.id
  and current_worksite.university_id = 1
  and current_worksite.type = 'school'
  and current_worksite.workplace_name = 'ONE-STOP서비스센터'
  and current_worksite.deleted_at is null
  and r.deleted_at is null;
