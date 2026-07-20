"""
================================================================================
[Day 1 종합실습] 저장 모듈 — CSV vs Parquet 저장·읽기 성능 비교
================================================================================
#작성자: 최강희
#작성일: 2026-07-20
#변경내역:
#    v1.0 (2026-07-20) 최초 작성 — 두 형식 쓰기/읽기 시간과 파일 크기 측정
#    v1.1 (2026-07-20) 크기 비교 해석을 측정값 기반 분기로 수정 —
#                      소규모 데이터에서 Parquet 이 더 큰 경우를 반영
측정 방법
    - time.perf_counter 로 쓰기/읽기 각각 REPEAT 회 반복해 평균을 낸다
      (1회 측정은 OS 캐시·디스크 상태에 따라 편차가 커서 신뢰도가 낮다)
    - 파일 크기(bytes)도 함께 기록해 공간 효율까지 비교한다
================================================================================
"""

import logging
import time
from pathlib import Path

import pandas as pd

logger = logging.getLogger("pipeline")

REPEAT = 5  # 측정 반복 횟수 (평균으로 편차 완화)


def _timeit(func) -> float:
    """func 를 REPEAT 회 실행해 평균 소요시간(ms)을 반환한다."""
    elapsed = 0.0
    for _ in range(REPEAT):
        start = time.perf_counter()
        func()
        elapsed += time.perf_counter() - start
    return elapsed / REPEAT * 1000  # ms


def benchmark_formats(df: pd.DataFrame, out_dir: Path) -> list[dict]:
    """DataFrame 을 CSV·Parquet 로 저장/재로딩하며 성능을 측정한다.

    Args:
        df: 검증을 통과한 데이터
        out_dir: 파일을 저장할 폴더
    Returns:
        형식별 측정 결과 [{format, write_ms, read_ms, size_bytes}, ...]
    Raises:
        OSError: 파일 쓰기에 실패한 경우 (호출부에서 처리)
        ImportError: parquet 엔진(pyarrow) 미설치 시 (호출부에서 처리)
    """
    csv_path = out_dir / "weather.csv"
    pq_path = out_dir / "weather.parquet"

    results = [
        {
            "format": "CSV",
            "write_ms": _timeit(lambda: df.to_csv(csv_path, index=False)),
            "read_ms": _timeit(lambda: pd.read_csv(csv_path)),
            "size_bytes": csv_path.stat().st_size,
        },
        {
            "format": "Parquet",
            "write_ms": _timeit(lambda: df.to_parquet(pq_path, index=False)),
            "read_ms": _timeit(lambda: pd.read_parquet(pq_path)),
            "size_bytes": pq_path.stat().st_size,
        },
    ]

    # 왕복 무결성: 두 형식 모두 원본과 행 수가 같아야 한다
    for path, fmt in ((csv_path, "CSV"), (pq_path, "Parquet")):
        reloaded = pd.read_csv(path) if fmt == "CSV" else pd.read_parquet(path)
        assert len(reloaded) == len(df), f"{fmt} 재로딩 행 수가 원본과 다릅니다."
    return results


def print_benchmark(results: list[dict]) -> None:
    """측정 결과를 표 형태로 출력하고 간단한 해석을 덧붙인다."""
    print("\n[성능 비교] 쓰기/읽기 평균 (반복 %d회)" % REPEAT)
    print(f"  {'형식':<8}{'쓰기(ms)':>10}{'읽기(ms)':>10}{'크기(bytes)':>14}")
    for r in results:
        print(
            f"  {r['format']:<8}{r['write_ms']:>10.2f}"
            f"{r['read_ms']:>10.2f}{r['size_bytes']:>14,}"
        )
    csv_r, pq_r = results[0], results[1]
    csv_size, pq_size = csv_r["size_bytes"], pq_r["size_bytes"]
    if pq_size < csv_size:
        print(f"  → 파일 크기: Parquet 이 CSV 의 1/{csv_size / pq_size:.1f} 수준으로 작다.")
    else:
        print(
            f"  → 파일 크기: 이 규모에서는 Parquet 이 CSV 의 "
            f"{pq_size / csv_size:.1f}배로 오히려 크다 — 스키마·푸터 등 "
            "메타데이터 오버헤드가 본문보다 크기 때문이다."
        )
    print("     컬럼 지향 압축은 데이터가 늘수록 유리해져 수천 행 이상에서 역전된다.")
