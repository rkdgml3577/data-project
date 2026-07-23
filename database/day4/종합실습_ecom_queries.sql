-- ============================================================================
-- [종합 실습] E-Commerce 데이터 분석 SQL — PostgreSQL
-- ============================================================================
-- 작성자: 최강희
-- 작성 목적: 월간 매출/AOV, 카테고리 성과, RFM, 재고·리뷰·쿠폰 분석과
--            실행 계획 기반 성능 개선(인덱스·Materialized View)까지 수행
-- 작성일: 2026-07-21
-- 변경내역:
--   v1.0 (2026-07-21) 최초 작성
--
-- [실행 전 확인 — 중요]
--   본 파일은 배포된 종합실습4_ecom_schema_postgres.sql 의 표준적인 구조를
--   가정하고 작성했다. 만약 실제 스키마의 테이블·컬럼명이 다르면 아래
--   가정 목록과 대조해 일괄 치환할 것 (psql: \d 테이블명 으로 확인).
--     orders(order_id, customer_id, channel, status, coupon_code, order_date)
--     order_items(order_id, product_id, quantity, unit_price)
--     products(product_id, category_id, name)
--     categories(category_id, parent_id, name)          -- parent_id NULL = 루트
--     product_prices(product_id, price, valid_from, valid_to)  -- SCD2
--     customers(customer_id, name)
--     inventory(product_id, stock_qty, reorder_point)
--     reviews(review_id, product_id, rating, created_at)
--
-- [공통 원칙 — 채점 기준 대응]
--   1) SELECT 에는 문항이 요구하는 컬럼만 나열한다 (SELECT * 금지,
--      불필요한 컬럼 선택은 감점 대상이자 I/O 낭비).
--   2) "실제 팔린" 매출은 항상 status IN ('paid','shipped','delivered') 로
--      한정한다 (created 는 미결제, cancelled/refunded 는 취소·환불).
--   3) 금액은 주문 시점 스냅샷인 order_items.unit_price 를 기준으로 한다.
--      (현재가 products/product_prices 를 쓰면 과거 주문이 현재 가격으로
--       왜곡됨 — SCD2 검증용 쿼리는 Q1 하단 참고)
-- ============================================================================


-- ============================================================================
-- Q1) 지난 한 달간 실제 팔린 총 금액 (paid + shipped + delivered)
-- ============================================================================
-- "지난 한 달" = 지난 달력월(예: 오늘이 7월이면 6/1~6/30)로 해석.
-- 최근 30일 해석이 필요하면 WHERE 절을 아래 주석처럼 교체.
SELECT
    SUM(oi.quantity * oi.unit_price) AS total_sales      -- 실판매 총액
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
WHERE o.status IN ('paid', 'shipped', 'delivered')       -- 실매출 상태만
  AND o.order_date >= date_trunc('month', CURRENT_DATE) - INTERVAL '1 month'
  AND o.order_date <  date_trunc('month', CURRENT_DATE);
-- 최근 30일 버전: AND o.order_date >= CURRENT_DATE - INTERVAL '30 days'

-- [SCD2 검증 — 참고] 주문 시점 유효 가격과 스냅샷 가격의 일치 확인.
-- 가격이력(valid_from ~ valid_to)에서 주문일이 속한 구간의 가격을 조인한다.
-- valid_to 가 NULL 이면 현재 유효 가격.
SELECT
    COUNT(*)                                            AS item_rows,
    COUNT(*) FILTER (WHERE oi.unit_price = pp.price)    AS snapshot_match  -- 일치 건수
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
JOIN product_prices pp
  ON  pp.product_id = oi.product_id
  AND o.order_date >= pp.valid_from                      -- SCD2: 주문일이
  AND (pp.valid_to IS NULL OR o.order_date < pp.valid_to) -- 유효구간에 포함
WHERE o.status IN ('paid', 'shipped', 'delivered');


-- ============================================================================
-- Q2) 월별 주문 수 / 매출 / 주문당 평균 금액(AOV)
-- ============================================================================
-- AOV(Average Order Value) = 매출 ÷ 주문 수. 주문 수는 아이템 행이 아니라
-- 주문 단위이므로 COUNT(DISTINCT order_id) 로 센다 (조인 뻥튀기 방지).
SELECT
    date_trunc('month', o.order_date)::date        AS sales_month,   -- 월
    COUNT(DISTINCT o.order_id)                     AS order_count,   -- 주문 수
    SUM(oi.quantity * oi.unit_price)               AS revenue,       -- 매출
    ROUND(SUM(oi.quantity * oi.unit_price)
          / COUNT(DISTINCT o.order_id), 2)         AS aov            -- 평균 주문액
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
WHERE o.status IN ('paid', 'shipped', 'delivered')
GROUP BY date_trunc('month', o.order_date)
ORDER BY sales_month;


