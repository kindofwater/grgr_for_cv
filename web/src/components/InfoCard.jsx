import { dash, formatWage, eligibleDegreeLabel, eligibleStatusLabel, formatMinGrade } from '../lib/scores'
import { effectiveActive } from '../lib/recruit'

// BO06은 KUPID 내부 게시판 경로라 세션 메뉴를 거치지 않은 직접 접속이 차단된다.
// 포털 첫 화면에서 게시판 → 공지사항 → 일반공지로 들어가게 안내한다.
const KUPID_PORTAL_URL = 'https://portal.korea.ac.kr/'
const SSC_LIST_URL = 'https://job.korea.ac.kr/ptfol/ncEm/job/rcrt/arb/index.do'

function Row({ label, value }) {
  return (
    <div className="info-row"><span className="info-lbl">{label}</span><span>{dash(value)}</span></div>
  )
}

// 공고 1건의 상세 필드 + 신청 버튼. InfoCard 본문과 PostingList 펼침이 공유(중복 제거).
export function PostingFields({ posting, isNational }) {
  const isOpen = effectiveActive(posting)
  const sourceUrl = posting?.source_url?.trim?.() || ''
  const schoolFallbackUrl = posting?.source === 'ssc' ? SSC_LIST_URL : KUPID_PORTAL_URL
  // 학교 공고도 대표 출처의 상세 링크를 우선 사용한다. 상세 링크가 없을 때만
  // 해당 출처의 목록/첫 화면으로 보낸다.
  const destinationUrl = sourceUrl || (isNational ? '' : schoolFallbackUrl)
  const hasDestinationUrl = Boolean(destinationUrl)
  const applyLabel = isNational ? '국가근장 장학 시스템에서 신청하기 ↗' : '근장 사이트에서 신청하기 ↗'
  const buttonLabel = isNational
    ? (hasDestinationUrl ? (isOpen ? applyLabel : '마감된 공고 보러가기 ↗') : (isOpen ? '공고 링크 없음' : '모집완료'))
    : '공고 보러가기 ↗'
  // 학위·학적: 한쪽만 가능할 때만 표시(둘 다 가능 = 제한 없음 → 행 생략)
  const degreeLabel = eligibleDegreeLabel(posting?.eligible_degree)
  const statusLabel = eligibleStatusLabel(posting?.eligible_status)
  const openSource = () => {
    if (!hasDestinationUrl) return
    window.open(destinationUrl, '_blank', 'noopener,noreferrer')
  }
  return (
    <>
      {isNational ? (
        <>
          <Row label="선호계열" value={posting?.preferred_track || '상관없음'} />
          <Row label="선호학년" value={formatMinGrade(posting?.min_grade)} />
          {posting?.recruitment_period_text && (
            <Row label="모집 기간" value={posting.recruitment_period_text} />
          )}
        </>
      ) : (
        <>
          {degreeLabel && <Row label="학위 과정" value={degreeLabel} />}
          {statusLabel && <Row label="학적 상태" value={statusLabel} />}
          <Row label="모집 기간" value={posting?.recruitment_period_text} />
        </>
      )}
      <Row label="모집 인원" value={posting?.recruit_count} />
      <Row label="시급" value={formatWage(posting?.hourly_wage)} />
      <Row label="근로기간" value={posting?.work_period_text} />
      <Row label="근로시간" value={posting?.work_time_text} />
      <Row label="직무 내용" value={posting?.job_description} />
      {!isNational && <Row label="우대조건" value={posting?.preference_notes} />}
      <Row label="기타" value={posting?.extra_notes} />

      <button className="btn-apply" type="button" onClick={openSource} disabled={!hasDestinationUrl}>
        {buttonLabel}
      </button>
    </>
  )
}

export default function InfoCard({ worksite, posting }) {
  const isNational = worksite.type === 'national'
  const isOpen = effectiveActive(posting)
  const typeLabel = isNational ? '국가근장' : '학교근장'
  const locLabel = worksite.type === 'school' ? null : (worksite.location_type === 'off_campus' ? '교외' : '교내')   // 학교근장은 전부 교내라 태그 생략 / 국가근장만 교내·교외

  return (
    <div className={`info-card ${isOpen ? 'status-open' : 'status-closed'}`}>
      <div className="det-head">
        <div className="det-titles">
          <div className="det-org">{dash(worksite.organization_name)}</div>
          <div className="det-name">{dash(worksite.workplace_name)}</div>
        </div>
        <span className={`det-status-badge ${isOpen ? 'badge-open' : 'badge-closed'}`}>
          <span className="badge-dot" />{isOpen ? '모집중' : '모집완료'}
        </span>
      </div>

      <div className="tag-rows">
        <div className="tag-row">
          <span className={`tag ${isNational ? 'tag-national' : 'tag-school'}`}>{typeLabel}</span>
          {locLabel && <span className="tag tag-loc">{locLabel}</span>}
        </div>
      </div>

      <Row label="주소" value={posting?.work_location || worksite.address} />
      <Row label="근로유형" value={typeLabel} />
      <PostingFields posting={posting} isNational={isNational} />
    </div>
  )
}
