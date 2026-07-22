-- ============================================================================
-- [학사 관리 시스템] 시드 데이터 (PostgreSQL)
-- ============================================================================
-- 규모: 학과 10 / 교수 12 / 학생 20 / 과목 15 / 개설강좌 15 /
--       수강신청 75 / 출결 180  — 전 테이블 최소 10건 요건 충족
-- 설계된 이야기(문항의 재료가 되도록 의도 배치):
--   · 2025-2(지난 학기) 성적 입력 완료, 2026-1(진행 중) 성적 NULL (R11)
--   · 학생 3: 2025-2 과목 F(0.5) → 2026-1 같은 과목 재수강 (R19·R20 사례)
--   · 수강신청 20번: 성적 지연 입력(지난 학기인데 NULL — COALESCE 재료)
--   · 학생 19(휴학)의 2026-1 신청 1건 = 의도된 위반 데이터 (R22, Q10 탐지 대상)
--   · 학생 20(졸업): 지난 학기 이수 기록만 보유
-- 생성 방식: 결정식(generate_series + 나머지 연산) — 재현 가능·랜덤 함정 없음
-- ============================================================================

-- 1) 학과 10 — 기준학점은 15/18/21 로 다양화 (R18 판정 문항 재료)
INSERT INTO departments (dept_id, name, office, required_credits) VALUES
 (1,'컴퓨터공학과','공학관 301', 18), (2,'전자공학과','공학관 402', 15),
 (3,'경영학과',  '경영관 201', 15), (4,'국어국문학과','문과관 105', 15),
 (5,'수학과',    '자연관 310', 18), (6,'물리학과',  '자연관 415', 21),
 (7,'화학과',    '자연관 220', 15), (8,'심리학과',  '사회관 512', 18),
 (9,'사학과',    '문과관 308', 15), (10,'통계학과', '자연관 118', 21);

-- 2) 교수 12 — 임용일을 2008~2022 로 분산 (근속 연차 날짜 함수 재료)
INSERT INTO professors (professor_id, dept_id, name, email, hired_date)
SELECT g,
       1 + (g - 1) % 10,
       '교수' || g,
       'prof' || g || '@univ.ac.kr',
       DATE '2008-03-01' + ((g - 1) * 420)   -- 약 14개월 간격
FROM generate_series(1, 12) AS g;

-- 3) 학생 20 — 입학년도 2020~2023, 생일 분산, 학적 상태 배치 (R15)
INSERT INTO students (student_id, student_no, dept_id, name, email,
                      admission_year, birth_date, status)
SELECT g,
       (2023 - (g % 4))::text || lpad(g::text, 4, '0'),   -- 학번 = 입학년도+일련
       1 + (g - 1) % 10,
       '학생' || g,
       'stu' || g || '@univ.ac.kr',
       2023 - (g % 4),
       DATE '2001-01-15' + ((g * 67) % 1400),             -- 2001~2004 분산
       CASE WHEN g = 19 THEN '휴학'                        -- R22 위반 시나리오용
            WHEN g = 20 THEN '졸업'
            ELSE '재학' END
FROM generate_series(1, 20) AS g;

-- 4) 과목 15 — 학점 1~3 순환 (R5)
INSERT INTO courses (course_id, dept_id, title, credits)
SELECT g,
       1 + (g - 1) % 10,
       (ARRAY['데이터베이스','자료구조','회로이론','경영통계','현대문학',
              '해석학','양자역학','유기화학','인지심리학','한국사',
              '회귀분석','운영체제','신호처리','마케팅','고전시가'])[g],
       1 + g % 3
FROM generate_series(1, 15) AS g;

-- 5) 개설강좌 15 (R6·R7·R16)
--    1~8  : 2026-1 (진행 중 학기) — 요일·교시 배치, 정원 3~5 (Q11 잔여석 재료)
--    9~15 : 2025-2 (지난 학기)   — 과목 1~7 이 양쪽 학기에 존재 → 재수강 가능 구조
INSERT INTO course_offerings (offering_id, course_id, professor_id, semester,
                              section, capacity, day_of_week, period)
SELECT g,
       CASE WHEN g <= 8 THEN g ELSE g - 8 END,
       1 + (g - 1) % 12,
       CASE WHEN g <= 8 THEN '2026-1' ELSE '2025-2' END,
       1,
       3 + g % 3,                                          -- 정원 3~5
       (ARRAY['월','화','수','목','금'])[1 + (g - 1) % 5],
       1 + g % 8
