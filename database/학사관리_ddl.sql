-- ============================================================================
-- [학사 관리 시스템] DDL — 테이블 생성 (PostgreSQL)
-- ============================================================================
-- 작성자: 최강희 / 작성일: 2026-07-22
-- 원칙: 모든 제약조건은 요구사항 정의서의 R# 에서 파생된다 (주석에 근거 표기)
-- 사용: createdb academy → psql -d academy -f 학사관리_ddl.sql
-- ============================================================================
-- ------------------------------------------------------------------
-- 스키마 (R1 이전 단계) — 학사 도메인 전용 이름공간
-- public 은 모든 롤이 접근하는 공용 공간이므로, 업무 객체는 별도 스키마로
-- 분리해 이름 충돌과 권한 범위를 좁힌다.
-- ------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS academy;

-- 이후 이 스크립트가 만드는 모든 객체는 academy 스키마에 생성된다
SET search_path TO academy;

-- 세션이 바뀌어도 유지되도록 DB 기본값에도 기록 (다음 접속부터 적용)
ALTER DATABASE academy SET search_path TO academy, public;

-- 재실행 가능하도록 자식 → 부모 순서로 정리
DROP TABLE IF EXISTS attendance;
DROP TABLE IF EXISTS enrollments;
DROP TABLE IF EXISTS course_offerings;
DROP TABLE IF EXISTS courses;
DROP TABLE IF EXISTS students;
DROP TABLE IF EXISTS professors;
DROP TABLE IF EXISTS departments;

-- ------------------------------------------------------------------
-- 학과 (R1) — 모든 소속의 뿌리
-- ------------------------------------------------------------------
CREATE TABLE departments (
    dept_id          INT         PRIMARY KEY,
    name             VARCHAR(50) NOT NULL UNIQUE,          -- 학과명 중복 금지
    office           VARCHAR(30),                          -- 부가 정보
    required_credits INT         NOT NULL DEFAULT 15
                     CHECK (required_credits > 0)          -- 졸업 기준학점 (R18)
);

-- ------------------------------------------------------------------
-- 교수 (R4, R14)
-- ------------------------------------------------------------------
CREATE TABLE professors (
    professor_id INT         PRIMARY KEY,
    dept_id      INT         NOT NULL
                 REFERENCES departments (dept_id) ON DELETE RESTRICT, -- R4·R21
    name         VARCHAR(30) NOT NULL,
    email        VARCHAR(80) UNIQUE,                       -- 이메일 유일 (R14)
    hired_date   DATE                                      -- 날짜 함수 문항 재료
);

-- ------------------------------------------------------------------
-- 학생 (R2, R3, R14, R15)
-- ------------------------------------------------------------------
CREATE TABLE students (
    student_id     INT         PRIMARY KEY,
    student_no     VARCHAR(10) NOT NULL UNIQUE,            -- 학번 유일 (R3)
    dept_id        INT         NOT NULL
                   REFERENCES departments (dept_id) ON DELETE RESTRICT, -- R2·R21
    name           VARCHAR(30) NOT NULL,
    email          VARCHAR(80) UNIQUE,                     -- (R14)
    admission_year INT         NOT NULL,
    birth_date     DATE,                                   -- AGE 문항 재료
    status         VARCHAR(4)  NOT NULL DEFAULT '재학'
                   CHECK (status IN ('재학','휴학','수료','졸업'))  -- 학적 (R15)
);

-- ------------------------------------------------------------------
-- 과목 (R5)
-- ------------------------------------------------------------------
CREATE TABLE courses (
    course_id INT         PRIMARY KEY,
    dept_id   INT         NOT NULL
              REFERENCES departments (dept_id) ON DELETE RESTRICT,  -- R5·R21
    title     VARCHAR(60) NOT NULL,
    credits   INT         NOT NULL CHECK (credits BETWEEN 1 AND 3)  -- 학점 (R5)
);

-- ------------------------------------------------------------------
-- 개설강좌 (R6, R7, R13, R16) — 과목의 학기별 실체
-- ------------------------------------------------------------------
CREATE TABLE course_offerings (
    offering_id  INT        PRIMARY KEY,
    course_id    INT        NOT NULL
                 REFERENCES courses (course_id) ON DELETE RESTRICT,
    professor_id INT        NOT NULL
                 REFERENCES professors (professor_id) ON DELETE RESTRICT,
    semester     VARCHAR(7) NOT NULL,                      -- 예: 2026-1
    section      INT        NOT NULL DEFAULT 1,            -- 분반
    capacity     INT        NOT NULL CHECK (capacity > 0), -- 정원 (R13 재료)
    day_of_week  VARCHAR(1) NOT NULL
                 CHECK (day_of_week IN ('월','화','수','목','금')),  -- 시간표 (R16)
    period       INT        NOT NULL CHECK (period BETWEEN 1 AND 8), -- 교시 (R16)
    UNIQUE (course_id, semester, section)                  -- 분반 중복 금지 (R7)
);

-- ------------------------------------------------------------------
-- 수강신청 (R8~R12, R20) — 학생 N:M 강좌를 해소하는 교차 테이블
-- ------------------------------------------------------------------
CREATE TABLE enrollments (
    enrollment_id INT  PRIMARY KEY,
    student_id    INT  NOT NULL
                  REFERENCES students (student_id) ON DELETE RESTRICT,
    offering_id   INT  NOT NULL
                  REFERENCES course_offerings (offering_id) ON DELETE RESTRICT,
    enrolled_at   DATE NOT NULL DEFAULT CURRENT_DATE,      -- 신청일 자동 (R10)
    grade         NUMERIC(2,1)
                  CHECK (grade BETWEEN 0.0 AND 4.5),       -- 평점 범위 (R12)
                  -- grade 는 NULL 허용: 미입력 상태 표현 (R11)
    UNIQUE (student_id, offering_id)
    -- UNIQUE 가 (학생, "강좌") 단위인 이유: 같은 과목의 다른 학기 강좌
    -- 재신청(재수강)은 허용하기 위함 (R20 의도된 설계)
    -- 참고: 휴학생 신청 금지(R22)·정원 초과 금지(R13)는 타 테이블 참조가
    -- 필요해 CHECK 로 표현 불가 → 문항 Q10 탐지 쿼리·확장(트리거)로 처리
);

-- ------------------------------------------------------------------
-- 출결 (R17) — 수강신청 1건에 수업일별 기록
-- ------------------------------------------------------------------
CREATE TABLE attendance (
    attendance_id INT        PRIMARY KEY,
    enrollment_id INT        NOT NULL
                  REFERENCES enrollments (enrollment_id) ON DELETE RESTRICT,
    class_date    DATE       NOT NULL,
    status        VARCHAR(2) NOT NULL
                  CHECK (status IN ('출석','지각','결석')),   -- 3종 (R17)
    UNIQUE (enrollment_id, class_date)          -- 같은 수업일 이중 기록 금지
);