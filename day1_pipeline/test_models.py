"""
================================================================================
[Day 1 종합실습] 스키마 검증 테스트 (pytest)
================================================================================
#작성자: 최강희
#작성일: 2026-07-20
#변경내역:
#    v1.0 (2026-07-20) 최초 작성

테스트 전략
    - 정상 케이스: 각 모델이 올바른 입력을 통과시키고 타입을 강제 변환하는지
    - 실패 케이스: 범위 이탈(기온·확률·위도)과 빈 문자열이 ValidationError 로
      정확히 거부되는지 — 성공 경로만이 아니라 실패 경로까지 증명한다
    - 추출 함수: API 응답 구조 편차(리스트 래핑, name 객체형)를 흡수하는지
================================================================================
"""

import pytest
from pydantic import ValidationError

from collect import extract_country, extract_weather_rows
from models import CountryInfo, IpInfo, WeatherHourly

# --- 정상 케이스 --------------------------------------------------------------


def test_weather_valid_and_coerced():
    """정상 날씨 행이 통과하고, 문자열 숫자도 float 로 강제 변환된다."""
    w = WeatherHourly(
        time="2026-07-20T09:00", temperature_2m="23.5", precipitation_probability=40
    )
    assert w.temperature_2m == 23.5  # str → float 변환 확인


def test_country_valid():
    """정상 국가 정보가 통과한다."""
    c = CountryInfo(
        name="South Korea", capital="Seoul", region="Asia", population=51_000_000
    )
    assert c.population > 0


def test_ip_valid():
    """정상 IP 정보가 통과한다."""
    ip = IpInfo(
        query="8.8.8.8", country="United States", city="Ashburn",
        lat=39.03, lon=-77.5, timezone="America/New_York",
    )
    assert -90 <= ip.lat <= 90


# --- 실패 케이스: 범위·빈값이 반드시 거부되어야 한다 ---------------------------


@pytest.mark.parametrize("temp", [-100, 999])
def test_weather_temperature_out_of_range(temp):
    """기온이 -50~60 범위를 벗어나면 ValidationError."""
    with pytest.raises(ValidationError):
        WeatherHourly(time="2026-07-20T09:00", temperature_2m=temp,
                      precipitation_probability=10)


def test_weather_probability_over_100():
    """강수확률 100 초과는 거부된다."""
    with pytest.raises(ValidationError):
        WeatherHourly(time="2026-07-20T09:00", temperature_2m=20,
                      precipitation_probability=150)


def test_weather_empty_time():
    """time 빈 문자열은 거부된다."""
    with pytest.raises(ValidationError):
        WeatherHourly(time="", temperature_2m=20, precipitation_probability=10)


def test_country_population_zero():
    """인구 0 이하는 거부된다 (gt=0)."""
    with pytest.raises(ValidationError):
        CountryInfo(name="X", capital="Y", region="Z", population=0)


def test_ip_latitude_out_of_range():
    """위도 90 초과는 거부된다."""
    with pytest.raises(ValidationError):
        IpInfo(query="1.1.1.1", country="A", city="B",
               lat=123.0, lon=0.0, timezone="UTC")


# --- 추출 함수: 응답 구조 편차 흡수 -------------------------------------------


def test_extract_weather_rows_zips_columns():
    """컬럼 단위 배열이 행 단위 dict 로 재구성된다."""
    raw = {"hourly": {
        "time": ["t1", "t2"],
        "temperature_2m": [20.0, 21.0],
        "precipitation_probability": [10, 30],
    }}
    rows = extract_weather_rows(raw)
    assert len(rows) == 2
    assert rows[0] == {"time": "t1", "temperature_2m": 20.0,
                       "precipitation_probability": 10}


def test_extract_weather_rows_bad_structure():
    """배열 길이가 안 맞으면 빈 리스트를 반환한다 (예외로 죽지 않음)."""
    raw = {"hourly": {"time": ["t1"], "temperature_2m": [],
                      "precipitation_probability": []}}
    assert extract_weather_rows(raw) == []


def test_extract_country_handles_list_and_name_object():
    """[ {...} ] 래핑과 name 객체형({common: ...})을 모두 흡수한다."""
    raw = [{"name": {"common": "South Korea"}, "capital": ["Seoul"],
            "region": "Asia", "population": 51_000_000}]
    out = extract_country(raw)
    assert out["name"] == "South Korea"
    assert out["capital"] == "Seoul"
