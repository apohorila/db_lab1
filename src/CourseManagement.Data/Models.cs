namespace CourseManagement.Data;

public record Course(
    int CourseId, string Title, string? Description, int CategoryId, string CategoryName,
    short Level, decimal Price, bool IsPublished, int? MaxStudents,
    string? InstructorName, decimal? AvgRating, int StudentsCount);

public record NewCourse(
    string Title, string? Description, int CategoryId, short Level, decimal Price, int? MaxStudents);

public record LessonInfo(
    int CourseId, int ModuleId, string ModuleTitle, int LessonId, string LessonTitle, int DurationMin);

public record StudentProgress(
    int EnrollmentId, int CourseId, string CourseTitle, string Status,
    decimal ProgressPercent, Guid? CertificateCode);
