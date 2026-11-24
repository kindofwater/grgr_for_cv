// 근장찾기(Search) 결과 영역 로딩 스켈레톤 — 검색 헤더는 Search가 항상 렌더하므로 여기선 결과만.
// (네이버처럼 검색바는 즉시 뜨고 그 아래만 로딩)
const S = ({ w = '100%', h = 16, mb = 0, br = 6 }) => (
  <div className="skeleton-box" style={{ width: w, height: h, marginBottom: mb, borderRadius: br }} />
)

export default function SkeletonSearch() {
  return (
    <>
      <div className="results-bar">
        <S w={140} h={20} />
        <S w={110} h={20} />
      </div>

      <div className="result-list">
        {[1, 2, 3, 4, 5].map((i) => (
          <div className="result-card" key={i} style={{ cursor: 'default' }}>
            <div>
              <S w="55%" h={12} mb={6} />
              <S w="78%" h={18} mb={10} />
              <div style={{ display: 'flex', gap: 5 }}>
                <S w={56} h={20} br={20} />
                <S w={40} h={20} br={20} />
              </div>
            </div>
            <div className="rc-mid"><S w="100%" h={56} /></div>
            <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 6 }}>
              <S w={44} h={30} />
              <S w={56} h={26} br={6} />
            </div>
          </div>
        ))}
      </div>
    </>
  )
}
