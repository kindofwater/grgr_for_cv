-- 목적: KUPID 학교근장 근무지 분리(A안) — 게시부서명으로 뭉친 공고를 실제 근무지로 이동
-- 날짜: 2026-07-20 · 담당: 배경록
--
-- 배경: KUPID 부서명=게시 부서라, 행정팀이 대신 올린 학과 공고가 행정팀 근무지로 적재됨.
--   제목 대괄호·본문·근무장소 대조로 7개 근무지 분리(물리학과 12·화학과 1·현장실습지원센터 3·
--   경영전문대학원 3·생명환경과학대학원 1·정책·융데 1·융합에너지공학과 2 = 23건 이동).
-- 방식: wipe 없이 수술식 UPDATE(worksite_id) — 기존 근무지·리뷰 보존. source_url(공고 고유)로 매칭.
-- 부수: 이과대학행정팀 주소 436B호(물리학과 사무실 오염)→103호 정정 · 교직팀→'사범대학 부설 교육연수원'
--   개명 · 공과대학행정실은 비면(공고 0·리뷰 0) soft-delete. 끝에 건수 자가검증(불일치 시 예외=적용 중단).

begin;

-- 1) 새 근무지 생성(이미 있으면 생략 — 멱등)
insert into worksites (university_id, type, location_type, organization_name, workplace_name, region, address)
select 1, 'school', 'on_campus', '고려대학교(본교)', '물리학과', null, '아산이학관 436B호'
where not exists (select 1 from worksites where university_id = 1 and type = 'school' and workplace_name = '물리학과' and deleted_at is null);

insert into worksites (university_id, type, location_type, organization_name, workplace_name, region, address)
select 1, 'school', 'on_campus', '고려대학교(본교)', '화학과', null, '아산이학관 334A호'
where not exists (select 1 from worksites where university_id = 1 and type = 'school' and workplace_name = '화학과' and deleted_at is null);

insert into worksites (university_id, type, location_type, organization_name, workplace_name, region, address)
select 1, 'school', 'on_campus', '고려대학교(본교)', '현장실습지원센터', null, '4.18 기념관 103호'
where not exists (select 1 from worksites where university_id = 1 and type = 'school' and workplace_name = '현장실습지원센터' and deleted_at is null);

insert into worksites (university_id, type, location_type, organization_name, workplace_name, region, address)
select 1, 'school', 'on_campus', '고려대학교(본교)', '경영전문대학원행정팀', null, '경영본관 307호'
where not exists (select 1 from worksites where university_id = 1 and type = 'school' and workplace_name = '경영전문대학원행정팀' and deleted_at is null);

insert into worksites (university_id, type, location_type, organization_name, workplace_name, region, address)
select 1, 'school', 'on_campus', '고려대학교(본교)', '생명환경과학대학원행정실', null, '생명과학관동관 219호'
where not exists (select 1 from worksites where university_id = 1 and type = 'school' and workplace_name = '생명환경과학대학원행정실' and deleted_at is null);

insert into worksites (university_id, type, location_type, organization_name, workplace_name, region, address)
select 1, 'school', 'on_campus', '고려대학교(본교)', '정책대학원·융합데이터과학대학원 행정팀', null, 'SK미래관 515호'
where not exists (select 1 from worksites where university_id = 1 and type = 'school' and workplace_name = '정책대학원·융합데이터과학대학원 행정팀' and deleted_at is null);

insert into worksites (university_id, type, location_type, organization_name, workplace_name, region, address)
select 1, 'school', 'on_campus', '고려대학교(본교)', '융합에너지공학과', null, '공학관 169호'
where not exists (select 1 from worksites where university_id = 1 and type = 'school' and workplace_name = '융합에너지공학과' and deleted_at is null);

