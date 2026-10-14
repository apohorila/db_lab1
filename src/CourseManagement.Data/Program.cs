using CourseManagement.Data;

var cs =
    Environment.GetEnvironmentVariable("LMS_CONN")
    ?? "Host=localhost;Database=course_management;Username=postgres;Password=labsistatp";

int courseId;

await using (var uow = await UnitOfWork.BeginAsync(cs, actorId: 2))
{
    courseId = await uow.Courses.CreateAsync(
        new NewCourse("C# для початківців", "Основи мови", 1, 1, 0m, 30),
        instructorId: 2
    );
    await uow.Courses.UpdateAsync(
        courseId,
        new NewCourse("C# для початківців", "Основи мови та .NET", 1, 1, 0m, 30),
        isPublished: true
    );

    var moduleId = await uow.Lessons.AddModuleAsync(courseId, "Вступ", 1);
    await uow.Lessons.AddLessonAsync(moduleId, "Змінні й типи", 20, 1);
    await uow.Lessons.AddLessonAsync(moduleId, "Умови та цикли", 25, 2);
    await uow.CommitAsync();
}

await using (var uow = await UnitOfWork.BeginAsync(cs, actorId: 3))
{
    var enrollmentId = await uow.Enrollments.EnrollAsync(courseId, studentId: 3);
    foreach (var l in await uow.Lessons.GetByCourseAsync(courseId))
        await uow.Enrollments.CompleteLessonAsync(enrollmentId, l.LessonId);
    await uow.Enrollments.AddReviewAsync(courseId, 3, 5, "Дуже зрозуміло");

    foreach (var p in await uow.Enrollments.GetByStudentAsync(3))
        Console.WriteLine(
            $"{p.CourseTitle}: {p.Status}, {p.ProgressPercent}%, сертифікат: {p.CertificateCode}"
        );
    await uow.CommitAsync();
}

await using (var uow = await UnitOfWork.BeginAsync(cs, actorId: 1))
{
    await uow.Courses.SoftDeleteAsync(courseId);
    Console.WriteLine(
        $"Після видалення знайдено: {await uow.Courses.GetByIdAsync(courseId) is not null}"
    );
    await uow.Courses.RestoreAsync(courseId);
    Console.WriteLine($"Після відновлення: {(await uow.Courses.GetByIdAsync(courseId))?.Title}");
    await uow.CommitAsync();
}
