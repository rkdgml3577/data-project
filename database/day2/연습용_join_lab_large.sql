-- ============================================================================
-- [연습용] JOIN 종합실습 스키마 + 시드 — PostgreSQL
-- ============================================================================
-- 용도: 배포 스크립트(postgres_join_lab_large) 수령 전 리허설용.
--       슬라이드 배경 수치를 정확히 재현한다:
--         student 1,000명 (student_id % 3 = 0 → 수강 0건 333명 /
--                          = 1 → 1건 334명 / = 2 → 2건 333명)
--         고아 수강 2건 (student_id 1001, 1010 — enroll 에만 존재)
--         customers 50명 × 정확히 6건 주문 = orders 300건
--         emp: CEO 1 + 매니저 10(Mgr_1~10) + 직원 300(Dev_1~300)
-- 사용: createdb joinlab && psql -d joinlab -f 이파일
-- 주의: 실제 배포 스크립트와 테이블·컬럼명이 다를 수 있음 — 수령 후
--       \d student 등으로 대조하여 문항 쿼리를 치환할 것.
-- 생성: 전부 결정식(나머지 연산) — 랜덤 함정 없음, 재현 가능
-- ============================================================================

DROP TABLE IF EXISTS course_owner;   -- 문항 12 에서 생성되는 테이블
DROP TABLE IF EXISTS enroll;
DROP TABLE IF EXISTS student;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS customers;
DROP TABLE IF EXISTS emp;

-- ------------------------------------------------------------------
-- 1) 학사: student / enroll
-- ------------------------------------------------------------------
CREATE TABLE student (
    student_id INT PRIMARY KEY,
    name       TEXT NOT NULL,
    major      TEXT NOT NULL,          -- 학과 (문항 16·19·20·21·23)
    gpa        NUMERIC(3,2) NOT NULL   -- 문항 15·16·21·23
);

CREATE TABLE enroll (
    enroll_id  INT PRIMARY KEY,
    student_id INT NOT NULL,           -- 의도적으로 FK 없음: 고아 수강 허용
    course     TEXT NOT NULL,
    grade      CHAR(1) NOT NULL        -- A~D (문항 24 점수 변환 재료)
);

INSERT INTO student (student_id, name, major, gpa)
SELECT g,
       'Stu_' || g,
       (ARRAY['CS','HR','Math','Biz','EE'])[1 + g % 5],   -- CS·HR 포함(문항 19·20)
       ROUND(2.00 + (g * 37 % 250) / 100.0, 2)            -- 2.00 ~ 4.49 분산
FROM generate_series(1, 1000) AS g;

-- 수강: %3=1 → 1건(334명), %3=2 → 2건(333명), %3=0 → 0건(333명)
INSERT INTO enroll (enroll_id, student_id, course, grade)
SELECT ROW_NUMBER() OVER (ORDER BY s.g, k.k),
       s.g,
       -- 과목 인덱스에 g/3(정수 나눗셈)을 섞는 이유: g%3 으로 수강 건수를
       -- 가르므로 선형식만 쓰면 6과목 중 4과목만 나오는 잉여류 함정이 있다
       (ARRAY['DB','OS','Net','Algo','Web','Stat'])[1 + (s.g + s.g/3 + k.k*2) % 6],
       (ARRAY['A','B','C','D'])[1 + (s.g + k.k) % 4]
FROM generate_series(1, 1000) AS s(g)
JOIN generate_series(1, 2) AS k(k)
  ON (s.g % 3 = 1 AND k.k = 1)        -- 1건 학생
  OR (s.g % 3 = 2 AND k.k <= 2);      -- 2건 학생 (과목은 +2 간격이라 중복 없음)

-- 고아 수강 2건: student 에 없는 1001·1010 (문항 3·4 의 NULL 재료)
INSERT INTO enroll (enroll_id, student_id, course, grade) VALUES
 (2001, 1001, 'DB', 'B'),
 (2002, 1010, 'OS', 'C');

-- ------------------------------------------------------------------
-- 2) 캠퍼스 스토어: customers / orders (고객 1명당 정확히 6건)
-- ------------------------------------------------------------------
CREATE TABLE customers (
    customer_id INT PRIMARY KEY,
    name        TEXT NOT NULL
);
CREATE TABLE orders (
    order_id    INT PRIMARY KEY,
    customer_id INT NOT NULL REFERENCES customers (customer_id),
    amount      NUMERIC(10,2) NOT NULL
);

INSERT INTO customers (customer_id, name)
SELECT g, 'Cust_' || g FROM generate_series(1, 50) AS g;

INSERT INTO orders (order_id, customer_id, amount)
SELECT (c.g - 1) * 6 + k.k,
       c.g,
       1000 + ((c.g * 13 + k.k * 7) % 90) * 100          -- 1,000 ~ 9,900
FROM generate_series(1, 50) AS c(g), generate_series(1, 6) AS k(k);

-- ------------------------------------------------------------------
-- 3) 조직도: emp — CEO(1) → 매니저(10) → 직원(300), SELF/재귀 조인 재료
-- ------------------------------------------------------------------
CREATE TABLE emp (
    emp_id     INT PRIMARY KEY,
    name       TEXT NOT NULL,
    manager_id INT REFERENCES emp (emp_id)   -- CEO 는 NULL
);

INSERT INTO emp VALUES (1, 'CEO', NULL);
INSERT INTO emp
SELECT 1 + g, 'Mgr_' || g, 1 FROM generate_series(1, 10) AS g;
INSERT INTO emp
SELECT 11 + g, 'Dev_' || g, 2 + (g % 10)                 -- 매니저 10명에 30명씩
FROM generate_series(1, 300) AS g;

-- ------------------------------------------------------------------
-- 적재 검증 (배경 수치와 일치해야 정상 — 캡처해 두면 증빙이 된다)
-- ------------------------------------------------------------------
SELECT 'student'          AS item, COUNT(*)::text AS value FROM student
UNION ALL SELECT 'enroll(고아 2 포함)', COUNT(*)::text FROM enroll
UNION ALL SELECT '수강 0건 학생',
          (SELECT COUNT(*) FROM student s
           WHERE NOT EXISTS (SELECT 1 FROM enroll e
                             WHERE e.student_id = s.student_id))::text
UNION ALL SELECT 'orders(50×6)', COUNT(*)::text FROM orders
UNION ALL SELECT 'emp(1+10+300)', COUNT(*)::text FROM emp;