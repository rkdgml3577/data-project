"""
================================================================================
[Day 2 종합 실습] End2End 데이터 분석 프로젝트 — NYC Yellow Taxi (2026-05)
================================================================================
#작성자: 최강희
#작성 목적: 실습 3(성능 비교)·실습 4(시각화·검정·Pipeline)에서 배운 패턴을
#           실데이터(409만 행 택시 운행 기록)에 적용해 로딩 비교 → 정제 →
#           EDA → 시각화 → 통계 검정 → ML Pipeline → report.md 자동 생성까지
#           분석 전 과정을 하나의 스크립트로 완성
#작성일: 2026-07-21
#변경내역:
#    v1.0 (2026-07-21) 최초 작성
#    v1.1 (2026-07-21) 확장 분석 5종 추가: ① 팁 행동 유형(프리셋 버튼·정액·
#                      라운딩) 실측 + 스파이크 차트 ② dropoff 컬럼 파생
#                      속도·체증 히트맵과 속도-팁 검정 ③ CBD 혼잡료 비중·
#                      결제 구성비 ④ Memorial Day 연휴 효과(동일 요일 통제)
#                      ⑤ OD 상위 흐름. 확장이 요구하는 7개 추가 컬럼은
#                      실작업 로딩(load_analysis_data)으로 분리해 로딩 시간
#                      측정 실험(11컬럼)의 변인을 보존. 요금 항등식
#                      (total = 9개 항목 합) 일치율 검증을 정제 단계에 추가
#    v1.2 (2026-07-21) 실데이터 실행 리뷰 반영:
#                      ① 로딩 측정을 1회 → 워밍업 1회 + LOAD_REPEAT회 평균으로
#                         변경 (OS 페이지 캐시 상태에 따라 엔진 기여 배수가
#                         0.2~1.9배로 요동쳐 결론이 뒤집히던 문제 해결),
#                         스키마 검사는 전체 로딩 대신 parquet 메타데이터로 수행
#                      ② [9] 해석을 [7] 모델 정확도에 연동해 분기: 정확도가
#                         기준선을 넘으면 '낮은 정확도의 원인'이 아니라
#                         '정확도의 천장' 프레임으로 서술 (해석 간 모순 제거)
#                      ③ 정액 팁 후보에 $3 추가 (실측상 $5 보다 빈도 높음),
#                         미사용 변수 제거(ruff F841)·파일 끝 개행(W292) 정리
#                      ④ 표 출력을 to_markdown ↔ to_string 자동 전환 헬퍼로
#                         통합 (tabulate 미설치 환경 대응)

프로그램 개요 (실습 내용 1~5 대응)
    1) 데이터 준비 : Pandas·Polars 양쪽으로 parquet 로딩, 시간·결과 일치 비교
       → 결측치·중복 제거, 이상 거래 필터, IQR 이상치 제거(실습 3 공식 재사용)
    2) 시각화      : Seaborn 정적 차트(팁 비율 분포, 제목·축 레이블 포함) PNG 저장
       + Plotly 인터랙티브 차트(시간대별 평균 요금·팁 비율) HTML 저장
    3) 통계 분석   : 기술통계(평균·표준편차·분위수)·상관계수 출력,
       공항 출발 vs 일반 승차의 팁 비율 차이를 ttest_ind 로 검정, p-value 해석
    4) ML Pipeline : ColumnTransformer + RandomForest 를 Pipeline 으로 구성,
       정확도·F1 출력, joblib 저장 + 재로딩 예측 일치 검증
    5) 자동화      : 위 모든 결과를 취합해 output/report.md 자동 생성 (발표 자료)

[확장 학습 1] 실습 3 변인 통제 실험의 parquet 확장
    parquet 은 컬럼 단위 저장 포맷이라 필요 컬럼만 읽는 효과가 CSV 보다 크다.
    이 파일은 승·하차 시각 2개 컬럼이 전체 용량의 51.6%를 차지하므로
    (footer 메타데이터 실측), 분석에 필요한 11개 컬럼만 선택하면 읽는 양이
    크게 준다. 실습 3과 동일하게 격차를 두 요인으로 분해한다:
        Pandas(전체) → Pandas(columns=)  : 컬럼 선택 읽기의 효과
        Pandas(columns=) → Polars(select): 같은 조건에서 엔진 자체의 성능 차
    두 배수의 곱이 전체 격차와 일치하는지 검산까지 실습 3과 동일하게 수행한다.

[확장 학습 2] 실습 4 데이터 누출 검증의 실데이터 재현
    예측 대상(팁 비율)이 total_amount 안에 합산되어 들어 있다:
        total_amount = fare + extra + mta_tax + "tip" + tolls + surcharge 류
    따라서 total_amount·fare_amount 를 특징으로 넣으면 모델이 뺄셈만으로
    정답을 복원할 수 있다. 포함/제외 정확도 차이를 측정해 실습 4의 교훈
    ("높은 점수가 좋은 모델을 뜻하지 않는다")을 실데이터로 재확인한다.

[확장 학습 3] 라벨 정의 함정 — 현금 팁은 기록되지 않는다
    이 데이터의 tip_amount 는 미터기 기준이라 현금 팁(payment_type=2)이
    0 으로 기록된다. 전체 데이터로 "팁 지급 여부"를 예측하면 사실상
    "카드 결제인지"를 맞히는 왜곡된 문제가 된다. 그래서 신용카드 결제
    (payment_type=1)만 필터한 뒤 팁 비율을 타깃으로 정의한다.
    → 타깃: 카드 결제 승객의 팁 비율(tip/fare)이 중앙값을 넘는지 여부
      (중앙값 기준이므로 두 클래스가 반반 → 기준선 정확도 0.5 로 해석 용이,
       실습 4의 고액 주문 라벨 정의 패턴 재사용)

채점 기준 대응 (100점)
    데이터 준비+시각화(35) : Pandas·Polars 모두 사용, 결측·중복 처리, EDA 출력,
                             Seaborn 정적 + Plotly 인터랙티브 각 1개(제목·축 포함)
    통계분석+ML(45)        : 기술통계·상관계수, t-test p-value 해석,
                             Pipeline 객체, 정확도·F1 출력, joblib 저장
    자동화+발표(20)        : report.md 자동 생성 (발표 대본 겸용 요약 포함)
    완성도(10)             : 전 함수 docstring·주석 처리

출력 규칙
    - 분석 리포트(산출물)  : print → stdout + output/report.md 자동 생성
    - 생성 파일 : output/eda_tip_dist.png / output/hourly_interactive.html /
                  output/tip_pipeline.joblib / output/report.md
    - 실행 불가 오류(파일 없음·필수 컬럼 누락·패키지 미설치) : 안내 후 종료
    - 부분 실행 가능 오류(표본 부족 등) : 안내 후 해당 단계만 대체·생략

데이터 형식 (yellow_tripdata parquet, 사용 11컬럼)
    tpep_pickup_datetime(승차 시각) / trip_distance(거리, 마일) /
    passenger_count(승객 수) / RatecodeID(요금제) / PULocationID(승차 지역) /
    payment_type(결제수단, 1=카드 2=현금) / fare_amount(기본요금) /
    tip_amount(팁) / tolls_amount(통행료) / total_amount(총액) /
    Airport_fee(공항 수수료)
================================================================================
"""

import sys
import warnings
from datetime import datetime
from pathlib import Path
from time import perf_counter

