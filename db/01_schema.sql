

CREATE TABLE roles (
    role_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name    VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE users (
    user_id       INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    role_id       INT NOT NULL REFERENCES roles(role_id),
    email         VARCHAR(256) NOT NULL,
    password_hash VARCHAR(256) NOT NULL,
    first_name    VARCHAR(100) NOT NULL,
    last_name     VARCHAR(100) NOT NULL,
    is_deleted    BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_at    TIMESTAMPTZ,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ,
    updated_by    INT REFERENCES users(user_id)
);

CREATE TABLE categories (
    category_id        INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    parent_category_id INT REFERENCES categories(category_id),
    name               VARCHAR(150) NOT NULL
);

CREATE TABLE courses (
    course_id    INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    category_id  INT NOT NULL REFERENCES categories(category_id),
    title        VARCHAR(200) NOT NULL,
    description  TEXT,
    level        SMALLINT NOT NULL CHECK (level BETWEEN 1 AND 3),
    price        NUMERIC(10,2) NOT NULL CHECK (price >= 0),
    is_published BOOLEAN NOT NULL DEFAULT FALSE,
    max_students INT CHECK (max_students > 0),
    is_deleted   BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_at   TIMESTAMPTZ,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by   INT REFERENCES users(user_id),
    updated_at   TIMESTAMPTZ,
    updated_by   INT REFERENCES users(user_id)
);


CREATE TABLE course_instructors (
    course_id     INT NOT NULL REFERENCES courses(course_id),
    instructor_id INT NOT NULL REFERENCES users(user_id),
    is_owner      BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (course_id, instructor_id)
);

CREATE TABLE modules (
    module_id  INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    course_id  INT NOT NULL REFERENCES courses(course_id),
    title      VARCHAR(200) NOT NULL,
    order_no   INT NOT NULL,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ,
    updated_by INT REFERENCES users(user_id)
);

CREATE TABLE lessons (
    lesson_id    INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    module_id    INT NOT NULL REFERENCES modules(module_id),
    title        VARCHAR(200) NOT NULL,
    content      TEXT,
    video_url    VARCHAR(500),
    duration_min INT NOT NULL DEFAULT 0,
    order_no     INT NOT NULL,
    is_deleted   BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_at   TIMESTAMPTZ,
    updated_at   TIMESTAMPTZ,
    updated_by   INT REFERENCES users(user_id)
);

CREATE TABLE lesson_materials (
    material_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    lesson_id   INT NOT NULL REFERENCES lessons(lesson_id),
    file_name   VARCHAR(255) NOT NULL,
    file_url    VARCHAR(500) NOT NULL,
    uploaded_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE assignments (
    assignment_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    lesson_id     INT NOT NULL REFERENCES lessons(lesson_id),
    title         VARCHAR(200) NOT NULL,
    description   TEXT,
    max_score     INT NOT NULL DEFAULT 100,
    due_date      TIMESTAMPTZ,
    is_deleted    BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_at    TIMESTAMPTZ,
    updated_at    TIMESTAMPTZ,
    updated_by    INT REFERENCES users(user_id)
);

CREATE TABLE enrollments (
    enrollment_id    INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    course_id        INT NOT NULL REFERENCES courses(course_id),
    student_id       INT NOT NULL REFERENCES users(user_id),
    enrolled_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    status           VARCHAR(20) NOT NULL DEFAULT 'Active'
                     CHECK (status IN ('Active', 'Completed', 'Cancelled')),
    progress_percent NUMERIC(5,2) NOT NULL DEFAULT 0,
    completed_at     TIMESTAMPTZ,
    UNIQUE (course_id, student_id)
);

CREATE TABLE lesson_progress (
    enrollment_id INT NOT NULL REFERENCES enrollments(enrollment_id),
    lesson_id     INT NOT NULL REFERENCES lessons(lesson_id),
    completed_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (enrollment_id, lesson_id)
);

CREATE TABLE submissions (
    submission_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    assignment_id INT NOT NULL REFERENCES assignments(assignment_id),
    student_id    INT NOT NULL REFERENCES users(user_id),
    answer_text   TEXT,
    submitted_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    score         INT,
    feedback      VARCHAR(1000),
    graded_by     INT REFERENCES users(user_id),
    graded_at     TIMESTAMPTZ,
    UNIQUE (assignment_id, student_id)
);

CREATE TABLE quizzes (
    quiz_id    INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    module_id  INT NOT NULL REFERENCES modules(module_id),
    title      VARCHAR(200) NOT NULL,
    pass_score INT NOT NULL DEFAULT 60,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ,
    updated_by INT REFERENCES users(user_id)
);

CREATE TABLE quiz_questions (
    question_id   INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    quiz_id       INT NOT NULL REFERENCES quizzes(quiz_id),
    question_text VARCHAR(1000) NOT NULL,
    points        INT NOT NULL DEFAULT 1
);

CREATE TABLE quiz_options (
    option_id   INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    question_id INT NOT NULL REFERENCES quiz_questions(question_id),
    option_text VARCHAR(500) NOT NULL,
    is_correct  BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE TABLE quiz_attempts (
    attempt_id  INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    quiz_id     INT NOT NULL REFERENCES quizzes(quiz_id),
    student_id  INT NOT NULL REFERENCES users(user_id),
    score       INT,
    started_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    finished_at TIMESTAMPTZ
);

CREATE TABLE reviews (
    review_id  INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    course_id  INT NOT NULL REFERENCES courses(course_id),
    student_id INT NOT NULL REFERENCES users(user_id),
    rating     SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
    comment    VARCHAR(1000),
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ,
    updated_by INT REFERENCES users(user_id)
);

CREATE TABLE certificates (
    certificate_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    enrollment_id  INT NOT NULL UNIQUE REFERENCES enrollments(enrollment_id),
    code           UUID NOT NULL DEFAULT gen_random_uuid() UNIQUE,
    issued_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE audit_log (
    audit_id   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    table_name VARCHAR(128) NOT NULL,
    record_id  INT NOT NULL,
    action     VARCHAR(20) NOT NULL,
    changed_by INT REFERENCES users(user_id),
    changed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    details    VARCHAR(1000)
);
