# [Day 1 종합실습] 데이터 수집 미니 파이프라인

3개 공개 API(Open-Meteo · Countries.dev · ip-api)를 **asyncio + httpx**로 동시
수집하고, **Pydantic v2**로 타입·범위를 검증한 뒤, 통과 데이터를 **CSV와
Parquet** 두 형식으로 저장하며 읽기/쓰기 성능을 비교하는 파이프라인.

## 폴더 구조
```
day1_pipeline/
├── main.py            # 파이프라인 실행 진입점 (수집→검증→저장·성능비교)
├── collect.py         # asyncio.gather 동시 수집 + 필드 추출
├── models.py          # Pydantic v2 스키마 (WeatherHourly/CountryInfo/IpInfo)
├── storage.py         # CSV vs Parquet 저장·읽기 벤치마크
├── test_models.py     # pytest 스키마 검증 테스트 (11건)
├── requirements.txt
└── output/            # 실행 시 생성 (weather.csv / weather.parquet)
```

## 실행 순서 (채점 기준: 환경 구성)
```bash
# 1. 가상환경 생성·활성화
python -m venv .venv
source .venv/bin/activate        # Windows: .venv\Scripts\activate

# 2. 패키지 설치
pip install -r requirements.txt

# 3. 파이프라인 실행
python main.py

# 4. 테스트·스타일 검사 (채점 기준: 테스트·커밋)
pytest -v
ruff check .
```

## Git 커밋 (채점 기준: 커밋 이력)
```bash
git init
git add .
git commit -m "feat: Day1 데이터 수집 파이프라인 (비동기 수집)"
# 이후 단계별로 나눠 커밋하면 이력이 풍부해진다:
# git commit -m "feat: Pydantic v2 스키마 검증 추가"
# git commit -m "feat: CSV/Parquet 성능 비교 추가"
# git commit -m "test: 스키마 검증 pytest 11건 추가"
```

## 제출
GitHub 연동 후 폴더 구조 그대로 다운로드하여
`광주캠퍼스_4반_최강희_day1종합실습.zip` 으로 압축 제출.
실행결과 화면 캡처 + 코드 분석 의견은 별도 PDF 로 제출.
