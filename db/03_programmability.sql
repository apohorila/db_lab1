
CREATE OR REPLACE FUNCTION fn_current_user_id() RETURNS INT
LANGUAGE sql STABLE AS
$$ SELECT NULLIF(current_setting('app.user_id', true), '')::INT $$;

CREATE OR REPLACE FUNCTION fn_enrollment_progress(p_enrollment_id INT) RETURNS NUMERIC(5,2)
LANGUAGE sql STABLE AS
$$
    WITH course_lessons AS (
        SELECT l.lesson_id
        FROM enrollments e
        JOIN modules m ON m.course_id = e.course_id AND NOT m.is_deleted
        JOIN lessons l ON l.module_id = m.module_id AND NOT l.is_deleted
        WHERE e.enrollment_id = p_enrollment_id
    )
    SELECT CASE WHEN COUNT(*) = 0 THEN 0
                ELSE ROUND(100.0 * COUNT(lp.lesson_id) / COUNT(*), 2) END
    FROM course_lessons cl
    LEFT JOIN lesson_progress lp
           ON lp.lesson_id = cl.lesson_id AND lp.enrollment_id = p_enrollment_id
$$;

CREATE OR REPLACE FUNCTION fn_course_avg_rating(p_course_id INT) RETURNS NUMERIC(3,2)
LANGUAGE sql STABLE AS
$$ SELECT ROUND(AVG(rating), 2)::NUMERIC(3,2)
   FROM reviews WHERE course_id = p_course_id AND NOT is_deleted $$;

CREATE OR REPLACE FUNCTION fn_student_courses(p_student_id INT)
RETURNS TABLE (enrollment_id INT, course_id INT, title VARCHAR, status VARCHAR,
               progress_percent NUMERIC, enrolled_at TIMESTAMPTZ)
LANGUAGE sql STABLE AS
$$
    SELECT e.enrollment_id, c.course_id, c.title, e.status, e.progress_percent, e.enrolled_at
    FROM enrollments e
    JOIN courses c ON c.course_id = e.course_id AND NOT c.is_deleted
    WHERE e.student_id = p_student_id
$$;


CREATE OR REPLACE VIEW v_active_courses AS
SELECT c.course_id, c.title, c.description, c.level, c.price, c.is_published, c.max_students,
       c.category_id, cat.name AS category_name,
       u.user_id AS instructor_id, u.first_name || ' ' || u.last_name AS instructor_name,
       fn_course_avg_rating(c.course_id) AS avg_rating,
       (SELECT COUNT(*) FROM enrollments e
         WHERE e.course_id = c.course_id AND e.status <> 'Cancelled')::INT AS students_count,
       c.created_at, c.updated_at, c.updated_by
FROM courses c
JOIN categories cat ON cat.category_id = c.category_id
LEFT JOIN course_instructors ci ON ci.course_id = c.course_id AND ci.is_owner
LEFT JOIN users u ON u.user_id = ci.instructor_id
WHERE NOT c.is_deleted;

CREATE OR REPLACE VIEW v_deleted_courses AS
SELECT c.course_id, c.title, c.deleted_at, c.updated_by, u.email AS deleted_by_email
FROM courses c
LEFT JOIN users u ON u.user_id = c.updated_by
WHERE c.is_deleted;

CREATE OR REPLACE VIEW v_course_structure AS
SELECT m.course_id, m.module_id, m.title AS module_title, m.order_no AS module_order,
       l.lesson_id, l.title AS lesson_title, l.order_no AS lesson_order, l.duration_min
FROM modules m
JOIN lessons l ON l.module_id = m.module_id AND NOT l.is_deleted
WHERE NOT m.is_deleted;

CREATE OR REPLACE VIEW v_student_progress AS
SELECT e.enrollment_id, e.student_id, s.first_name || ' ' || s.last_name AS student_name,
       e.course_id, c.title AS course_title, e.status, e.progress_percent,
       e.enrolled_at, e.completed_at, cert.code AS certificate_code
FROM enrollments e
JOIN users s ON s.user_id = e.student_id
JOIN courses c ON c.course_id = e.course_id AND NOT c.is_deleted
LEFT JOIN certificates cert ON cert.enrollment_id = e.enrollment_id;

CREATE OR REPLACE VIEW v_pending_submissions AS
SELECT sb.submission_id, sb.submitted_at, a.assignment_id, a.title AS assignment_title, a.max_score,
       sb.student_id, s.first_name || ' ' || s.last_name AS student_name, m.course_id
