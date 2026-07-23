-- ############################################################################
--  같은 답을 내는 5가지 구조 — 어느 쪽이 빠른가 (문항 14 심화)
-- ############################################################################
-- 문항 14 는 "CTE 로 학과 마스터를 만들고 스칼라 서브쿼리로 조회"하는 구조다.
-- 그런데 student.major 를 그냥 꺼내면 한 줄이면 끝난다. 결과가 같다면
-- 무엇이 다른가? 실행계획으로 확인한다.
--
-- 비교 대상 (전부 같은 1,000행을 되돌린다 — 결과 동일함은 사전 검증 완료)
--   A. 직접 컬럼 참조            ← 기준선
--   B. CTE + 스칼라 서브쿼리     ← 문항 14 형태
--   C. CTE + LEFT JOIN           ← 같은 CTE 를 조인으로
--   D. 자기 테이블 스칼라 서브쿼리 (student_id 로 자기 행을 다시 찾기)
--   E. CTE AS MATERIALIZED + 스칼라 서브쿼리  ← B 의 변형
--
-- ★ 측정 방법 (이 순서를 지켜야 비교가 성립한다)
--   1) LIMIT 을 붙이지 말 것. LIMIT 5 면 5행만 만들고 멈춰서 차이가 안 보인다.
--      아래 쿼리들이 LIMIT 없이 1,000행 전체를 만드는 이유다.
--   2) 출력 자체가 느리므로 화면 출력을 빼고 계산 비용만 본다 →
--      COUNT(*) 로 감싸거나, psql 에서 \o /dev/null 로 출력을 버린다.
--   3) 첫 실행은 디스크에서 읽느라 느리다. 각 쿼리를 2~3회 실행하고
--      두 번째 이후 값을 쓸 것 (\timing on 으로 실행 시간도 함께 본다).
--   4) EXPLAIN (ANALYZE, BUFFERS) 로 계획·실측·버퍼를 함께 확인한다.
--
-- 준비:
--   \timing on
--   \pset pager off
 
-- ----------------------------------------------------------------------------
-- 3-A) 직접 컬럼 참조 — 기준선
-- ----------------------------------------------------------------------------
EXPLAIN (ANALYZE, BUFFERS)
SELECT s.name, s.major AS dept_name
FROM student s
ORDER BY s.student_id;
-- 예상: Index Scan(또는 Seq Scan + Sort) 한 번. 가장 단순한 계획.
 
-- ----------------------------------------------------------------------------
-- 3-B) CTE + 스칼라 서브쿼리 — 문항 14 형태
-- ----------------------------------------------------------------------------
EXPLAIN (ANALYZE, BUFFERS)
WITH dept AS (
    SELECT DISTINCT major AS dept_name
    FROM student
)
SELECT s.name,
       (SELECT d.dept_name FROM dept d WHERE d.dept_name = s.major) AS dept_name
FROM student s
ORDER BY s.student_id;
-- ★ 확인 지점 — 계획에서 SubPlan 을 찾고 그 안의 loops 값을 볼 것.
--   PostgreSQL 12 부터 WITH 는 참조가 1회면 본문에 인라인된다. 여기서는
--   CTE 가 상관 서브쿼리 안에서만 쓰이므로, 인라인되면 DISTINCT 집계가
--   바깥 행마다 다시 계산될 수 있다. 그 경우 loops 가 1000 근처로 찍힌다.
--   즉 "학생 1,000명 각각에 대해 학과 목록을 새로 만드는" 셈이다.
-- [가설] A 보다 눈에 띄게 느리다. 얼마나 느린지는 직접 재야 안다.
 
-- ----------------------------------------------------------------------------
-- 3-C) CTE + LEFT JOIN — 같은 CTE 를 조인으로 바꾸면
-- ----------------------------------------------------------------------------
EXPLAIN (ANALYZE, BUFFERS)
WITH dept AS (
    SELECT DISTINCT major AS dept_name
    FROM student
)
SELECT s.name, d.dept_name
FROM student s
LEFT JOIN dept d ON d.dept_name = s.major
ORDER BY s.student_id;
-- ★ 확인 지점: SubPlan 이 사라지고 Hash Left Join 이 나타나는지.
--   CTE 는 한 번만 만들어지고(6행) 해시로 올려 1,000행에 붙인다.
--   "행마다 반복" → "한 번 만들어 붙이기" 로 바뀌는 지점이다.
-- [의미] 슬라이드의 N+1 문제와 정확히 같은 구조 — 반복 조회를 JOIN 한 번으로.
 
