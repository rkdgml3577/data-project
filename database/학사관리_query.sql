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

-- ============================================================================
-- [학사 관리 시스템 · 확장] 동시성 제어 시연 — 정원 초과(R13)·휴학생 신청(R22) 차단
-- ============================================================================
-- 배경: Q11 에서 확인했듯 '유기화학'(offering 8, 정원 5)은 잔여 1석이다.
--       마지막 한 자리를 학생 1(세션 A)과 학생 2(세션 B)가 동시에 신청하는
--       상황을 재현한다. 두 학생 모두 아직 이 강좌 미신청 상태라 UNIQUE 에
--       걸리지 않는다 — 막을 수단은 오직 동시성 제어뿐이다.
-- 준비: 터미널 창 2개를 나란히 열고 둘 다  psql -d academy  로 접속.
--       왼쪽 = [세션 A], 오른쪽 = [세션 B]. 아래 번호 ①②③… 순서대로
--       "해당 세션에" 입력한다. 순서가 곧 시나리오다.
-- ============================================================================


-- ============================================================================
-- 제1부. 문제 재현 — 보호 없이 동시 신청하면 정원이 뚫린다
-- ============================================================================
-- 두 트랜잭션이 "잔여석 확인 → 신청" 사이에 서로를 보지 못하는 것이 원인.

-- ① [세션 A] 트랜잭션 시작 + 잔여석 확인 → "1석 남음" 을 본다
BEGIN;
SELECT o.capacity - COUNT(e.enrollment_id) AS seats_left
FROM course_offerings o
LEFT JOIN enrollments e ON e.offering_id = o.offering_id
WHERE o.offering_id = 8
GROUP BY o.capacity;

-- ② [세션 B] 같은 확인 → B "도" 1석 남음을 본다 (A 의 신청은 아직 미확정)
BEGIN;
SELECT o.capacity - COUNT(e.enrollment_id) AS seats_left
FROM course_offerings o
LEFT JOIN enrollments e ON e.offering_id = o.offering_id
WHERE o.offering_id = 8
GROUP BY o.capacity;

-- ③ [세션 A] 1석 남았다고 믿고 신청 + 확정
INSERT INTO enrollments (enrollment_id, student_id, offering_id) VALUES (76, 1, 8);
COMMIT;

-- ④ [세션 B] B 도 1석 남았다고 믿고 신청 + 확정 → 아무 오류 없이 성공한다(!)
INSERT INTO enrollments (enrollment_id, student_id, offering_id) VALUES (77, 2, 8);
COMMIT;

-- ⑤ [아무 세션] 결과 확인 → 신청 6 / 정원 5 = 초과 발생  ★캡처(문제 증거)
SELECT o.capacity, COUNT(e.enrollment_id) AS enrolled,
       o.capacity - COUNT(e.enrollment_id) AS seats_left
FROM course_offerings o
LEFT JOIN enrollments e ON e.offering_id = o.offering_id
WHERE o.offering_id = 8
GROUP BY o.capacity;

-- ⑥ [아무 세션] 다음 시연을 위해 원상 복구 (다시 잔여 1석 상태로)
DELETE FROM enrollments WHERE enrollment_id IN (76, 77);


-- ============================================================================
-- 제2부. 방어 — SELECT ... FOR UPDATE 로 강좌 행을 잠그고 확인·신청을 직렬화
-- ============================================================================
-- 원리: "확인 전에 강좌 행을 먼저 잠근다". 뒤에 온 트랜잭션은 그 잠금이
-- 풀릴 때까지 대기하므로, 확인~신청 구간에 끼어들 수 없다.

-- ① [세션 A] 잠금 획득 후 잔여석 확인 → 1석
BEGIN;
SELECT capacity FROM course_offerings
WHERE offering_id = 8
FOR UPDATE;                                   -- ★ 강좌 행 잠금 (핵심)
SELECT COUNT(*) AS enrolled FROM enrollments WHERE offering_id = 8;

-- ② [세션 B] 같은 잠금 시도 → ★★ 커서가 멈추고 대기한다 — 이 "멈춘 화면" 이
--    이번 시연의 결정적 캡처다 (B 는 A 가 끝날 때까지 확인조차 못 한다)
BEGIN;
SELECT capacity FROM course_offerings
WHERE offering_id = 8
FOR UPDATE;

-- ③ [세션 A] 1석 확인했으므로 신청 + 확정 → 이 순간 B 의 잠금이 풀린다
INSERT INTO enrollments (enrollment_id, student_id, offering_id) VALUES (78, 1, 8);
COMMIT;

-- ④ [세션 B] 방금 깨어나 ②의 결과가 출력됐다. 이제 잔여석 확인 → 0석!
--    A 의 확정이 반영된 최신 상태를 본다 (제1부와의 차이)
SELECT capacity FROM course_offerings WHERE offering_id = 8;   -- 5
SELECT COUNT(*) AS enrolled FROM enrollments WHERE offering_id = 8;  -- 5 → 만석