FROM generate_series(1, 15) AS g;

-- 6) 수강신청 (R8~R11, R20)
-- 6-1) 지난 학기(2025-2): 재학생 1~18 이 각 2강좌, 성적 입력 완료
--      성적 결정식: 1.0 ~ 4.4 (한 자리 소수)
INSERT INTO enrollments (enrollment_id, student_id, offering_id, enrolled_at, grade)
SELECT (s - 1) * 2 + k,                                   -- id 1~36
       s,
       9 + (s - 1 + (k - 1) * 3) % 7,                     -- 강좌 9~15 분산
       DATE '2025-08-20' + s % 10,
       ((s * 7 + (9 + (s - 1 + (k - 1) * 3) % 7) * 3) % 35 + 10) / 10.0
FROM generate_series(1, 18) AS s, generate_series(1, 2) AS k;

-- 6-2) 진행 중 학기(2026-1): 재학생 1~18 이 각 2강좌, 성적 미입력(NULL, R11)
INSERT INTO enrollments (enrollment_id, student_id, offering_id, enrolled_at, grade)
SELECT 36 + (s - 1) * 2 + k,                              -- id 37~72
       s,
       1 + (s - 1 + (k - 1) * 4) % 8,                     -- 강좌 1~8 분산
       DATE '2026-02-15' + s % 12,
       NULL                                               -- 미입력 (R11)
FROM generate_series(1, 18) AS s, generate_series(1, 2) AS k;

-- 6-3) 이야기 행 (명시 삽입)
INSERT INTO enrollments (enrollment_id, student_id, offering_id, enrolled_at, grade) VALUES
 (73, 19, 2, DATE '2026-02-20', NULL),   -- [의도된 위반] 휴학생의 신청 (R22, Q10 탐지 대상)
 (74, 20, 10, DATE '2025-08-25', 3.5),   -- 졸업생의 지난 학기 이수 기록
 (75, 20, 12, DATE '2025-08-25', 4.0);

-- 6-4) 성적 보정 (이야기 주입)
UPDATE enrollments SET grade = 0.5  WHERE enrollment_id = 5;
 -- ↑ 학생 3, 2025-2 '회로이론' F (R19 미이수) — 같은 과목이 2026-1 강좌 3으로
 --   열려 있고 학생 3의 6-2 결정식이 강좌 3을 포함 → 재수강 사례 완성 (R20)
UPDATE enrollments SET grade = NULL WHERE enrollment_id = 20;
 -- ↑ 지난 학기인데 성적 지연 입력 — COALESCE '미입력' 표시 문항 재료 (R11)

-- 7) 출결 (R17): 2026-1 수강신청(id 37~72)에 주 1회 × 5주차 기록
--    상태 결정식: 나머지 0=결석(10%), 1·2=지각(20%), 그 외=출석(70%)
--    (위반 신청 73번은 휴학생이므로 출결 미기록 — 의도)
INSERT INTO attendance (attendance_id, enrollment_id, class_date, status)
SELECT (e - 37) * 5 + w + 1,                              -- id 1~180
       e,
       DATE '2026-03-02' + w * 7,                         -- 매주 월요일 기준
       CASE (e + w) % 10
            WHEN 0 THEN '결석'
            WHEN 1 THEN '지각'
            WHEN 2 THEN '지각'
            ELSE '출석' END
FROM generate_series(37, 72) AS e, generate_series(0, 4) AS w;

-- ------------------------------------------------------------------
-- 적재 증빙: 전 테이블 건수 (min 10건 요건 확인 — 캡처 대상)
-- ------------------------------------------------------------------
SELECT 'departments' AS tbl,      COUNT(*) FROM departments
UNION ALL SELECT 'professors',       COUNT(*) FROM professors
UNION ALL SELECT 'students',         COUNT(*) FROM students
UNION ALL SELECT 'courses',          COUNT(*) FROM courses
UNION ALL SELECT 'course_offerings', COUNT(*) FROM course_offerings
UNION ALL SELECT 'enrollments',      COUNT(*) FROM enrollments
UNION ALL SELECT 'attendance',       COUNT(*) FROM attendance;