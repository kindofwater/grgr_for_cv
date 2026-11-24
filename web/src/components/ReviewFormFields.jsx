import { useState } from "react";
import Dropdown from "./Dropdown";

function StarRating({ value, onChange }) {
  const [hoverValue, setHoverValue] = useState(null);
  const displayValue = hoverValue ?? value;

  function getScoreFromEvent(score, event) {
    const rect = event.currentTarget.getBoundingClientRect();
    const isLeftHalf = event.clientX < rect.left + rect.width / 2;
    return isLeftHalf ? score - 0.5 : score;
  }

  function getStarClass(score) {
    if (score <= displayValue) return "star on";
    if (score - 0.5 === displayValue) return "star half";
    return "star";
  }

  return (
    <div
      className="stars"
      data-val={value}
      onMouseLeave={() => setHoverValue(null)}
    >
      {[1, 2, 3, 4, 5].map((score) => (
        <span
          key={score}
          className={getStarClass(score)}
          data-val={score}
          role="button"
          tabIndex={0}
          aria-label={`${score - 0.5}점 또는 ${score}점 선택`}
          onClick={(event) => onChange(getScoreFromEvent(score, event))}
          onMouseMove={(event) =>
            setHoverValue(getScoreFromEvent(score, event))
          }
          onKeyDown={(event) => {
            if (event.key === "Enter" || event.key === " ") {
              event.preventDefault();
              onChange(score);
            }
          }}
        >
          ★
        </span>
      ))}
    </div>
  );
}