-- ⑤ [세션 B] 만석이므로 신청을 포기하고 트랜잭션 철회  ★캡처(방어 성공)
ROLLBACK;

-- ⑥ [아무 세션] 최종 상태: 신청 5 / 정원 5 — 초과 없이 마지막 1석이
--    "먼저 잠근" A 에게 돌아갔다
SELECT o.capacity, COUNT(e.enrollment_id) AS enrolled
FROM course_offerings o
LEFT JOIN enrollments e ON e.offering_id = o.offering_id
WHERE o.offering_id = 8
GROUP BY o.capacity;


-- ============================================================================
-- 제3부. 자동화 — 트리거로 R13(정원)·R22(휴학생) 를 INSERT 시점에 차단
-- ============================================================================
-- 제2부의 잠금·확인 절차를 사람이 매번 지키게 할 수는 없다. 트리거에 넣으면
-- 어떤 경로의 INSERT 든 같은 검사를 강제로 통과해야 한다.

CREATE OR REPLACE FUNCTION check_enrollment()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_status   TEXT;
    v_capacity INT;
    v_enrolled INT;
BEGIN
    -- (R22) 재학생만 신청 가능 — CHECK 로 못 걸던 타 테이블 참조 규칙
    SELECT status INTO v_status
    FROM students WHERE student_id = NEW.student_id;
    IF v_status <> '재학' THEN
        RAISE EXCEPTION '수강신청 불가: 재학생이 아닙니다 (현재 학적: %)', v_status;
    END IF;

    -- (R13) 정원 검사 — FOR UPDATE 로 강좌 행을 잠가 동시 신청도 직렬화
    SELECT capacity INTO v_capacity
    FROM course_offerings WHERE offering_id = NEW.offering_id
    FOR UPDATE;
    SELECT COUNT(*) INTO v_enrolled
    FROM enrollments WHERE offering_id = NEW.offering_id;
    IF v_enrolled >= v_capacity THEN
        RAISE EXCEPTION '수강신청 불가: 정원 초과 (정원 %, 현재 %)',
                        v_capacity, v_enrolled;
    END IF;

    RETURN NEW;   -- 두 검사 통과 시에만 INSERT 진행
END;
$$;

CREATE TRIGGER trg_enrollment_check
BEFORE INSERT ON enrollments
FOR EACH ROW EXECUTE FUNCTION check_enrollment();

-- ---- 트리거 검증 3종 (한 세션에서 순서대로) ----
-- ⓐ 휴학생 신청 시도 → "재학생이 아닙니다" 예외  ★캡처(R22 원천 차단)
INSERT INTO enrollments (enrollment_id, student_id, offering_id) VALUES (90, 19, 1);

-- ⓑ 만석 강좌(유기화학, 제2부 결과 5/5) 신청 시도 → "정원 초과" 예외  ★캡처(R13)
INSERT INTO enrollments (enrollment_id, student_id, offering_id) VALUES (91, 2, 8);

-- ⓒ 정상 케이스: "자리가 나면 통과된다" — 학생 1 의 신청(78)을 취소해
--    1석을 만든 뒤, 재학생(학생 2)이 신청하면 트리거를 통과해야 정상
DELETE FROM enrollments WHERE enrollment_id = 78;   -- 수강 취소 → 잔여 1석
INSERT INTO enrollments (enrollment_id, student_id, offering_id) VALUES (92, 2, 8);
-- 성공 메시지(INSERT 0 1)가 나오면 "차단은 위반만, 정상은 통과" 증명 완료

-- ---- 시연 종료: 원상 복구 (본 문항 데이터와 동일 상태로 되돌리기) ----
DELETE FROM enrollments WHERE enrollment_id = 92;
-- 트리거는 유지해도 되고, 원본 상태 보존을 원하면 아래로 제거:
--   DROP TRIGGER trg_enrollment_check ON enrollments;
--   DROP FUNCTION check_enrollment();

-- ============================================================================
-- [해석 — PDF 캡션용]
-- 제1부: 확인과 신청 사이의 틈을 두 트랜잭션이 서로 못 보면 정원이 뚫린다
--        (Q11 의 초과 4건이 실제로 이렇게 생긴 것).
-- 제2부: 확인 "전에" 강좌 행을 잠그면(FOR UPDATE) 뒤 트랜잭션은 대기하고,
--        깨어난 뒤에는 확정된 최신 상태를 보므로 초과가 불가능해진다.
-- 제3부: 그 절차를 트리거에 넣어 모든 INSERT 에 강제하면, CHECK 로 표현
--        불가하던 R13·R22 가 원천 차단된다 — 관찰(Q10·Q11) → 수동 방어
--        (FOR UPDATE) → 자동 차단(트리거)의 3단 완성.
-- ============================================================================