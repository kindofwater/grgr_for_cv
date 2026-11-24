import "./ReviewForm.css";
import PageMeta from "../components/PageMeta";
import { useEffect, useMemo, useState } from "react";
import { useLocation, useNavigate, useParams } from "react-router-dom";
import ConfirmModal from "../components/ConfirmModal";
import ReviewFormFields from "../components/ReviewFormFields";
import { useToast } from "../components/ToastContext";
import {
  createReview,
  fetchMyReviewById,
  fetchMyReviewForPeriod,
  fetchWorksite,
  updateReview,
} from "../data/worksiteQueries";
import {
  reviewFormSemesterOptions,
  reviewFormYearOptions,
  SEMESTER_ORDER,
} from "../lib/semesters";
import { useAuth } from "../components/AuthContext";
import { ANONYMOUS_REVIEW_POINTS, reviewPoints } from "../lib/points";

function reviewSaveErrorMessage(error) {
  const errorText = [
    error?.code,
    error?.message,
    error?.details,
    error?.hint,
  ]
    .filter(Boolean)
    .join(" ");

  if (errorText.includes("INSUFFICIENT_POINTS")) {
    return "포인트가 부족해 익명으로 바꿀 수 없어요.";
  }

  // 서버(write_review_with_points)가 대학 스코프를 어기면 던지는 코드.
  //   아래 진입 가드에서 대부분 걸러지지만, RPC 직접 호출·가드 통과 후 상황 변경 대비 최종 방어선.
  if (errorText.includes("FORBIDDEN_WORKSITE")) {
    return "내 학교의 근무지가 아니라 리뷰를 작성할 수 없어요.";
  }
  if (errorText.includes("WORKSITE_NOT_FOUND")) {
    return "근무지를 찾을 수 없어요. 삭제되었을 수 있습니다.";
  }
  if (errorText.includes("INVALID_WORK_SEMESTER")) {
    return "이 근로장학 유형에는 선택할 수 없는 학기예요.";
  }

  if (
    error?.code === "23505" ||
    errorText.includes("reviews_user_id_work_year_work_semester_key") ||
    errorText.includes("reviews_user_worksite_year_semester_key") ||
    errorText.includes("reviews_user_year_semester_key")
  ) {
    return "이미 이 학기에 작성한 리뷰가 있어요. 기존 리뷰를 수정해 주세요.";
  }

  return `리뷰 저장에 실패했습니다: ${error?.message ?? "알 수 없는 오류"}`;
}

function isDuplicateReviewError(error) {
  const errorText = [
    error?.code,
    error?.message,
    error?.details,
    error?.hint,
  ]
    .filter(Boolean)
    .join(" ");

  return (
    error?.code === "23505" ||
    errorText.includes("reviews_user_id_work_year_work_semester_key") ||
    errorText.includes("reviews_user_worksite_year_semester_key") ||
    errorText.includes("reviews_user_year_semester_key")
  );
}

