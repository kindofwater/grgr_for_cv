import pandas as pd
from supabase import create_client
import os
from dotenv import load_dotenv
import sys

sys.stdout.reconfigure(encoding='utf-8')

load_dotenv(dotenv_path=os.path.join(os.path.dirname(__file__), '..', 'web', '.env.local'))
SUPABASE_URL = os.getenv('VITE_SUPABASE_URL')
SUPABASE_KEY = os.getenv('VITE_SUPABASE_ANON_KEY')
supabase = create_client(SUPABASE_URL, SUPABASE_KEY)

BATCH_SIZE = 500

def batch_insert(table: str, rows: list):
    inserted = []
    for i in range(0, len(rows), BATCH_SIZE):
        res = supabase.table(table).insert(rows[i:i+BATCH_SIZE]).execute()
        inserted.extend(res.data)
        print(f'  {table}: {min(i+BATCH_SIZE, len(rows))}/{len(rows)} 삽입')
    return inserted

# ──────────────────────────────────────────────
# 1. 고려대학교 서울캠퍼스 university_id
# ──────────────────────────────────────────────
res = supabase.table('universities').select('id').eq('name', '고려대학교').eq('campus', '서울').execute()
if res.data:
    university_id = res.data[0]['id']
else:
    res = supabase.table('universities').insert({'name': '고려대학교', 'campus': '서울', 'email_domain': 'korea.ac.kr'}).execute()
    university_id = res.data[0]['id']
print(f'university_id: {university_id}')

# ──────────────────────────────────────────────
# 헬퍼 함수들
# ──────────────────────────────────────────────
def parse_min_grade(val):
    if pd.isna(val) or val in ('상관없음', '1학년이상'):
        return None
    try:
        return int(str(val)[0])
    except:
        return None

def parse_preferred_track(val):
    if pd.isna(val) or val == '상관없음':
        return None
    return str(val)

def parse_eligible_degree(undergrad, grad):
    u = str(undergrad).strip() == 'O'
    g = str(grad).strip() == 'O'
    if u and g: return 2
    if u: return 0
    if g: return 1
    return 3

def parse_eligible_status(enrolled, leave):
    e = str(enrolled).strip() == 'O'
    l = str(leave).strip() == 'O'
    if e and l: return 2
    if e: return 0
    if l: return 1
    return 3

def parse_location_type(val):
    return 'off_campus' if str(val).strip() == 'O' else 'on_campus'

def parse_is_active(val):
    v = str(val).strip()
    if v == '모집중': return True
    if v == '마감':  return False
    return v != 'O'  # KOSAF fallback

def parse_recruitment_period(row):
    if pd.notna(row.get('지원마감일')):
        return str(row['지원마감일'])
    if pd.notna(row.get('게시기한')):
        return str(row['게시기한'])
    return None

def s(val):
    return str(val) if pd.notna(val) else None

# ──────────────────────────────────────────────
# 2. KOSAF 처리
# ──────────────────────────────────────────────
print('\nKOSAF 데이터 처리 중...')
kosaf = pd.read_excel('c:/새 폴더/kosaf_jobs.xlsx')
kosaf = kosaf.dropna(subset=['근로장학기관', '근로지'])

# 2-1. 중복 제거된 worksites 목록
unique_worksites = kosaf.drop_duplicates(subset=['근로장학기관', '근로지', '근로지(부서)주소'])
print(f'  고유 근무지: {len(unique_worksites)}개')

# 2-2. 이미 DB에 있는 worksites 가져오기 (페이지네이션)
def fetch_all_worksites(university_id, ws_type):
    result = []
    page = 0
    while True:
        batch = supabase.table('worksites').select('id,organization_name,workplace_name,address') \
            .eq('university_id', university_id).eq('type', ws_type) \
            .range(page * 1000, (page + 1) * 1000 - 1).execute().data
        result.extend(batch)
        if len(batch) < 1000:
            break
        page += 1
    return result

existing = fetch_all_worksites(university_id, 'national')
worksite_cache = {(r['organization_name'], r['workplace_name'], r.get('address')): r['id'] for r in existing}

# 2-3. 새 worksites만 삽입
new_worksites = []
for _, row in unique_worksites.iterrows():
    key = (str(row['근로장학기관']), str(row['근로지']), s(row['근로지(부서)주소']))
    if key not in worksite_cache:
        new_worksites.append({
            'university_id':     university_id,
            'type':              'national',
            'location_type':     'off_campus',
            'national_work_term': 'vacation',
            'organization_name': key[0],
            'workplace_name':    key[1],
            'region':            s(row['지역']),
            'address':           s(row['근로지(부서)주소']),
        })

if new_worksites:
    print(f'  새 근무지 {len(new_worksites)}개 삽입 중...')
    inserted = batch_insert('worksites', new_worksites)
    # 삽입 결과를 직접 cache에 추가
    for r in inserted:
        worksite_cache[(r['organization_name'], r['workplace_name'], r.get('address'))] = r['id']

print(f'  KOSAF worksite_cache 크기: {len(worksite_cache)}')

