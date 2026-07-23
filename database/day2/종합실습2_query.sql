-- ============================================================================
-- [종합 실습 2] JOIN · 서브쿼리 · 집계 심화 — 문항별 쿼리 (PostgreSQL)
-- ============================================================================
-- 작성자: 최강희 / 작성일: 2026-07-23
-- 변경내역
--   v1.0  2026-07-23  연습용 스키마 기준으로 Q1~Q25 작성
--   v1.1  2026-07-23  배포 스크립트(postgres_join_lab_large) 수령 후 대조·수정
--                     ① customers.name → customer_name (Q7·Q8, 미수정 시 오류)
--                     ② 배경 수치 전면 교체 (연습본과 시드 규모가 다름)
--                     ③ Q12 매니저 배정식 수정 (배포본 매니저는 Mgr_2~Mgr_11)
--   v1.2  2026-07-23  ④ Q14 재작성 — 강사 확인 결과 학과명은 major 코드값이며
--                        본 문항은 CTE 연습을 겸한다. CTE 로 학과 마스터를
--                        만들고 SELECT 절 스칼라 서브쿼리가 그것을 조회하는
--                        구조로 변경(컬럼 2개 — 불필요 컬럼 없음).
-- 공통 규칙: 조회 확인은 LIMIT 5 (문항이 건수를 명시하면 그 수를 따름)
--          \pset null '(null)' 로 NULL 을 화면에 명시 (세션 시작 시 1회)
--          \pset pager off 도 함께 (페이저에 걸려 캡처가 반복되는 사고 방지)
-- ----------------------------------------------------------------------------
-- 실제 스키마 (배포 스크립트 STEP B2 에서 확인 — 전부 lab 스키마)
--   student  (student_id, name, major, gpa)
--   enroll   (student_id, course, grade)          ← enroll_id 컬럼 없음
--   customers(customer_id, customer_name)         ← name 아님
--   orders   (order_id, customer_id, amount)
--   emp      (emp_id, name, manager_id)
-- 배경 수치 (배포본 실측)
--   student 1,000 / enroll 2,302(고아 2 포함) / customers 500 / orders 3,000
--   emp 311 (CEO 1 + Mgr_2~Mgr_11 10명 + Dev_12~Dev_311 300명)
--   수강 건수: student_id %10=0 → 0건(100명) / 그 외 짝수 → 2건(400명)
--              / 홀수 → 3건(500명)
-- ============================================================================

-- 세션 준비 (캡처 품질용 — 접속할 때마다 1회)
--   \pset pager off
--   \pset null '(null)'
SET search_path TO lab, public;   -- 배포본의 모든 객체는 lab 스키마에 있다

-- ============================================================================
-- Q1) INNER JOIN — 수강이 존재하는 학생의 과목/성적
-- ============================================================================
-- INNER 는 양쪽에 짝이 있는 행만 남긴다: 무수강 학생(100명)도, 고아 수강(2건)도
-- 결과에서 빠진다. 기대 행 수 2,300 (= enroll 2,302 - 고아 2).
-- 검산: 400명×2건 + 500명×3건 = 800 + 1,500 = 2,300
SELECT s.student_id, s.name, e.course, e.grade
FROM student s
INNER JOIN enroll e ON e.student_id = s.student_id
ORDER BY s.student_id
LIMIT 5;

-- ============================================================================
-- Q2) LEFT JOIN — 모든 학생 기준, 과목 없으면 NULL 까지 보이기()
-- ============================================================================
-- 기준(왼쪽) 테이블 student 는 전원 유지, 짝 없는 학생의 과목·성적이 NULL.
-- 기대 행 수 2,400 (= 매칭 2,300 + 무수강 100). 고아 수강 2건은 빠진다.
SELECT s.student_id, s.name, e.course, e.grade
FROM student s
LEFT JOIN enroll e ON e.student_id = s.student_id
ORDER BY s.student_id
LIMIT 5;

-- ============================================================================
-- Q3) RIGHT JOIN — 수강 기준, 학생이 없으면 학생 정보가 NULL
-- ============================================================================
-- 고아 수강(student_id 1001·1010)이 학생 정보 NULL 로 나타나는 것이 핵심.
-- 고아부터 보이도록 학생 NULL 우선 정렬로 확인한다.
SELECT s.student_id, s.name, e.student_id AS enroll_student_id,
       e.course, e.grade
