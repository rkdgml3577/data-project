"""
================================================================================
[Day 1 종합실습] 수집 모듈 — asyncio + httpx 동시 수집과 필드 추출
================================================================================
#작성자: 최강희
#작성일: 2026-07-20
#변경내역:
#    v1.0 (2026-07-20) 최초 작성 — 3개 API 를 asyncio.gather 로 동시 수집

핵심 설계
    - fetch_json(): 단일 URL 수집. HTTP 오류·타임아웃·JSON 오류를 원인별로
      잡아 logger.error 후 None 반환 (한 API 실패가 전체를 중단시키지 않음)
    - collect_all(): AsyncClient 하나를 공유하며 asyncio.gather 로 3개를
      동시에 요청 — 순차 대비 총 소요시간이 가장 느린 1개 수준으로 줄어든다
    - extract_*(): 원본 JSON 에서 필요한 필드만 뽑아 검증 직전 형태로 변환.
      응답 구조 편차(리스트/딕셔너리, name 이 문자열/객체)는 여기서 흡수한다
================================================================================
"""

import asyncio
import logging

import httpx

logger = logging.getLogger("pipeline")

# 사용 API (실습 자료 지정 URL)
WEATHER_URL = (
    "https://api.open-meteo.com/v1/forecast"
    "?latitude=37.5665&longitude=126.9780"
    "&hourly=temperature_2m,precipitation_probability"
    "&forecast_days=3&timezone=Asia/Seoul"
)
COUNTRY_URL = "https://countries.dev/alpha/KOR"
IP_URL = "http://ip-api.com/json/8.8.8.8"

TIMEOUT_SEC = 10.0  # 무한 대기 방지


async def fetch_json(client: httpx.AsyncClient, url: str) -> dict | list | None:
    """URL 하나를 GET 해 JSON 으로 반환한다. 실패 시 None.

    Args:
        client: 공유 AsyncClient (커넥션 재사용)
        url: 요청 주소
    Returns:
        파싱된 JSON(dict 또는 list), 실패 시 None
    """
    try:
        resp = await client.get(url, timeout=TIMEOUT_SEC)
        resp.raise_for_status()  # 4xx/5xx 를 예외로 승격해 '응답 정상' 확인
        data = resp.json()
        logger.info("수집 성공 [%d] %s", resp.status_code, url.split("?")[0])
        return data
    except httpx.TimeoutException:
        logger.error("타임아웃(%.0fs): %s", TIMEOUT_SEC, url)
        return None
    except httpx.HTTPStatusError as exc:
        logger.error("HTTP %d 응답: %s", exc.response.status_code, url)
        return None
    except httpx.HTTPError as exc:  # 연결 실패·DNS 오류 등 나머지 전송 오류
        logger.error("요청 실패: %s (%s)", url, exc)
        return None
    except ValueError as exc:  # 본문이 JSON 이 아닌 경우
        logger.error("JSON 파싱 실패: %s (%s)", url, exc)
        return None


async def collect_all() -> tuple[dict | None, dict | list | None, dict | None]:
    """3개 API 를 동시에 수집해 (weather, country, ip) 원본 JSON 을 반환한다.

    asyncio.gather 로 세 요청을 병렬 실행하므로 총 소요시간은
    (세 응답시간의 합)이 아니라 (가장 느린 하나) 수준이 된다.
    """
    async with httpx.AsyncClient() as client:
        return await asyncio.gather(
            fetch_json(client, WEATHER_URL),
            fetch_json(client, COUNTRY_URL),
            fetch_json(client, IP_URL),
        )


def extract_weather_rows(raw: dict) -> list[dict]:
    """Open-Meteo 응답에서 시간대별 (time, 기온, 강수확률) 행 목록을 만든다.

    응답의 hourly 는 {"time": [...], "temperature_2m": [...], ...} 처럼
    컬럼 단위 배열이므로 zip 으로 행 단위 dict 로 재구성한다.

    Args:
        raw: Open-Meteo 원본 JSON
    Returns:
        검증 직전 형태의 행 dict 리스트 (구조가 다르면 빈 리스트)
    """
    hourly = raw.get("hourly", {}) if isinstance(raw, dict) else {}
    times = hourly.get("time", [])
    temps = hourly.get("temperature_2m", [])
    probs = hourly.get("precipitation_probability", [])
    if not (times and len(times) == len(temps) == len(probs)):
        logger.error("날씨 응답 구조가 예상과 다릅니다 (hourly 배열 불일치)")
        return []
    return [
        {"time": t, "temperature_2m": v, "precipitation_probability": p}
        for t, v, p in zip(times, temps, probs)
    ]


def extract_country(raw: dict | list) -> dict:
    """Countries.dev 응답에서 (name, capital, region, population) 을 추출한다.

    응답이 [ {...} ] 리스트일 수도, name 이 문자열/객체({"common": ...})일
    수도 있어 두 형태 모두 흡수한다. capital 도 문자열/리스트 겸용 처리.

    Args:
        raw: Countries.dev 원본 JSON
    Returns:
        검증 직전 형태의 dict (없는 필드는 빈 값 → 모델 검증에서 걸러짐)
    """
    obj = raw[0] if isinstance(raw, list) and raw else raw
    if not isinstance(obj, dict):
        return {}
    name = obj.get("name", "")
    if isinstance(name, dict):  # restcountries 계열: {"common": "...", ...}
        name = name.get("common") or name.get("official") or ""
    capital = obj.get("capital", "")
    if isinstance(capital, list):
        capital = capital[0] if capital else ""
    return {
        "name": name,
        "capital": capital,
        "region": obj.get("region", ""),
        "population": obj.get("population", 0),
    }


def extract_ip(raw: dict) -> dict:
    """ip-api 응답에서 (query, country, city, lat, lon, timezone) 을 추출한다.

    Args:
        raw: ip-api 원본 JSON
    Returns:
        검증 직전 형태의 dict
    """
    if not isinstance(raw, dict):
        return {}
    keys = ("query", "country", "city", "lat", "lon", "timezone")
    return {k: raw.get(k, "" if k not in ("lat", "lon") else 0.0) for k in keys}
