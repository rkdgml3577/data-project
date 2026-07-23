-- ============================================================================
-- [연습용] E-Commerce 시드 데이터 — PostgreSQL
-- ============================================================================
-- 용도: 배포 파일 수령 전 리허설용. 적재 시점의 CURRENT_DATE 를 기준으로
--       최근 180일 치 주문을 생성하므로, 언제 실행해도 Q1(지난달)·
--       Q3(90일)·Q10(60일) 같은 날짜 기반 문항이 바로 동작한다.
-- 사용: psql -d ecom -f 연습용_ecom_seed_postgres.sql  (스키마 실행 후)
-- 규모: 고객 500 / 상품 60 / 주문 8,000 / 주문상세 약 16,000 / 리뷰 4,300
-- ============================================================================

SELECT setseed(0.42);   -- random() 재현성 고정 (리허설 결과 비교 용이)

-- ------------------------------------------------------------------
-- 1) 카테고리 트리: 루트 3개, 그 아래 자식·손자 (재귀 CTE 문항용 구조)
-- ------------------------------------------------------------------
INSERT INTO categories (category_id, parent_id, name) VALUES
    (1, NULL, '전자'), (2, NULL, '패션'), (3, NULL, '식품'),
    (4, 1, '노트북'), (5, 1, '음향'), (6, 4, '게이밍노트북'),
    (7, 2, '남성의류'), (8, 2, '여성의류'), (9, 3, '신선'), (10, 3, '가공');

-- ------------------------------------------------------------------
-- 2) 상품 60개 — 말단 카테고리(4~10)에 랜덤 배정
-- ------------------------------------------------------------------
INSERT INTO products (product_id, category_id, name)
SELECT g,
       4 + (random() * 6)::int,              -- 4~10 사이 말단 카테고리
       '상품' || g
FROM generate_series(1, 60) AS g;

-- ------------------------------------------------------------------
-- 3) 가격 이력 (SCD2) — 상품마다 2개 구간:
--    구가격(과거 ~ 80일 전) → 신가격(80일 전 ~ 현재, valid_to NULL)
--    기준가는 product_id 로부터 결정적으로 계산해 두 INSERT 가 일관되게 한다
-- ------------------------------------------------------------------
INSERT INTO product_prices (product_id, price, valid_from, valid_to)
SELECT product_id,
       (5 + (product_id * 37) % 195) * 100,          -- 구가격 (500~19,900)
       DATE '2025-01-01',
       CURRENT_DATE - 80
FROM products;

INSERT INTO product_prices (product_id, price, valid_from, valid_to)
SELECT product_id,
       ROUND(((5 + (product_id * 37) % 195) * 100) * 1.1, -1),  -- 10% 인상
       CURRENT_DATE - 80,
       NULL                                           -- 현재 유효
FROM products;

-- ------------------------------------------------------------------
-- 4) 고객 500명
-- ------------------------------------------------------------------
INSERT INTO customers (customer_id, name)
SELECT g, '고객' || g
FROM generate_series(1, 500) AS g;

-- ------------------------------------------------------------------
-- 5) 주문 8,000건 — 최근 180일, 상태 분포는 실매출(paid/shipped/delivered)
--    합계 85% 가 되도록 설정. 쿠폰(SAVE10)은 30% 사용.
-- ------------------------------------------------------------------
INSERT INTO orders (order_id, customer_id, channel, status, coupon_code, order_date)
SELECT g,
       1 + (random() * 499)::int,
       (ARRAY['web', 'mobile', 'marketplace'])[1 + floor(random() * 3)::int],
       CASE                                            -- 상태 분포
           WHEN r < 0.05 THEN 'created'                -- 5%  미결제
           WHEN r < 0.30 THEN 'paid'                   -- 25%
           WHEN r < 0.55 THEN 'shipped'                -- 25%
           WHEN r < 0.90 THEN 'delivered'              -- 35%
           WHEN r < 0.95 THEN 'cancelled'              -- 5%
           ELSE               'refunded'               -- 5%
       END,
       CASE WHEN random() < 0.30 THEN 'SAVE10' END,    -- 30% 쿠폰
       CURRENT_DATE - (random() * 180)::int            -- 최근 180일