-- 2) 공고 이동 — 현재 근무지 + source_url 이중 조건(다른 공고 오이동 방지)
update postings p set worksite_id = t.id
from worksites w, worksites t
where p.worksite_id = w.id
  and w.university_id = 1 and w.type = 'school' and w.workplace_name in ('이과대학행정실', '이과대학행정팀')
  and t.university_id = 1 and t.type = 'school' and t.workplace_name = '물리학과' and t.deleted_at is null
  and p.source_url in (
    'https://portal.korea.ac.kr/p/BO06?encQS=hMHVHi3u3QvCp8G06ziRODK5Ip9tC8vAODgRX9AqEX7clBzzoyHriiNUi8LIbyUWviOU2ZJ0oXTZ%0AUPT29rPuz1xmRzqc5c38i%2B1J9gg2j%2BK4WrGrgTLtaswoWcDylVq%2FW8Q%2FHiHBbKdI%2B%2FLbLzByNw%3D%3D',
    'https://portal.korea.ac.kr/p/BO06?encQS=hMHVHi3u3QvCp8G06ziRODK5Ip9tC8vAODgRX9AqEX7clBzzoyHriiNUi8LIbyUWviOU2ZJ0oXTZ%0AUPT29rPuz1xmRzqc5c38i%2B1J9gg2j%2BK4WrGrgTLtaswoWcDylVq%2FRXBycc7H2xxQl2yaQ91P3A%3D%3D',
    'https://portal.korea.ac.kr/p/BO06?encQS=hMHVHi3u3QvCp8G06ziRODlA9C6v2bpTw3vlkljA0%2BnclBzzoyHriiNUi8LIbyUWviOU2ZJ0oXTZ%0AUPT29rPuz1xmRzqc5c38i%2B1J9gg2j%2BK4WrGrgTLtaswoWcDylVq%2FjVDkyAevTU42TtXyRZcs5g%3D%3D',
    'https://portal.korea.ac.kr/p/BO06?encQS=hMHVHi3u3QvCp8G06ziROFLLD59Pl5RyKFM5w72NME%2FclBzzoyHriiNUi8LIbyUWviOU2ZJ0oXTZ%0AUPT29rPuz1xmRzqc5c38i%2B1J9gg2j%2BIaC2PvLWUhbdbLAeYLgmu9fau5HZiWkuKKmNpNbWCi9A%3D%3D',
    'https://portal.korea.ac.kr/p/BO06?encQS=hMHVHi3u3QvCp8G06ziROFLLD59Pl5RyKFM5w72NME%2FclBzzoyHriiNUi8LIbyUWviOU2ZJ0oXTZ%0AUPT29rPuz1xmRzqc5c38i%2B1J9gg2j%2BIaC2PvLWUhbdbLAeYLgmu9BELgCjNoViu8SCQuWu76iA%3D%3D',
    'https://portal.korea.ac.kr/p/BO06?encQS=hMHVHi3u3QvCp8G06ziROFfkYSbU%2Fq8%2FG1ReSYpfoKnclBzzoyHriiNUi8LIbyUWviOU2ZJ0oXTZ%0AUPT29rPuz1xmRzqc5c38i%2B1J9gg2j%2BIaC2PvLWUhbdbLAeYLgmu92F6jgNtjifdHBEaBY0mZpg%3D%3D',
    'https://portal.korea.ac.kr/p/BO06?encQS=hMHVHi3u3QvCp8G06ziRODX0ahNl6peTZGvKkiwT7TnclBzzoyHriiNUi8LIbyUWviOU2ZJ0oXTZ%0AUPT29rPuz1xmRzqc5c38i%2B1J9gg2j%2BIR6VG5q99Z9V9k%2BYX9ddnU6eThZEoRMMKoD91NmMyVwQ%3D%3D',
    'https://portal.korea.ac.kr/p/BO06?encQS=hMHVHi3u3QvCp8G06ziROCnkfvG7NLbZkPpSszMpJgHclBzzoyHriiNUi8LIbyUWviOU2ZJ0oXTZ%0AUPT29rPuz1xmRzqc5c38i%2B1J9gg2j%2BIR6VG5q99Z9V9k%2BYX9ddnUUiIv6yutVRlTCzFjWyk7cA%3D%3D',
    'https://portal.korea.ac.kr/p/BO06?encQS=hMHVHi3u3QvCp8G06ziROBbFaV2aQRl%2BI99oY9xMRTKHP4HPZUqmcBMWYx6Xzay44z6Mb4pD97wI%0Akm%2BrTtWWZhAsVSwrLCCGET3szFoHs%2FUdIrClTAvPTrIAhV6bRXk9jR3DAnoKQM%2BqajQcVK%2BsKg%3D%3D',
    'https://portal.korea.ac.kr/p/BO06?encQS=hMHVHi3u3QvCp8G06ziRON1GV2i6ZVNGkJU3UEXaSheHP4HPZUqmcBMWYx6Xzay44z6Mb4pD97wI%0Akm%2BrTtWWZhAsVSwrLCCGET3szFoHs%2FUdIrClTAvPTrIAhV6bRXk9sYvUGgPVZ1iCxuW59MeK9Q%3D%3D',
    'https://portal.korea.ac.kr/p/BO06?encQS=hMHVHi3u3QvCp8G06ziROJJUxmKqcbWFCfJcNHFDGN%2BHP4HPZUqmcBMWYx6Xzay44z6Mb4pD97wI%0Akm%2BrTtWWZhAsVSwrLCCGET3szFoHs%2FUdIrClTAvPTrIAhV6bRXk9Nz8V62nRCqA4jAfEYDFiNQ%3D%3D',
    'https://portal.korea.ac.kr/p/BO06?encQS=hMHVHi3u3QvCp8G06ziROEw6gDD%2BmNKr5no1r8IuzV%2BHP4HPZUqmcBMWYx6Xzay44z6Mb4pD97wI%0Akm%2BrTtWWZhAsVSwrLCCGET3szFoHs%2FUdIrClTAvPTrIAhV6bRXk9eKcdJfCP7Q%2FGV5Der2mtRQ%3D%3D'
  );

