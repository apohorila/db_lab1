using Npgsql;

namespace CourseManagement.Data;

public interface ICourseRepository
{
    Task<int> CreateAsync(NewCourse c, int instructorId);
    Task UpdateAsync(int id, NewCourse c, bool isPublished);
    Task SoftDeleteAsync(int id);
    Task RestoreAsync(int id);
    Task<Course?> GetByIdAsync(int id);
    Task<List<Course>> GetAllAsync(int? categoryId = null, string? search = null);
}

public interface ILessonRepository
{
    Task<int> AddModuleAsync(int courseId, string title, int order);
    Task<int> AddLessonAsync(int moduleId, string title, int durationMin, int order);
    Task<List<LessonInfo>> GetByCourseAsync(int courseId);
}

public interface IEnrollmentRepository
{
    Task<int> EnrollAsync(int courseId, int studentId);
    Task CompleteLessonAsync(int enrollmentId, int lessonId);
    Task AddReviewAsync(int courseId, int studentId, short rating, string? comment);
    Task<List<StudentProgress>> GetByStudentAsync(int studentId);
}

public sealed class CourseRepository : RepositoryBase, ICourseRepository
{
    public CourseRepository(NpgsqlConnection c, NpgsqlTransaction t, int actor) : base(c, t, actor) { }

    public async Task<int> CreateAsync(NewCourse c, int instructorId)
    {
        await using (var create = Cmd(
            "SELECT fn_course_create(@title, @descr, @cat, @level, @price, @max, @actor)",
            ("title", c.Title), ("descr", c.Description), ("cat", c.CategoryId),
            ("level", c.Level), ("price", c.Price), ("max", c.MaxStudents), ("actor", ActorId)))
        {
            var courseId = (int)(await create.ExecuteScalarAsync())!;

            await using var assign = Cmd(
                "CALL sp_course_assign_instructor(@course, @instr, @owner, @actor)",
                ("course", courseId), ("instr", instructorId), ("owner", true), ("actor", ActorId));
            await assign.ExecuteNonQueryAsync();
            return courseId;
        }
    }

    public async Task UpdateAsync(int id, NewCourse c, bool isPublished)
    {
        await using var cmd = Cmd(
            "CALL sp_course_update(@id, @title, @descr, @cat, @level, @price, @pub, @max, @actor)",
            ("id", id), ("title", c.Title), ("descr", c.Description), ("cat", c.CategoryId),
            ("level", c.Level), ("price", c.Price), ("pub", isPublished), ("max", c.MaxStudents),
            ("actor", ActorId));
        await cmd.ExecuteNonQueryAsync();
    }

    public async Task SoftDeleteAsync(int id)
    {
        await using var cmd = Cmd("CALL sp_course_soft_delete(@id, @actor)", ("id", id), ("actor", ActorId));
        await cmd.ExecuteNonQueryAsync();
    }

    public async Task RestoreAsync(int id)
    {
        await using var cmd = Cmd("CALL sp_course_restore(@id, @actor)", ("id", id), ("actor", ActorId));
        await cmd.ExecuteNonQueryAsync();
    }

    public async Task<Course?> GetByIdAsync(int id)
    {
        await using var cmd = Cmd("SELECT * FROM fn_course_get_by_id(@id)", ("id", id));
        await using var r = await cmd.ExecuteReaderAsync();
        return await r.ReadAsync() ? Map(r) : null;
    }

    public async Task<List<Course>> GetAllAsync(int? categoryId = null, string? search = null)
    {
        await using var cmd = Cmd("SELECT * FROM fn_course_get_all(@cat, @search)",
                                  ("cat", categoryId), ("search", search));
        await using var r = await cmd.ExecuteReaderAsync();
        var list = new List<Course>();
        while (await r.ReadAsync()) list.Add(Map(r));
        return list;
    }

