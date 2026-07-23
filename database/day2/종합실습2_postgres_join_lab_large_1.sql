-- ============================================================
-- STEP A. 롤(skala_user) & 데이터베이스(skala_db) 생성
-- ============================================================
-- ⚠️ DBeaver 사용 안내
--  1) 이 파일은 "postgres" (또는 template1 등 기본 관리용 DB)에 연결된
--     슈퍼유저 계정(예: postgres)으로 실행하세요. skala_db에는 아직
--     아무것도 없으므로 skala_db로 접속해서 실행하면 안 됩니다.
--  2) 전체 실행(Alt+X)하지 말고, 아래 STEP을 순서대로 한 문장씩(Ctrl+Enter)
--     실행하세요. CREATE DATABASE는 트랜잭션 안에서 실행할 수 없어서
--     다른 문장과 묶어 한 번에 실행하면 오류가 날 수 있습니다.
--  3) 원본 스크립트의 `\prompt`(대화형 비밀번호 입력)는 DBeaver에서 지원되지
--     않으므로, 아래 STEP A2에서 'CHANGE_ME_PASSWORD' 부분을 실제 비밀번호로
--     직접 바꿔서 실행하세요.
-- ============================================================

-- ─────────────────────────────────────────────
-- STEP A1: 롤(사용자) 생성
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

-- ─────────────────────────────────────────────
-- STEP A2: 비밀번호 설정
--   ↓↓↓ 'CHANGE_ME_PASSWORD' 를 실제 비밀번호로 바꾼 뒤 실행하세요 ↓↓↓
-- ─────────────────────────────────────────────
ALTER ROLE skala_user PASSWORD 'CHANGE_ME_PASSWORD';

-- ─────────────────────────────────────────────
-- STEP A3: 데이터베이스 존재 여부 확인
--   결과가 0건이면 STEP A4를 실행하고, 1건 이상이면 STEP A4는 건너뛰세요.
-- ─────────────────────────────────────────────
SELECT datname FROM pg_database WHERE datname = 'skala_db';

-- ─────────────────────────────────────────────
-- STEP A4: 데이터베이스 생성 (STEP A3 결과가 0건일 때만 실행)
--   CREATE DATABASE는 단독 문장으로만 실행 가능하므로 반드시
--   이 줄만 커서에 두고 Ctrl+Enter로 실행하세요.
-- ─────────────────────────────────────────────
CREATE DATABASE skala_db
  OWNER    = skala_user
  ENCODING = 'UTF8'
  TEMPLATE = template0;

-- ─────────────────────────────────────────────
-- 다음 단계 안내
-- ─────────────────────────────────────────────
-- 여기까지 완료되면, DBeaver에서 skala_db로 접속하는 "새 커넥션"을 만들거나
-- Database Navigator에서 skala_db를 더블클릭해 접속을 전환한 뒤,
-- 종합실습2_postgres_join_lab_large_2.sql 파일을 이어서 실행하세요.