FROM student s
RIGHT JOIN enroll e ON e.student_id = s.student_id
ORDER BY s.student_id NULLS FIRST
LIMIT 5;

-- ============================================================================
-- Q4) FULL JOIN — 학생/수강 모두 포함
-- ============================================================================
-- 짝 있는 행 + 무수강 학생(오른쪽 NULL) + 고아 수강(왼쪽 NULL) 전부.
-- 검산: 전체 행 = 매칭 2,300 + 무수강 100 + 고아 2 = 2,402
--       (Q1 결과 + Q5 결과 + Q3 의 NULL 행 수와 각각 맞아떨어져야 정상)
SELECT s.student_id, s.name, e.course, e.grade
FROM student s
FULL JOIN enroll e ON e.student_id = s.student_id
ORDER BY s.student_id NULLS FIRST
LIMIT 5;

-- (검산용) FULL JOIN 총 행 수 확인
SELECT COUNT(*) AS full_join_rows
FROM student s
FULL JOIN enroll e ON e.student_id = s.student_id;

-- ============================================================================
-- Q5) 한 번도 수강하지 않은 학생 — LEFT JOIN 안티조인
-- ============================================================================
-- LEFT 로 붙인 뒤 짝이 안 생긴(NULL) 행만 남긴다.
-- 기대: 100명 (배포본은 student_id 가 10의 배수인 학생에게 수강을 만들지 않는다)
-- → LIMIT 5 로 보면 10, 20, 30, 40, 50 이 나와야 정상
SELECT s.student_id, s.name
FROM student s
LEFT JOIN enroll e ON e.student_id = s.student_id
WHERE e.student_id IS NULL           -- 짝 없음 = 무수강
ORDER BY s.student_id
LIMIT 5;

-- ============================================================================
-- Q6) 한 과목 이상 수강한 학생 목록 (중복 제거)
-- ============================================================================
-- 기대: 900명 (1,000 - 무수강 100)
-- SELECT DISTINCT + JOIN 으로도 수행
SELECT DISTINCT s.student_id, s.name
FROM student s
INNER JOIN enroll e ON e.student_id = s.student_id
ORDER BY s.student_id
LIMIT 5;

-- ============================================================================
-- Q7) 고객별 주문건수 / 총액
-- ============================================================================
-- 배포본은 고객 500명 × 주문 3,000건 = 전원 정확히 6건이어야 정상.
-- order_count 가 전부 6 이면 시드 적재 검증도 겸한다. (컬럼명 customer_name 주의)
SELECT c.customer_id, c.customer_name,
       COUNT(o.order_id) AS order_count,
       SUM(o.amount)     AS total_amount
FROM customers c
JOIN orders o ON o.customer_id = c.customer_id
GROUP BY c.customer_id, c.customer_name
ORDER BY c.customer_id
LIMIT 5;

-- ============================================================================
-- Q8) 총액 상위 10명과 금액 (문항이 10명을 명시 → LIMIT 10)
-- ============================================================================
SELECT c.customer_name,
       SUM(o.amount) AS total_amount
FROM customers c
JOIN orders o ON o.customer_id = c.customer_id
GROUP BY c.customer_id, c.customer_name
ORDER BY total_amount DESC
LIMIT 10;

-- ============================================================================
-- Q9) 모든 직원과 그 매니저 이름 — SELF JOIN
-- ============================================================================
-- 같은 테이블을 두 역할(직원 e / 매니저 m)로 조인. CEO 는 매니저가 없으므로
-- LEFT JOIN 으로 유지하고 '없음' 표시(안 하면 CEO 가 결과에서 사라진다).
-- 기대 311행. [배포본 관찰] Dev 의 manager_id 는 1~10 인데 매니저의 emp_id 는
-- 2~11 이라, manager_id=1 인 Dev 30명은 CEO 직속이 되고 Mgr_11 은 부하가 0명이다.
-- 오류가 아니라 배포 시드의 성질이므로 결과 해석에 반영한다 (Q22 에서 재확인).
SELECT e.name                         AS employee,
       COALESCE(m.name, '(없음)')     AS manager
FROM emp e
LEFT JOIN emp m ON m.emp_id = e.manager_id
ORDER BY e.emp_id
LIMIT 5;