-- ============================================================================
-- Q3) 최근 90일 카테고리 Top10  (트리 구조 → 재귀 CTE로 루트 카테고리 귀속)
-- ============================================================================
-- 카테고리는 parent_id 로 이어진 트리이므로, 하위 카테고리 매출을
-- 최상위(루트) 카테고리로 합산해야 "카테고리 성과"가 된다.
-- 재귀 CTE: 루트(부모 없음)에서 출발해 자식으로 내려가며
-- 각 카테고리가 어느 루트에 속하는지(root_id) 매핑 테이블을 만든다.
WITH RECURSIVE category_root AS (
    -- ① 기저: 루트 카테고리는 자기 자신이 루트
    SELECT category_id, category_id AS root_id, name AS root_name
    FROM categories
    WHERE parent_id IS NULL
    UNION ALL
    -- ② 재귀: 자식은 부모의 root_id 를 물려받는다
    SELECT c.category_id, cr.root_id, cr.root_name
    FROM categories c
    JOIN category_root cr ON c.parent_id = cr.category_id
)
SELECT
    cr.root_name                          AS category,        -- 루트 카테고리명
    SUM(oi.quantity * oi.unit_price)      AS revenue_90d      -- 90일 매출
FROM orders o
JOIN order_items oi  ON oi.order_id  = o.order_id
JOIN products p      ON p.product_id = oi.product_id
JOIN category_root cr ON cr.category_id = p.category_id
WHERE o.status IN ('paid', 'shipped', 'delivered')
  AND o.order_date >= CURRENT_DATE - INTERVAL '90 days'
GROUP BY cr.root_name
ORDER BY revenue_90d DESC
LIMIT 10;


-- ============================================================================
-- Q4) 제품별 누적매출 RANK() Top20
-- ============================================================================
-- RANK(): 동점이면 같은 순위, 다음 순위는 건너뜀 (예: 1,2,2,4).
-- 보너스로 누적 비중(cum_share)을 함께 출력 — 상위 몇 개 제품이 매출의
-- 몇 %를 차지하는지(파레토) 한 번에 보이게 한다.
WITH product_revenue AS (
    SELECT
        p.product_id,
        p.name,
        SUM(oi.quantity * oi.unit_price) AS total_revenue
    FROM orders o
    JOIN order_items oi ON oi.order_id  = o.order_id
    JOIN products p     ON p.product_id = oi.product_id
    WHERE o.status IN ('paid', 'shipped', 'delivered')
    GROUP BY p.product_id, p.name
)
SELECT
    RANK() OVER (ORDER BY total_revenue DESC)  AS revenue_rank,   -- 순위
    product_id,
    name,
    total_revenue,
    ROUND(100.0 * SUM(total_revenue) OVER (ORDER BY total_revenue DESC)
          / SUM(total_revenue) OVER (), 1)     AS cum_share_pct   -- 누적 비중(%)
FROM product_revenue
ORDER BY revenue_rank
LIMIT 20;


-- ============================================================================
-- Q5) RFM — 고객이 얼마나 최근에(R), 얼마나 자주(F), 얼마나 많이(M) 샀는지
-- ============================================================================
-- NTILE(5): 고객을 5등분해 1~5점 부여. 관례상 5점이 가장 좋은 등급이 되도록
-- R 은 최근일수록, F·M 은 클수록 5점이 되게 정렬 방향을 맞춘다.
WITH customer_orders AS (
    SELECT
        o.customer_id,
        MAX(o.order_date)                          AS last_order_date,
        COUNT(DISTINCT o.order_id)                 AS frequency,
        SUM(oi.quantity * oi.unit_price)           AS monetary
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.order_id
    WHERE o.status IN ('paid', 'shipped', 'delivered')
    GROUP BY o.customer_id
)
SELECT
    customer_id,
    (CURRENT_DATE - last_order_date::date)         AS recency_days,  -- R(일)
    frequency,                                                        -- F(회)
    monetary,                                                         -- M(금액)
    NTILE(5) OVER (ORDER BY last_order_date ASC)   AS r_score,  -- 최근일수록 5
    NTILE(5) OVER (ORDER BY frequency)             AS f_score,  -- 잦을수록 5
    NTILE(5) OVER (ORDER BY monetary)              AS m_score   -- 많을수록 5
FROM customer_orders
ORDER BY r_score DESC, f_score DESC, m_score DESC;


