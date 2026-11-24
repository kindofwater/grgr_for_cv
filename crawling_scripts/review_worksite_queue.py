"""Review queued worksite identities without spending LLM tokens.

Examples:
    python crawling_scripts/review_worksite_queue.py
    python crawling_scripts/review_worksite_queue.py --resolve 12 --worksite-id 6761
    python crawling_scripts/review_worksite_queue.py --resolve 13 \
        --new-name "신규센터" --address "건물 101호"
    python crawling_scripts/review_worksite_queue.py --resolve 14 --skip

After resolving an item, this command reruns the cached pipeline immediately.
The posting then uses the saved human decision without waiting for the next
scheduled crawl.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys

from crawler_config import get_supabase_credentials
from supabase import create_client
from worksite_norm import (
    canonicalize_worksite_display_name,
    normalize_worksite_name,
)

ROOT = Path(__file__).resolve().parent.parent
PIPELINE_CLI = ROOT / "crawling_scripts" / "crawler_pipeline" / "cli.py"


def _client():
    url, key = get_supabase_credentials()
    return create_client(url, key)


def _resolve_rpc(client, **params) -> dict:
    response = client.rpc("resolve_worksite_review", params).execute()
    data = response.data
    if isinstance(data, list):
        data = data[0] if data else None
    if not isinstance(data, dict):
        raise RuntimeError("resolve_worksite_review returned no result")
    return data


def resolve_existing(client, queue_id: int, worksite_id: int, *,
                     global_alias: bool = False, learn_alias: bool | None = None) -> dict:
    return _resolve_rpc(
        client,
        p_queue_id=queue_id,
        p_action="existing",
        p_worksite_id=worksite_id,
        p_new_name=None,
        p_normalized_name=None,
        p_address=None,
        p_learn_alias=learn_alias,
        p_global_alias=global_alias,
    )


def resolve_new(client, queue_id: int, name: str, address: str | None = None,
                *, global_alias: bool = False) -> dict:
    display_name = canonicalize_worksite_display_name(name)
    normalized_name = normalize_worksite_name(display_name)
    if not display_name or not normalized_name:
        raise ValueError("new worksite name normalizes to empty")
    return _resolve_rpc(
        client,
        p_queue_id=queue_id,
        p_action="new",
        p_worksite_id=None,
        p_new_name=display_name,
        p_normalized_name=normalized_name,
        p_address=address.strip() if address else None,
        # 신규 정본명 자체를 그 정본명의 별칭으로 자동 학습할 이득은 없고,
        # 잘못 추출된 원문 표기를 영구 규칙으로 굳힐 위험만 커진다.
        p_learn_alias=False,
        p_global_alias=global_alias,
    )


def skip(client, queue_id: int) -> dict:
    return _resolve_rpc(
        client,
        p_queue_id=queue_id,
        p_action="skip",
        p_worksite_id=None,
        p_new_name=None,
        p_normalized_name=None,
        p_address=None,
        p_learn_alias=False,
        p_global_alias=False,
    )


def reprocess_pending_postings() -> dict:
    """Run the cached pipeline immediately after a review decision."""
    env = os.environ.copy()
    env["PYTHONIOENCODING"] = "utf-8"
    completed = subprocess.run(
        [sys.executable, str(PIPELINE_CLI)],
        cwd=ROOT,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        env=env,
        timeout=120,
        check=False,
    )
    output_lines = [
        line.strip() for line in completed.stdout.splitlines() if line.strip()
    ]
    if completed.returncode != 0:
        detail = completed.stderr.strip() or (
            output_lines[-1] if output_lines else "no pipeline output"
        )
        raise RuntimeError(
            "review decision was saved, but posting reprocessing failed "
            f"(exit {completed.returncode}): {detail}"
        )
    if not output_lines:
        raise RuntimeError(
            "review decision was saved, but posting reprocessing returned no result"
        )
    try:
        payload = json.loads(output_lines[-1])
    except json.JSONDecodeError as exc:
        raise RuntimeError(
            "review decision was saved, but posting reprocessing returned "
            "an invalid result"
        ) from exc
    if not isinstance(payload, dict):
        raise RuntimeError(
            "review decision was saved, but posting reprocessing returned "
            "an invalid payload"
        )
    return payload


def resolution_with_reprocessing(
    result: dict,
    *,
    reprocess_fn=None,
) -> dict:
    runner = reprocess_fn or reprocess_pending_postings
    return {
        **result,
        "pipeline": runner(),
    }


def finish_interactive_resolution(
    result: dict,
    *,
    reprocess_fn=None,
    output_fn=print,
) -> bool:
    try:
        resolution_with_reprocessing(
            result,
            reprocess_fn=reprocess_fn,
        )
    except Exception as exc:
        output_fn(f"검토 결정은 저장됐지만 공고 DB 반영에 실패했습니다: {exc}")
        return False
    output_fn("공고 DB 반영 완료")
    return True


def list_queue(client, include_all: bool = False) -> list[dict]:
    query = (
        client.table("worksite_resolution_queue")
        .select(
            "id, source, external_id, raw_worksite_name, normalized_worksite,"
            "title, evidence_text, office_phone, resolution_reason, explicit_worksite_names,"
            "candidate_scores, status, resolved_worksite_id, created_at"
        )
        .order("created_at")
    )
    if not include_all:
        query = query.eq("status", "pending")
    return query.execute().data or []


def _print_human(rows: list[dict]) -> None:
    if not rows:
        print("검토 대기 근무지가 없습니다.")
        return
    for row in rows:
        print(f"\n#{row['id']} [{row['source']}] {row['raw_worksite_name']}")
        print(f"  사유: {row['resolution_reason']} / 제목: {row.get('title') or '-'}")
        if row.get("explicit_worksite_names"):
            print("  본문 조직:", ", ".join(row["explicit_worksite_names"]))
        if row.get("evidence_text"):
            for line in row["evidence_text"].splitlines():
                print(f"  > {line}")
        if row.get("office_phone"):
            print(f"  사무실 전화: {row['office_phone']}")
        candidates = row.get("candidate_scores") or []
        if candidates:
            print("  후보:")
            for item in candidates:
                address = f" · {item['address']}" if item.get("address") else ""
                print(
                    f"    {item['worksite_id']}: {item['workplace_name']}"
                    f" ({item['score']:.3f}){address}"
                )
        print(
            f"  선택: --resolve {row['id']} --worksite-id ID"
            f"  또는 --new-name \"이름\""
        )


def interactive_review(
    client,
    *,
    input_fn=input,
    output_fn=print,
    reprocess_fn=None,
) -> int:
    """Review pending rows one by one using number/letter choices."""
    rows = list_queue(client)
    if not rows:
        output_fn("검토 대기 중인 근무지가 없습니다.")
        return 0

    for row in rows:
        output_fn("")
        output_fn(f"#{row['id']} [{row['source']}] {row['raw_worksite_name']}")
        output_fn(f"제목: {row.get('title') or '-'}")
        output_fn(f"사유: {row['resolution_reason']}")
        if row.get("explicit_worksite_names"):
            output_fn("본문 조직: " + ", ".join(row["explicit_worksite_names"]))
        if row.get("evidence_text"):
            output_fn("확인 근거:")
            for line in row["evidence_text"].splitlines():
                output_fn(f"  {line}")
        if row.get("office_phone"):
            output_fn(f"사무실 전화: {row['office_phone']}")

        candidates = row.get("candidate_scores") or []
        if candidates:
            output_fn("기존 근무지 후보:")
            for index, item in enumerate(candidates, start=1):
                address = f" · {item['address']}" if item.get("address") else ""
                output_fn(
                    f"  {index}. {item['workplace_name']}"
                    f" (ID {item['worksite_id']}, 유사도 {item['score']:.3f}){address}"
                )
        output_fn("  I. 다른 기존 근무지 ID 입력")
        output_fn("  N. 신규 근무지 등록")
        output_fn("  S. 이 공고 제외")
        output_fn("  L. 나중에 검토")
        output_fn("  Q. 검토 종료")

        while True:
            choice = input_fn("선택: ").strip().lower()
            if choice.isdigit() and 1 <= int(choice) <= len(candidates):
                target = candidates[int(choice) - 1]
                result = resolve_existing(client, row["id"], target["worksite_id"])
                output_fn(f"연결 완료: {result['worksite']['workplace_name']}")
                if not finish_interactive_resolution(
                    result,
                    reprocess_fn=reprocess_fn,
                    output_fn=output_fn,
                ):
                    return 1
                break
            if choice == "i":
                raw_id = input_fn("기존 근무지 ID: ").strip()
                if not raw_id.isdigit():
                    output_fn("숫자 ID를 입력해 주세요.")
                    continue
                result = resolve_existing(client, row["id"], int(raw_id))
                output_fn(f"연결 완료: {result['worksite']['workplace_name']}")
                if not finish_interactive_resolution(
                    result,
                    reprocess_fn=reprocess_fn,
                    output_fn=output_fn,
                ):
                    return 1
                break
            if choice == "n":
                name = input_fn("신규 근무지명: ").strip()
                if not name:
                    output_fn("근무지명을 입력해 주세요.")
                    continue
                address = input_fn("주소/호실(없으면 Enter): ").strip() or None
                result = resolve_new(client, row["id"], name, address)
                output_fn(f"신규 등록 완료: {result['worksite']['workplace_name']}")
                if not finish_interactive_resolution(
                    result,
                    reprocess_fn=reprocess_fn,
                    output_fn=output_fn,
                ):
                    return 1
                break
            if choice == "s":
                result = skip(client, row["id"])
                if not finish_interactive_resolution(
                    result,
                    reprocess_fn=reprocess_fn,
                    output_fn=output_fn,
                ):
                    return 1
                output_fn("공고를 제외했습니다.")
                break
            if choice == "l":
                output_fn("결정하지 않고 다음으로 넘어갑니다.")
                break
            if choice == "q":
                output_fn("검토를 종료합니다.")
                return 0
            output_fn("후보 번호 또는 I/N/S/L/Q를 입력해 주세요.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="근무지 정규화 검토 대기열")
    parser.add_argument("--resolve", type=int, metavar="QUEUE_ID")
    choice = parser.add_mutually_exclusive_group()
    choice.add_argument("--worksite-id", type=int)
    choice.add_argument("--new-name")
    choice.add_argument("--skip", action="store_true")
    parser.add_argument("--address")
    parser.add_argument("--global-alias", action="store_true")
    parser.add_argument("--learn-alias", action="store_true",
                        help="본문 충돌 건도 선택한 별칭을 학습(주의해서 사용)")
    parser.add_argument("--all", action="store_true")
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--interactive", action="store_true",
                        help="대기 건을 하나씩 보며 번호로 선택")
    args = parser.parse_args()

    sys.stdout.reconfigure(encoding="utf-8")
    client = _client()
    if args.resolve is None:
        if args.interactive:
            return interactive_review(client)
        rows = list_queue(client, include_all=args.all)
        if args.json:
            print(json.dumps(rows, ensure_ascii=False, indent=2))
        else:
            _print_human(rows)
        return 0

    if sum((
        args.worksite_id is not None,
        bool(args.new_name),
        args.skip,
    )) != 1:
        parser.error("--resolve에는 --worksite-id, --new-name, --skip 중 하나가 필요합니다")

    if args.worksite_id is not None:
        result = resolve_existing(
            client,
            args.resolve,
            args.worksite_id,
            global_alias=args.global_alias,
            learn_alias=True if args.learn_alias else None,
        )
    elif args.new_name:
        result = resolve_new(
            client,
            args.resolve,
            args.new_name,
            args.address,
            global_alias=args.global_alias,
        )
    else:
        result = skip(client, args.resolve)
    try:
        result = resolution_with_reprocessing(result)
    except Exception as exc:
        print(json.dumps({
            "review": result,
            "pipeline": {
                "status": "failed",
                "error": str(exc),
            },
        }, ensure_ascii=False, indent=2))
        return 1
    print(json.dumps(result, ensure_ascii=False, indent=2))
    print("검토 결정과 공고 DB 반영이 완료됐습니다.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