export default function ReviewFormFields({
  isEdit,
  worksite,
  onBack,
  yearOptions,
  workYear,
  setWorkYear,
  workSemester,
  setWorkSemester,
  semesterOptions,
  workContent,
  setWorkContent,
  opinion,
  setOpinion,
  scoreWork,
  setScoreWork,
  scoreGrowth,
  setScoreGrowth,
  scoreVibe,
  setScoreVibe,
  scoreFlex,
  setScoreFlex,
  scoreRecommend,
  setScoreRecommend,
  isUserLoading,
  userError,
  isSubmitting,
  isAnonymous,
  setIsAnonymous,
  pointDelta,
  isSubmitDisabled,
  duplicateReview,
  onEditDuplicate,
  onSubmit,
}) {
  const recommendStatusClass =
    scoreRecommend >= 4 ? "on" : scoreRecommend > 0 ? "off" : "";
  const recommendStatusText =
    scoreRecommend === 0
      ? "별점을 선택해 주세요"
      : scoreRecommend >= 4
        ? "이 근무지를 추천합니다"
        : "추천으로 집계되지 않습니다";

  return (
    <div className="form-wrap">
      <div className="form-card">
        <div className="form-place">
          <div className="form-place-info">
            <div className="det-org">{worksite?.organization_name ?? ""}</div>
            <div className="det-name">{worksite?.workplace_name ?? ""}</div>
          </div>
          <button type="button" className="review-form-back" onClick={onBack}>
            <span aria-hidden="true">←</span>
            <span>근무지로 돌아가기</span>
          </button>
        </div>

        <div className="fg">
          <label className="fg-lab">근로 학기</label>
          <div className="fg-note">언제 근로장학을 했나요?</div>
          <div style={{ display: "flex", gap: "10px" }}>
            <div style={{ flex: 1 }}>
              <Dropdown
                value={workYear}
                onChange={setWorkYear}
                options={
                  isUserLoading || userError
                    ? [{ value: String(workYear), label: `${workYear}년` }]
                    : yearOptions.map((year) => ({
                        value: String(year),
                        label: `${year}년`,
                      }))
                }
                ariaLabel="근로 연도"
                disabled={isUserLoading || Boolean(userError)}
                size="sm"
              />
            </div>
            <div style={{ flex: 1 }}>
              <Dropdown
                value={workSemester}
                onChange={setWorkSemester}
                options={semesterOptions}
                ariaLabel="근로 학기"
                size="sm"
              />
            </div>
          </div>
          {duplicateReview && (
            <div className="duplicate-review-notice" role="status">
              <span>⚠ 이미 작성한 리뷰가 있어요.</span>
              <button type="button" onClick={onEditDuplicate}>
                리뷰 수정하기
              </button>
            </div>
          )}
        </div>

        <div className="fg">
          <label className="fg-lab">평점</label>
          <div className="fg-note">1 = 매우 별로 · 5 = 매우 좋음</div>
          <div className="rate-list">
            <div className="rate-row">
              <span className="rate-cat">업무</span>
              <StarRating value={scoreWork} onChange={setScoreWork} />
              <span className="star-val">{scoreWork || "-"} / 5</span>
            </div>
            <div className="rate-row">
              <span className="rate-cat">자기계발</span>
              <StarRating value={scoreGrowth} onChange={setScoreGrowth} />
              <span className="star-val">{scoreGrowth || "-"} / 5</span>
            </div>
            <div className="rate-row">
              <span className="rate-cat">분위기</span>
              <StarRating value={scoreVibe} onChange={setScoreVibe} />
              <span className="star-val">{scoreVibe || "-"} / 5</span>
            </div>
            <div className="rate-row">
              <span className="rate-cat">시간 유연성</span>
              <StarRating value={scoreFlex} onChange={setScoreFlex} />
              <span className="star-val">{scoreFlex || "-"} / 5</span>
            </div>
          </div>
        </div>

        <div className="fg">
          <div className="recommend-heading-row">
            <label className="fg-lab">이 근무지를 추천하나요?</label>
            <div className="fg-note">4점 이상이면 추천으로 집계돼요</div>
          </div>
          <div className="rate-row rate-row-rec">
            <div className="rate-cat-wrap">
              <span className="rate-cat">추천 점수</span>
              <span
                className={`recommend-status ${recommendStatusClass}`.trim()}
              >
                {recommendStatusText}
              </span>
            </div>
            <StarRating value={scoreRecommend} onChange={setScoreRecommend} />
            <span className="star-val">{scoreRecommend || "-"} / 5</span>
          </div>
        </div>

        <div className="fg">
          <label className="fg-lab">실제 업무는 무엇을 했나요?</label>
          <div className="fg-note">30자 이상 · 최대 1000자</div>
          <textarea
            maxLength="1000"
            placeholder="실제로 어떤 업무를 했는지 구체적으로 적어주세요"
            value={workContent}
            onChange={(event) => setWorkContent(event.target.value)}
          />
          <div className={`char-cnt ${workContent.length >= 30 ? "ok" : ""}`}>
            {workContent.length} / 1000자
            {workContent.length >= 30 && " ✓"}
          </div>
        </div>

        <div className="fg">
          <label className="fg-lab">자유 의견</label>
          <div className="fg-note">50자 이상 · 최대 2000자</div>
          <textarea
            className="textarea-long"
            maxLength="2000"
            placeholder={
              "솔직한 후기를 자유롭게 남겨주세요.\n\n특정인을 비방하거나 허위 사실을 포함한 내용, 욕설·혐오 표현은 관리자 검토 후 삭제될 수 있어요."
            }
            value={opinion}
            onChange={(event) => setOpinion(event.target.value)}
          />
          <div className={`char-cnt ${opinion.length >= 50 ? "ok" : ""}`}>
            {opinion.length} / 2000자
            {opinion.length >= 50 && " ✓"}
          </div>
        </div>

        <label className="anonymous-review-option">
          <input
            type="checkbox"
            checked={isAnonymous}
            disabled={isSubmitting}
            onChange={(event) => setIsAnonymous(event.target.checked)}
          />
          <span className="anonymous-review-copy">
            <strong>익명으로 작성하기</strong>
            <span>작성자 닉네임과 근무 학기가 공개되지 않아요.</span>
          </span>
        </label>

        <button
          className={`btn-submit${isSubmitting ? " is-submitting" : ""}`}
          disabled={isSubmitDisabled}
          aria-busy={isSubmitting}
          onClick={onSubmit}
        >
          {isEdit ? "리뷰 수정하기" : "리뷰 제출하기"}
          {pointDelta !== 0 && (
            <span className="submit-point-delta">
              {` (${pointDelta > 0 ? "+" : "−"}${Math.abs(pointDelta)}P)`}
            </span>
          )}
        </button>
      </div>
    </div>
  );
}