-- ============================================================================
-- Q10) "모든 학생 기준" 과목 분포 — LEFT JOIN + 집계
-- ============================================================================
-- INNER 로 집계하면 무수강 학생이 분포에서 사라진다. LEFT + COALESCE 로
-- '(미수강)' 그룹까지 포함해야 "모든 학생 기준"이 된다.
-- 기대: 22행 = 과목 21종(Course_1~20 + DB) + '(미수강)' 1행.
--       고아 수강의 AI·ML 은 student 기준 LEFT 조인이라 나타나지 않는다.
--       '(미수강)' 은 100 이어야 하고, 전체 cnt 합은 2,400 (= Q2 행 수).
SELECT COALESCE(e.course, '(미수강)') AS course,
       COUNT(*)                       AS cnt
FROM student s
LEFT JOIN enroll e ON e.student_id = s.student_id
GROUP BY COALESCE(e.course, '(미수강)')
ORDER BY cnt DESC;

-- ============================================================================
-- Q11) [심화] DB 과목을 듣지 않은 모든 학생 — ON vs WHERE 차이의 실전
-- ============================================================================
-- 과목 조건을 ON 에 두면 "DB 수강 기록만 붙여보고" 못 붙은 학생을 남긴다.
-- 같은 조건을 WHERE e.course='DB' 로 옮기면 NULL 행이 걸러져 LEFT 가
-- INNER 로 변질된다 — 학습 목표(ON vs WHERE)의 정답 사례.
-- 기대: 893명 (배포본의 DB 수강 107건 → 학생 107명이 제외)
SELECT s.student_id, s.name
FROM student s
LEFT JOIN enroll e
  ON  e.student_id = s.student_id
  AND e.course     = 'DB'            -- 조건은 ON 에! (WHERE 면 의미가 깨짐)
WHERE e.student_id IS NULL           -- DB 를 못 붙인 = 안 들은 학생
ORDER BY s.student_id
LIMIT 5;

-- ============================================================================
-- Q12) [심화] course_owner 생성 → 과목별 수강 인원 + 책임 매니저 리포트
-- ============================================================================
-- 과목마다 emp 의 매니저를 결정식으로 배정해 테이블 생성.
-- [중요] 매니저를 이름 문자열('Mgr_1' 등)로 찾으면 안 된다. 배포본의 매니저는
-- Mgr_2~Mgr_11 이라 'Mgr_1' 이 없고, 그 과목은 INNER JOIN 에서 조용히 사라진다
-- (오류가 안 나서 더 위험하다). 이름 대신 "매니저를 번호로 세어" 배정한다.
DROP TABLE IF EXISTS course_owner;
CREATE TABLE course_owner AS
WITH courses AS (            -- ① 과목 목록 먼저
    SELECT course, ROW_NUMBER() OVER (ORDER BY course) AS rn
    FROM (SELECT DISTINCT course FROM enroll) AS d
),
mgrs AS (                    -- ② 매니저 10명에 1~10 번호 부여
    SELECT emp_id, ROW_NUMBER() OVER (ORDER BY emp_id) AS mn,
           COUNT(*) OVER ()  AS total
    FROM emp
    WHERE name LIKE 'Mgr%'   -- 매니저 = 이름이 Mgr 로 시작하는 사원 (10명)
    -- [왜 "CEO 직속"으로 정의하지 않는가] 배포본은 Dev 30명의 manager_id 도
    -- 1(CEO)이라, CEO 부하로 뽑으면 40명이 잡혀 과목이 Dev 에게 배정된다.
)
SELECT c.course, m.emp_id AS manager_id
FROM courses c
JOIN mgrs   m ON m.mn = (c.rn % m.total) + 1;   -- ③ 매니저 수만큼 순환 배정
-- [주의] DISTINCT 와 윈도 함수를 한 층에 쓰면(SELECT DISTINCT course,
-- ROW_NUMBER()...) 윈도 함수가 먼저 평가되어 전 행에 번호가 붙고 DISTINCT
-- 가 무력화된다 — 과목당 1행을 보장하려면 위처럼 단계를 분리해야 한다.
-- 정상 판정: 생성 메시지가 SELECT 23 (배포본 과목 23종 = Course_1~20 + DB
--            + 고아 수강의 AI·ML), 아래 리포트가 23행.
-- 검산: 리포트의 enroll_count 합 = 2,302 (enroll 전체 건수)
 
-- 리포트: 과목별 수강 인원 + 책임 매니저 이름
SELECT e.course,
       COUNT(*) AS enroll_count,
       m.name   AS manager