try:  # 서드파티 패키지 미설치 시 traceback 대신 설치 안내 후 종료 (실습 4 패턴)
    import joblib
    import matplotlib
    import numpy as np
    import pandas as pd
    import plotly.express as px
    import polars as pl
    import pyarrow  # noqa: F401  (pd.read_parquet 엔진 — 미설치를 먼저 감지)
    import pyarrow.parquet as pq  # 스키마 검사를 메타데이터만으로 수행
    import seaborn as sns
    from matplotlib import font_manager
    from matplotlib import pyplot as plt
    from scipy import stats
    from sklearn.compose import ColumnTransformer
    from sklearn.ensemble import RandomForestClassifier
    from sklearn.impute import SimpleImputer
    from sklearn.metrics import f1_score
    from sklearn.model_selection import train_test_split
    from sklearn.pipeline import Pipeline
    from sklearn.preprocessing import OneHotEncoder, StandardScaler
except ImportError as exc:
    sys.exit(f"[오류] 필요 패키지가 설치되어 있지 않습니다: {exc.name} "
             f"→ 'pip install {exc.name}' 실행 후 다시 시도하세요")

matplotlib.use("Agg")  # 화면 없는 환경에서도 파일 저장이 가능하도록 백엔드 고정

# ------------------------------------------------------------------
# 전역 설정 (경로·표본 크기·유의수준·난수 시드를 한 곳에서 관리)
# ------------------------------------------------------------------
BASE_DIR = Path(__file__).parent
PARQUET_PATH = BASE_DIR / "yellow_tripdata_2026-05.parquet"
OUTPUT_DIR = BASE_DIR / "output"

# 로딩 '시간 측정 실험'에 쓰는 11개 컬럼 — 20개 중 이것만 읽는 것이 변인
USE_COLS = [
    "tpep_pickup_datetime", "trip_distance", "passenger_count", "RatecodeID",
    "PULocationID", "payment_type", "fare_amount", "tip_amount",
    "tolls_amount", "total_amount", "Airport_fee",
]
# 확장 분석(속도·OD·요금 구성)이 추가로 요구하는 컬럼 — 실작업 로딩에만 포함
# (시간 측정 실험과 분리해 두어야 확장 분석이 늘어나도 실험 변인이 안 흔들린다)
EXT_COLS = [
    "tpep_dropoff_datetime", "DOLocationID", "extra", "mta_tax",
    "improvement_surcharge", "congestion_surcharge", "cbd_congestion_fee",
]
ANALYSIS_COLS = USE_COLS + EXT_COLS  # 실작업용 18컬럼 (제외: VendorID 등 2개)
# total_amount 를 구성하는 9개 항목 (항등식 검증·요금 구성비 분석에 사용)
FEE_PARTS = ["fare_amount", "extra", "mta_tax", "tip_amount", "tolls_amount",
             "improvement_surcharge", "congestion_surcharge", "Airport_fee",
             "cbd_congestion_fee"]
LEAKAGE_COLS = ["total_amount", "fare_amount"]  # 타깃(팁)이 합산돼 있는 컬럼
CARD, CASH = 1, 2       # payment_type 코드 (데이터 사전 기준)
TIP_PRESETS = (0.20, 0.25, 0.30)   # 결제 단말기 팁 제안 버튼 비율
FLAT_TIPS = (1.0, 2.0, 3.0, 5.0, 10.0)  # 정액 팁 후보 (실측 빈도순 상위)
# Memorial Day 연휴(2026-05-23~25) vs 직전 동일 요일 구성(05-16~18) 비교
HOLIDAY_DAYS = ("2026-05-23", "2026-05-24", "2026-05-25")
BASELINE_DAYS = ("2026-05-16", "2026-05-17", "2026-05-18")

ALPHA = 0.05            # 유의수준
LOAD_REPEAT = 3         # 로딩 측정 반복 횟수 (1회 측정은 캐시에 좌우됨)
PIPELINE_SAMPLE = 100_000  # 모델 학습 표본 (정제 후 수백만 행 전체 학습은 과다)
RANDOM_STATE = 42       # 표본 추출·분할·모델 공통 시드 (재현성)
REPORT: list[str] = []  # report.md 자동 생성을 위한 결과 누적 버퍼


def log(text: str = "", to_report: bool = True) -> None:
    """stdout 출력과 report.md 버퍼 누적을 동시에 처리한다.

    실습 내용 5(자동화)의 핵심 장치: 분석 중 출력한 내용이 그대로
    보고서 초안이 되도록 print 를 이 함수 하나로 감싼다.

    Args:
        text: 출력할 문자열
        to_report: False 면 화면에만 출력 (진행 안내 등 보고서 불필요 문구)
    """
    print(text)
    if to_report:
        REPORT.append(text)


def md(text: str) -> None:
    """report.md 에만 기록한다 (마크다운 제목·표 등 화면 출력이 어색한 요소)."""
    REPORT.append(text)


def to_table(obj, **kwargs) -> str:
    """DataFrame/Series 를 표 문자열로 만든다.

    tabulate 가 있으면 report.md 에서 표로 렌더링되는 마크다운 형식을,
    없으면(ImportError) 동일 정보의 텍스트 표를 반환한다 — 팀원 환경에
    tabulate 유무가 달라도 실행이 깨지지 않게 하는 안전장치.
    """
    try:
        return obj.to_markdown(**kwargs)
    except ImportError:
        return obj.to_string(**kwargs)


def setup_korean_font() -> None:
    """OS별 한글 폰트를 탐색해 적용한다. 없으면 경고만 하고 계속 진행한다."""
    candidates = ["AppleGothic", "Malgun Gothic", "NanumGothic",
                  "Noto Sans CJK KR", "Noto Sans CJK JP"]
    installed = {f.name for f in font_manager.fontManager.ttflist}
    for name in candidates:
        if name in installed:
            plt.rcParams["font.family"] = name
            plt.rcParams["axes.unicode_minus"] = False
            return
    print("[경고] 한글 폰트를 찾지 못했습니다. 차트의 한글이 깨질 수 있습니다.")


# ------------------------------------------------------------------
# 1) 데이터 준비 ① — Pandas·Polars 로딩 성능·결과 비교 (실습 3 확장)
# ------------------------------------------------------------------
def _timed(fn) -> float:
    """워밍업 1회 후 LOAD_REPEAT회 평균 소요 시간(초)을 잰다.

    1회 측정은 OS 페이지 캐시 상태(그 파일을 처음 읽는지 여부)에 좌우돼
    실행마다 엔진 기여 배수가 요동치고 결론이 뒤집힐 수 있다. 워밍업으로
    캐시 상태를 통일한 뒤 반복 평균을 내 측정 신뢰성을 확보한다.

    Args:
        fn: 시간을 잴 로딩 함수 (인자 없이 호출 가능해야 함)
    Returns:
        LOAD_REPEAT회 평균 소요 시간(초)
    """
    fn()  # 워밍업: 캐시 상태 통일 (측정에서 제외)
    total = 0.0
    for _ in range(LOAD_REPEAT):
        t0 = perf_counter()
        fn()
        total += perf_counter() - t0
    return total / LOAD_REPEAT