FROM (SELECT g, random() AS r FROM generate_series(1, 8000) AS g) AS t;

-- ------------------------------------------------------------------
-- 6) 주문 상세 — 주문당 1~3개 품목, unit_price 는 "주문일에 유효한"
--    SCD2 가격을 조인해 스냅샷으로 저장 (Q1 하단 검증 쿼리가 100% 일치해야 정상)
-- ------------------------------------------------------------------
INSERT INTO order_items (item_id, order_id, product_id, quantity, unit_price)
SELECT ROW_NUMBER() OVER (ORDER BY o.order_id, pick.gs) AS item_id,
       o.order_id,
       pick.pid,
       1 + (random() * 2)::int          AS quantity,   -- 1~3개
       pp.price                                         -- 주문일 유효 가격
FROM orders AS o
CROSS JOIN LATERAL (                                   -- 주문마다 품목 1~3개 추첨
    SELECT gs, 1 + floor(random() * 60)::int AS pid
    FROM generate_series(1, 3) AS gs
    WHERE gs <= 1 + floor(random() * 3)::int           -- 개수 1~3 랜덤
) AS pick
JOIN product_prices AS pp
  ON  pp.product_id = pick.pid
  AND o.order_date >= pp.valid_from                    -- SCD2: 주문일이
  AND (pp.valid_to IS NULL OR o.order_date < pp.valid_to);  -- 유효구간 안

-- ------------------------------------------------------------------
-- 7) 재고 — 일부 상품은 의도적으로 임계치 미만이 되도록 범위 설정 (Q7용)
-- ------------------------------------------------------------------
INSERT INTO inventory (product_id, stock_qty, reorder_point)
SELECT product_id,
       (random() * 100)::int,            -- 재고 0~100
       10 + (random() * 30)::int         -- 임계치 10~40 → 일부는 재고<임계치
FROM products;

-- ------------------------------------------------------------------
-- 8) 리뷰 — 상품 1~5 는 효자상품이 되도록 60개씩(평점 4·5만),
--    나머지 상품은 랜덤 평점 4,000개 (Q8에서 정확히 5개가 걸리는지 확인용)
-- ------------------------------------------------------------------
INSERT INTO reviews (review_id, product_id, rating, created_at)
SELECT ROW_NUMBER() OVER (),
       p,
       CASE WHEN random() < 0.25 THEN 4 ELSE 5 END,    -- 평균 약 4.75
       CURRENT_DATE - (random() * 180)::int
FROM generate_series(1, 5) AS p,
     generate_series(1, 60) AS n;

INSERT INTO reviews (review_id, product_id, rating, created_at)
SELECT 300 + g,                                        -- id 충돌 방지 오프셋
       6 + floor(random() * 55)::int,                  -- 상품 6~60
       1 + floor(random() * 5)::int,                   -- 평점 1~5
       CURRENT_DATE - (random() * 180)::int
FROM generate_series(1, 4000) AS g;

-- ------------------------------------------------------------------
-- 적재 결과 확인
-- ------------------------------------------------------------------
SELECT 'categories'     AS tbl, COUNT(*) FROM categories
UNION ALL SELECT 'products',       COUNT(*) FROM products
UNION ALL SELECT 'product_prices', COUNT(*) FROM product_prices
UNION ALL SELECT 'customers',      COUNT(*) FROM customers
UNION ALL SELECT 'orders',         COUNT(*) FROM orders
UNION ALL SELECT 'order_items',    COUNT(*) FROM order_items
UNION ALL SELECT 'inventory',      COUNT(*) FROM inventory
UNION ALL SELECT 'reviews',        COUNT(*) FROM reviews;