FROM enroll e
JOIN course_owner co ON co.course = e.course
JOIN emp m           ON m.emp_id  = co.manager_id
GROUP BY e.course, m.name
ORDER BY enroll_count DESC;

-- ============================================================================
-- Q13) [심화] 학생 × 과목 전체 조합 — CROSS JOIN "추천 후보" 샘플 100건
-- ============================================================================
-- CROSS JOIN 은 조건 없는 모든 조합 = 1,000명 × 23과목 = 23,000행.
-- 폭발 위험이 있어 반드시 LIMIT 으로 샘플만 본다 — 문항 지시대로 100건.
SELECT s.student_id, s.name, c.course
FROM student s
CROSS JOIN (SELECT DISTINCT course FROM enroll) AS c
ORDER BY s.student_id, c.course
LIMIT 100;

-- ============================================================================
-- Q14) [심화] 스칼라 서브쿼리(SELECT 절) — 학생 + 학과 + 평균 GPA 붙이기
-- ============================================================================
-- 학과명은 student.major 코드값 그대로이며, 본 문항은 CTE 연습을
-- 겸한다 → CTE 로 "학과 마스터"를 만들고, SELECT 절 스칼라 서브쿼리가 그
-- CTE 를 조회해 학과명을 가져오는 구조로 작성한다.
--
-- 왜 이런 구조인가: 배포 스키마에는 학과 테이블이 없고 student.major 에
-- 학과가 직접 들어 있다. 그래서 실제 학사 DB 라면 존재했을 학과 마스터를
-- CTE 로 대신 만든다(DISTINCT 로 학과 목록을 뽑아 학과당 1행). 서브쿼리가
-- 반드시 1행만 되돌려야 스칼라 서브쿼리가 성립하는데, DISTINCT 가 그것을
-- 보장한다 — 중복이 있으면 "more than one row returned" 오류가 난다.
WITH dept AS (                       -- 학과 마스터 대용 (학과당 정확히 1행)
    SELECT DISTINCT major AS dept_name
    FROM student
)
SELECT s.name,
       (SELECT d.dept_name           -- ★ 스칼라 서브쿼리 (SELECT 절)
        FROM dept d
        WHERE d.dept_name = s.major) AS dept_name
FROM student s
ORDER BY s.student_id
LIMIT 5;
-- ============================================================================
-- Q15) [심화] 전체 평균 GPA 보다 높은 학생 — WHERE 서브쿼리
-- ============================================================================
-- 기대: 495명 (전체 평균 GPA 약 3.44 초과)
SELECT name, major, gpa
FROM student
WHERE gpa > (SELECT AVG(gpa) FROM student)   -- 전체 평균과 비교
ORDER BY gpa DESC
LIMIT 5;

-- ============================================================================
-- Q16) [심화] 자기 학과 평균 GPA 보다 높은 학생 — 상관 서브쿼리
-- ============================================================================
-- 서브쿼리가 바깥 행(s.major)을 참조하므로 행마다 기준이 달라진다
-- (correlated subquery) — Q15 와의 차이가 채점 포인트.
SELECT s.name, s.major, s.gpa
FROM student s
WHERE s.gpa > (SELECT AVG(s2.gpa)
               FROM student s2
               WHERE s2.major = s.major)     -- 자기 학과 평균 (상관)
ORDER BY s.major, s.gpa DESC
LIMIT 5;

-- ============================================================================
-- Q17) [심화] 수강(enroll) 기록이 있는 학생만 — EXISTS 세미조인
-- ============================================================================
-- Q6 과 같은 결과지만 "기법 자체"가 문항: EXISTS 는 존재 확인 즉시 멈추고
-- 행을 불려놓지 않는다.
SELECT s.student_id, s.name
FROM student s
WHERE EXISTS (SELECT 1 FROM enroll e WHERE e.student_id = s.student_id)
ORDER BY s.student_id
LIMIT 5;

-- ============================================================================
-- Q18) [심화] 한 번도 수강하지 않은 학생 — NOT EXISTS 안티조인
-- ============================================================================
-- Q5(LEFT+IS NULL)와 같은 결과를 다른 기법으로: 같은 질문에 대한 두 표현.
-- (NOT IN 은 NULL 이 섞이면 전체가 빈 결과가 되는 함정이 있어 권장 안 함)
SELECT s.student_id, s.name
FROM student s
WHERE NOT EXISTS (SELECT 1 FROM enroll e WHERE e.student_id = s.student_id)
ORDER BY s.student_id
LIMIT 5;

