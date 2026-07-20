"""
================================================================================
[Day 1 종합실습] 데이터 수집 미니 파이프라인 — 메인
================================================================================
#작성자: 최강희
#작성 목적: 3개 공개 API 를 비동기 수집해 검증·저장하고 CSV/Parquet 성능을 비교
#작성일: 2026-07-20
#변경내역:
#    v1.0 (2026-07-20) 최초 작성
#    v1.1 (2026-07-20) 개인 템플릿 정합화 — __main__ 의 AssertionError 처리,
#                      경고 레벨 한글화, 작성 목적 명시

프로그램 개요 (실습 요구 대응)
    1) 비동기 수집   : asyncio + httpx 로 3개 API 동시 수집 (collect.py)
                       Open-Meteo(서울 3일 예보) / Countries.dev / ip-api
    2) 스키마 검증   : 필요한 필드만 추출해 Pydantic v2 모델로 검증 (models.py)
                       타입 오류·범위 이탈은 ValidationError 로 잡아 집계
    3) 저장·성능     : 검증 통과 데이터를 CSV·Parquet 로 저장하고
                       쓰기/읽기 평균 시간과 파일 크기 비교 (storage.py)
    4) 테스트        : pytest 로 스키마 검증 테스트 (test_models.py)

실행 방법
    venv 활성화 후:  pip install -r requirements.txt  →  python main.py
    테스트         :  pytest -v
    스타일 검사     :  ruff check .

출력 규칙
    - 운영 메시지(수집·오류) : logging → stderr
    - 결과 리포트           : print → stdout
================================================================================
"""

import asyncio
import logging
import sys
from pathlib import Path

import pandas as pd
from pydantic import ValidationError

from collect import collect_all, extract_country, extract_ip, extract_weather_rows
from models import CountryInfo, IpInfo, WeatherHourly
from storage import benchmark_formats, print_benchmark

logging.basicConfig(
    stream=sys.stderr, level=logging.INFO, format="[%(levelname)s] %(message)s"
)
logging.addLevelName(logging.ERROR, "오류")
logging.addLevelName(logging.WARNING, "경고")
logging.addLevelName(logging.INFO, "정보")
logger = logging.getLogger("pipeline")

BASE_DIR = Path(__file__).parent
OUT_DIR = BASE_DIR / "output"


def banner(title: str) -> None:
    """구분선과 제목을 출력한다 (리포트 서식 통일용)."""
    print("=" * 62, f" {title}", "=" * 62, sep="\n")


def validate_weather(rows: list[dict]) -> list[WeatherHourly]:
    """날씨 행 목록을 검증해 통과분만 반환하고 실패는 사유와 함께 집계한다.

    ValidationError 만 잡는다 — Exception 전체를 잡으면 코드 버그까지
    삼켜 원인 파악이 어려워지므로 검증 실패와 프로그램 오류를 구분한다.
    ※ try/except 로 결과를 갈라 담는 루프이므로 컴프리헨션 대상이 아니다.

    Args:
        rows: extract_weather_rows 가 만든 행 dict 리스트
    Returns:
        검증 통과 WeatherHourly 리스트
    """
    valid: list[WeatherHourly] = []
    failed = 0
    for i, row in enumerate(rows, start=1):
        try:
            valid.append(WeatherHourly(**row))
        except ValidationError as exc:
            failed += 1
            reason = "; ".join(
                f"{'.'.join(map(str, e['loc']))}: {e['msg']}" for e in exc.errors()
            )
            print(f"  [검증 실패] {i}행 → {reason}")
    if failed:
        logger.error("날씨 데이터 %d행이 검증에서 제외되었습니다.", failed)
    return valid


def validate_single(model, data: dict, label: str):
    """단건 응답(국가/IP)을 모델로 검증한다. 실패 시 사유 출력 후 None.

    Args:
        model: 적용할 Pydantic 모델 클래스
        data: 추출된 필드 dict
        label: 리포트에 표시할 이름
    Returns:
        검증 통과 모델 인스턴스 또는 None
    """
    try:
        obj = model(**data)
        print(f"  [{label}] 검증 통과: {obj.model_dump()}")
        return obj
    except ValidationError as exc:
        reason = "; ".join(
            f"{'.'.join(map(str, e['loc']))}: {e['msg']}" for e in exc.errors()
        )
        print(f"  [{label}] 검증 실패 → {reason}")
        return None


def main() -> int:
    """수집 → 추출 → 검증 → 저장·성능 비교 순으로 실행한다.

    Returns:
        정상 0, 수집·검증·저장 실패 시 1 (셸에서 성공/실패 판별용)
    """
    banner("데이터 수집 미니 파이프라인 (asyncio + Pydantic + CSV/Parquet)")

    # [1] 비동기 수집: 3개 API 동시 요청 (gather)
    print("[수집] 3개 API 동시 요청 중...")
    weather_raw, country_raw, ip_raw = asyncio.run(collect_all())
    ok_count = sum(x is not None for x in (weather_raw, country_raw, ip_raw))
    print(f"  수집 결과: {ok_count}/3 성공")
    if weather_raw is None:  # 날씨는 저장·성능 비교의 원천이라 없으면 진행 불가
        logger.error("날씨 데이터 수집 실패로 파이프라인을 중단합니다.")
        return 1

    # [2] 필드 추출 + Pydantic 검증
    print("\n[검증] Pydantic v2 스키마 검증")
    weather_valid = validate_weather(extract_weather_rows(weather_raw))
    print(f"  [날씨] 검증 통과: {len(weather_valid)}행 (3일 × 24시간 = 72행 기대)")
    if country_raw is not None:
        validate_single(CountryInfo, extract_country(country_raw), "국가")
    if ip_raw is not None:
        validate_single(IpInfo, extract_ip(ip_raw), "IP")
    if not weather_valid:
        logger.error("검증을 통과한 날씨 데이터가 없어 저장을 생략합니다.")
        return 1

    # [3] CSV vs Parquet 저장·성능 비교 (model_dump 로 직렬화)
    OUT_DIR.mkdir(exist_ok=True)
    df = pd.DataFrame([w.model_dump() for w in weather_valid])
    try:
        results = benchmark_formats(df, OUT_DIR)
    except ImportError:
        logger.error("pyarrow 미설치 — requirements.txt 로 설치 후 재실행하세요.")
        return 1
    except OSError as exc:
        logger.error("파일 저장 실패: %s", exc)
        return 1
    print_benchmark(results)

    banner("파이프라인 정상 완료 (pytest -v / ruff check . 로 마무리 점검)")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as exc:  # 무결성 검증 실패를 명확히 보고 (템플릿 패턴)
        logger.error("검증 실패: %s", exc)
        raise SystemExit(1)