-- ============================================================================
-- Q6) 첫 구매 후 30일 내 재구매율
-- ============================================================================
-- 정의: (첫 주문일 이후 30일 안에 두 번째 주문이 존재하는 고객 수)
--        ÷ (첫 구매가 있는 전체 고객 수)
-- FILTER + EXISTS: 고객별 재구매 여부를 세는 가장 읽기 쉬운 형태.
WITH first_orders AS (
    SELECT customer_id, MIN(order_date) AS first_order_date
    FROM orders
    WHERE status IN ('paid', 'shipped', 'delivered')
    GROUP BY customer_id
)
SELECT
    COUNT(*)                                        AS total_customers,   -- 전체
    COUNT(*) FILTER (WHERE EXISTS (                                        -- 재구매
        SELECT 1
        FROM orders o2
        WHERE o2.customer_id = f.customer_id
          AND o2.status IN ('paid', 'shipped', 'delivered')
          AND o2.order_date >  f.first_order_date
          AND o2.order_date <= f.first_order_date + INTERVAL '30 days'
    ))                                              AS repurchased,
    ROUND(100.0 * COUNT(*) FILTER (WHERE EXISTS (
        SELECT 1
        FROM orders o2
        WHERE o2.customer_id = f.customer_id
          AND o2.status IN ('paid', 'shipped', 'delivered')
          AND o2.order_date >  f.first_order_date
          AND o2.order_date <= f.first_order_date + INTERVAL '30 days'
    )) / COUNT(*), 2)                               AS repurchase_rate_pct -- 재구매율
FROM first_orders f;


-- ============================================================================
-- Q7) 재고가 임계치(reorder_point)보다 낮은 상품 — 품절 위험
-- ============================================================================
-- 부족분(shortage)이 큰 순으로 정렬해 발주 우선순위까지 보이게 한다.
SELECT
    p.product_id,
    p.name,
    i.stock_qty,                                    -- 현재 재고
    i.reorder_point,                                -- 재주문 임계치
    i.reorder_point - i.stock_qty AS shortage       -- 부족분(발주 우선순위)
FROM inventory i
JOIN products p ON p.product_id = i.product_id
WHERE i.stock_qty < i.reorder_point                 -- 임계치 미만 = 위험
ORDER BY shortage DESC;


-- ============================================================================
-- Q8) 리뷰 평점 4.5 이상 & 리뷰 50개 이상 — 효자상품
-- ============================================================================
-- 집계 결과에 대한 조건이므로 WHERE 가 아니라 HAVING 으로 거른다.
SELECT
    p.product_id,
    p.name,
    ROUND(AVG(r.rating), 2) AS avg_rating,          -- 평균 평점
    COUNT(*)                AS review_count         -- 리뷰 수
FROM reviews r
JOIN products p ON p.product_id = r.product_id
GROUP BY p.product_id, p.name
HAVING AVG(r.rating) >= 4.5                         -- 평점 조건
   AND COUNT(*) >= 50                               -- 리뷰 수 조건
ORDER BY avg_rating DESC, review_count DESC;


-- ============================================================================
-- Q9) 쿠폰 사용 영향 — 쿠폰 주문 vs 비쿠폰 주문의 평균 주문 금액 비교
-- ============================================================================
-- 주문 단위 총액을 먼저 만들고(서브쿼리), 쿠폰 사용 여부로 두 그룹 평균을
-- 나란히 출력한다. 행 2개(사용/미사용)로 나와 비교가 한눈에 된다.
SELECT
    (ot.coupon_code IS NOT NULL) AS used_coupon,    -- true=쿠폰 사용
    COUNT(*)                     AS order_count,
    ROUND(AVG(ot.order_total), 2) AS avg_order_amount
FROM (
    SELECT
        o.order_id,
        o.coupon_code,
        SUM(oi.quantity * oi.unit_price) AS order_total   -- 주문 단위 총액
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.order_id
    WHERE o.status IN ('paid', 'shipped', 'delivered')
    GROUP BY o.order_id, o.coupon_code
) AS ot
GROUP BY (ot.coupon_code IS NOT NULL)
ORDER BY used_coupon DESC;


