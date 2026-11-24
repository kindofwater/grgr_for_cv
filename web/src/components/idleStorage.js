// 유휴 로그아웃 — lastActive의 localStorage I/O.
// lib은 의존성 0·DOM 금지 계약이라(lib/README.md) 스토리지 접근은 여기에 둔다.
// storage를 '인자로 주입'받아 node 환경에서 mock 테스트가 가능하게 한다(jsdom 불필요).
//
// ⚠️ 삭제 함수는 두지 않는다. 설계상 lastActive는 로그아웃 시에도 지우지 않는다 —
//    signOut()이 네트워크 오류로 실패하면 auth-js가 세션을 안 지우는데, 키까지 지우면
//    다음 부팅에서 만료 판정 근거가 사라져 전임자 계정이 부활한다(fail-open).

export const LAST_ACTIVE_KEY = 'honeyjang.idle.lastActive'

// 실패해도 앱을 죽이지 않는다(사파리 프라이빗 등) — 지속성만 포기한다.
export function readLastActive(storage) {
  try {
    return storage.getItem(LAST_ACTIVE_KEY)
  } catch {
    return null
  }
}

export function writeLastActive(storage, uid, ts) {
  try {
    storage.setItem(LAST_ACTIVE_KEY, JSON.stringify({ uid, ts }))
    return true
  } catch {
    return false
  }
}
