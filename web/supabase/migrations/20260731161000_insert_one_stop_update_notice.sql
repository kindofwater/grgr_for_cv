-- 고려대학교 ONE-STOP서비스센터 근무지 분리 반영 안내.

insert into public.notices (
  title,
  content,
  is_pinned,
  university_id
)
select
  '[안내] ONE-STOP서비스센터 근무지 정보 업데이트',
  'ONE-STOP서비스센터 근무지 정보가 실제 운영 단위에 맞게 업데이트되었습니다.

- ONE-STOP서비스센터(인문·사회계): 중앙광장 지하 1층 B111호
- ONE-STOP서비스센터(자연계): 하나스퀘어 지하 1층 B107호
- ONE-STOP서비스센터(의료공제): 중앙광장 지하 1층 B112호

기존 ONE-STOP서비스센터에 함께 표시되던 모집 공고와 리뷰도 실제 근무지에 맞게 분리·이전했습니다. 근로장학 지원 및 리뷰 확인 시 근무지 구분을 확인해 주세요.

정확한 정보 제공을 위해 제보해 주신 이용자분께 감사드립니다.',
  false,
  1
where not exists (
  select 1
  from public.notices
  where university_id = 1
    and title = '[안내] ONE-STOP서비스센터 근무지 정보 업데이트'
);
