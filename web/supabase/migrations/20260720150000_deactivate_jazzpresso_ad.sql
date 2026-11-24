-- 목적: 시드 광고(재즈프레소) 노출 중단 — is_active=false
-- 날짜: 2026-07-20 · 담당: 배경록
-- 배경: 2026-06-24 리워드 광고 배포 때 넣은 시드 소재다(배포 런북의 잔여 액션 ⓐ "최종 광고
--   소재 교체"). 실제 광고주 계약 건이 아니라 노출을 멈춘다.
-- ⚠️ DELETE 하지 않는다: ad_views.ad_id / ad_clicks.ad_id 가 on delete set null 이라
--   행을 지우면 과거 시청·클릭 기록의 광고 연결이 끊긴다(첫 광고주에게 보여줄 실측 실적).
--   is_active=false 면 노출만 멈추고 기록은 남으며 되돌리기도 쉽다.
do $$
declare v_n int;
begin
  update ads
     set is_active = false
   where is_active
     and (title ilike '%재즈프레소%' or title ilike '%jazz%');
  get diagnostics v_n = row_count;

  if v_n = 0 then
    -- 조용한 no-op 방지: 대상 자체가 없으면 title 표기가 다른 것이므로 실패시켜 알린다.
    -- (이미 비활성이면 대상은 존재하므로 통과 — 재실행 안전)
    if not exists (select 1 from ads where title ilike '%재즈프레소%' or title ilike '%jazz%') then
      raise exception '재즈프레소 광고를 찾지 못했습니다 — ads.title 표기를 확인하세요';
    end if;
    raise notice '이미 비활성 상태입니다 (멱등 no-op)';
  else
    raise notice '재즈프레소 광고 %건 비활성화', v_n;
  end if;

  -- 안전장치: 활성 광고가 0개가 되면 start_ad_view가 NO_ADS로 터져 리워드 플로우가 통째로 죽는다
  -- (사용자는 포인트를 못 벌고 → 열람권도 못 산다). 그런 상태로는 커밋시키지 않는다.
  if (select count(*) from ads where is_active) = 0 then
    raise exception '활성 광고가 0개가 됩니다 — 리워드 광고가 NO_ADS로 중단됩니다. 대체 소재를 먼저 넣으세요';
  end if;

  raise notice '남은 활성 광고: %건', (select count(*) from ads where is_active);
end $$;
