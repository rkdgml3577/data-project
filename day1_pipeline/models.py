"""
================================================================================
[Day 1 종합실습] 스키마 모듈 — Pydantic v2 모델 정의
================================================================================
#작성자: 최강희
#작성일: 2026-07-20
#변경내역:
#    v1.0 (2026-07-20) 최초 작성 — 3개 API 응답의 필요 필드만 추출·검증하는 모델

각 API 의 원본 JSON 은 필드가 매우 많으므로, 파이프라인에 필요한 필드만
추출한 뒤 이 모델들로 타입·범위를 검증한다. 범위 규칙:
    - 기온        : -50 ~ 60 ℃ (센서 오류값 차단)
    - 강수확률    : 0 ~ 100 %
    - 위도/경도   : -90~90 / -180~180
    - 인구        : 0 초과
================================================================================
"""

from pydantic import BaseModel, Field


class WeatherHourly(BaseModel):
    """Open-Meteo 시간대별 예보 1행 (time·기온·강수확률)."""

    time: str = Field(min_length=1, description="예보 시각 (ISO, Asia/Seoul)")
    temperature_2m: float = Field(ge=-50, le=60, description="기온(℃)")
    precipitation_probability: float = Field(ge=0, le=100, description="강수확률(%)")


class CountryInfo(BaseModel):
    """Countries.dev 국가 정보 요약 (한국)."""

    name: str = Field(min_length=1, description="국가명")
    capital: str = Field(min_length=1, description="수도")
    region: str = Field(min_length=1, description="대륙/지역")
    population: int = Field(gt=0, description="인구 수")


class IpInfo(BaseModel):
    """ip-api IP 기반 지역 정보 요약."""

    query: str = Field(min_length=1, description="조회한 IP")
    country: str = Field(min_length=1, description="국가")
    city: str = Field(min_length=1, description="도시")
    lat: float = Field(ge=-90, le=90, description="위도")
    lon: float = Field(ge=-180, le=180, description="경도")
    timezone: str = Field(min_length=1, description="시간대")
