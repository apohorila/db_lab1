INSERT INTO roles (name) VALUES ('Admin'), ('Instructor'), ('Student');

INSERT INTO users (role_id, email, password_hash, first_name, last_name) VALUES
 (1, 'admin@lms.test',   'hash', 'Admin',  'Root'),
 (2, 'teacher@lms.test', 'hash', 'Olena',  'Kovalenko'),
 (3, 'student@lms.test', 'hash', 'Andrii', 'Shevchenko');

INSERT INTO categories (name) VALUES ('Programming'), ('Marketing'), ('Design');
