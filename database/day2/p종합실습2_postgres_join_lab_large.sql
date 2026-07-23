-- ==============================================
-- SKALA 4기 실습 DB 전체 설정 스크립트
--
-- [실행 방법 A] 실행 중 비밀번호 직접 입력 (권장):
--   psql -U postgres -f setup_skala_db.sql
--
-- [실행 방법 B] 명령줄에서 비밀번호 미리 지정:
--   psql -U postgres -v pw="MyPass123!" -f setup_skala_db.sql
--
-- ==============================================

-- ─────────────────────────────────────────────
-- STEP 0: 비밀번호 입력
--   방법 A: 실행 중 프롬프트로 입력
--   방법 B: -v pw="..." 으로 전달 (이 블록 건너뜀)
-- ─────────────────────────────────────────────

-- -v pw=... 로 전달됐는지 확인
-- 전달되지 않은 경우 :'pw' 는 빈 문자열이므로 \prompt 로 보완
\if :{?pw}
  -- -v pw=값 이 넘어온 경우 → 그대로 사용 (아무것도 안 함)
  \echo '>> 비밀번호가 명령줄 인자로 전달되었습니다.'
\else
  -- 대화형 입력
  \prompt 'skala_user 비밀번호를 입력하세요: ' pw
\endif

\echo '>> 비밀번호 설정 완료. DB 생성을 시작합니다...'

-- ─────────────────────────────────────────────
-- STEP 1: 롤(사용자) 생성
-- ─────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'skala_user') THEN
    CREATE ROLE skala_user
      LOGIN
      NOSUPERUSER NOCREATEDB NOCREATEROLE;
    RAISE NOTICE 'Role skala_user created.';
  ELSE
    RAISE NOTICE 'Role skala_user already exists — password will be updated.';
  END IF;
END
$$;

-- 비밀번호는 ALTER ROLE로 별도 적용 (변수 치환 사용)
ALTER ROLE skala_user PASSWORD :'pw';

-- ─────────────────────────────────────────────
-- STEP 2: 데이터베이스 생성
-- ─────────────────────────────────────────────
SELECT 'CREATE DATABASE skala_db
          OWNER      = skala_user
          ENCODING   = ''UTF8''
          TEMPLATE   = template0;'
WHERE NOT EXISTS (
  SELECT FROM pg_database WHERE datname = 'skala_db'
)
\gexec

\echo '>> skala_db 생성 완료 (또는 이미 존재). 접속 중...'

-- ─────────────────────────────────────────────
-- STEP 3 이후: skala_db 에 접속
-- ─────────────────────────────────────────────
\c skala_db

-- ─────────────────────────────────────────────
-- STEP 4: 스키마 생성 및 권한 설정
-- ─────────────────────────────────────────────
CREATE SCHEMA IF NOT EXISTS lab AUTHORIZATION skala_user;

SET search_path TO lab, public;
ALTER DATABASE skala_db SET search_path TO lab, public;
ALTER ROLE     skala_user SET search_path TO lab, public;

GRANT USAGE  ON SCHEMA lab TO skala_user;
GRANT CREATE ON SCHEMA lab TO skala_user;

ALTER DEFAULT PRIVILEGES IN SCHEMA lab
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO skala_user;

ALTER DEFAULT PRIVILEGES IN SCHEMA lab
  GRANT USAGE, SELECT ON SEQUENCES TO skala_user;

\echo '>> 스키마 lab 및 권한 설정 완료.'

-- ─────────────────────────────────────────────
-- STEP 5: 테이블 DDL
-- ─────────────────────────────────────────────
DROP TABLE IF EXISTS lab.enroll    CASCADE;
DROP TABLE IF EXISTS lab.orders    CASCADE;
DROP TABLE IF EXISTS lab.emp       CASCADE;
DROP TABLE IF EXISTS lab.student   CASCADE;
DROP TABLE IF EXISTS lab.customers CASCADE;

CREATE TABLE lab.student (
  student_id INT PRIMARY KEY,
  name       VARCHAR(50),
  major      VARCHAR(50),
  gpa        NUMERIC(3,2)
);

CREATE TABLE lab.enroll (
  student_id INT,
  course     VARCHAR(50),
  grade      CHAR(1)
);

CREATE TABLE lab.customers (
  customer_id   INT PRIMARY KEY,
  customer_name VARCHAR(50)
);