# 2-5. postings 배치 삽입
posting_rows = []
for _, row in kosaf.iterrows():
    key = (str(row['근로장학기관']), str(row['근로지']), s(row['근로지(부서)주소']))
    wid = worksite_cache.get(key)
    if not wid:
        continue
    posting_rows.append({
        'worksite_id':             wid,
        'source_url':              'https://www.kosaf.go.kr/ko/main.do',
        'job_category':            s(row['직무내용']),
        'preferred_track':         parse_preferred_track(row['선호학과']),
        'preferred_college':       None,
        'preferred_dept':          None,
        'recruit_count':           s(row['모집(명)']),
        'min_grade':               parse_min_grade(row['선호학년']),
        'eligible_degree':         3,
        'eligible_status':         3,
        'job_description':         s(row['상세직무내용']),
        'preference_notes':        s(row['비고(요구업무능력)']),
        'extra_notes':             None,
        'hourly_wage':             12430,
        'work_period_text':        s(row['근로기간']),
        'work_duration_type':      'unknown',
        'work_time_text':          s(row['근로시간']),
        'recruitment_period_text': None,
        'raw_text':                None,
        'is_active':               False,
        'contact_name':            s(row['담당자']),
        'contact_phone':           s(row['연락처']),
        'contact_email':           s(row['이메일']),
    })

print(f'  postings {len(posting_rows)}개 삽입 중...')
batch_insert('postings', posting_rows)
print(f'KOSAF 완료!')

# ──────────────────────────────────────────────
# 3. KUPID 처리
# ──────────────────────────────────────────────
print('\nKUPID 데이터 처리 중...')
kupid = pd.read_excel('c:/새 폴더/kupid_parsed_result.xlsx')
kupid = kupid.dropna(subset=['부서명'])

# 3-1. 중복 제거된 worksites
unique_kupid = kupid.drop_duplicates(subset=['부서명'])
print(f'  고유 근무지: {len(unique_kupid)}개')

# 3-2. 이미 DB에 있는 worksites
existing_k = fetch_all_worksites(university_id, 'school')
kupid_cache = {(r['organization_name'], r['workplace_name']): r['id'] for r in existing_k}

# 3-3. 새 worksites 삽입
new_kupid_ws = []
for _, row in unique_kupid.iterrows():
    key = ('고려대학교 서울캠퍼스', str(row['부서명']))
    if key not in kupid_cache:
        new_kupid_ws.append({
            'university_id':     university_id,
            'type':              'school',
            # 학교근장은 전부 교내로 확정(2026-07-20) — parse_kupid에서 '교외여부' 컬럼 자체를 제거했다.
            # ⚠️ 이 파일은 레거시(RLS 컷오버로 anon INSERT 불가). 적재는 generate_school_migration.py 사용.
            'location_type':     'on_campus',
            'organization_name': '고려대학교 서울캠퍼스',
            'workplace_name':    str(row['부서명']),
            'region':            None,
            'address':           s(row['근무장소']),
        })

if new_kupid_ws:
    print(f'  새 근무지 {len(new_kupid_ws)}개 삽입 중...')
    inserted_k = batch_insert('worksites', new_kupid_ws)
    for r in inserted_k:
        kupid_cache[(r['organization_name'], r['workplace_name'])] = r['id']

print(f'  KUPID worksite_cache 크기: {len(kupid_cache)}')

# 3-5. postings 배치 삽입
kupid_postings = []
for _, row in kupid.iterrows():
    key = ('고려대학교 서울캠퍼스', str(row['부서명']))
    wid = kupid_cache.get(key)
    if not wid:
        continue
    kupid_postings.append({
        'worksite_id':             wid,
        'source_url':              'https://portal.korea.ac.kr/front/Intro.kpd',
        'job_category':            None,
        'preferred_track':         None,
        'preferred_college':       None,
        'preferred_dept':          None,
        'recruit_count':           s(row['모집인원']),
        'min_grade':               None,
        'eligible_degree':         parse_eligible_degree(row['학부생가능'], row['대학원생가능']),
        'eligible_status':         parse_eligible_status(row['재학생가능'], row['휴학생가능']),
        'job_description':         s(row['직무내용']),
        'preference_notes':        s(row['우대조건']),
        'extra_notes':             s(row['기타특이사항']),
        'hourly_wage':             int(row['시급']) if pd.notna(row['시급']) else None,
        'work_period_text':        s(row['근무기간']),
        'work_duration_type':      'short' if str(row['단기여부']).strip() == 'O' else 'long',
        'work_time_text':          s(row['근무시간']),
        'recruitment_period_text': parse_recruitment_period(row),
        'raw_text':                None,
        'is_active':               parse_is_active(row['마감여부']),
        'contact_name':            None,
        'contact_phone':           s(row['전화번호']),
        'contact_email':           s(row['이메일']),
    })

print(f'  postings {len(kupid_postings)}개 삽입 중...')
batch_insert('postings', kupid_postings)
print('KUPID 완료!')
print('\n전체 완료!')