update postings p set worksite_id = t.id
from worksites w, worksites t
where p.worksite_id = w.id
  and w.university_id = 1 and w.type = 'school' and w.workplace_name in ('이과대학행정실', '이과대학행정팀')
  and t.university_id = 1 and t.type = 'school' and t.workplace_name = '화학과' and t.deleted_at is null
  and p.source_url in (
    'https://portal.korea.ac.kr/p/BO06?encQS=hMHVHi3u3QvCp8G06ziROFZLazBbcy2jt71Kd6Zr9uuHP4HPZUqmcBMWYx6Xzay44z6Mb4pD97wI%0Akm%2BrTtWWZhAsVSwrLCCGET3szFoHs%2FUdIrClTAvPTrIAhV6bRXk9IYfrevIpHFUInYJb5QmxNA%3D%3D'
  );

update postings p set worksite_id = t.id
from worksites w, worksites t
where p.worksite_id = w.id
  and w.university_id = 1 and w.type = 'school' and w.workplace_name in ('Student Success Center')
  and t.university_id = 1 and t.type = 'school' and t.workplace_name = '현장실습지원센터' and t.deleted_at is null
  and p.source_url in (
    'https://portal.korea.ac.kr/p/BO06?encQS=hMHVHi3u3QvCp8G06ziROBbFaV2aQRl%2BI99oY9xMRTKHP4HPZUqmcBMWYx6Xzay44z6Mb4pD97wI%0Akm%2BrTtWWZhAsVSwrLCCGET3szFoHs%2FUdIrClTAvPTrIAhV6bRXk9rqlbQi8VFtbuq55lhwtSew%3D%3D',
    'https://portal.korea.ac.kr/p/BO06?encQS=hMHVHi3u3QvCp8G06ziROJJUxmKqcbWFCfJcNHFDGN%2BHP4HPZUqmcBMWYx6Xzay44z6Mb4pD97wI%0Akm%2BrTtWWZhAsVSwrLCCGET3szFoHs%2FUdIrClTAvPTrIAhV6bRXk9R6hMHPSlJoQmuwrATWKl0Q%3D%3D',
    'https://portal.korea.ac.kr/p/BO06?encQS=hMHVHi3u3QvCp8G06ziROJENgJMxncc%2F2M8c7rwInp6HP4HPZUqmcBMWYx6Xzay44z6Mb4pD97wI%0Akm%2BrTtWWZhAsVSwrLCCGET3szFoHs%2FUdIrClTAvPTrIAhV6bRXk9GeozmQV0ik9%2BKpT%2Fu5PpfA%3D%3D'
  );

