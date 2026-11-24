import './CardTags.css'

// 근무지 카드 태그 목록 — max개까지 개별 칩, 넘치면 '+N' 칩. +N에 마우스를 올리면
// 브라우저 기본 툴팁(HTML title 속성 — 근무지명 말줄임에 커서 대면 뜨는 그것)으로 숨은 태그명을 콤마로 표시.
// props: tags = [{ label, cls }] · max(기본 Infinity = 전부 개별 표시. 홈은 max={3}, 근장찾기는 미지정=전부)
// 홈(PlaceCard·FeaturedRec)·근장찾기(ResultCard) 공용. 부모 flex 컨테이너(.tag-row/.hf-tags, flex-wrap) 안에 조각(fragment)으로 렌더.
export default function CardTags({ tags, max = Infinity }) {
  const visible = tags.slice(0, max)
  const hidden = tags.slice(max)
  return (
    <>
      {visible.map((t, i) => <span key={i} className={`tag ${t.cls}`}>{t.label}</span>)}
      {hidden.length > 0 && (
        <span className="tag tag-more" title={hidden.map((t) => t.label).join(', ')}>+{hidden.length}</span>
      )}
    </>
  )
}