-- ----------------------------------------------------------------------------
-- 3-D) 자기 테이블 스칼라 서브쿼리 — PK 로 자기 행을 다시 찾기
-- ----------------------------------------------------------------------------
EXPLAIN (ANALYZE, BUFFERS)
SELECT s.name,
       (SELECT s2.major FROM student s2 WHERE s2.student_id = s.student_id) AS dept_name
FROM student s
ORDER BY s.student_id;
-- ★ 확인 지점: SubPlan 안이 Index Scan using student_pkey 인지.
--   B 와 달리 PK 를 타므로 1회 조회 비용은 매우 싸다. 다만 그것을 1,000번
--   반복하는 것은 같다 — "싼 일도 1,000번 하면 비싸다"를 재는 대조군이다.
 
-- ----------------------------------------------------------------------------
-- 3-E) CTE AS MATERIALIZED — 인라인을 막으면 달라지는가
-- ----------------------------------------------------------------------------
EXPLAIN (ANALYZE, BUFFERS)
WITH dept AS MATERIALIZED (          -- ★ 한 번만 계산하고 결과를 재사용하라
    SELECT DISTINCT major AS dept_name
    FROM student
)
SELECT s.name,
       (SELECT d.dept_name FROM dept d WHERE d.dept_name = s.major) AS dept_name
FROM student s
ORDER BY s.student_id;
-- ★ 확인 지점: CTE Scan on dept 가 나타나고, DISTINCT 집계(HashAggregate)가
--   계획 위쪽에 딱 1회만 등장하는지. B 와 비교하면 MATERIALIZED 의 효과가
--   숫자로 드러난다.
-- [배경] PostgreSQL 11 이하는 CTE 가 항상 MATERIALIZED 였다("optimization
--   fence"). 12 부터 기본이 인라인으로 바뀌었고, 예전 동작이 필요하면
--   이 키워드를 명시한다. 버전에 따라 같은 SQL 의 성능이 달라지는 사례다.
 
-- ----------------------------------------------------------------------------
-- 3-F) 출력 비용을 뺀 순수 계산 시간 비교
-- ----------------------------------------------------------------------------
-- 위 5개는 1,000행을 화면에 뿌리는 비용이 섞여 있다. COUNT 로 감싸면
-- 계산 비용만 남아 비교가 선명해진다. \timing on 상태에서 각각 3회 실행.
SELECT COUNT(*) FROM (
    SELECT s.name, s.major AS dept_name FROM student s
) AS a;                                                        -- A
 
SELECT COUNT(*) FROM (
    WITH dept AS (SELECT DISTINCT major AS dept_name FROM student)
    SELECT s.name, (SELECT d.dept_name FROM dept d WHERE d.dept_name = s.major) AS dept_name
    FROM student s
) AS b;                                                        -- B
 
SELECT COUNT(*) FROM (
    WITH dept AS (SELECT DISTINCT major AS dept_name FROM student)
    SELECT s.name, d.dept_name FROM student s
    LEFT JOIN dept d ON d.dept_name = s.major
) AS c;                                                        -- C
-- 세 결과 모두 1000 이어야 한다. 값이 다르면 어느 쿼리가 행을 잃거나
-- 불린 것이므로, 성능 비교 이전에 그것부터 봐야 한다.
 
-- ----------------------------------------------------------------------------
-- 3-G) 결과가 정말 같은지 확인 — 성능 비교의 전제
-- ----------------------------------------------------------------------------
-- 느린 쿼리가 답까지 다르면 비교 자체가 무의미하다. 차집합이 양쪽 다
-- 0행이면 완전히 같은 집합이다.
(
    SELECT s.name, s.major AS dept_name FROM student s
    EXCEPT
    WITH dept AS (SELECT DISTINCT major AS dept_name FROM student)
    SELECT s.name, (SELECT d.dept_name FROM dept d WHERE d.dept_name = s.major)
    FROM student s
)
UNION ALL
(
    WITH dept AS (SELECT DISTINCT major AS dept_name FROM student)
    SELECT s.name, (SELECT d.dept_name FROM dept d WHERE d.dept_name = s.major)
    FROM student s
    EXCEPT
    SELECT s.name, s.major FROM student s
);