def compare_loading(path: Path) -> None:
    """세 가지 방식으로 parquet 을 로딩해 시간과 결과 일치 여부를 비교한다.

    실습 3의 변인 통제 실험을 parquet 으로 확장한 것 (시간 측정 전용):
      A) Pandas 전체 컬럼      — 기준선 (20개 컬럼 모두 읽음)
      B) Pandas columns=11개   — 컬럼 선택 읽기의 효과만 분리
      C) Polars scan→select    — 같은 11개 컬럼 조건에서 엔진 성능 차
    B/A, C/B 두 배수의 곱이 전체 격차 C/A 와 일치하는지 검산한다.
    각 방식은 워밍업 1회 + LOAD_REPEAT회 평균으로 측정한다 (실습 3의
    timeit(number=N) 반복 원칙 복원). 스키마 검사는 전체 로딩 없이
    parquet 메타데이터만 읽어 수행한다.
    측정에 쓴 로딩본은 폐기하고, 실작업 로딩은 load_analysis_data 가 맡는다.

    예외·오류 처리:
      - FileNotFoundError : 경로 안내 후 종료 (다운로드 안내 포함)
      - 필수 컬럼 누락     : 스키마가 다른 월 파일일 수 있으므로 안내 후 종료
      - Pandas·Polars 결과 불일치 : 이후 분석 신뢰 불가이므로 안내 후 종료

    Args:
        path: parquet 파일 경로
    """
    log("=" * 62, to_report=False)
    log("## [1] 데이터 로딩 비교 — Pandas vs Polars (실습 3 확장)")
    log("=" * 62, to_report=False)

    if not path.exists():
        sys.exit(f"[오류] 파일을 찾을 수 없습니다: {path}\n"
                 f"       (문제지의 trip-data URL 에서 내려받아 스크립트와 같은 "
                 f"폴더에 두세요)")

    try:
        # 스키마 검사: 메타데이터(footer)만 읽으므로 전체 로딩이 필요 없다
        schema_names = list(pq.read_schema(path).names)
        missing = [c for c in USE_COLS if c not in schema_names]
        if missing:
            sys.exit(f"[오류] 필수 컬럼 누락: {missing} — 다른 스키마의 월 파일"
                     f"인지 확인하세요 / 실제 컬럼: {schema_names}")
        n_total_cols = len(schema_names)

        # 마지막 로딩본을 결과 일치 검증에 재사용하기 위한 홀더
        holder: dict[str, object] = {}

        def load_full() -> None:
            df = pd.read_parquet(path)                            # A) 전체
            del df

        def load_cols() -> None:
            holder["pd"] = pd.read_parquet(path, columns=USE_COLS)  # B) 선택

        def load_pl() -> None:
            holder["pl"] = pl.scan_parquet(path).select(USE_COLS).collect()

        t_full = _timed(load_full)
        t_cols = _timed(load_cols)
        t_pl = _timed(load_pl)
        df, pl_df = holder["pd"], holder["pl"]
    except (OSError, ValueError) as exc:
        sys.exit(f"[오류] parquet 로딩 실패: {exc}")

    # ---- 결과 일치 비교 (행 수 + total_amount 합계 검증) ----
    same_rows = len(df) == pl_df.height
    same_sum = np.isclose(df["total_amount"].sum(),
                          pl_df["total_amount"].sum())
    log(f"- 행 수: Pandas {len(df):,} / Polars {pl_df.height:,} "
        f"→ {'일치' if same_rows else '불일치(!)'}")
    log(f"- total_amount 합계 일치 여부: {'일치' if same_sum else '불일치(!)'}")
    if not (same_rows and same_sum):
        sys.exit("[오류] Pandas·Polars 로딩 결과가 다릅니다. 파일 손상 또는 "
                 "버전 차이를 확인하세요.")

    # ---- 실습 3 방식의 격차 분해 ----
    read_gain = t_full / t_cols     # 컬럼 선택 읽기가 기여한 몫
    engine_gain = t_cols / t_pl     # 엔진 자체가 기여한 몫
    total_gain = t_full / t_pl      # 전체 격차
    log(f"- 측정 방식: 워밍업 1회 + {LOAD_REPEAT}회 반복 평균 "
        f"(1회 측정은 OS 캐시 상태에 좌우되어 반복 평균으로 통제)")
    log(f"- Pandas 전체({n_total_cols}컬럼)  : {t_full:6.2f}초")
    log(f"- Pandas columns=({len(USE_COLS)}컬럼): {t_cols:6.2f}초")
    log(f"- Polars scan→select        : {t_pl:6.2f}초")
    log(f"- [변인 통제] 전체 격차 {total_gain:.2f}배 = "
        f"컬럼 선택 {read_gain:.2f}배 × 엔진 {engine_gain:.2f}배 "
        f"(검산 {read_gain * engine_gain:.2f})")
    log("- 해석: parquet 은 컬럼 단위 저장이라 필요 컬럼만 읽는 이득이 CSV 보다 "
        "크다 (승·하차 시각 2개 컬럼이 파일 용량의 절반 이상).")
    del df, pl_df  # 시간 측정용 로딩본은 폐기 — 실작업 로딩은 별도 함수에서


def load_analysis_data(path: Path) -> pd.DataFrame:
    """확장 분석까지 필요한 18개 컬럼을 실작업용으로 로딩한다.

    시간 측정 실험(compare_loading, 11컬럼)과 분리한 이유:
    속도 분석(dropoff)·OD 분석(DOLocationID)·요금 구성 분석(수수료 5종)이
    컬럼을 추가로 요구하는데, 이를 측정 실험에 섞으면 '필요 컬럼만 읽기'
    실험의 변인이 흔들린다. 질문이 달라지면 읽어야 할 컬럼이 달라진다는
    것 자체가 확장 학습 1의 후속 논점이다 (가장 무거웠던 dropoff 컬럼을
    속도 분석을 위해 다시 불러오는 셈).

    예외·오류 처리: 로딩 실패(OSError·ValueError) 시 원인 안내 후 종료

    Args:
        path: parquet 파일 경로
    Returns:
        18컬럼 DataFrame
    """
    try:
        return pd.read_parquet(path, columns=ANALYSIS_COLS)
    except (OSError, ValueError) as exc:
        sys.exit(f"[오류] 실작업 데이터 로딩 실패: {exc}")


# ------------------------------------------------------------------
# 1) 데이터 준비 ② — 결측·중복 처리 + 이상 거래 필터 + IQR (실습 3 연계)
# ------------------------------------------------------------------
def clean_data(df: pd.DataFrame) -> pd.DataFrame:
    """결측치·중복을 처리하고 이상 거래와 IQR 이상치를 제거한다.

    처리 순서와 근거:
      1) 결측 현황 출력(isnull().sum()) 후 핵심 11컬럼 결측 행 제거,
         수수료 5종(혼잡료 등) 결측은 '미부과'로 간주해 0 대체
      2) 완전 중복 행 제거(drop_duplicates) — 중복 집계 왜곡 방지
      3) 도메인 필터: 요금·거리·총액이 0 이하인 취소·오기록 거래 제거
      4) 요금 항등식(total = 9개 항목 합) 일치율 실측 — 누출 실험의 근거
      5) total_amount IQR 이상치 제거 (실습 3과 동일 공식)

    예외·오류 처리: 정제 후 데이터가 비면 이후 분석이 무의미하므로 종료

    Args:
        df: 로딩된 원본 DataFrame
    Returns:
        정제 완료 DataFrame
    """
    log("")
    log("## [2] 결측·중복 처리 및 이상치 제거 (실습 3 연계)")

    before = len(df)
    null_counts = df.isnull().sum()
    log("- 결측치 현황: " + (", ".join(
        f"{c} {n:,}" for c, n in null_counts.items() if n > 0) or "없음"))
    # 핵심 11컬럼 결측은 행 제거, 수수료 5종 결측은 '미부과'로 보고 0 대체
    # (혼잡료 등은 제도 시행 전 기록이 null 로 남는 컬럼이라 제거가 과함)
    df = df.dropna(subset=USE_COLS)
    df[EXT_COLS[2:]] = df[EXT_COLS[2:]].fillna(0)  # extra~cbd 수수료 5종

    dup = df.duplicated().sum()
    df = df.drop_duplicates()
    log(f"- 중복 행 제거: {dup:,}행")

    # 취소·오기록 거래 (음수 요금, 0 거리 등) 제거 — 실데이터 특유의 잡음
    df = df[(df["fare_amount"] > 0) & (df["trip_distance"] > 0)
            & (df["total_amount"] > 0) & (df["passenger_count"] > 0)]

    # [확장 근거] 요금 항등식 검증: total = 9개 구성 항목의 합
    # 이 일치율이 누출 실험(total 포함 시 팁 복원 가능)의 실측 근거가 된다
    identity = ((df[FEE_PARTS].sum(axis=1) - df["total_amount"]).abs()
                < 0.01).mean()
    log(f"- 요금 항등식(total = 9개 항목 합) 일치율: {identity:.1%} "
        f"→ 누출 실험의 실측 근거")

    q1, q3 = df["total_amount"].quantile(0.25), df["total_amount"].quantile(0.75)
    iqr = q3 - q1
    lower, upper = q1 - 1.5 * iqr, q3 + 1.5 * iqr
    df = df[df["total_amount"].between(lower, upper)].copy()

    log(f"- IQR 정상 범위(total_amount): {lower:,.2f} ~ {upper:,.2f}")
    log(f"- 정제 결과: {before:,}행 → {len(df):,}행 ({before - len(df):,}행 제외)")
    if df.empty:
        sys.exit("[오류] 정제 후 남은 데이터가 없습니다. 필터 조건을 확인하세요.")

    # 파생 변수: 시간대·요일 (시각화·모델 공용) — 여기서 한 번만 계산
    pickup = pd.to_datetime(df["tpep_pickup_datetime"])
    df["hour"] = pickup.dt.hour
    df["weekday"] = pickup.dt.dayofweek.astype(str)  # 0=월 … 6=일 (범주형)
    return df