update postings p set worksite_id = t.id
from worksites w, worksites t
where p.worksite_id = w.id
  and w.university_id = 1 and w.type = 'school' and w.workplace_name in ('경영대학행정팀')
  and t.university_id = 1 and t.type = 'school' and t.workplace_name = '경영전문대학원행정팀' and t.deleted_at is null
  and p.source_url in (
    'https://portal.korea.ac.kr/p/BO06?encQS=hMHVHi3u3QvCp8G06ziROK4FY9SCTWNOGz0ajU8VAH%2FclBzzoyHriiNUi8LIbyUWviOU2ZJ0oXTZ%0AUPT29rPuz1xmRzqc5c38i%2B1J9gg2j%2BK4WrGrgTLtaswoWcDylVq%2F3kqVi%2FwGOePcb8CudH%2B9Dw%3D%3D',
    'https://portal.korea.ac.kr/p/BO06?encQS=hMHVHi3u3QvCp8G06ziRODX0ahNl6peTZGvKkiwT7TnclBzzoyHriiNUi8LIbyUWviOU2ZJ0oXTZ%0AUPT29rPuz1xmRzqc5c38i%2B1J9gg2j%2BIR6VG5q99Z9V9k%2BYX9ddnUijdZq3ueK0%2Fk%2B6Dtsg0bZw%3D%3D',
    'https://portal.korea.ac.kr/p/BO06?encQS=hMHVHi3u3QvCp8G06ziROLtUWo5psGx8tfq5d78NPjvclBzzoyHriiNUi8LIbyUWviOU2ZJ0oXTZ%0AUPT29rPuz1xmRzqc5c38i%2B1J9gg2j%2BLXmkRbWVxsSGSIOpu6LOemmJtaPPOAdRkb4xdh2NuB0Q%3D%3D'
  );

update postings p set worksite_id = t.id
from worksites w, worksites t
where p.worksite_id = w.id
  and w.university_id = 1 and w.type = 'school' and w.workplace_name in ('생명과학대학행정팀')
  and t.university_id = 1 and t.type = 'school' and t.workplace_name = '생명환경과학대학원행정실' and t.deleted_at is null
  and p.source_url in (
    'https://portal.korea.ac.kr/p/BO06?encQS=hMHVHi3u3QvCp8G06ziROEKn9Ns%2BhQz39QOlCeCGYrWHP4HPZUqmcBMWYx6Xzay44z6Mb4pD97wI%0Akm%2BrTtWWZhAsVSwrLCCGET3szFoHs%2FUdIrClTAvPTrIAhV6bRXk9neLGFr4Onovaq1d9qXUmLA%3D%3D'
  );

update postings p set worksite_id = t.id
from worksites w, worksites t
where p.worksite_id = w.id
  and w.university_id = 1 and w.type = 'school' and w.workplace_name in ('정경대학행정팀')
  and t.university_id = 1 and t.type = 'school' and t.workplace_name = '정책대학원·융합데이터과학대학원 행정팀' and t.deleted_at is null
  and p.source_url in (
    'https://portal.korea.ac.kr/p/BO06?encQS=hMHVHi3u3QvCp8G06ziROK4FY9SCTWNOGz0ajU8VAH%2FclBzzoyHriiNUi8LIbyUWviOU2ZJ0oXTZ%0AUPT29rPuz1xmRzqc5c38i%2B1J9gg2j%2BK4WrGrgTLtaswoWcDylVq%2F46p%2BrVe681Y8vh4j4CoLIg%3D%3D'
  );

