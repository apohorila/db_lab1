
CREATE UNIQUE INDEX ux_users_email_active ON users (lower(email)) WHERE NOT is_deleted;


CREATE UNIQUE INDEX ux_reviews_course_student_active ON reviews (course_id, student_id) WHERE NOT is_deleted;

CREATE INDEX ix_courses_category_active ON courses (category_id) INCLUDE (title, price, is_published) WHERE NOT is_deleted;

CREATE INDEX ix_lessons_module_order ON lessons (module_id, order_no) INCLUDE (title, duration_min) WHERE NOT is_deleted;
CREATE INDEX ix_modules_course_order ON modules (course_id, order_no) WHERE NOT is_deleted;
CREATE INDEX ix_enrollments_student  ON enrollments (student_id) INCLUDE (course_id, status, progress_percent);


CREATE INDEX ix_submissions_pending ON submissions (assignment_id) WHERE score IS NULL;


CREATE INDEX gin_courses_title_fts ON courses USING GIN (to_tsvector('simple', title));

CREATE INDEX brin_audit_log_changed_at ON audit_log USING BRIN (changed_at);
CREATE INDEX ix_audit_log_table_record ON audit_log (table_name, record_id);