CREATE TABLE lab.orders (
  order_id    INT PRIMARY KEY,
  customer_id INT REFERENCES lab.customers(customer_id),
  amount      NUMERIC(10,2)
);

CREATE TABLE lab.emp (
  emp_id     INT PRIMARY KEY,
  name       VARCHAR(50),
  manager_id INT NULL REFERENCES lab.emp(emp_id)
);

-- ─────────────────────────────────────────────
-- STEP 6: 인덱스
-- ─────────────────────────────────────────────
CREATE INDEX ix_enroll_student  ON lab.enroll(student_id);
CREATE INDEX ix_orders_customer ON lab.orders(customer_id);
CREATE INDEX ix_emp_manager     ON lab.emp(manager_id);

\echo '>> 테이블 및 인덱스 생성 완료.'

-- ─────────────────────────────────────────────
-- STEP 7: 데이터 적재
-- ─────────────────────────────────────────────

-- 학생 1,000건
INSERT INTO lab.student (student_id, name, major, gpa)
SELECT gs,
       'Student_' || gs,
       CASE gs % 5
         WHEN 0 THEN 'CS'  WHEN 1 THEN 'EE'
         WHEN 2 THEN 'ME'  WHEN 3 THEN 'CE'
         ELSE 'BIO'
       END,
       ROUND(2.0 + (gs % 30) / 10.0, 2)
FROM generate_series(1, 1000) AS gs;

UPDATE lab.student SET major = 'HR'
WHERE student_id BETWEEN 981 AND 1000;

-- 수강 데이터
INSERT INTO lab.enroll (student_id, course, grade)
SELECT s.student_id,
       CASE WHEN ((s.student_id + k) % 21) = 0 THEN 'DB'
            ELSE 'Course_' || (((s.student_id + k) % 20) + 1)
       END,
       (ARRAY['A','B','C','D'])[((s.student_id + k) % 4) + 1]
FROM lab.student s
JOIN LATERAL generate_series(
  1,
  CASE WHEN (s.student_id % 10) = 0 THEN 0
       WHEN (s.student_id % 2)  = 0 THEN 2
       ELSE 3 END
) AS g(k) ON TRUE;

INSERT INTO lab.enroll VALUES (1001,'AI','A'), (1010,'ML','B');

-- 고객 500건
INSERT INTO lab.customers (customer_id, customer_name)
SELECT gs, 'Customer_' || gs FROM generate_series(1,500) gs;

-- 주문 3,000건
INSERT INTO lab.orders (order_id, customer_id, amount)
SELECT gs,
       (gs % 500) + 1,
       ROUND(5 + (gs * 13) % 5000 + (gs % 100) / 100.0, 2)
FROM generate_series(1, 3000) gs;

-- 직원 조직도
INSERT INTO lab.emp VALUES (1, 'CEO', NULL);
INSERT INTO lab.emp (emp_id, name, manager_id)
  SELECT 1+gs, 'Mgr_'||(1+gs), 1 FROM generate_series(1,10) gs;
INSERT INTO lab.emp (emp_id, name, manager_id)
  SELECT 11+gs, 'Dev_'||(11+gs), 1+((gs-1)%10) FROM generate_series(1,300) gs;

\echo '>> 데이터 적재 완료.'

-- ─────────────────────────────────────────────
-- STEP 8: 검증
-- ─────────────────────────────────────────────
SELECT tablename AS "테이블",
       (xpath('/row/cnt/text()',
              query_to_xml(
                'SELECT COUNT(*) AS cnt FROM lab.' || tablename,
                false, true, ''))
       )[1]::text::int AS "건수"
FROM pg_tables
WHERE schemaname = 'lab'
ORDER BY tablename;

-- ─────────────────────────────────────────────
-- STEP 9: 접속 정보 출력
-- ─────────────────────────────────────────────
\echo ''
\echo '======================================'
\echo '  설정 완료! 접속 정보'
\echo '======================================'
\echo '  Host    : localhost'
\echo '  Port    : 5432'
\echo '  DB      : skala_db'
\echo '  Schema  : lab'
\echo '  User    : skala_user'
\echo '  Password: (방금 입력한 비밀번호)'
\echo ''
\echo '  접속 명령어:'
\echo '  psql -h localhost -U skala_user -d skala_db'
\echo '======================================'