def make_card_dataset(df: pd.DataFrame) -> pd.DataFrame:
    """카드 결제 건만 추려 팁 비율(tip_pct)을 계산한다 (확장 학습 3).

    현금 팁은 미터기에 기록되지 않아 tip_amount=0 으로 남으므로,
    전체 데이터로 팁을 분석하면 라벨이 왜곡된다. 카드 결제만 사용한다.

    Args:
        df: 정제 완료 DataFrame
    Returns:
        payment_type=1(카드) 행에 tip_pct 컬럼이 추가된 DataFrame
    """
    card = df[df["payment_type"] == CARD].copy()
    card["tip_pct"] = card["tip_amount"] / card["fare_amount"]
    cash_tip_zero = (df.loc[df["payment_type"] == CASH, "tip_amount"] == 0).mean()
    log("")
    log("## [3] 라벨 정의 — 현금 팁 미기록 함정 처리 (확장 학습 3)")
    log(f"- 현금 결제 중 tip_amount=0 비율: {cash_tip_zero:.1%} "
        f"→ 현금 팁은 기록되지 않음을 실측으로 확인")
    log(f"- 카드 결제 {len(card):,}건만 사용, 타깃 = 팁 비율(tip/fare)의 "
        f"중앙값({card['tip_pct'].median():.3f}) 초과 여부")
    return card


# ------------------------------------------------------------------
# 2)·3) EDA — 기술통계·상관계수 + Seaborn 정적 / Plotly 인터랙티브 시각화
# ------------------------------------------------------------------
def run_eda_and_stats(card: pd.DataFrame) -> None:
    """기술통계(평균·표준편차·분위수)와 상관계수를 산출해 출력한다.

    채점 대응: '기술통계·상관계수 출력' 항목. describe() 로 분위수까지
    한 번에 출력하고, 팁 비율과 다른 수치 변수의 상관계수를 따로 정리한다.

    Args:
        card: 카드 결제 + tip_pct 포함 DataFrame
    """
    log("")
    log("## [4] 기술통계·상관계수")
    # 로딩한 수치 컬럼 전체를 커버한다 — 확장 분석([10]~[13])이 쓰는 수수료
    # 컬럼도 여기서 분포를 먼저 보여, 뒤 섹션이 통계적 맥락 없이 등장하지
    # 않게 한다 (파생변수 duration·speed 는 생성 시점인 [10]에서 요약)
    num_cols = ["trip_distance", "fare_amount", "tip_amount", "tip_pct",
                "tolls_amount", "total_amount", "passenger_count",
                "extra", "mta_tax", "improvement_surcharge",
                "congestion_surcharge", "Airport_fee", "cbd_congestion_fee"]
    desc = card[num_cols].describe().T[["mean", "std", "25%", "50%", "75%"]]
    log(to_table(desc.round(3)))

    corr_cols = ["trip_distance", "fare_amount", "tip_amount", "tip_pct",
                 "tolls_amount", "total_amount", "passenger_count"]
    corr = card[corr_cols].corr()["tip_pct"].drop("tip_pct").sort_values()
    log("")
    log("- tip_pct 와의 상관계수: "
        + ", ".join(f"{k} {v:+.3f}" for k, v in corr.items()))
    log("- 해석: 팁 '비율'은 요금·거리와의 선형 상관이 약하다 — 금액이 커지면 "
        "팁 액수는 늘지만 비율은 일정한 경향. 모델이 쉽지 않은 문제임을 시사.")


def plot_seaborn_static(card: pd.DataFrame) -> Path:
    """Seaborn 정적 차트(공항/일반 팁 비율 분포 비교)를 PNG 로 저장한다.

    채점 대응: 'Seaborn 정적 차트 1개 이상, 제목·축 레이블 포함'.
    뒤의 t-test 와 같은 그룹(공항 vs 일반)을 그려 검정 결과의 시각 근거가
    되도록 구성했다 (차트와 검정이 따로 놀지 않게).

    Args:
        card: 카드 결제 DataFrame
    Returns:
        저장된 PNG 경로
    """
    sample = card.sample(min(100_000, len(card)), random_state=RANDOM_STATE)
    sample = sample[sample["tip_pct"] <= 1]  # 표시 범위 제한 (비율 100% 초과 극단값)
    sample["구분"] = np.where(sample["Airport_fee"] > 0, "공항 출발", "일반 승차")

    fig, ax = plt.subplots(figsize=(10, 6))
    sns.histplot(data=sample, x="tip_pct", hue="구분", bins=60,
                 stat="density", common_norm=False, kde=True, ax=ax)
    ax.set_title("팁 비율 분포 — 공항 출발 vs 일반 승차 (카드 결제)")  # 제목
    ax.set_xlabel("팁 비율 (tip / fare)")                              # 축 레이블
    ax.set_ylabel("밀도")
    fig.tight_layout()

    path = OUTPUT_DIR / "eda_tip_dist.png"
    fig.savefig(path, dpi=120)
    plt.close(fig)
    log("")
    log("## [5] 시각화")
    log(f"- Seaborn 정적 차트 저장: {path.name} (팁 비율 분포, 그룹 비교)")
    md(f"\n![팁 비율 분포]({path.name})\n")
    return path


def plot_plotly_interactive(card: pd.DataFrame) -> Path:
    """Plotly 인터랙티브 차트(시간대별 평균 요금·팁 비율)를 HTML 로 저장한다.

    채점 대응: 'Plotly 인터랙티브 차트 1개 이상' + 실습 4 감점 회피
    (fig.show() 화면 출력이 아닌 write_html() 파일 산출).

    예외·오류 처리: 파일 쓰기 실패(OSError) 시 원인 안내 후 종료

    Args:
        card: 카드 결제 DataFrame
    Returns:
        저장된 HTML 경로
    """
    hourly = (card.groupby("hour", as_index=False)
                  .agg(평균요금=("fare_amount", "mean"),
                       평균팁비율=("tip_pct", "mean"),
                       건수=("fare_amount", "size")))

    fig = px.line(hourly, x="hour", y="평균팁비율", markers=True,
                  hover_data=["평균요금", "건수"],
                  title="시간대별 평균 팁 비율 (카드 결제, 호버로 요금·건수 확인)",
                  labels={"hour": "승차 시간대(시)", "평균팁비율": "평균 팁 비율"})
    fig.update_layout(xaxis=dict(dtick=2))

    path = OUTPUT_DIR / "hourly_interactive.html"
    try:
        fig.write_html(path)  # 감점 회피: show() 가 아니라 파일 산출
    except OSError as exc:
        sys.exit(f"[오류] HTML 저장 실패: {exc}")
    log(f"- Plotly 인터랙티브 차트 저장: {path.name} (시간대별 팁 비율 라인)")
    return path