-- ============================================================================
-- Q19) [심화] HR 학과 학생 일부와의 비교 데모 — ANY / ALL
-- ============================================================================
-- > ANY : HR 의 "누구 한 명"보다만 높으면 됨 (사실상 HR 최소값 초과)
SELECT name, major, gpa
FROM student
WHERE gpa > ANY (SELECT gpa FROM student WHERE major = 'HR')
ORDER BY gpa
LIMIT 5;

-- > ALL : HR 의 "전원"보다 높아야 함 (사실상 HR 최대값 초과) — 대비 확인
-- [기대 결과] 0행. 배포본의 HR(학번 981~1000) GPA 범위가 2.0~4.9 로 전체
-- 최대값과 같아, 전원을 넘는 학생은 존재할 수 없다. 빈 결과가 정답이며
-- ANY(967명)와의 대비가 이 문항의 요지다 — 쿼리 오류가 아니다.
SELECT name, major, gpa
FROM student
WHERE gpa > ALL (SELECT gpa FROM student WHERE major = 'HR')
ORDER BY gpa
LIMIT 5;

-- ============================================================================
-- Q20) [심화] CS 학과 학생 또는 DB 과목 수강 학생 — UNION (중복 제거)
-- ============================================================================
-- 서로 다른 조건의 두 집합을 합친다. UNION 은 중복을 제거하므로
-- "CS 이면서 DB 수강"인 학생도 한 번만 나온다 (UNION ALL 과의 차이).
-- 기대: 290명. (CS 196명 + DB 수강 107명 - 양쪽 겹침 13명)
-- 참고: 배포본은 CS 가 200명이 아니라 196명 — 학번 981~1000 을 HR 로
--       덮어쓰는 UPDATE 가 있어 그중 CS 였던 4명이 HR 로 바뀌었다.
SELECT s.student_id, s.name
FROM student s
WHERE s.major = 'CS'
UNION
SELECT s.student_id, s.name
FROM student s
JOIN enroll e ON e.student_id = s.student_id
WHERE e.course = 'DB'
ORDER BY student_id
LIMIT 5;

-- ============================================================================
-- Q21) [심화] 학과별·GPA 구간별 인원 — ROLLUP + GROUPING (소계·총계 한 번에)
-- ============================================================================
-- ① 파생 컬럼 gpa_tier (3.0 미만 / 3.0~3.5 / 3.5 초과)
-- ② ROLLUP(major, gpa_tier): (학과,구간) → 학과 소계 → 전체 총계 자동 생성
-- ③ GROUPING(major)=1 인 행(총계)에 '전체' 라벨
-- ④ 소계·총계가 하단에 오도록 GROUPING 값으로 정렬
WITH tiered AS (
    SELECT major,
           CASE WHEN gpa < 3.0  THEN '3.0 미만'
                WHEN gpa <= 3.5 THEN '3.0~3.5'
                ELSE                 '3.5 초과' END AS gpa_tier
    FROM student
)
SELECT CASE WHEN GROUPING(major) = 1 THEN '전체' ELSE major END AS major,
       CASE WHEN GROUPING(gpa_tier) = 1 THEN '(소계)' ELSE gpa_tier END
                                                              AS gpa_tier,
       COUNT(*) AS student_count
FROM tiered
GROUP BY ROLLUP (major, gpa_tier)
ORDER BY GROUPING(major),            -- 총계(전체)를 맨 아래로
         major,
         GROUPING(gpa_tier),         -- 학과 소계를 각 학과의 아래로
         gpa_tier;

-- ============================================================================
-- Q22) [심화] WITH RECURSIVE — 조직 트리의 depth 와 path
-- ============================================================================
-- CEO(depth 0)에서 출발해 자식으로 내려가며 경로를 문자열로 누적한다.
WITH RECURSIVE org AS (
    -- 기저: CEO (manager_id 없음)
    SELECT emp_id, name, 0 AS depth, name::text AS path
    FROM emp
    WHERE manager_id IS NULL
    UNION ALL
    -- 재귀: 자식은 부모의 depth+1, 경로 뒤에 자기 이름을 붙인다
    SELECT e.emp_id, e.name, o.depth + 1, o.path || ' > ' || e.name
    FROM emp e
    JOIN org o ON e.manager_id = o.emp_id
)
SELECT emp_id, name, depth, path
FROM org
ORDER BY path
LIMIT 5;

