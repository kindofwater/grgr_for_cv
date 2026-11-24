-- 목적: 30일 열람권 가격을 20P에서 25P로 조정한다.
-- purchase_pass와 refund_pass는 pass_price()를 호출하므로 이 함수만 갱신한다.

create or replace function public.pass_price(p_days int)
returns int
language sql
immutable
as $$
  select case p_days when 7 then 10 when 30 then 25 else null end
$$;

-- 교환센터 안내 공지의 가격 표기도 현재 정책과 맞춘다.
update public.notices
set content = replace(content, '7일 10P·30일 20P', '7일 10P·30일 25P')
where content like '%7일 10P·30일 20P%';