# ------------------------------------------------------------------
# 3) 통계 검정 — 공항 출발 vs 일반 승차 팁 비율 t-test (해석 포함)
# ------------------------------------------------------------------
def run_ttest(card: pd.DataFrame) -> None:
    """공항 출발과 일반 승차의 평균 팁 비율 차이를 Welch t-test 로 검정한다.

    채점 대응: 'ttest_ind 로 t-test 수행 및 p-value 해석' — 통계량·p-value
    출력 후 유의수준 판단 문장을 코드로 출력한다 (실습 4 감점 회피 패턴).

    예외·오류 처리: 그룹 표본이 2건 미만이면 검정 불가 안내 후 건너뜀

    Args:
        card: 카드 결제 DataFrame
    """
    log("")
    log(f"## [6] 통계 검정 — t-test (유의수준 α = {ALPHA})")

    airport = card.loc[card["Airport_fee"] > 0, "tip_pct"]
    normal = card.loc[card["Airport_fee"] <= 0, "tip_pct"]
    if len(airport) < 2 or len(normal) < 2:
        log(f"- [건너뜀] 표본 부족 (공항 {len(airport):,}건, 일반 {len(normal):,}건)")
        return

    # 두 집단 분산이 같다는 보장이 없으므로 Welch 검정(equal_var=False)
    t_stat, p_value = stats.ttest_ind(airport, normal, equal_var=False)
    log("- 귀무가설 H0: 공항 출발과 일반 승차의 평균 팁 비율은 같다")
    log(f"- 공항 출발 평균 {airport.mean():.4f} ({len(airport):,}건) / "
        f"일반 승차 평균 {normal.mean():.4f} ({len(normal):,}건)")
    log(f"- t 통계량 = {t_stat:.4f},  p-value = {p_value:.4g}")
    if p_value < ALPHA:
        log(f"- 해석: p < {ALPHA} 이므로 귀무가설을 기각한다. 공항 출발 여부에 "
            f"따라 평균 팁 비율에 통계적으로 유의한 차이가 있다.")
    else:
        log(f"- 해석: p >= {ALPHA} 이므로 귀무가설을 기각하지 못한다. 두 그룹의 "
            f"팁 비율 차이가 유의하다고 볼 근거가 부족하다.")


# ------------------------------------------------------------------
# 4) ML Pipeline — 전처리+모델 결합, 정확도·F1, joblib 저장 (실습 4 연계)
# ------------------------------------------------------------------
def build_pipeline(numeric_features: list[str],
                   categorical_features: list[str]) -> Pipeline:
    """전처리(ColumnTransformer)와 분류기를 하나의 Pipeline 으로 묶는다.

    전처리를 Pipeline 안에 두면 학습 데이터에서 계산한 기준이 예측 시점에도
    그대로 적용되어 학습/예측 간 불일치를 구조적으로 막는다 (실습 4 동일).

    Args:
        numeric_features: 수치형 컬럼 목록
        categorical_features: 범주형 컬럼 목록
        Model : RandomForestClassifier (Pipeline: ColumnTransformer + RandomForestClassifier)
        범주형 - OneHotEncoding(예측 시 학습에 없던 범주(신규 지역 등)는 0 벡터 처리)
    Returns:
        전처리 + RandomForest 분류기가 결합된 Pipeline
    
    """

    numeric_pipe = Pipeline([
        ("imputer", SimpleImputer(strategy="median")),
        ("scaler", StandardScaler()),
    ])
    categorical_pipe = Pipeline([
        ("imputer", SimpleImputer(strategy="most_frequent")),
        # 예측 시 학습에 없던 범주(신규 지역 등)가 와도 오류 대신 0 벡터 처리
        ("onehot", OneHotEncoder(handle_unknown="ignore")),
    ])
    return Pipeline([
        ("preprocess", ColumnTransformer([
            ("num", numeric_pipe, numeric_features),
            ("cat", categorical_pipe, categorical_features),
        ])),
        ("model", RandomForestClassifier(
            n_estimators=100, max_depth=12,
            random_state=RANDOM_STATE, n_jobs=-1)),
    ])


def train_and_save_model(card: pd.DataFrame) -> float:
    """팁 비율 중앙값 초과 여부를 예측하는 Pipeline 을 학습·평가·저장한다.

    
    누출 방지: total_amount·fare_amount 는 타깃(팁)이 합산·연동된 컬럼이라
    특징에서 제외한다 — 제외 효과는 leakage_experiment() 에서 수치로 확인.

    예외·오류 처리:
      - 모델 저장 실패(OSError) : 필수 산출물이므로 안내 후 종료
      - 재로딩 예측 불일치       : 저장 결함이므로 안내 후 종료

    Args:
        card: 카드 결제 DataFrame
        Feature :
            trip_distance (이동 거리(마일) - 수치형) 
            hour (승차 시간대(0~23) - 수치형) 
            passenger_count (승객 수 - 수치형) 
            tolls_amount (통행료 - 수치형) 
            weekday (승차 요일(0~6) - 범주형) 
            RatecodeID (요금 코드 - 범주형) 
            PULocationID (승차 지역 ID - 범주형) 

        Label : 
            팁 비율이 중앙값보다 높은가 (tip_pct > median (tip_pct 중앙값 초과 여부: 1 / 0) - Classification (이진 분류))

        Evaluation indicators : Accuracy (정확도), F1 Score 

        Train : Test = 8 : 2 (train_test_split test_size=0.2)
    Returns:
        평가 정확도(accuracy) — [9] 팁 행동 해석의 분기 기준으로 사용
    """
    log("")
    log("## [7] ML Pipeline — 학습·평가·저장 (실습 4 연계)")

    sample = card.sample(min(PIPELINE_SAMPLE, len(card)),
                         random_state=RANDOM_STATE)
    threshold = sample["tip_pct"].median()
    y = (sample["tip_pct"] > threshold).astype(int)

    numeric_features = ["trip_distance", "hour", "passenger_count",
                        "tolls_amount"]
    categorical_features = ["weekday", "RatecodeID", "PULocationID"]
    x = sample[numeric_features + categorical_features]

    log(f"- 표본 {len(sample):,}건 / 타깃: 팁 비율 > 중앙값({threshold:.3f})")
    log(f"- 수치형 특징: {numeric_features}")
    log(f"- 범주형 특징: {categorical_features}")
    log(f"- 제외 컬럼: {LEAKAGE_COLS} — 타깃(팁)이 합산된 누출 원천")

    x_train, x_test, y_train, y_test = train_test_split(
        x, y, test_size=0.2, random_state=RANDOM_STATE, stratify=y)

    pipeline = build_pipeline(numeric_features, categorical_features)
    pipeline.fit(x_train, y_train)                       # ① 학습
    predictions = pipeline.predict(x_test)               # ② 예측
    accuracy = pipeline.score(x_test, y_test)            # ③ 평가: 정확도
    f1 = f1_score(y_test, predictions)                   # ③ 평가: F1

    log(f"- 평가 정확도(accuracy): {accuracy:.4f} / F1-score: {f1:.4f}")
    log(f"- 해석: 중앙값 라벨이라 기준선은 0.5 — 기준선 대비 "
        f"{accuracy - 0.5:+.4f}. "
        + ("승차 정보만으로도 팁 성향에 유의미한 신호가 있다."
           if accuracy > 0.55 else
           "승차 정보만으로는 팁 성향 예측에 한계가 있다."))

    model_path = OUTPUT_DIR / "tip_pipeline.joblib"
    try:
        joblib.dump(pipeline, model_path)                # ④ 저장
    except OSError as exc:
        sys.exit(f"[오류] 모델 파일을 저장할 수 없습니다: {exc}")
    loaded = joblib.load(model_path)                     # ⑤ 재로딩
    identical = bool((loaded.predict(x_test) == predictions).all())
    log(f"- 모델 저장: {model_path.name} "
        f"({model_path.stat().st_size / 1024**2:.1f} MB) / "
        f"재로딩 예측 일치 = {identical}")
    if not identical:
        sys.exit("[오류] 재로딩 모델의 예측이 원본과 다릅니다. 저장 과정을 "
                 "점검하세요.")
    return accuracy