-- ============================================================================
-- Q10) 상위 1% 고객의 최근 60일 매출
-- ============================================================================
-- ① 전체 기간 누적 매출로 고객 순위를 매겨 상위 1% 선별 (PERCENT_RANK)
-- ② 그 고객들의 최근 60일 매출 합계 + 전체 60일 매출 대비 비중까지 출력
WITH customer_revenue AS (
    SELECT
        o.customer_id,
        SUM(oi.quantity * oi.unit_price) AS lifetime_revenue
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.order_id
    WHERE o.status IN ('paid', 'shipped', 'delivered')
    GROUP BY o.customer_id
),
top1_customers AS (
    SELECT customer_id
    FROM (
        SELECT customer_id,
               PERCENT_RANK() OVER (ORDER BY lifetime_revenue DESC) AS pr
        FROM customer_revenue
    ) ranked
    WHERE pr <= 0.01                                -- 상위 1%
),
recent_60d AS (
    SELECT
        o.customer_id,
        SUM(oi.quantity * oi.unit_price) AS revenue_60d
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.order_id
    WHERE o.status IN ('paid', 'shipped', 'delivered')
      AND o.order_date >= CURRENT_DATE - INTERVAL '60 days'
    GROUP BY o.customer_id
)
SELECT
    COUNT(t.customer_id)                            AS top1_customer_count,
    COALESCE(SUM(r.revenue_60d), 0)                 AS top1_revenue_60d,
    ROUND(100.0 * COALESCE(SUM(r.revenue_60d), 0)
          / (SELECT SUM(revenue_60d) FROM recent_60d), 2)
                                                    AS share_of_60d_pct  -- 비중
FROM top1_customers t
LEFT JOIN recent_60d r ON r.customer_id = t.customer_id;


-- ============================================================================
-- Q11) 0으로 나누어도 에러가 안 나는 나눗셈 함수 → 안전한 평균 계산
-- ============================================================================
-- DB 프로그래밍: SQL 함수 정의. 분모가 0 또는 NULL 이면 에러 대신 0을
-- 반환한다. (NULL 을 원하면 내장 표현 numerator / NULLIF(denominator, 0)
-- 로도 가능 — 함수는 의도를 이름으로 드러내고 재사용하기 위한 것)
CREATE OR REPLACE FUNCTION safe_div(numerator NUMERIC, denominator NUMERIC)
RETURNS NUMERIC
LANGUAGE sql
IMMUTABLE                       -- 같은 입력 → 같은 출력 (옵티마이저 최적화 허용)
AS $$
    SELECT CASE
               WHEN denominator IS NULL OR denominator = 0 THEN 0  -- 방어
               ELSE numerator / denominator
           END
$$;

-- 사용 예 ①: 단순 확인 — 0으로 나눠도 에러 없이 0
SELECT safe_div(10, 2) AS ok_case,      -- 5
       safe_div(10, 0) AS zero_case;    -- 0 (division by zero 에러 없음)

-- 사용 예 ②: 안전한 AOV — 특정 기간에 주문이 0건이어도 에러 없이 0 반환
SELECT
    safe_div(SUM(oi.quantity * oi.unit_price),
             COUNT(DISTINCT o.order_id)) AS safe_aov
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
WHERE o.status IN ('paid', 'shipped', 'delivered')
  AND o.order_date >= CURRENT_DATE - INTERVAL '7 days';  -- 최근 7일 (0건 가능)


-- ============================================================================
-- [성능] 실행 계획 비교 & 개선 — EXPLAIN ANALYZE → 인덱스 → Join → MV
-- ============================================================================

-- ---------------------------------------------------------------
-- P1. EXPLAIN ANALYZE 로 병목 파악
-- ---------------------------------------------------------------
-- 대상: Q2 월별 리포트 (가장 자주 돌 질의). 인덱스 생성 "전"에 실행해
-- Seq Scan(전체 스캔) 이 나오는 것을 캡처해 둔다 → 개선 전 증거.
EXPLAIN ANALYZE
SELECT
    date_trunc('month', o.order_date)::date AS sales_month,
    COUNT(DISTINCT o.order_id)              AS order_count,
    SUM(oi.quantity * oi.unit_price)        AS revenue
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
WHERE o.status IN ('paid', 'shipped', 'delivered')
GROUP BY date_trunc('month', o.order_date);

-- ---------------------------------------------------------------
-- P2. 인덱스 추가 — 자주 쓰는 조건·조인 키 기준
-- ---------------------------------------------------------------
-- 상태+날짜 복합: 모든 매출 질의의 공통 WHERE (선두 컬럼 = 등호 조건인 status)
CREATE INDEX IF NOT EXISTS idx_orders_status_date
    ON orders (status, order_date);
-- 조인 키: order_items 는 항상 order_id 로 orders 와 조인됨
CREATE INDEX IF NOT EXISTS idx_order_items_order_id
    ON order_items (order_id);
-- 제품 집계(Q3·Q4)용 조인 키
CREATE INDEX IF NOT EXISTS idx_order_items_product_id
    ON order_items (product_id);
