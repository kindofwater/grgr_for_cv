-- ──────────────────────────────────────────────────────────────
-- 근로고래 DB 스키마 (Supabase / PostgreSQL)
-- 테이블 생성 전 실행: 기존 테이블·타입 전체 삭제 후 재생성
-- ──────────────────────────────────────────────────────────────

-- Drop existing tables (order matters due to foreign keys)
DROP TABLE IF EXISTS notices, reports, points, review_helpful, reviews, ad_views, postings, worksites, users, departments, colleges, universities CASCADE;

-- Drop existing types
DROP TYPE IF EXISTS worksite_type_e, location_type_e, degree_program_e, academic_status_e, report_status_e, duration_type_e CASCADE;

-- ──────────────────────────────────────────────────────────────
-- ENUM types
-- ──────────────────────────────────────────────────────────────
CREATE TYPE worksite_type_e    AS ENUM ('national', 'school');
CREATE TYPE location_type_e    AS ENUM ('on_campus', 'off_campus');
CREATE TYPE degree_program_e   AS ENUM ('undergrad', 'graduate');
CREATE TYPE academic_status_e  AS ENUM ('enrolled', 'leave', 'completed', 'deferred_graduation');
CREATE TYPE report_status_e    AS ENUM ('pending', 'deleted', 'ignored');
CREATE TYPE duration_type_e    AS ENUM ('short', 'long', 'unknown');

-- ──────────────────────────────────────────────────────────────
-- Tables
-- ──────────────────────────────────────────────────────────────

-- 학교
CREATE TABLE universities (
  id           SERIAL PRIMARY KEY,
  name         VARCHAR(100) NOT NULL,
  campus       VARCHAR(50),
  email_domain VARCHAR(100) NOT NULL
);

-- 단과대학
CREATE TABLE colleges (
  id            SERIAL PRIMARY KEY,
  university_id INTEGER NOT NULL REFERENCES universities(id) ON DELETE RESTRICT,
  name          VARCHAR(100) NOT NULL
);

-- 학과
CREATE TABLE departments (
  id            SERIAL PRIMARY KEY,
  college_id    INTEGER NOT NULL REFERENCES colleges(id) ON DELETE RESTRICT,
  name          VARCHAR(100) NOT NULL,
  default_track VARCHAR(20) NOT NULL
);

-- 유저
CREATE TABLE users (
  id              SERIAL PRIMARY KEY,
  university_id   INTEGER NOT NULL REFERENCES universities(id) ON DELETE RESTRICT,
  college_id      INTEGER NOT NULL REFERENCES colleges(id) ON DELETE RESTRICT,
  department_id   INTEGER NOT NULL REFERENCES departments(id) ON DELETE RESTRICT,
  track           VARCHAR(20) NOT NULL,
  email           VARCHAR(255) UNIQUE NOT NULL,
  password_hash   VARCHAR(255) NOT NULL,
  nickname        VARCHAR(50) UNIQUE NOT NULL,
  admission_year  INTEGER NOT NULL,
  degree_program  degree_program_e NOT NULL,
  academic_status academic_status_e NOT NULL,
  grade           INTEGER CHECK (grade BETWEEN 1 AND 6),
  point_balance   INTEGER DEFAULT 0 CHECK (point_balance >= 0),
  pass_balances   JSONB DEFAULT '{}',
  pass_expires_at TIMESTAMP,
  region          VARCHAR(50),
  is_admin        BOOLEAN DEFAULT FALSE,
  created_at      TIMESTAMP DEFAULT NOW(),
  updated_at      TIMESTAMP DEFAULT NOW(),
  deleted_at      TIMESTAMP
);

-- 근장
CREATE TABLE worksites (
  id                SERIAL PRIMARY KEY,
  university_id     INTEGER NOT NULL REFERENCES universities(id) ON DELETE RESTRICT,
  type              worksite_type_e NOT NULL,
  location_type     location_type_e NOT NULL,
  organization_name VARCHAR(200),
  workplace_name    VARCHAR(200),
  region            VARCHAR(50),
  address           TEXT,
  view_count        INTEGER DEFAULT 0 CHECK (view_count >= 0),
  created_at        TIMESTAMP DEFAULT NOW(),
  updated_at        TIMESTAMP DEFAULT NOW(),
  deleted_at        TIMESTAMP
);

