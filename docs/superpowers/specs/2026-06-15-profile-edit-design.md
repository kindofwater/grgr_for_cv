# 프로필 수정 (Profile Edit) v1 — 설계

- 날짜: 2026-06-15 · 담당: 배경록
- 위치: 마이페이지(`/mypage?tab=profile`) — `ProfileTab` (현재 placeholder)

## 목적
로그인 유저가 자기 프로필 일부를 직접 수정할 수 있게 한다. (현재는 "곧 추가될 예정" placeholder)

## 범위 — 수정 가능 필드
드롭다운으로만 입력 (자유 텍스트 없음 → DB enum/check가 최종 검증):
- **거주지역** (`region`)
- **입학연도** (`admission_year`)
- **학위과정** (`degree_program`, enum)
- **학년** (`grade`, 1~6)
- **학적상태** (`academic_status`, enum)

### 이번 범위에서 제외 (이유)
- **닉네임** — 이번 선택에서 빠짐. (추후: 중복검사 RPC 필요)
- **학교/단과대/학과/계열** — 학교만 바꾸면 `college_id`/`department_id`(NOT NULL FK)가 옛 학교 것으로 남아 **데이터 정합성 깨짐**. 단과대/학과는 옵션 데이터(시드) 미정. → 네 항목을 **묶어서 추후** 한 번에.
- **이메일(로그인 ID) / 비밀번호** — 별도 흐름, 범위 밖.

## DB — 새 마이그레이션 `update_profile` RPC
- `security definer`, `set search_path = public, extensions`
- 인자: `p_user_id int, p_region text, p_admission_year int, p_degree_program text, p_academic_status text, p_grade int`
- 동작: 위 **5개 컬럼만** update (+ `updated_at = now()`), `where id = p_user_id and deleted_at is null`
- 반환: 안전 컬럼(비밀번호 제외) — `verify_login`과 동일 형태 + `region`
- 시그니처 변경 대비 **`DROP FUNCTION IF EXISTS update_profile(...)` 선행** (CLAUDE.md §3)
- 파일 헤더 2줄 필수(`-- 목적:` / `-- 날짜: YYYY-MM-DD · 담당:`)
- **배포**: 배경록이 로컬 `supabase db reset`로 검증 후 `db push`(디스코드 공유). 라이브 DB에 RPC가 있어야 프론트가 동작.

### 보안 메모 (정직하게)
- 이 앱은 아직 서버 인증(Supabase Auth/JWT)이 없음 → `p_user_id`를 **클라가 전달**하므로 "본인 확인"은 못 함(직접 update 방식과 동일 한계).
- RPC의 실익 = **컬럼 화이트리스트**(이 경로로 `point_balance`·`is_admin`·`password_hash` 변경 불가) + **6/21 anon UPDATE REVOKE 후에도 definer라 동작**(직접 update는 그때 깨짐).
- 진짜 권한검증은 추후 Supabase Auth + RLS에서.

## data 계층 — `authQueries.js`
```js
export async function updateProfile(userId, { region, admission_year, degree_program, academic_status, grade }) {
  const { data, error } = await supabase.rpc('update_profile', {
    p_user_id: userId, p_region: region, p_admission_year: admission_year,
    p_degree_program: degree_program, p_academic_status: academic_status, p_grade: grade,
  })
  if (error) throw error
  return data && data.length > 0 ? data[0] : null
}
```

## lib — `lib/profileOptions.js` (신규)
드롭다운 옵션 상수 단일 소스: `REGIONS`, `DEGREE_PROGRAMS`, `ACADEMIC_STATUSES`, `GRADES` + `admissionYears()`(현재 연도 기준 17개).
- ProfileTab이 사용. **Signup.jsx(현수)는 이번엔 안 건드림** — 추후 같은 파일로 합쳐 dedup.

## UI — `ProfileTab` (MyPage.jsx 내)
- placeholder → 폼. 필드 5개를 회원가입과 동일한 드롭다운으로.
- **현재 값으로 미리 채움**(context `user`).
- 저장 버튼: `updateProfile(user.id, fields)` → 성공 시 **AuthContext `login({...user, ...updated})`** 로 갱신(사이드바/다른 화면 즉시 반영) + 성공 안내(토스트/메시지). 실패 시 에러 알림.
- 저장 중/변경 없음일 때 버튼 처리.
- 기존 **회원 탈퇴 버튼은 placeholder 그대로**(범위 밖).

## 흐름
진입 → user에서 폼 초기화 → 수정 → 저장(RPC) → 컨텍스트 반영 → "저장됐어요" → 사이드바·드롭다운 등 최신.

## 검증
- 빌드 통과.
- **RPC push 후** 실제 저장 확인(거주지역·학적정보 변경 → 새로고침 유지, 사이드바/드롭다운 반영).
- 잘못된 값은 드롭다운이라 발생 X — 서버 enum/check가 최종 방어선.

## v1.1 변경 (2026-06-15 · 현수와 합의)
초기 설계는 region을 컨텍스트에 안 싣고 ProfileTab이 `fetchProfile`로 직접 읽었으나, **region·소속학교를 로그인 시 컨텍스트에 싣기로 합의**해 변경:
- **마이그레이션 `20260615130000_login_return_region_school.sql`**: `verify_login`이 `region` + 소속학교(`university_id`·`university_name`·`university_campus`, universities 조인)까지 반환. `register_user`도 동일 반환 + **회원가입 때 누락되던 region 저장 보완**(`p_region` 추가·insert). 둘 다 시그니처 변경이라 `DROP FUNCTION` 선행. — **현수 auth라 리뷰 후 push.**
- **ProfileTab**: `fetchProfile` 제거 → 컨텍스트 `user`로 초기화(추가 조회·로딩 없음). **소속학교 읽기전용 표시.**
- **Signup.jsx**: `registerUser`에 `region` 전달(이제 실제 저장됨).
- 배포 의존성: 이 마이그레이션 push + **기존 로그인 유저는 재로그인**해야 컨텍스트에 region/소속학교가 채워짐.

## 후속 (이번 범위 밖)
- 학교/단과대/학과/계열 수정(옵션 데이터 정리 후 묶어서)
- 닉네임 수정(중복검사 RPC)
- 비밀번호 변경
- 진짜 권한검증(Supabase Auth + RLS, 6/21+)