-- 기대 depth: CEO 0 / CEO 직속 40명(매니저 10 + Dev 30) 1 / 나머지 Dev 270명 2

-- (별도 쿼리) 매니저별 직속 부하 수 — 문항 지시 컬럼명 direct_reports
-- 기대: CEO 40, Mgr_2~Mgr_10 각 30. Mgr_11 은 부하가 0명이라 INNER JOIN 에서
--       빠진다(=11행). 부하 0명까지 보이려면 LEFT JOIN 으로 바꿔야 한다.
SELECT m.name,
       COUNT(e.emp_id) AS direct_reports
FROM emp m
JOIN emp e ON e.manager_id = m.emp_id
GROUP BY m.emp_id, m.name
ORDER BY direct_reports DESC, m.name;

-- ============================================================================
-- Q23) [심화] 학과별 GPA 상위 3명 — Window Function (서브쿼리·CTE 두 방식)
-- ============================================================================
-- 순위: ROW_NUMBER() OVER (PARTITION BY major ORDER BY gpa DESC,
--       student_id) — 동률이면 student_id 오름차순이 2차 기준.
-- RANK / DENSE_RANK 를 함께 계산해 동점 처리 차이를 비교하고,
-- COUNT() OVER (PARTITION BY major) 로 학과별 전체 인원도 붙인다.

-- [방식 A] 서브쿼리
SELECT major, name, gpa, rn, rank_no, dense_no, total_in_major
FROM (
    SELECT major, name, gpa,
           ROW_NUMBER() OVER (PARTITION BY major
                              ORDER BY gpa DESC, student_id) AS rn,
           RANK()       OVER (PARTITION BY major
                              ORDER BY gpa DESC)             AS rank_no,
           DENSE_RANK() OVER (PARTITION BY major
                              ORDER BY gpa DESC)             AS dense_no,
           COUNT(*)     OVER (PARTITION BY major)            AS total_in_major
    FROM student
) AS ranked
WHERE rn <= 3                        -- 학과별 상위 3명
ORDER BY major, rn;

-- [방식 B] CTE — 같은 로직, 이름 붙은 단계로 표현
WITH ranked AS (
    SELECT major, name, gpa,
           ROW_NUMBER() OVER (PARTITION BY major
                              ORDER BY gpa DESC, student_id) AS rn,
           RANK()       OVER (PARTITION BY major
                              ORDER BY gpa DESC)             AS rank_no,
           DENSE_RANK() OVER (PARTITION BY major
                              ORDER BY gpa DESC)             AS dense_no,
           COUNT(*)     OVER (PARTITION BY major)            AS total_in_major
    FROM student
)
SELECT major, name, gpa, rn, rank_no, dense_no, total_in_major
FROM ranked
WHERE rn <= 3
ORDER BY major, rn;

-- ============================================================================
-- Q24) [심화] LAG — 학생별 이전 과목 대비 성적 변화
-- ============================================================================
-- ① 문자 성적을 점수로 변환 (A=4, B=3, C=2, D=1)
-- ② LAG(score) OVER (PARTITION BY student_id ORDER BY course) 로 이전 점수
-- ③ diff = 현재 - 이전, 방향을 상승/유지/하락 텍스트로
-- ④ 학생별 최고-최저 차이 score_range 를 윈도로 계산
-- 대상: 2건 이상 수강한 학생 900명에서 비교가 성립한다.
--       (배포본에는 1과목만 듣는 학생이 없고, 0건 100명은 enroll 에 아예 없다)
WITH scored AS (
    SELECT student_id, course,
           CASE grade WHEN 'A' THEN 4 WHEN 'B' THEN 3
                      WHEN 'C' THEN 2 ELSE 1 END AS score
    FROM enroll
)
SELECT student_id, course, score,
       LAG(score) OVER (PARTITION BY student_id ORDER BY course) AS prev_score,
       score - LAG(score) OVER (PARTITION BY student_id
                                ORDER BY course)                 AS diff,
       CASE
           WHEN LAG(score) OVER (PARTITION BY student_id
                                 ORDER BY course) IS NULL THEN '(첫 과목)'
           WHEN score > LAG(score) OVER (PARTITION BY student_id
                                         ORDER BY course) THEN '상승'
           WHEN score = LAG(score) OVER (PARTITION BY student_id
                                         ORDER BY course) THEN '유지'
           ELSE '하락'
       END AS trend,
       MAX(score) OVER (PARTITION BY student_id)
         - MIN(score) OVER (PARTITION BY student_id)             AS score_range