-- 모집 공고
CREATE TABLE postings (
  id                      SERIAL PRIMARY KEY,
  worksite_id             INTEGER NOT NULL REFERENCES worksites(id) ON DELETE CASCADE,
  source_url              TEXT,
  job_category            VARCHAR(100),
  preferred_track         VARCHAR(50),
  preferred_college       VARCHAR(100),
  preferred_dept          VARCHAR(200),
  recruit_count           VARCHAR(20),
  min_grade               INTEGER,
  eligible_degree         SMALLINT DEFAULT 3,
  eligible_status         SMALLINT DEFAULT 3,
  job_description         TEXT,
  preference_notes        TEXT,
  extra_notes             TEXT,
  hourly_wage             INTEGER,
  work_period_text        TEXT,
  work_duration_type      duration_type_e DEFAULT 'unknown',
  work_time_text          TEXT,
  recruitment_period_text TEXT,
  contact_name            VARCHAR(50),
  contact_phone           VARCHAR(50),
  contact_email           VARCHAR(100),
  raw_text                TEXT,
  is_active               BOOLEAN DEFAULT TRUE,
  created_at              TIMESTAMP DEFAULT NOW(),
  updated_at              TIMESTAMP DEFAULT NOW(),
  deleted_at              TIMESTAMP
);

-- 광고 시청
CREATE TABLE ad_views (
  id         SERIAL PRIMARY KEY,
  user_id    INTEGER REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMP DEFAULT NOW()
);

-- 리뷰
CREATE TABLE reviews (
  id              SERIAL PRIMARY KEY,
  user_id         INTEGER REFERENCES users(id) ON DELETE SET NULL,
  worksite_id     INTEGER NOT NULL REFERENCES worksites(id) ON DELETE RESTRICT,
  work_year       INTEGER NOT NULL,
  work_semester   VARCHAR(10) NOT NULL,
  score_work      NUMERIC(2,1) CHECK (score_work BETWEEN 0.5 AND 5.0),
  score_growth    NUMERIC(2,1) CHECK (score_growth BETWEEN 0.5 AND 5.0),
  score_vibe      NUMERIC(2,1) CHECK (score_vibe BETWEEN 0.5 AND 5.0),
  score_flex      NUMERIC(2,1) CHECK (score_flex BETWEEN 0.5 AND 5.0),
  score_recommend NUMERIC(2,1) CHECK (score_recommend BETWEEN 0.5 AND 5.0),
  work_content    TEXT CHECK (char_length(work_content) BETWEEN 30 AND 1000),
  opinion         TEXT CHECK (char_length(opinion) BETWEEN 50 AND 2000),
  helpful_count   INTEGER DEFAULT 0,
  created_at      TIMESTAMP DEFAULT NOW(),
  updated_at      TIMESTAMP DEFAULT NOW(),
  deleted_at      TIMESTAMP,
  UNIQUE (user_id, work_year, work_semester)
);

-- 도움됐어요
CREATE TABLE review_helpful (
  user_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  review_id  INTEGER NOT NULL REFERENCES reviews(id) ON DELETE CASCADE,
  created_at TIMESTAMP DEFAULT NOW(),
  PRIMARY KEY (user_id, review_id)
);

-- 포인트 내역
CREATE TABLE points (
  id         SERIAL PRIMARY KEY,
  user_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  amount     INTEGER NOT NULL,
  reason     VARCHAR(50) NOT NULL,
  review_id  INTEGER REFERENCES reviews(id) ON DELETE SET NULL,
  ad_view_id INTEGER REFERENCES ad_views(id) ON DELETE SET NULL,
  created_at TIMESTAMP DEFAULT NOW()
);

-- 신고
CREATE TABLE reports (
  id               SERIAL PRIMARY KEY,
  reporter_id      INTEGER REFERENCES users(id) ON DELETE SET NULL,
  reported_user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
  review_id        INTEGER REFERENCES reviews(id) ON DELETE SET NULL,
  reason           VARCHAR(100),
  status           report_status_e DEFAULT 'pending',
  created_at       TIMESTAMP DEFAULT NOW()
);

-- 공지사항
CREATE TABLE notices (
  id         SERIAL PRIMARY KEY,
  title      VARCHAR(200) NOT NULL,
  content    TEXT,
  is_pinned  BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);