    private static Course Map(NpgsqlDataReader r) => new(
        Get<int>(r, "course_id"), Get<string>(r, "title")!, Get<string>(r, "description"),
        Get<int>(r, "category_id"), Get<string>(r, "category_name")!, Get<short>(r, "level"),
        Get<decimal>(r, "price"), Get<bool>(r, "is_published"), Get<int?>(r, "max_students"),
        Get<string>(r, "instructor_name"), Get<decimal?>(r, "avg_rating"), Get<int>(r, "students_count"));
}

public sealed class LessonRepository : RepositoryBase, ILessonRepository
{
    public LessonRepository(NpgsqlConnection c, NpgsqlTransaction t, int actor) : base(c, t, actor) { }

    public async Task<int> AddModuleAsync(int courseId, string title, int order)
    {
        await using var cmd = Cmd("SELECT fn_module_create(@course, @title, @order, @actor)",
            ("course", courseId), ("title", title), ("order", order), ("actor", ActorId));
        return (int)(await cmd.ExecuteScalarAsync())!;
    }

    public async Task<int> AddLessonAsync(int moduleId, string title, int durationMin, int order)
    {
        await using var cmd = Cmd("SELECT fn_lesson_create(@module, @title, @dur, @order, @actor)",
            ("module", moduleId), ("title", title), ("dur", durationMin), ("order", order), ("actor", ActorId));
        return (int)(await cmd.ExecuteScalarAsync())!;
    }

    public async Task<List<LessonInfo>> GetByCourseAsync(int courseId)
    {
        await using var cmd = Cmd("SELECT * FROM fn_lesson_get_by_course(@course)", ("course", courseId));
        await using var r = await cmd.ExecuteReaderAsync();
        var list = new List<LessonInfo>();
        while (await r.ReadAsync())
            list.Add(new(Get<int>(r, "course_id"), Get<int>(r, "module_id"), Get<string>(r, "module_title")!,
                         Get<int>(r, "lesson_id"), Get<string>(r, "lesson_title")!, Get<int>(r, "duration_min")));
        return list;
    }
}

public sealed class EnrollmentRepository : RepositoryBase, IEnrollmentRepository
{
    public EnrollmentRepository(NpgsqlConnection c, NpgsqlTransaction t, int actor) : base(c, t, actor) { }

    public async Task<int> EnrollAsync(int courseId, int studentId)
    {
        await using var cmd = Cmd("SELECT fn_enrollment_enroll(@course, @student, @actor)",
            ("course", courseId), ("student", studentId), ("actor", ActorId));
        return (int)(await cmd.ExecuteScalarAsync())!;
    }

    public async Task CompleteLessonAsync(int enrollmentId, int lessonId)
    {
        await using var cmd = Cmd("CALL sp_lesson_complete(@enr, @lesson, @actor)",
            ("enr", enrollmentId), ("lesson", lessonId), ("actor", ActorId));
        await cmd.ExecuteNonQueryAsync();
    }

    public async Task AddReviewAsync(int courseId, int studentId, short rating, string? comment)
    {
        await using var cmd = Cmd("CALL sp_review_add(@course, @student, @rating, @comment, @actor)",
            ("course", courseId), ("student", studentId), ("rating", rating),
            ("comment", comment), ("actor", ActorId));
        await cmd.ExecuteNonQueryAsync();
    }

    public async Task<List<StudentProgress>> GetByStudentAsync(int studentId)
    {
        await using var cmd = Cmd("SELECT * FROM fn_enrollment_get_by_student(@student)", ("student", studentId));
        await using var r = await cmd.ExecuteReaderAsync();
        var list = new List<StudentProgress>();
        while (await r.ReadAsync())
            list.Add(new(Get<int>(r, "enrollment_id"), Get<int>(r, "course_id"), Get<string>(r, "course_title")!,
                         Get<string>(r, "status")!, Get<decimal>(r, "progress_percent"),
                         Get<Guid?>(r, "certificate_code")));
        return list;
    }
}