FROM submissions sb
JOIN assignments a ON a.assignment_id = sb.assignment_id AND NOT a.is_deleted
JOIN lessons l ON l.lesson_id = a.lesson_id
JOIN modules m ON m.module_id = l.module_id
JOIN users s ON s.user_id = sb.student_id
WHERE sb.score IS NULL;

CREATE OR REPLACE VIEW v_instructor_stats AS
SELECT u.user_id AS instructor_id, u.first_name || ' ' || u.last_name AS instructor_name,
       COUNT(DISTINCT c.course_id)::INT AS courses_count,
       COUNT(DISTINCT e.student_id)::INT AS students_count
FROM users u
JOIN course_instructors ci ON ci.instructor_id = u.user_id
JOIN courses c ON c.course_id = ci.course_id AND NOT c.is_deleted
LEFT JOIN enrollments e ON e.course_id = c.course_id AND e.status <> 'Cancelled'
WHERE NOT u.is_deleted
GROUP BY u.user_id, u.first_name, u.last_name;


CREATE OR REPLACE FUNCTION tf_set_updated() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at := now();
    NEW.updated_by := COALESCE(fn_current_user_id(), OLD.updated_by);
    RETURN NEW;
END $$;

DO $$
DECLARE t TEXT;
BEGIN
    FOREACH t IN ARRAY ARRAY['users','courses','modules','lessons','assignments','quizzes','reviews'] LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS trg_%s_set_updated ON %I', t, t);
        EXECUTE format('CREATE TRIGGER trg_%s_set_updated BEFORE UPDATE ON %I
                        FOR EACH ROW EXECUTE FUNCTION tf_set_updated()', t, t);
    END LOOP;
END $$;


CREATE OR REPLACE FUNCTION tf_courses_soft_delete() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE courses SET is_deleted = TRUE, deleted_at = now()
     WHERE course_id = OLD.course_id AND NOT is_deleted;
    UPDATE modules SET is_deleted = TRUE, deleted_at = now()
     WHERE course_id = OLD.course_id AND NOT is_deleted;
    UPDATE lessons SET is_deleted = TRUE, deleted_at = now()
     WHERE module_id IN (SELECT module_id FROM modules WHERE course_id = OLD.course_id)
       AND NOT is_deleted;
    INSERT INTO audit_log (table_name, record_id, action, changed_by, details)
    VALUES ('courses', OLD.course_id, 'SOFT_DELETE', fn_current_user_id(), LEFT(OLD.title, 1000));
    RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS trg_courses_soft_delete ON courses;
CREATE TRIGGER trg_courses_soft_delete BEFORE DELETE ON courses
    FOR EACH ROW EXECUTE FUNCTION tf_courses_soft_delete();


CREATE OR REPLACE FUNCTION tf_lesson_progress_recalc() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE v_id INT;
BEGIN
    IF TG_OP = 'DELETE' THEN v_id := OLD.enrollment_id; ELSE v_id := NEW.enrollment_id; END IF;

    UPDATE enrollments SET progress_percent = fn_enrollment_progress(v_id)
     WHERE enrollment_id = v_id;

    UPDATE enrollments SET status = 'Completed', completed_at = now()
     WHERE enrollment_id = v_id AND progress_percent >= 100 AND status = 'Active';

    INSERT INTO certificates (enrollment_id)
    SELECT enrollment_id FROM enrollments WHERE enrollment_id = v_id AND status = 'Completed'
    ON CONFLICT (enrollment_id) DO NOTHING;

    RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS trg_lesson_progress_recalc ON lesson_progress;
CREATE TRIGGER trg_lesson_progress_recalc AFTER INSERT OR DELETE ON lesson_progress
    FOR EACH ROW EXECUTE FUNCTION tf_lesson_progress_recalc();


CREATE OR REPLACE FUNCTION fn_course_create(
    p_title TEXT, p_description TEXT, p_category_id INT, p_level SMALLINT,
    p_price NUMERIC, p_max_students INT, p_actor_id INT) RETURNS INT
LANGUAGE plpgsql AS $$
DECLARE v_id INT;
BEGIN
    PERFORM set_config('app.user_id', p_actor_id::TEXT, true);
    INSERT INTO courses (category_id, title, description, level, price, max_students, created_by)
    VALUES (p_category_id, p_title, p_description, p_level, p_price, p_max_students, p_actor_id)
    RETURNING course_id INTO v_id;
    RETURN v_id;
END $$;

CREATE OR REPLACE PROCEDURE sp_course_assign_instructor(
    p_course_id INT, p_instructor_id INT, p_is_owner BOOLEAN, p_actor_id INT)
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM set_config('app.user_id', p_actor_id::TEXT, true);
    IF NOT EXISTS (SELECT 1 FROM users u JOIN roles r ON r.role_id = u.role_id
                   WHERE u.user_id = p_instructor_id AND NOT u.is_deleted AND r.name = 'Instructor') THEN
        RAISE EXCEPTION 'Користувач не є активним викладачем.';
    END IF;
    INSERT INTO course_instructors (course_id, instructor_id, is_owner)
    VALUES (p_course_id, p_instructor_id, p_is_owner)
    ON CONFLICT (course_id, instructor_id) DO UPDATE SET is_owner = EXCLUDED.is_owner;
END $$;

CREATE OR REPLACE PROCEDURE sp_course_update(
    p_course_id INT, p_title TEXT, p_description TEXT, p_category_id INT, p_level SMALLINT,
    p_price NUMERIC, p_is_published BOOLEAN, p_max_students INT, p_actor_id INT)
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM set_config('app.user_id', p_actor_id::TEXT, true);
    UPDATE courses
       SET title = p_title, description = p_description, category_id = p_category_id,
           level = p_level, price = p_price, is_published = p_is_published,
           max_students = p_max_students
     WHERE course_id = p_course_id AND NOT is_deleted;
    IF NOT FOUND THEN RAISE EXCEPTION 'Курс не знайдено.'; END IF;
END $$;

CREATE OR REPLACE PROCEDURE sp_course_soft_delete(p_course_id INT, p_actor_id INT)
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM set_config('app.user_id', p_actor_id::TEXT, true);
    DELETE FROM courses WHERE course_id = p_course_id;   -- перехоплює BEFORE DELETE тригер
END $$;

CREATE OR REPLACE PROCEDURE sp_course_restore(p_course_id INT, p_actor_id INT)
LANGUAGE plpgsql AS $$
DECLARE v_deleted_at TIMESTAMPTZ;
BEGIN
    PERFORM set_config('app.user_id', p_actor_id::TEXT, true);
    SELECT deleted_at INTO v_deleted_at FROM courses WHERE course_id = p_course_id AND is_deleted;
    IF v_deleted_at IS NULL THEN RAISE EXCEPTION 'Видаленого курсу не знайдено.'; END IF;

    UPDATE courses SET is_deleted = FALSE, deleted_at = NULL WHERE course_id = p_course_id;
    UPDATE modules SET is_deleted = FALSE, deleted_at = NULL
     WHERE course_id = p_course_id AND deleted_at = v_deleted_at;
    UPDATE lessons SET is_deleted = FALSE, deleted_at = NULL
     WHERE module_id IN (SELECT module_id FROM modules WHERE course_id = p_course_id)
       AND deleted_at = v_deleted_at;
END $$;

CREATE OR REPLACE FUNCTION fn_course_get_by_id(p_course_id INT) RETURNS SETOF v_active_courses
LANGUAGE sql STABLE AS
$$ SELECT * FROM v_active_courses WHERE course_id = p_course_id $$;

CREATE OR REPLACE FUNCTION fn_course_get_all(p_category_id INT DEFAULT NULL, p_search TEXT DEFAULT NULL)
RETURNS SETOF v_active_courses
LANGUAGE sql STABLE AS
$$ SELECT * FROM v_active_courses
   WHERE (p_category_id IS NULL OR category_id = p_category_id)
     AND (p_search IS NULL OR title ILIKE '%' || p_search || '%')
   ORDER BY title $$;

CREATE OR REPLACE FUNCTION fn_course_get_deleted() RETURNS SETOF v_deleted_courses
LANGUAGE sql STABLE AS
$$ SELECT * FROM v_deleted_courses ORDER BY deleted_at DESC $$;


CREATE OR REPLACE FUNCTION fn_module_create(p_course_id INT, p_title TEXT, p_order_no INT, p_actor_id INT)
RETURNS INT
LANGUAGE plpgsql AS $$
DECLARE v_id INT;
BEGIN
    PERFORM set_config('app.user_id', p_actor_id::TEXT, true);
    INSERT INTO modules (course_id, title, order_no) VALUES (p_course_id, p_title, p_order_no)
    RETURNING module_id INTO v_id;
    RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION fn_lesson_create(
    p_module_id INT, p_title TEXT, p_duration_min INT, p_order_no INT, p_actor_id INT) RETURNS INT
LANGUAGE plpgsql AS $$
DECLARE v_id INT;
BEGIN
    PERFORM set_config('app.user_id', p_actor_id::TEXT, true);
    INSERT INTO lessons (module_id, title, duration_min, order_no)
    VALUES (p_module_id, p_title, p_duration_min, p_order_no)
    RETURNING lesson_id INTO v_id;
    RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION fn_lesson_get_by_course(p_course_id INT) RETURNS SETOF v_course_structure
LANGUAGE sql STABLE AS
$$ SELECT * FROM v_course_structure WHERE course_id = p_course_id
   ORDER BY module_order, lesson_order $$;


CREATE OR REPLACE FUNCTION fn_enrollment_enroll(p_course_id INT, p_student_id INT, p_actor_id INT)
RETURNS INT
LANGUAGE plpgsql AS $$
DECLARE v_max INT; v_id INT; v_status VARCHAR;
BEGIN
    PERFORM set_config('app.user_id', p_actor_id::TEXT, true);

    SELECT max_students INTO v_max FROM courses
     WHERE course_id = p_course_id AND NOT is_deleted AND is_published;
    IF NOT FOUND THEN RAISE EXCEPTION 'Курс недоступний для запису.'; END IF;

    IF v_max IS NOT NULL AND
       (SELECT COUNT(*) FROM enrollments WHERE course_id = p_course_id AND status <> 'Cancelled') >= v_max THEN
        RAISE EXCEPTION 'Досягнуто ліміт студентів.';
    END IF;

    SELECT enrollment_id, status INTO v_id, v_status
      FROM enrollments WHERE course_id = p_course_id AND student_id = p_student_id;

    IF v_id IS NULL THEN
        INSERT INTO enrollments (course_id, student_id) VALUES (p_course_id, p_student_id)
        RETURNING enrollment_id INTO v_id;
    ELSIF v_status = 'Cancelled' THEN
        UPDATE enrollments SET status = 'Active', enrolled_at = now() WHERE enrollment_id = v_id;
    ELSE
        RAISE EXCEPTION 'Студент уже записаний на курс.';
    END IF;
    RETURN v_id;
END $$;

CREATE OR REPLACE PROCEDURE sp_lesson_complete(p_enrollment_id INT, p_lesson_id INT, p_actor_id INT)
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM set_config('app.user_id', p_actor_id::TEXT, true);
    IF NOT EXISTS (SELECT 1 FROM enrollments e
                   JOIN modules m ON m.course_id = e.course_id AND NOT m.is_deleted
                   JOIN lessons l ON l.module_id = m.module_id AND NOT l.is_deleted
                   WHERE e.enrollment_id = p_enrollment_id AND e.status = 'Active'
                     AND l.lesson_id = p_lesson_id) THEN
        RAISE EXCEPTION 'Урок не належить курсу або запис неактивний.';
    END IF;
    INSERT INTO lesson_progress (enrollment_id, lesson_id) VALUES (p_enrollment_id, p_lesson_id)
    ON CONFLICT DO NOTHING;                -- тригер перерахує прогрес
END $$;

CREATE OR REPLACE FUNCTION fn_enrollment_get_by_student(p_student_id INT) RETURNS SETOF v_student_progress
LANGUAGE sql STABLE AS
$$ SELECT * FROM v_student_progress WHERE student_id = p_student_id ORDER BY enrolled_at DESC $$;

CREATE OR REPLACE PROCEDURE sp_review_add(
    p_course_id INT, p_student_id INT, p_rating SMALLINT, p_comment TEXT, p_actor_id INT)
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM set_config('app.user_id', p_actor_id::TEXT, true);
    IF NOT EXISTS (SELECT 1 FROM enrollments
                   WHERE course_id = p_course_id AND student_id = p_student_id AND status <> 'Cancelled') THEN
        RAISE EXCEPTION 'Відгук можуть залишити лише студенти курсу.';
    END IF;

    UPDATE reviews SET rating = p_rating, comment = p_comment
     WHERE course_id = p_course_id AND student_id = p_student_id AND NOT is_deleted;
    IF NOT FOUND THEN
        INSERT INTO reviews (course_id, student_id, rating, comment)
        VALUES (p_course_id, p_student_id, p_rating, p_comment);
    END IF;
END $$;
