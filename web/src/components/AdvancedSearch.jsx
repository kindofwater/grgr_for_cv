import { useEffect, useRef, useState } from 'react'
import { REGIONS } from '../lib/profileOptions'
import './AdvancedSearch.css'

const EMPTY = {
  recruit: [],
  type: [],
  location: [],
  region: [],
  duration: [],
  track: [],
  degree: [],
  status: [],
}

const GROUPS = [
  { key: 'recruit', label: '모집상태', options: ['모집중', '모집완료'] },
  { key: 'type', label: '근장유형', options: ['국가근장', '학교근장'] },
  { key: 'location', label: '교내외', options: ['교외', '교내'] },
  { key: 'region', label: '지역', options: REGIONS, note: '지역 필터는 교외 국가근로장학 공고에만 적용돼요.' },
  {
    key: 'duration',
    label: '기간',
    options: ['장기', '단기'],
    note: '단기는 6주 미만 공고만 보여요.',
  },
  { key: 'degree', label: '학위', options: ['학부생만', '대학원생만'] },
  { key: 'status', label: '학적', options: ['재학생만', '휴학생만'] },
]

// pending 선택은 mount 시 initial로 시작. 적용/초기화로 부모의 적용필터가 바뀌면
// 부모가 key로 리마운트시켜 동기화한다(여기서 effect로 setState하면 cascading render 룰 위반).
export default function AdvancedSearch({ initial, onChange, onApply, onReset }) {
  const [sel, setSel] = useState(() => ({ ...EMPTY, ...(initial ?? {}) }))
  const [hintOpen, setHintOpen] = useState(null)
  const hintRef = useRef(null)

  // 말풍선 바깥 클릭 닫기 (setState는 핸들러 콜백 안 — effect 본문 동기 setState 아님)
  useEffect(() => {
    function onDoc(e) { if (hintRef.current && !hintRef.current.contains(e.target)) setHintOpen(null) }
    document.addEventListener('mousedown', onDoc)
    return () => document.removeEventListener('mousedown', onDoc)
  }, [])

  function isOn(key, opt) {
    return sel[key].includes(opt)
  }
  function toggle(key, opt) {
    const cur = sel[key]
    const next = {
      ...sel,
      [key]: cur.includes(opt) ? cur.filter((x) => x !== opt) : [...cur, opt],
    }
    setSel(next)
    onChange(next)
  }
  function handleReset() {
    setSel({ ...EMPTY })
    onReset()
  }

  return (
    <div className="adv-search" ref={hintRef}>
      {GROUPS.map((g) => (
        <div className="adv-row" key={g.key}>
          <div className="adv-label">
            {g.note && (
              <span className="adv-hint">
                <button type="button" className="adv-hint-btn"
                  onClick={() => setHintOpen((v) => v === g.key ? null : g.key)}
                  aria-label={`${g.label} 안내`}>?</button>
                {hintOpen === g.key && <span className="adv-hint-pop">{g.note}</span>}
              </span>
            )}
            {g.label}
          </div>
          <div className="adv-opts">
            {g.options.map((opt) => (
              <button type="button" key={opt}
                className={`adv-chip ${isOn(g.key, opt) ? 'on' : ''}`}
                disabled={opt === '추가예정'}
                onClick={() => toggle(g.key, opt)}>{opt}</button>
            ))}
          </div>
        </div>
      ))}
      <div className="adv-actions">
        <button type="button" className="adv-apply" onClick={() => onApply(sel)}>검색</button>
        <button type="button" className="adv-reset" onClick={handleReset}>초기화</button>
      </div>
    </div>
  )
}
