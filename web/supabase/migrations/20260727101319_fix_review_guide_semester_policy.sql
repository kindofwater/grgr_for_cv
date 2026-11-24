-- 목적: 리뷰 작성 안내의 중복 정책을 실제 DB 제약과 일치시킨다.
-- 정본: reviews_user_year_semester_key = 사용자별 근무 연도·학기당 1리뷰(근무지 무관).

update public.notices
set content = replace(
      content,
      '같은 근무지의 같은 학기에는 리뷰를 1개만 작성할 수 있습니다. 이미 작성한 리뷰가 있다면 새로 등록하는 대신 기존 리뷰를 수정할 수 있습니다.',
      '리뷰는 근무지와 관계없이 한 학기에 1개만 작성할 수 있습니다. 해당 학기에 이미 작성한 리뷰가 있다면 새로 등록하는 대신 기존 리뷰를 수정할 수 있습니다.'
    ),
    updated_at = now()
where university_id is null
  and title = '[필독] 리뷰 작성 방법 안내';