update postings p set worksite_id = t.id
from worksites w, worksites t
where p.worksite_id = w.id
  and w.university_id = 1 and w.type = 'school' and w.workplace_name in ('공과대학행정실', '공과대학행정팀')
  and t.university_id = 1 and t.type = 'school' and t.workplace_name = '융합에너지공학과' and t.deleted_at is null
  and p.source_url in (
    'https://portal.korea.ac.kr/p/BO06?encQS=hMHVHi3u3QvCp8G06ziROFZLazBbcy2jt71Kd6Zr9uuHP4HPZUqmcBMWYx6Xzay44z6Mb4pD97wI%0Akm%2BrTtWWZhAsVSwrLCCGET3szFoHs%2FUdIrClTAvPTrIAhV6bRXk9UkW5SdHND2wv%2B%2Fn1LxyaKw%3D%3D',
    'https://portal.korea.ac.kr/p/BO06?encQS=hMHVHi3u3QvCp8G06ziROJENgJMxncc%2F2M8c7rwInp6HP4HPZUqmcBMWYx6Xzay44z6Mb4pD97wI%0Akm%2BrTtWWZhAsVSwrLCCGET3szFoHs%2FUdIrClTAvPTrIAhV6bRXk93IAWNfbXClHeFYzb5YHRTQ%3D%3D'
  );

-- 3) 이과대학행정팀 주소 정정(436B호=물리학과 사무실 → 행정팀 공고 기재 103호)
update worksites set address = '아산이학관 103호'
where university_id = 1 and type = 'school' and workplace_name = '이과대학행정팀' and deleted_at is null;

-- 4) 교직팀 → 실제 근무지명으로 개명(공고 1건 전부 교육연수원 연수 보조)
update worksites set workplace_name = '사범대학 부설 교육연수원', address = '운초우선교육관'
where university_id = 1 and type = 'school' and workplace_name = '교직팀' and deleted_at is null;

-- 5) 공과대학행정실: 유일 공고(융합에너지공학과)가 빠져 빈 껍데기면 soft-delete(리뷰 있으면 보존)
update worksites w set deleted_at = now()
where w.university_id = 1 and w.type = 'school' and w.workplace_name = '공과대학행정실' and w.deleted_at is null
  and not exists (select 1 from postings p where p.worksite_id = w.id)
  and not exists (select 1 from reviews r where r.worksite_id = w.id);

-- 6) 자가검증 — 근무지별 최종 공고 수(기존 부서명 공고 + 이동분)가 기대와 다르면 롤백
do $$
declare n int;
begin
  select count(*) into n from postings p join worksites w on w.id = p.worksite_id
    where w.university_id = 1 and w.type = 'school' and w.workplace_name = '물리학과' and w.deleted_at is null;
  if n <> 12 then raise exception '물리학과: 공고 %건(기대 12)', n; end if;
  select count(*) into n from postings p join worksites w on w.id = p.worksite_id
    where w.university_id = 1 and w.type = 'school' and w.workplace_name = '화학과' and w.deleted_at is null;
  if n <> 1 then raise exception '화학과: 공고 %건(기대 1)', n; end if;
  select count(*) into n from postings p join worksites w on w.id = p.worksite_id
    where w.university_id = 1 and w.type = 'school' and w.workplace_name = '현장실습지원센터' and w.deleted_at is null;
  if n <> 6 then raise exception '현장실습지원센터: 공고 %건(기대 6)', n; end if;
  select count(*) into n from postings p join worksites w on w.id = p.worksite_id
    where w.university_id = 1 and w.type = 'school' and w.workplace_name = '경영전문대학원행정팀' and w.deleted_at is null;
  if n <> 6 then raise exception '경영전문대학원행정팀: 공고 %건(기대 6)', n; end if;
  select count(*) into n from postings p join worksites w on w.id = p.worksite_id
    where w.university_id = 1 and w.type = 'school' and w.workplace_name = '생명환경과학대학원행정실' and w.deleted_at is null;
  if n <> 2 then raise exception '생명환경과학대학원행정실: 공고 %건(기대 2)', n; end if;
  select count(*) into n from postings p join worksites w on w.id = p.worksite_id
    where w.university_id = 1 and w.type = 'school' and w.workplace_name = '정책대학원·융합데이터과학대학원 행정팀' and w.deleted_at is null;
  if n <> 1 then raise exception '정책대학원·융합데이터과학대학원 행정팀: 공고 %건(기대 1)', n; end if;
  select count(*) into n from postings p join worksites w on w.id = p.worksite_id
    where w.university_id = 1 and w.type = 'school' and w.workplace_name = '융합에너지공학과' and w.deleted_at is null;
  if n <> 2 then raise exception '융합에너지공학과: 공고 %건(기대 2)', n; end if;
end $$;

commit;