FROM scored
ORDER BY student_id, course
LIMIT 5;

-- ============================================================================
-- Q25) [심화] 주문 누적합 · 3개 이동평균 · 고객별 누적 — ROWS BETWEEN
-- ============================================================================
-- 요구 4가지를 한 화면에서 확인한다:
--   ① SUM(amount) OVER (ORDER BY order_id
--      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)  → 전체 누적합
--   ② AVG(amount) OVER (ORDER BY order_id
--      ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)          → 3개 이동평균
--   ③ PARTITION BY customer_id                            → 고객별 누적 구매금액
--   ④ 누적합이 전체 합의 50% 를 넘는 첫 order_id          → 25-B 에서 별도 작성
--
-- [프레임을 왜 명시하는가] ORDER BY 만 쓰고 프레임을 생략하면 기본값이
-- RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW 라, 정렬 키가 같은 행이
-- 있으면 그 행들을 한 덩어리로 묶어 같은 값을 준다. ROWS 는 "행 단위"라
-- 동률이 있어도 한 행씩 누적된다. 여기서는 order_id 가 PK 라 결과가 같지만,
-- 문항이 ROWS 를 지정한 이유가 이 차이다.
-- [이동평균의 첫 두 행] 2 PRECEDING 이라도 앞에 행이 없으면 있는 만큼만
-- 평균한다 → 1행은 자기 1개, 2행은 2개 평균. NULL 이 아니라 정상 동작이다.
 
-- 25-A) 누적합 · 3개 이동평균 · 고객별 누적 (한 쿼리에서 ①②③)
SELECT order_id,
       customer_id,
       amount,
       SUM(amount) OVER (ORDER BY order_id
                         ROWS BETWEEN UNBOUNDED PRECEDING
                                  AND CURRENT ROW)        AS running_total,
       ROUND(AVG(amount) OVER (ORDER BY order_id
                         ROWS BETWEEN 2 PRECEDING
                                  AND CURRENT ROW), 2)    AS moving_avg_3,
       SUM(amount) OVER (PARTITION BY customer_id         -- ③ 고객별로 프레임 분리
                         ORDER BY order_id
                         ROWS BETWEEN UNBOUNDED PRECEDING
                                  AND CURRENT ROW)        AS cust_running_total
FROM orders
ORDER BY order_id
LIMIT 5;
--   cust_running_total 각 행의 amount 와 같다 — 앞 5건은 고객 2~6 으로 전부
--     다른 사람이라 "그 고객의 첫 주문"이기 때문. 고객당 6건이므로 같은
--     고객의 2번째 주문은 order_id 가 500 뒤에 온다(customer_id = order_id%500+1).
--   검산: running_total 은 매 행 amount 만큼 늘어야 하고, 3행부터의
--         moving_avg_3 은 직전 3개 amount 의 평균과 일치해야 한다.
 
-- 25-B) ④ 누적합이 전체 합의 50% 를 초과하는 첫 order_id
-- 누적합과 전체합을 같은 층에서 만든 뒤 비교한다. WHERE 절에서는 윈도 함수를
-- 쓸 수 없어(WHERE 가 윈도 계산보다 먼저 평가된다) CTE 로 한 단계 내린다.
WITH running AS (
    SELECT order_id,
           amount,
           SUM(amount) OVER (ORDER BY order_id
                             ROWS BETWEEN UNBOUNDED PRECEDING
                                      AND CURRENT ROW) AS running_total,
           SUM(amount) OVER ()                         AS grand_total
    FROM orders
)
SELECT order_id,
       amount,
       running_total,
       grand_total,
       ROUND(100.0 * running_total / grand_total, 2) AS pct_of_total
FROM running
WHERE running_total > grand_total * 0.5   -- 50% 를 "초과"하는 지점
ORDER BY order_id
LIMIT 1;                                  -- 그중 첫 번째
-- 주문이 3,000건이니 절반은 1,500번째일 것 같지만 1503 이 나온다.
-- amount 가 균등하지 않아 "건수의 절반"과 "금액의 절반"이 어긋나기 때문에 누적합을 사용한다.
--
-- 검산: grand_total 은 SELECT SUM(amount) FROM orders 와 같아야 하고,
--       order_id = 1502 의 running_total 은 3,682,992.50 이하여야 한다.