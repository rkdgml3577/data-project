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
FOR UPDATE;                                   -- ★ 강좌 행 잠금 
SELECT COUNT(*) AS enrolled FROM enrollments WHERE offering_id = 8;

-- ② [세션 B] 같은 잠금 시도 → ★★ 커서가 멈추고 대기한다 — 이 "멈춘 화면" 
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

DROP TRIGGER IF EXISTS trg_enrollment_check ON enrollments;
CREATE TRIGGER trg_enrollment_check
BEFORE INSERT ON enrollments
FOR EACH ROW EXECUTE FUNCTION check_enrollment();

-- ---- 트리거 검증 3종 (한 세션에서 순서대로) ----
-- ⓐ 휴학생 신청 시도 → "재학생이 아닙니다" 예외  ★캡처(R22 원천 차단)
INSERT INTO enrollments (enrollment_id, student_id, offering_id) VALUES (90, 19, 1);

-- ⓑ 만석 강좌(유기화학, 제2부 결과 5/5) 신청 시도 → "정원 초과" 예외  
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