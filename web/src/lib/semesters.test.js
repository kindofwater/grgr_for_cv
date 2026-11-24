// web/src/lib/semesters.test.js
import { describe, it, expect } from "vitest";
import {
  REVIEW_YEAR_SPAN,
  reviewFormSemesterOptions,
  reviewFormYearOptions,
} from "./semesters";

const YEAR_NOW = new Date(2026, 6, 26);

describe("reviewFormYearOptions", () => {
  it("올해부터 5년 전까지 6개를 최신순으로 반환", () => {
    const options = reviewFormYearOptions({ now: YEAR_NOW });
    expect(options).toHaveLength(REVIEW_YEAR_SPAN);
    expect(options).toEqual([2026, 2025, 2024, 2023, 2022, 2021]);
  });

  it("범위보다 오래된 원래 리뷰 연도는 끝에 병합", () => {
    expect(
      reviewFormYearOptions({ now: YEAR_NOW, include: 2020 }),
    ).toEqual([2026, 2025, 2024, 2023, 2022, 2021, 2020]);
  });

  it("기본 범위 안 연도는 중복 추가하지 않음", () => {
    expect(
      reviewFormYearOptions({ now: YEAR_NOW, include: 2024 }),
    ).toEqual([2026, 2025, 2024, 2023, 2022, 2021]);
  });

  it("include가 null이면 기본 6개 그대로", () => {
    expect(
      reviewFormYearOptions({ now: YEAR_NOW, include: null }),
    ).toEqual([2026, 2025, 2024, 2023, 2022, 2021]);
  });

  it("미래·0 이하·비정수·NaN은 예외로 추가하지 않음", () => {
    for (const include of [2027, 0, -1, 2020.5, Number.NaN]) {
      expect(
        reviewFormYearOptions({ now: YEAR_NOW, include }),
      ).toEqual([2026, 2025, 2024, 2023, 2022, 2021]);
    }
  });
});

describe("reviewFormSemesterOptions", () => {
  it("현재 연도 6월에는 1학기만 선택 가능", () => {
    expect(
      reviewFormSemesterOptions({
        year: 2026,
        now: new Date("2026-06-07"),
      }),
    ).toEqual(["1학기"]);
  });

  it("현재 연도 8월에는 1학기와 여름방학만 선택 가능", () => {
    expect(
      reviewFormSemesterOptions({
        year: 2026,
        now: new Date("2026-08-01"),
      }),
    ).toEqual(["1학기", "여름방학"]);
  });

  it("현재 연도 11월에는 2학기까지만 선택 가능", () => {
    expect(
      reviewFormSemesterOptions({
        year: 2026,
        now: new Date("2026-11-01"),
      }),
    ).toEqual(["1학기", "여름방학", "2학기"]);
  });

  it("과거 연도는 모든 학기를 선택 가능", () => {
    expect(
      reviewFormSemesterOptions({
        year: 2025,
        now: new Date("2026-06-07"),
      }),
    ).toEqual(["1학기", "여름방학", "2학기", "겨울방학"]);
  });

  it("방학 집중 국가근로는 여름방학·겨울방학만 선택 가능", () => {
    expect(
      reviewFormSemesterOptions({
        year: 2025,
        now: new Date("2026-06-07"),
        nationalWorkTerm: "vacation",
      }),
    ).toEqual(["여름방학", "겨울방학"]);
  });

  it("학기 중 국가근로는 1학기·2학기만 선택 가능", () => {
    expect(
      reviewFormSemesterOptions({
        year: 2025,
        now: new Date("2026-06-07"),
        nationalWorkTerm: "semester",
      }),
    ).toEqual(["1학기", "2학기"]);
  });
});