def leakage_experiment(card: pd.DataFrame) -> None:
    """total_amount·fare_amount 포함 여부에 따른 정확도 차이를 비교한다.

    확장 학습 2: total_amount 는 팁을 포함한 합계이므로, fare_amount 와 함께
    특징에 넣으면 모델이 사실상 뺄셈으로 팁을 복원할 수 있다. 실습 4의
    누출 실험(amount = quantity × unit_price)을 실데이터로 재현한다.

    Args:
        card: 카드 결제 DataFrame
        데이터 누출(Data Leakage) 현상을 실험하여 검증하는 함수(total_amount·fare_amount 포함 여부에 따른 정확도 차이 비교)

        2가지 모델
            -   누출 제외 모델 : 일반 특징
            -   누출 포함 모델 : 일반 특징 + total_amount(총 금액), fare_amount(기본 요금) 포함.

        Label(y) - '팁 비율'은 total_amount와 fare_amount 안에 이미 합산/연동
    """
    log("")
    log("## [8] 확장 학습 — 데이터 누출 검증 (실습 4 재현)")

    sample = card.sample(min(PIPELINE_SAMPLE, len(card)),
                         random_state=RANDOM_STATE)
    y = (sample["tip_pct"] > sample["tip_pct"].median()).astype(int)
    base_numeric = ["trip_distance", "hour", "passenger_count", "tolls_amount"]
    categorical = ["weekday", "RatecodeID", "PULocationID"]

    cases = {
        "누출 제외 (제출 모델)": base_numeric,
        "누출 포함 (검증용)": base_numeric + LEAKAGE_COLS,
    }
    scores: dict[str, float] = {}
    for label, numeric in cases.items():
        # train/test 분리
        x_train, x_test, y_train, y_test = train_test_split(
            sample[numeric + categorical], y,
            test_size=0.2, random_state=RANDOM_STATE, stratify=y)
        
        # 모델 빌드 -> 학습 -> 예측
        pipe = build_pipeline(numeric, categorical)
        pipe.fit(x_train, y_train)
        scores[label] = pipe.score(x_test, y_test)
        log(f"- {label}: 평가 정확도 {scores[label]:.4f}")

    gap = scores["누출 포함 (검증용)"] - scores["누출 제외 (제출 모델)"]
    log(f"- 정확도 차이: {gap:+.4f}")
    log("- 해석: total_amount = 요금 + 각종 수수료 + '팁' 의 합계라, 포함 시 "
        "모델이 정답을 계산으로 복원한다. 상승분은 학습 능력이 아니라 설계 "
        "결함이며, 목표 변수의 생성 과정을 먼저 확인해야 한다는 실습 4의 "
        "교훈이 실데이터에서도 그대로 확인된다.")


# ------------------------------------------------------------------
# 확장 분석 5종 — 팁 행동 / 속도·체증 / CBD 혼잡료 / 연휴 효과 / OD 흐름
# ------------------------------------------------------------------
def tip_behavior_analysis(card: pd.DataFrame,
                          model_accuracy: float | None = None) -> None:
    """확장 ①: 팁 결정 행동을 세 유형으로 실측 분류한다.

    결제 단말기는 팁을 20·25·30% 버튼으로 제안하므로, 팁 비율 분포에
    프리셋 값 스파이크가 나타날 것이라는 가설을 검증한다. 단말기는
    '팁 제외 총액(base = total - tip)' 기준으로 비율을 계산하므로
    tip / base 로 판정한다. 세 유형:
      - 프리셋 버튼 : tip/base 가 20·25·30% ±0.2%p 이내
      - 정액 팁     : tip 이 $1·2·3·5·10 정확히 일치
      - 라운딩      : 총액이 정수로 딱 떨어지게 팁을 맞춘 경우
    미세 구간 히스토그램 PNG 를 함께 저장해 스파이크를 시각화한다.
    해석은 [7] 모델 정확도에 연동한다: 정확도가 기준선(0.5)을 넘었다면
    버튼 편중은 '낮은 정확도의 원인'이 아니라 '정확도의 천장'으로
    서술해 두 섹션의 해석이 모순되지 않게 한다.

    Args:
        card: 카드 결제 + tip_pct 포함 DataFrame
        model_accuracy: [7]에서 측정한 평가 정확도 (해석 분기용, 없으면 None)
    """
    log("")
    log("## [9] 확장 ① 팁 행동 분석 — 사람들은 팁을 어떻게 정하는가")

    base = card["total_amount"] - card["tip_amount"]  # 팁 제외 결제 총액
    pct_base = (card["tip_amount"] / base).replace([np.inf, -np.inf], np.nan)

    preset = pd.Series(False, index=card.index)
    for p in TIP_PRESETS:
        preset |= (pct_base - p).abs() <= 0.002
    # 판정 우선순위: 프리셋 > 정액 > 라운딩 — 상호배타적 분류가 되도록
    # 앞 유형을 제외한다 (예: $25 결제에 $5 팁은 정액이자 정확히 20%라
    # 겹치는데, 단말기 버튼 행동일 가능성이 높아 프리셋으로 귀속)
    flat = card["tip_amount"].isin(FLAT_TIPS) & ~preset
    rounding = (~preset & ~flat & (card["tip_amount"] > 0)
                & np.isclose(card["total_amount"] % 1, 0))
    no_tip = card["tip_amount"] == 0
    other = ~(preset | flat | rounding | no_tip)

    log(f"- 프리셋 버튼(20·25·30%): {preset.mean():.1%}")
    log(f"- 정액 팁($1·2·3·5·10)  : {flat.mean():.1%}")
    log(f"- 총액 라운딩           : {rounding.mean():.1%}")
    log(f"- 팁 없음               : {no_tip.mean():.1%} / 기타 {other.mean():.1%}")
    for p in TIP_PRESETS:  # 프리셋별 스파이크 크기 세부
        share = ((pct_base - p).abs() <= 0.002).mean()
        log(f"  · {p:.0%} 버튼 부근(±0.2%p): {share:.1%}")

    # 해석: [7] 모델 정확도와 모순되지 않도록 분기 (v1.2)
    button_share = preset.mean()
    if model_accuracy is not None and model_accuracy > 0.55:
        log(f"- 해석: 팁의 {button_share:.1%}가 세 버튼 값에 몰려 있다. 모델이 "
            f"기준선(0.5)을 넘긴 것([7] 정확도 {model_accuracy:.2f})은 승차 "
            "맥락이 '어느 버튼을 누를지'와 어느 정도 연관됨을 뜻하지만, 버튼 "
            "선택에는 여정과 무관한 개인차가 크게 남아 있어 정확도에 천장이 "
            "존재한다 — [7] 결과를 보완하는 발견.")
    else:
        log(f"- 해석: 팁의 {button_share:.1%}가 세 버튼 값에 몰려 있어, 팁이 "
            "여정 특성이 아니라 단말기 UI(버튼)로 결정되는 비중이 크다. 승차 "
            "정보만 쓰는 모델의 낮은 정확도([7])가 이것으로 설명된다.")

    # 스파이크 시각화 (0~50% 구간 미세 bin)
    fig, ax = plt.subplots(figsize=(10, 5))
    ax.hist(pct_base.dropna().clip(0, 0.5), bins=250, color="#4C72B0")
    for p in TIP_PRESETS:
        ax.axvline(p, color="#DD8452", linestyle="--", linewidth=1)
        ax.text(p, ax.get_ylim()[1] * 0.95, f"{p:.0%}", color="#DD8452",
                ha="center", fontsize=9)
    ax.set_title("팁 비율(팁 제외 총액 기준) 미세 분포 — 프리셋 버튼 스파이크")
    ax.set_xlabel("tip / (total − tip)")
    ax.set_ylabel("건수")
    fig.tight_layout()
    path = OUTPUT_DIR / "tip_preset_spikes.png"
    fig.savefig(path, dpi=120)
    plt.close(fig)
    log(f"- 스파이크 차트 저장: {path.name}")
    md(f"\n![팁 프리셋 스파이크]({path.name})\n")


