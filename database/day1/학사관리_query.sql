-- ============================================================================
-- [학사 관리 시스템] 문항별 실습 쿼리 (PostgreSQL)
-- ============================================================================
-- 원칙: ① SELECT 는 문항이 요구하는 컬럼만 (SELECT * 금지)
--       ② 모든 쿼리에 의도·해석 주석  ③ 문항마다 대응 요구사항(R#) 표기
-- ============================================================================

-- ============================================================================
-- Q1) 기초 조회 — 컴퓨터공학과 "재학생" 명단, 입학년도 오름차순
--     (SELECT + WHERE + ORDER BY / R2·R15)
-- ============================================================================
SELECT student_no, name, admission_year
FROM students
WHERE dept_id = 1                    -- 컴퓨터공학과
  AND status  = '재학'               -- 학적 상태 필터 (R15)
ORDER BY admission_year, student_no;

-- ============================================================================
-- Q2) 조건 응용 — 2021~2023학번 중 이메일이 등록된 학생 (BETWEEN + IS NOT NULL)
-- ============================================================================
SELECT student_no, name, admission_year, email
FROM students
WHERE admission_year BETWEEN 2021 AND 2023
  AND email IS NOT NULL
ORDER BY admission_year DESC, name;

-- ============================================================================
-- Q3) COALESCE — 성적 조회: 미입력(NULL)을 '미입력' 으로 표시 (R11)
--     grade 가 숫자형이므로 문자로 변환 후 COALESCE 로 대체한다
-- ============================================================================
SELECT s.name              AS student,
       c.title             AS course,
       o.semester,
       COALESCE(e.grade::text, '미입력') AS grade_display   -- NULL → '미입력'
FROM enrollments e
JOIN students s         ON s.student_id = e.student_id
JOIN course_offerings o ON o.offering_id = e.offering_id
JOIN courses c          ON c.course_id  = o.course_id
ORDER BY o.semester, s.name
LIMIT 15;                            -- 화면 확인용 (전체는 75행)

-- ============================================================================
-- Q4) CASE WHEN — 평점 → 등급 변환 + 이수/미이수 판정 (R19)
--     1.0 미만은 F(미이수), NULL 은 미입력으로 구분
-- ============================================================================
SELECT s.name,
       c.title,
       e.grade,
       CASE
           WHEN e.grade IS NULL  THEN '미입력'
           WHEN e.grade >= 4.5   THEN 'A+'          
           WHEN e.grade >= 4.0   THEN 'A'
           WHEN e.grade >= 3.5   THEN 'B+'
           WHEN e.grade >= 3.0   THEN 'B'
           WHEN e.grade >= 2.5   THEN 'C+'
           WHEN e.grade >= 2.0   THEN 'C'
           WHEN e.grade >= 1.5   THEN 'D+'
           WHEN e.grade >= 1.0   THEN 'D'
           ELSE                       'F(미이수)'          -- R19
       END AS letter_grade
FROM enrollments e
JOIN students s         ON s.student_id = e.student_id
JOIN course_offerings o ON o.offering_id = e.offering_id
JOIN courses c          ON c.course_id  = o.course_id
WHERE o.semester = '2025-2'          -- 성적이 존재하는 지난 학기
ORDER BY e.grade ASC NULLS FIRST
LIMIT 15;

-- ============================================================================
-- Q5) 날짜 함수 — 학생 나이(AGE) · 교수 근속 연차 (두 조회)
-- ============================================================================
-- 5-1) 학생 나이: AGE 는 interval 을 주므로 EXTRACT 로 '만 나이' 정수 추출
SELECT name,
       birth_date,
       EXTRACT(YEAR FROM AGE(CURRENT_DATE, birth_date))::int AS age
FROM students
ORDER BY birth_date
LIMIT 10;

-- 5-2) 교수 근속 연차: 임용일 기준 몇 년차인지
SELECT name,
       hired_date,
       EXTRACT(YEAR FROM AGE(CURRENT_DATE, hired_date))::int + 1 AS year_of_service
FROM professors
ORDER BY hired_date;

-- ============================================================================
-- Q6) 교차 테이블 JOIN — 학생 3의 전체 수강 내역 (5테이블 조인 / R8)
--     학생 ⋈ 수강신청 ⋈ 개설강좌 ⋈ 과목 ⋈ 담당교수
--     [관찰 포인트] '회로이론' 이 2025-2 F 와 2026-1 재신청으로 두 번 등장
--                   = 재수강 허용 설계(R20)의 실증
-- ============================================================================
SELECT o.semester,
       c.title,
       c.credits,
       p.name AS professor,
       COALESCE(e.grade::text, '미입력') AS grade
FROM enrollments e
JOIN students s         ON s.student_id  = e.student_id
JOIN course_offerings o ON o.offering_id = e.offering_id
JOIN courses c          ON c.course_id   = o.course_id
JOIN professors p       ON p.professor_id = o.professor_id
WHERE s.student_id = 3
ORDER BY o.semester, c.title;

