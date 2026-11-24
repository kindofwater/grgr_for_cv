-- Estimated KUPID deadlines use one deterministic cascade:
-- explicit deadline (not estimated) -> 15 calendar days including posted day
-- -> work-start-day-minus-one only when a posted date is unavailable.
--
-- Existing estimated rows all preserve the source posting date in created_at,
-- so normalize them to the 15-day window. Explicit deadlines are untouched.

begin;

update public.postings
set recruit_until = (
      (created_at at time zone 'Asia/Seoul')::date + 14
    ),
    is_active = (
      (created_at at time zone 'Asia/Seoul')::date + 14
      >= (now() at time zone 'Asia/Seoul')::date
    ),
    updated_at = now()
where source = 'kupid'
  and recruit_until_estimated is true
  and created_at is not null
  and deleted_at is null
  and (
    recruit_until is distinct from (
      (created_at at time zone 'Asia/Seoul')::date + 14
    )
    or is_active is distinct from (
      (created_at at time zone 'Asia/Seoul')::date + 14
      >= (now() at time zone 'Asia/Seoul')::date
    )
  );

commit;