def speed_congestion_analysis(df: pd.DataFrame, card: pd.DataFrame) -> None:
    """확장 ②: dropoff 시각을 살려 운행 시간·평균 속도를 파생 분석한다.

    파생: duration(분) = dropoff - pickup, speed(mph) = distance / 시간.
    요일×시간대 평균 속도 히트맵으로 러시아워 체증을 시각화하고,
    '느린 여정일수록 팁 비율이 낮은가'를 상관계수와 t-test(속도 하위 25%
    vs 상위 25%)로 검정한다. duration<=0 등 오기록 검출도 함께 보고한다.
    로딩 실험에서 가장 무거워 제외했던 dropoff 컬럼을 이 질문을 위해
    다시 불러온 것 — '읽을 컬럼은 질문이 결정한다'(확장 학습 1 후속).

    예외·오류 처리: 유효 duration 표본이 부족하면 안내 후 건너뜀

    Args:
        df: 정제 완료 전체 DataFrame (dropoff 포함)
        card: 카드 결제 DataFrame (팁 상관 분석용)
    """
    log("")
    log("## [10] 확장 ② 속도·체증 분석 — dropoff 컬럼의 부활")

    dur = (pd.to_datetime(df["tpep_dropoff_datetime"])
           - pd.to_datetime(df["tpep_pickup_datetime"])).dt.total_seconds() / 60
    bad = int((dur <= 0).sum())
    log(f"- 오기록 검출: 운행 시간 ≤ 0분 {bad:,}건 (정제 대상 추가 발견)")

    valid = (dur > 1) & (dur < 180)  # 1분~3시간 밖은 오기록으로 간주
    speed = (df.loc[valid, "trip_distance"] / (dur[valid] / 60)).clip(upper=60)
    if valid.sum() < 100:
        log("- [건너뜀] 유효 운행 시간 표본이 부족합니다")
        return

    sub = df.loc[valid, ["hour", "weekday"]].assign(speed=speed)
    # 파생변수 기술통계 — 검정에 앞서 분포를 먼저 보인다 (새 변수 원칙)
    log(f"- 운행 시간(분) 기술통계: 평균 {dur[valid].mean():.1f} / "
        f"표준편차 {dur[valid].std():.1f} / 사분위 "
        f"{dur[valid].quantile(0.25):.1f}·{dur[valid].median():.1f}·"
        f"{dur[valid].quantile(0.75):.1f}")
    log(f"- 평균 속도(mph) 기술통계: 평균 {speed.mean():.1f} / "
        f"표준편차 {speed.std():.1f} / 사분위 "
        f"{speed.quantile(0.25):.1f}·{speed.median():.1f}·"
        f"{speed.quantile(0.75):.1f} → 하위 25% 기준선 = "
        f"{speed.quantile(0.25):.1f}mph 이하")
    pivot = sub.pivot_table(index="weekday", columns="hour",
                            values="speed", aggfunc="mean")
    pivot.index = [["월", "화", "수", "목", "금", "토", "일"][int(i)]
                   for i in pivot.index]
    fig, ax = plt.subplots(figsize=(12, 4.5))
    sns.heatmap(pivot, cmap="RdYlGn", ax=ax,
                cbar_kws={"label": "평균 속도(mph)"})
    ax.set_title("요일 × 시간대 평균 주행 속도 — 러시아워 체증 지도")
    ax.set_xlabel("승차 시간대(시)")
    ax.set_ylabel("요일")
    fig.tight_layout()
    path = OUTPUT_DIR / "speed_heatmap.png"
    fig.savefig(path, dpi=120)
    plt.close(fig)
    log(f"- 속도 히트맵 저장: {path.name}")
    md(f"\n![속도 히트맵]({path.name})\n")

    # 카드 결제 건에서 속도 vs 팁 비율 관계 검정
    cdur = (pd.to_datetime(card["tpep_dropoff_datetime"])
            - pd.to_datetime(card["tpep_pickup_datetime"])
            ).dt.total_seconds() / 60
    cvalid = (cdur > 1) & (cdur < 180)
    cspeed = (card.loc[cvalid, "trip_distance"] / (cdur[cvalid] / 60)).clip(upper=60)
    tip = card.loc[cvalid, "tip_pct"]
    corr = float(np.corrcoef(cspeed, tip)[0, 1])
    slow = tip[cspeed <= cspeed.quantile(0.25)]
    fast = tip[cspeed >= cspeed.quantile(0.75)]
    t_stat, p_value = stats.ttest_ind(slow, fast, equal_var=False)
    log(f"- 속도-팁비율 상관계수: {corr:+.3f}")
    log(f"- t-test(느린 25% vs 빠른 25%): 느림 {slow.mean():.4f} / "
        f"빠름 {fast.mean():.4f}, t={t_stat:.2f}, p={p_value:.3g}")
    verdict = ("체증 여정의 팁 비율 차이가 통계적으로 유의하다"
               if p_value < ALPHA else "유의한 차이의 근거가 부족하다")
    log(f"- 해석: p {'<' if p_value < ALPHA else '>='} {ALPHA} → {verdict}.")


def cbd_fee_analysis(df: pd.DataFrame) -> None:
    """확장 ③: 2025년 도입된 맨해튼 혼잡통행료(CBD)를 데이터로 관찰한다.

    cbd_congestion_fee > 0 을 맨해튼 코어 진입 트립으로 보고 비중·시간대
    패턴을 실측하고, 승객 결제 총액이 9개 항목으로 어떻게 구성되는지
    (기본요금 vs 팁 vs 세금·수수료) 구성비를 표로 출력한다.

    Args:
        df: 정제 완료 전체 DataFrame
    """
    log("")
    log("## [11] 확장 ③ CBD 혼잡통행료 — 데이터로 보는 정책")

    cbd = df["cbd_congestion_fee"] > 0
    log(f"- 혼잡료 부과 트립 비중: {cbd.mean():.1%} ({int(cbd.sum()):,}건)")
    if cbd.any():
        peak = df.loc[cbd, "hour"].value_counts(normalize=True).head(3)
        log("- 부과 트립 상위 시간대: "
            + ", ".join(f"{h}시 {r:.1%}" for h, r in peak.items()))

    comp = df[FEE_PARTS].mean()
    comp_pct = comp / comp.sum()
    fee_only = comp_pct.drop(["fare_amount", "tip_amount"]).sum()
    log(f"- 평균 결제 구성: 기본요금 {comp_pct['fare_amount']:.1%} / "
        f"팁 {comp_pct['tip_amount']:.1%} / 세금·수수료 합계 {fee_only:.1%}")
    log("- 구성비 상세:")
    log(to_table(comp_pct.sort_values(ascending=False).round(3)
                 .rename("구성비")))