function ReviewForm() {
  const { id: worksiteId, reviewId } = useParams();
  const navigate = useNavigate();
  const location = useLocation();
  const { user: authUser, refreshProfile } = useAuth();
  const toast = useToast();
  const isEdit = Boolean(reviewId);
  const now = useMemo(() => new Date(), []);
  const currentYear = now.getFullYear();

  const [workYear, setWorkYear] = useState(() => String(currentYear));
  const [workSemester, setWorkSemester] = useState(SEMESTER_ORDER[2]);
  const [workContent, setWorkContent] = useState("");
  const [opinion, setOpinion] = useState("");
  const [scoreWork, setScoreWork] = useState(0);
  const [scoreGrowth, setScoreGrowth] = useState(0);
  const [scoreVibe, setScoreVibe] = useState(0);
  const [scoreFlex, setScoreFlex] = useState(0);
  const [scoreRecommend, setScoreRecommend] = useState(0);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [isAnonymous, setIsAnonymous] = useState(false);
  const [originalIsAnonymous, setOriginalIsAnonymous] = useState(false);
  const [showAnonymousConfirm, setShowAnonymousConfirm] = useState(false);
  const [originalWorkYear, setOriginalWorkYear] = useState(null);
  const [currentUser, setCurrentUser] = useState(null);
  const [worksite, setWorksite] = useState(null);
  const [duplicateReview, setDuplicateReview] = useState(null);
  const [isUserLoading, setIsUserLoading] = useState(true);
  const [userError, setUserError] = useState(null);

  const yearOptions = useMemo(
    () => reviewFormYearOptions({ now, include: originalWorkYear }),
    [now, originalWorkYear],
  );
  const semesterOptions = useMemo(() => {
    return reviewFormSemesterOptions({
      year: workYear,
      now,
      nationalWorkTerm: worksite?.national_work_term,
    });
  }, [now, workYear, worksite?.national_work_term]);
  const hasDuplicate = Boolean(duplicateReview);
  // 제출 시 발생할 포인트 증감(버튼 표시용): 작성=익명 +20/닉네임 공개 +30, 수정=익명 토글 차액(±10/0)
  const pointDelta = isEdit
    ? reviewPoints(isAnonymous) - reviewPoints(originalIsAnonymous)
    : reviewPoints(isAnonymous);

  useEffect(() => {
    let alive = true;

    async function loadFormData() {
      setIsUserLoading(true);
      setUserError(null);
      setOriginalWorkYear(null);
      if (!isEdit) setWorkYear(String(currentYear));

      if (!authUser) {
        setIsUserLoading(false);
        navigate("/login", { replace: true }); // 인증 바운스는 replace — push면 뒤로가기가 가드로 되돌아와 핑퐁 트랩
        return;
      }

      try {
        const nextWorksite = await fetchWorksite(worksiteId);

        if (!alive) return;

        // 대학 스코프 가드 — 내 학교(또는 공용 0)의 근무지가 아니면 폼을 열지 않는다.
        //   URL로 /worksite/:id/review에 직접 들어와 남의 학교 근무지에 리뷰를 쓸 수 있었다.
        //   ※ 진짜 차단은 서버(write_review_with_points의 FORBIDDEN_WORKSITE)가 한다. 여기는
        //     "다 쓰고 나서 실패"를 막는 UX 가드일 뿐이라, 이걸 우회해도 저장은 안 된다.
        const wsUni = nextWorksite?.university_id;
        if (wsUni !== 0 && wsUni !== authUser?.university_id) {
          toast("내 학교의 근무지가 아니라 리뷰를 작성할 수 없어요.", "error");
          navigate(`/worksite/${worksiteId}`, { replace: true });
          return;
        }

        setCurrentUser(authUser);
        setWorksite(nextWorksite);

        if (isEdit) {
          const review = await fetchMyReviewById(reviewId, worksiteId);
          if (!alive) return;

          if (!review) {
            setUserError("수정할 리뷰가 없습니다.");
            toast("수정할 리뷰가 없습니다.", "error");
            return;
          }

          const fetchedWorkYear = Number(review.work_year);
          const validOriginalWorkYear =
            Number.isInteger(fetchedWorkYear) && fetchedWorkYear >= 1
              ? fetchedWorkYear
              : null;
          const fetchedYearOptions = reviewFormYearOptions({
            now,
            include: validOriginalWorkYear,
          });
          const normalizedWorkYear = fetchedYearOptions.includes(fetchedWorkYear)
            ? fetchedWorkYear
            : currentYear;

          setOriginalWorkYear(validOriginalWorkYear);
          setWorkYear(String(normalizedWorkYear));
          setWorkSemester(review.work_semester ?? SEMESTER_ORDER[2]);
          setScoreWork(review.score_work ?? 0);
          setScoreGrowth(review.score_growth ?? 0);
          setScoreVibe(review.score_vibe ?? 0);
          setScoreFlex(review.score_flex ?? 0);
          setScoreRecommend(review.score_recommend ?? 0);
          setWorkContent(review.work_content ?? "");
          setOpinion(review.opinion ?? "");
          setIsAnonymous(Boolean(review.is_anonymous));
          setOriginalIsAnonymous(Boolean(review.is_anonymous));
        }
      } catch (error) {
        if (!alive) return;
        setUserError(error.message);
        toast(`정보를 불러오지 못했습니다: ${error.message}`, "error");
      } finally {
        if (alive) setIsUserLoading(false);
      }
    }

    if (worksiteId) {
      loadFormData();
    }

    return () => {
      alive = false;
    };
  }, [authUser, currentYear, isEdit, navigate, now, reviewId, toast, worksiteId]);

  useEffect(() => {
    setDuplicateReview(null);
  }, [reviewId, worksiteId]);

  useEffect(() => {
    let active = true;

    async function checkExistingReview() {
      if (!currentUser || !workYear || !workSemester) {
        setDuplicateReview(null);
        return;
      }

      try {
        const existingReview = await fetchMyReviewForPeriod(
          Number.parseInt(workYear, 10),
          workSemester,
        );

        if (!active) return;

        const isCurrentReview =
          existingReview &&
          reviewId &&
          String(existingReview.id) === String(reviewId);

        setDuplicateReview(!isCurrentReview ? existingReview : null);
      } catch {
        if (active) setDuplicateReview(null);
      }
    }

    checkExistingReview();

    return () => {
      active = false;
    };
  }, [currentUser, reviewId, workSemester, workYear, worksiteId]);

  useEffect(() => {
    const toastMessage = location.state?.toastMessage;
    if (!toastMessage) return;

    toast(
      toastMessage,
      "info",
      toastMessage === "기존에 작성한 리뷰를 불러왔어요." ? 5000 : 2800,
    );
    navigate(location.pathname, { replace: true, state: null });
  }, [location.pathname, location.state, navigate, toast]);

  useEffect(() => {
    if (semesterOptions.length > 0 && !semesterOptions.includes(workSemester)) {
      setWorkSemester(semesterOptions[0]);
    }
  }, [semesterOptions, workSemester]);

  function handleSubmit() {
    if (isUserLoading) return;  // 로딩 중엔 조용히 제출만 막음('불러오는 중' 문구 X)

    if (userError || !currentUser || !worksiteId) {
      toast("필수 정보를 확인할 수 없어 리뷰를 저장할 수 없습니다.", "error");
      return;
    }

    const selectedWorkYear = Number(workYear);
    if (!yearOptions.includes(selectedWorkYear)) {
      setWorkYear(String(currentYear));
      toast(
        "선택할 수 없는 근로 연도라 올해로 조정했어요. 학기를 다시 확인해 주세요.",
        "error",
      );
      return;
    }

    if (
      !scoreWork ||
      !scoreGrowth ||
      !scoreVibe ||
      !scoreFlex ||
      !scoreRecommend
    ) {
      toast("모든 별점을 선택해 주세요.", "error");
      return;
    }

    if (workContent.trim().length < 30) {
      toast("실제 업무 내용은 30자 이상 작성해 주세요.", "error");
      return;
    }

    if (opinion.trim().length < 50) {
      toast("자유 의견은 50자 이상 작성해 주세요.", "error");
      return;
    }

    // 익명으로 전환(포인트 감소)되는 경우만 확인 모달: 신규 익명 / 실명→익명.
    if (isAnonymous && (!isEdit || !originalIsAnonymous)) {
      setShowAnonymousConfirm(true);
      return;
    }

    submitReview();
  }

  async function submitReview() {
    setIsSubmitting(true);
    setDuplicateReview(null);

    try {
      if (isEdit) {
        if (!reviewId) {
          throw new Error("수정할 리뷰를 찾을 수 없습니다.");
        }

        await updateReview(reviewId, {
          work_year: Number.parseInt(workYear, 10),
          work_semester: workSemester,
          score_work: scoreWork,
          score_growth: scoreGrowth,
          score_vibe: scoreVibe,
          score_flex: scoreFlex,
          score_recommend: scoreRecommend,
          work_content: workContent.trim(),
          opinion: opinion.trim(),
          is_anonymous: isAnonymous,
        });
      } else {
        await createReview({
          p_worksite_id: Number(worksiteId),
          p_work_year: Number.parseInt(workYear, 10),
          p_work_semester: workSemester,
          p_work: scoreWork,
          p_growth: scoreGrowth,
          p_vibe: scoreVibe,
          p_flex: scoreFlex,
          p_recommend: scoreRecommend,
          p_work_content: workContent.trim(),
          p_opinion: opinion.trim(),
          p_is_anonymous: isAnonymous,
        });
      }

      // 적립/회수된 포인트를 컨텍스트에 반영 → AccountMenu(드롭다운) 잔액 즉시 갱신
      await refreshProfile();
      navigate(`/worksite/${worksiteId}`);
    } catch (error) {
      const isDuplicate = isDuplicateReviewError(error);

      if (isDuplicate && currentUser) {
        try {
          const existingReview = await fetchMyReviewForPeriod(
            Number.parseInt(workYear, 10),
            workSemester,
          );
          setDuplicateReview(existingReview);
          toast("이미 해당 학기에 작성한 리뷰가 있어요.", "error");
        } catch {
          setDuplicateReview(null);
        }
      } else {
        toast(reviewSaveErrorMessage(error), "error");
      }
    } finally {
      setIsSubmitting(false);
    }
  }

  return (
    <>
      <PageMeta title="리뷰 작성" />
      <ReviewFormFields
        isEdit={isEdit}
        worksite={worksite}
        onBack={() => navigate(`/worksite/${worksiteId}`)}
        yearOptions={yearOptions}
        workYear={workYear}
        setWorkYear={(year) => {
          const selectedYear = Number(year);
          const normalizedYear = yearOptions.includes(selectedYear)
            ? selectedYear
            : currentYear;
          setDuplicateReview(null);
          setWorkYear(String(normalizedYear));
        }}
        workSemester={workSemester}
        setWorkSemester={(semester) => {
          setDuplicateReview(null);
          setWorkSemester(semester);
        }}
        semesterOptions={semesterOptions}
        workContent={workContent}
        setWorkContent={setWorkContent}
        opinion={opinion}
        setOpinion={setOpinion}
        scoreWork={scoreWork}
        setScoreWork={setScoreWork}
        scoreGrowth={scoreGrowth}
        setScoreGrowth={setScoreGrowth}
        scoreVibe={scoreVibe}
        setScoreVibe={setScoreVibe}
        scoreFlex={scoreFlex}
        setScoreFlex={setScoreFlex}
        scoreRecommend={scoreRecommend}
        setScoreRecommend={setScoreRecommend}
        isUserLoading={isUserLoading}
        userError={userError}
        isSubmitting={isSubmitting}
        isAnonymous={isAnonymous}
        setIsAnonymous={setIsAnonymous}
        pointDelta={pointDelta}
        isSubmitDisabled={isSubmitting || hasDuplicate}
        duplicateReview={duplicateReview}
        onEditDuplicate={() => {
          setDuplicateReview(null);
          navigate(
            `/worksite/${duplicateReview.worksite_id}/review/${duplicateReview.id}/edit`,
            {
              state: {
                toastMessage: "기존에 작성한 리뷰를 불러왔어요.",
              },
            },
          );
        }}
        onSubmit={handleSubmit}
      />
      {showAnonymousConfirm && (
        <ConfirmModal
          confirmText="확인"
          intent="primary"
          message={
            // 주 질문(600) + 옅은 설명(.modal-note, 500) — 다른 확인 모달과 같은 계층·굵기 구조.
            // (구 <strong> 제목은 700이라 삭제 등 다른 확인 질문보다 굵어 계층이 어긋났음)
            isEdit ? (
              <>
                익명으로 수정할까요?
                <span className="modal-note">적립된 10P가 회수돼요.</span>
              </>
            ) : (
              <>
                익명으로 제출할까요?
                <span className="modal-note">닉네임·근무 학기가 공개되지 않고, 닉네임 공개 리뷰보다 10P 적은 {ANONYMOUS_REVIEW_POINTS}P가 적립돼요.</span>
              </>
            )
          }
          onConfirm={() => {
            setShowAnonymousConfirm(false);
            submitReview();
          }}
          onCancel={() => setShowAnonymousConfirm(false)}
        />
      )}
    </>
  );
}

export default ReviewForm;