-- 리뷰 집계(Q8)용
CREATE INDEX IF NOT EXISTS idx_reviews_product_id
    ON reviews (product_id);
-- 고객 시계열(Q5·Q6·Q10)용
CREATE INDEX IF NOT EXISTS idx_orders_customer_date
    ON orders (customer_id, order_date);

-- 인덱스 생성 "후" P1 을 다시 실행해 Index Scan / Bitmap Heap Scan 으로
-- 바뀌고 실행 시간이 줄었는지 전·후를 나란히 캡처한다.

-- ---------------------------------------------------------------
-- P3. Join 전략 비교 — Hash Join vs Nested Loop
-- ---------------------------------------------------------------
-- 옵티마이저는 보통 대량 조인에 Hash Join, 소량·인덱스 조인에 Nested Loop
-- 를 고른다. 강제로 꺼서 계획이 어떻게 바뀌고 얼마나 느려지는지 비교한다.
-- (실험 후 반드시 RESET — 세션 설정이라 접속 종료 시에도 초기화됨)
SET enable_hashjoin = off;      -- 해시 조인 금지 → Nested Loop 등으로 대체됨
EXPLAIN ANALYZE
SELECT o.order_id, SUM(oi.quantity * oi.unit_price) AS order_total
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
WHERE o.status = 'delivered'
GROUP BY o.order_id;
RESET enable_hashjoin;          -- 원상 복구 (실험용 설정 해제)

-- ---------------------------------------------------------------
-- P4. Materialized View — 일별 GMV 리포트 가속
-- ---------------------------------------------------------------
-- 매일 조회하는 "일별 총 판매금액"을 매번 JOIN+SUM 하면 느리므로,
-- 결과를 물리적으로 저장해 두는 Materialized View 를 만든다.
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_daily_gmv AS
SELECT
    o.order_date::date               AS sale_date,   -- 일자
    COUNT(DISTINCT o.order_id)       AS order_count, -- 일별 주문 수
    SUM(oi.quantity * oi.unit_price) AS gmv          -- 일별 총 판매금액
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
WHERE o.status IN ('paid', 'shipped', 'delivered')
GROUP BY o.order_date::date;

-- CONCURRENTLY 갱신(조회 차단 없이 갱신)에는 UNIQUE 인덱스가 필수
CREATE UNIQUE INDEX IF NOT EXISTS uq_mv_daily_gmv_date
    ON mv_daily_gmv (sale_date);

-- 리포트 질의: JOIN 없이 MV 만 읽으므로 빠르다 (EXPLAIN 으로 전·후 비교)
EXPLAIN ANALYZE
SELECT sale_date, gmv
FROM mv_daily_gmv
WHERE sale_date >= CURRENT_DATE - INTERVAL '30 days'
ORDER BY sale_date;

-- 갱신 전략: 데이터 변경 빈도에 맞춰 주기 설계 — 요구사항대로 "매일 오후 3시"
-- 수동 갱신(즉시 1회):
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_daily_gmv;
-- 자동 갱신 ① pg_cron 확장이 있는 경우 (DB 안에서 스케줄):
--   SELECT cron.schedule('refresh_daily_gmv', '0 15 * * *',
--          $$REFRESH MATERIALIZED VIEW CONCURRENTLY mv_daily_gmv$$);
-- 자동 갱신 ② OS crontab 을 쓰는 경우:
--   0 15 * * * psql -d ecom -c "REFRESH MATERIALIZED VIEW CONCURRENTLY mv_daily_gmv"
-- 설계 근거: 리포트는 하루 단위 집계라 실시간성이 필요 없고, 오후 3시 갱신이면
-- 당일 오전분까지 반영된 상태로 오후 보고에 사용할 수 있다.

-- ---------------------------------------------------------------
-- P5. (Option) 엔진별 옵티마이저 특징 한 줄 정리
-- ---------------------------------------------------------------
-- PostgreSQL : 비용 기반 + 통계(ANALYZE) 의존, MV 는 수동 REFRESH,
--              EXPLAIN (ANALYZE, BUFFERS) 로 실측 지원
-- MySQL      : 옵티마이저 힌트/인덱스 힌트 문화, MV 없음(요약 테이블로 대체),
--              EXPLAIN ANALYZE 는 8.0.18+
-- Oracle     : 힌트 풍부, MV 자동 갱신(ON COMMIT/REFRESH FAST)과
--              쿼리 재작성(Query Rewrite) 지원이 강력
-- SQL Server : 실행 계획 캐시·인덱스 뷰(Indexed View)가 MV 역할,
--              실제 실행 계획 GUI 분석이 표준 워크플로
