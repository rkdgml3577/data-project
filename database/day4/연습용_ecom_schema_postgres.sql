-- ============================================================================
-- [연습용] E-Commerce 스키마 — PostgreSQL
-- ============================================================================
-- 용도: 배포 파일 수령 전 리허설용. 종합실습_ecom_queries.sql 이 가정한
--       테이블·컬럼명과 동일하게 만들어, 쿼리를 치환 없이 바로 실행할 수 있다.
-- 사용: psql -d ecom -f 연습용_ecom_schema_postgres.sql
-- 주의: 실제 배포 스키마와 구조가 다를 수 있으므로 제출은 반드시 배포
--       파일 기준으로 다시 실행할 것.
-- ============================================================================

-- 재실행 가능하도록 기존 객체 정리 (자식 → 부모 순서 무관하게 CASCADE)
DROP MATERIALIZED VIEW IF EXISTS mv_daily_gmv;
DROP TABLE IF EXISTS reviews        CASCADE;
DROP TABLE IF EXISTS inventory      CASCADE;
DROP TABLE IF EXISTS order_items    CASCADE;
DROP TABLE IF EXISTS orders         CASCADE;
DROP TABLE IF EXISTS product_prices CASCADE;
DROP TABLE IF EXISTS products       CASCADE;
DROP TABLE IF EXISTS categories     CASCADE;
DROP TABLE IF EXISTS customers      CASCADE;
DROP FUNCTION IF EXISTS safe_div(NUMERIC, NUMERIC);

-- 카테고리: parent_id 로 이어지는 트리 (NULL = 루트)
CREATE TABLE categories (
    category_id INT PRIMARY KEY,
    parent_id   INT REFERENCES categories (category_id),
    name        TEXT NOT NULL
);

-- 상품
CREATE TABLE products (
    product_id  INT PRIMARY KEY,
    category_id INT NOT NULL REFERENCES categories (category_id),
    name        TEXT NOT NULL
);

-- 가격 이력 (SCD2): 한 상품이 기간별로 여러 가격 행을 가진다
-- valid_to 가 NULL 이면 현재 유효한 가격
CREATE TABLE product_prices (
    product_id INT  NOT NULL REFERENCES products (product_id),
    price      NUMERIC(12, 2) NOT NULL,
    valid_from DATE NOT NULL,
    valid_to   DATE,                          -- NULL = 현재 유효
    PRIMARY KEY (product_id, valid_from)
);

-- 고객
CREATE TABLE customers (
    customer_id INT PRIMARY KEY,
    name        TEXT NOT NULL
);

-- 주문 (상태: created/paid/shipped/delivered/cancelled/refunded)
CREATE TABLE orders (
    order_id    INT  PRIMARY KEY,
    customer_id INT  NOT NULL REFERENCES customers (customer_id),
    channel     TEXT NOT NULL CHECK (channel IN ('web','mobile','marketplace')),
    status      TEXT NOT NULL CHECK (status IN
                  ('created','paid','shipped','delivered','cancelled','refunded')),
    coupon_code TEXT,                         -- NULL = 쿠폰 미사용
    order_date  DATE NOT NULL
);

-- 주문 상세 (unit_price = 주문 시점 가격 스냅샷)
CREATE TABLE order_items (
    item_id    INT PRIMARY KEY,
    order_id   INT NOT NULL REFERENCES orders (order_id),
    product_id INT NOT NULL REFERENCES products (product_id),
    quantity   INT NOT NULL CHECK (quantity > 0),
    unit_price NUMERIC(12, 2) NOT NULL
);

-- 재고 (reorder_point 미만이면 재주문 필요)
CREATE TABLE inventory (
    product_id    INT PRIMARY KEY REFERENCES products (product_id),
    stock_qty     INT NOT NULL,
    reorder_point INT NOT NULL
);

-- 리뷰 (평점 1~5)
CREATE TABLE reviews (
    review_id  INT PRIMARY KEY,
    product_id INT NOT NULL REFERENCES products (product_id),
    rating     INT NOT NULL CHECK (rating BETWEEN 1 AND 5),
    created_at DATE NOT NULL
);