-- ============================================================================
-- Q7) 개인 시간표 조회 — 학생 3의 2026-1 시간표, 요일·교시 정렬 (R16)
--     실제 학사시스템의 '개인강의시간표조회' 메뉴 재현.
--     요일은 문자라 그대로 정렬하면 가나다순이 되므로 CASE 로 순서를 부여
-- ============================================================================
SELECT o.day_of_week,
       o.period,
       c.title,
       p.name AS professor
FROM enrollments e
JOIN course_offerings o ON o.offering_id = e.offering_id
JOIN courses c          ON c.course_id   = o.course_id
JOIN professors p       ON p.professor_id = o.professor_id
WHERE e.student_id = 3
  AND o.semester   = '2026-1'
ORDER BY CASE o.day_of_week                 -- 월~금 순서 강제
             WHEN '월' THEN 1 WHEN '화' THEN 2 WHEN '수' THEN 3
             WHEN '목' THEN 4 ELSE 5 END,
         o.period;

-- ============================================================================
-- Q8) 출석률 산정 — 학생×강좌별 (지각은 0.5 가중 / R17)
--     출석률 = (출석 1.0 + 지각 0.5 + 결석 0) ÷ 전체 수업 수
-- ============================================================================
SELECT s.name,
       c.title,
       COUNT(*)                                            AS total_classes,
       COUNT(*) FILTER (WHERE a.status = '출석')           AS attended,
       COUNT(*) FILTER (WHERE a.status = '지각')           AS late,
       COUNT(*) FILTER (WHERE a.status = '결석')           AS absent,
       ROUND(100.0 * SUM(CASE a.status
                             WHEN '출석' THEN 1.0
                             WHEN '지각' THEN 0.5
                             ELSE 0 END) / COUNT(*), 1)    AS attendance_pct
FROM attendance a
JOIN enrollments e      ON e.enrollment_id = a.enrollment_id
JOIN students s         ON s.student_id   = e.student_id
JOIN course_offerings o ON o.offering_id  = e.offering_id
JOIN courses c          ON c.course_id    = o.course_id
GROUP BY s.name, c.title
ORDER BY attendance_pct ASC          -- 위험(저출석) 순으로
LIMIT 10;

-- ============================================================================
-- Q9) 이수학점 · 졸업 기준 충족 판정 (R18·R19)
--     이수학점 = 성적이 입력되고 1.0 이상(F 아님)인 과목의 학점 합
-- ============================================================================
SELECT s.name,
       d.name                                   AS department,
       d.required_credits,
       COALESCE(SUM(c.credits) FILTER (WHERE e.grade >= 1.0), 0) AS earned_credits,
       CASE
           WHEN COALESCE(SUM(c.credits) FILTER (WHERE e.grade >= 1.0), 0)
                >= d.required_credits THEN '충족'
           ELSE '미충족'
       END AS graduation_check                  -- R18 판정
FROM students s
JOIN departments d       ON d.dept_id = s.dept_id
LEFT JOIN enrollments e  ON e.student_id = s.student_id   -- 신청 0건 학생 포함
LEFT JOIN course_offerings o ON o.offering_id = e.offering_id
LEFT JOIN courses c      ON c.course_id = o.course_id
GROUP BY s.student_id, s.name, d.name, d.required_credits
ORDER BY earned_credits DESC;

-- ============================================================================
-- Q10) 무결성 점검 — 휴학·수료·졸업 상태의 수강신청 위반 탐지 (R22)
--      CHECK 로 막을 수 없는 규칙은 탐지 쿼리로 감시한다.
--      기대 결과: 시드에 심어둔 위반 1건(학생 19, 휴학)이 검출되어야 정상
-- ============================================================================
SELECT s.student_no,
       s.name,
       s.status,
       c.title,
       o.semester,
       e.enrolled_at
FROM enrollments e
JOIN students s         ON s.student_id  = e.student_id
JOIN course_offerings o ON o.offering_id = e.offering_id
JOIN courses c          ON c.course_id   = o.course_id
WHERE s.status <> '재학'             -- 재학생이 아닌데
  AND o.semester = '2026-1';         -- 진행 중 학기를 신청한 경우 (R22 위반)

-- ============================================================================
-- Q11) 강좌별 신청 인원 vs 정원 — 잔여석 현황 (R13 으로 가는 다리)
--      잔여석이 음수면 정원 초과 = R13 을 어길 수 있음을 보여주는 관찰
-- ============================================================================
SELECT c.title,
       o.semester,
       o.capacity,
       COUNT(e.enrollment_id)              AS enrolled,
       o.capacity - COUNT(e.enrollment_id) AS seats_left
FROM course_offerings o
JOIN courses c          ON c.course_id = o.course_id
LEFT JOIN enrollments e ON e.offering_id = o.offering_id  -- 신청 0건 강좌 포함
WHERE o.semester = '2026-1'
GROUP BY c.title, o.semester, o.capacity
ORDER BY seats_left;