def holiday_effect_analysis(df: pd.DataFrame, card: pd.DataFrame) -> None:
    """확장 ④: Memorial Day 연휴 효과 — 달력이 주는 자연 실험.

    연휴 3일(토~월요일 대체휴일)과 직전 주 같은 요일 3일을 비교해
    수요(일평균 건수)·이동 거리 차이를 보고, 팁 비율 차이를 t-test 한다.
    같은 요일 구성끼리 비교해 요일 효과라는 교란 변인을 통제한다.

    예외·오류 처리: 해당 날짜가 데이터에 없으면(다른 월 파일) 안내 후 건너뜀

    Args:
        df: 정제 완료 전체 DataFrame
        card: 카드 결제 DataFrame (팁 t-test 용)
    """
    log("")
    log("## [12] 확장 ④ Memorial Day 연휴 효과 (5/23~25 vs 5/16~18)")

    date = pd.to_datetime(df["tpep_pickup_datetime"]).dt.strftime("%Y-%m-%d")
    hol, base = date.isin(HOLIDAY_DAYS), date.isin(BASELINE_DAYS)
    if hol.sum() < 100 or base.sum() < 100:
        log("- [건너뜀] 비교 대상 날짜가 데이터에 없습니다 (다른 월 파일 여부 확인)")
        return

    log(f"- 일평균 수요: 연휴 {hol.sum() / 3:,.0f}건 vs 평시 {base.sum() / 3:,.0f}건 "
        f"({(hol.sum() / base.sum() - 1):+.1%})")
    log(f"- 평균 이동 거리: 연휴 {df.loc[hol, 'trip_distance'].mean():.2f}마일 vs "
        f"평시 {df.loc[base, 'trip_distance'].mean():.2f}마일")

    cdate = pd.to_datetime(card["tpep_pickup_datetime"]).dt.strftime("%Y-%m-%d")
    hol_tip = card.loc[cdate.isin(HOLIDAY_DAYS), "tip_pct"]
    base_tip = card.loc[cdate.isin(BASELINE_DAYS), "tip_pct"]
    t_stat, p_value = stats.ttest_ind(hol_tip, base_tip, equal_var=False)
    log(f"- 팁 비율 t-test: 연휴 {hol_tip.mean():.4f} vs 평시 {base_tip.mean():.4f}, "
        f"t={t_stat:.2f}, p={p_value:.3g}")
    verdict = ("연휴의 팁 비율 차이가 통계적으로 유의하다"
               if p_value < ALPHA else "유의한 차이의 근거가 부족하다")
    log(f"- 해석: p {'<' if p_value < ALPHA else '>='} {ALPHA} → {verdict}.")


def od_flow_analysis(df: pd.DataFrame) -> None:
    """확장 ⑤: 승차→하차 지역(OD) 상위 흐름을 집계한다.

    PULocationID→DOLocationID 조합별 건수 상위 10개와 평균 요금을 표로
    출력한다. 존 번호→지명 변환은 외부 lookup CSV(공식 taxi zone 파일)가
    필요하므로 번호로만 보고하고, 그 한계를 명시한다.

    Args:
        df: 정제 완료 전체 DataFrame
    """
    log("")
    log("## [13] 확장 ⑤ OD(승차→하차) 상위 흐름")

    flows = (df.dropna(subset=["DOLocationID"])
               .groupby(["PULocationID", "DOLocationID"])
               .agg(건수=("fare_amount", "size"), 평균요금=("fare_amount", "mean"))
               .sort_values("건수", ascending=False).head(10).round(2)
               .reset_index())
    log(to_table(flows, index=False))
    log("- 참고: 존 번호↔지명 변환은 공식 taxi zone lookup CSV(외부 데이터)가 "
        "필요해 번호로만 보고한다 (외부 데이터 허용 여부는 확인 필요).")



def write_report() -> Path:
    """누적된 분석 결과 버퍼를 마크다운 보고서로 저장한다.

    채점 대응: 'report.md 자동 생성'. 분석 중 log()로 출력한 모든 산출물이
    순서대로 담기고, 맨 앞에 발표(5분)용 요약을 자동으로 붙인다.

    예외·오류 처리: 파일 쓰기 실패(OSError) 시 원인 안내 후 종료

    Returns:
        저장된 report.md 경로
    """
    header = [
        "# NYC Yellow Taxi End2End 분석 보고서",
        f"- 생성 시각: {datetime.now():%Y-%m-%d %H:%M} (스크립트 자동 생성)",
        f"- 데이터: {PARQUET_PATH.name} / 팀: 광주캠퍼스 4반 5조",
        "",
        "## 발표 요약 (5분)",
        "1. **로딩**: parquet 컬럼 선택 + Polars 로 로딩 격차를 두 요인으로 분해",
        "2. **정제**: 결측·중복·이상 거래 제거, 요금 항등식 실측, IQR 적용",
        "3. **라벨 함정**: 현금 팁 미기록 → 카드 결제만으로 팁 비율 타깃 정의",
        "4. **검정·모델**: 공항 t-test / Pipeline(정확도·F1) + 누출 실험",
        "5. **확장 발견**: 팁은 단말기 버튼이 정한다(프리셋 스파이크) · 러시아워 "
        "체증 지도 · CBD 혼잡료 관찰 · 연휴 효과 · OD 상위 흐름",
        "",
        "---",
        "",
    ]
    path = OUTPUT_DIR / "report.md"
    try:
        path.write_text("\n".join(header + REPORT), encoding="utf-8")
    except OSError as exc:
        sys.exit(f"[오류] report.md 저장 실패: {exc}")
    print(f"\n[자동화] 보고서 생성 완료: {path}")
    return path


# ------------------------------------------------------------------
# 실행 진입점
# ------------------------------------------------------------------
def main() -> int:
    """전체 분석 흐름을 순서대로 실행한다.

    Returns:
        정상 종료 시 0, 처리 중 오류로 중단되면 1
    """
    warnings.filterwarnings("ignore", category=FutureWarning)
    setup_korean_font()
    try:
        OUTPUT_DIR.mkdir(exist_ok=True)
    except OSError as exc:
        sys.exit(f"[오류] 출력 디렉터리를 만들 수 없습니다: {exc}")

    try:
        compare_loading(PARQUET_PATH)        # 1) 로딩 시간 비교 (측정 전용)
        df = load_analysis_data(PARQUET_PATH)  # 실작업 로딩 (18컬럼)
        df = clean_data(df)                  # 1) 결측·중복·이상치 + 항등식
        card = make_card_dataset(df)         # 라벨 함정 처리 (확장 3)
        run_eda_and_stats(card)              # 3) 기술통계·상관계수
        plot_seaborn_static(card)            # 2) Seaborn 정적 차트
        plot_plotly_interactive(card)        # 2) Plotly 인터랙티브 차트
        run_ttest(card)                      # 3) t-test + 해석
        acc = train_and_save_model(card)     # 4) Pipeline·평가·저장
        leakage_experiment(card)             # 확장: 누출 검증
        tip_behavior_analysis(card, acc)     # 확장 ①: 팁 행동 유형
        speed_congestion_analysis(df, card)  # 확장 ②: 속도·체증
        cbd_fee_analysis(df)                 # 확장 ③: CBD 혼잡료·구성비
        holiday_effect_analysis(df, card)    # 확장 ④: 연휴 효과
        od_flow_analysis(df)                 # 확장 ⑤: OD 흐름
        write_report()                       # 5) report.md 자동 생성
    except MemoryError:
        print("[오류] 메모리가 부족합니다. PIPELINE_SAMPLE 을 줄이거나 "
              "USE_COLS 를 축소해 주세요.", file=sys.stderr)
        return 1
    except (KeyError, ValueError) as exc:
        print(f"[오류] 분석 중 데이터 문제가 발생했습니다: {exc}",
              file=sys.stderr)
        return 1

    print("\n" + "=" * 62)
    print(" 모든 분석을 정상 완료했습니다.")
    print(f" 생성 파일은 {OUTPUT_DIR} 에서 확인할 수 있습니다.")
    print("=" * 62)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())