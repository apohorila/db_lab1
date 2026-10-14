using Npgsql;

namespace CourseManagement.Data;

public interface IUnitOfWork : IAsyncDisposable
{
    ICourseRepository Courses { get; }
    ILessonRepository Lessons { get; }
    IEnrollmentRepository Enrollments { get; }
    Task CommitAsync();
    Task RollbackAsync();
}


public sealed class UnitOfWork : IUnitOfWork
{
    private readonly NpgsqlConnection _conn;
    private readonly NpgsqlTransaction _tx;
    private bool _finished;

    public ICourseRepository Courses { get; }
    public ILessonRepository Lessons { get; }
    public IEnrollmentRepository Enrollments { get; }

    private UnitOfWork(NpgsqlConnection conn, NpgsqlTransaction tx, int actorId)
    {
        (_conn, _tx) = (conn, tx);
        Courses = new CourseRepository(conn, tx, actorId);
        Lessons = new LessonRepository(conn, tx, actorId);
        Enrollments = new EnrollmentRepository(conn, tx, actorId);
    }

    public static async Task<UnitOfWork> BeginAsync(string connectionString, int actorId)
    {
        var conn = new NpgsqlConnection(connectionString);
        await conn.OpenAsync();
        var tx = await conn.BeginTransactionAsync();
        return new UnitOfWork(conn, tx, actorId);
    }

    public async Task CommitAsync()   { await _tx.CommitAsync();   _finished = true; }
    public async Task RollbackAsync() { await _tx.RollbackAsync(); _finished = true; }

    public async ValueTask DisposeAsync()
    {
        if (!_finished) { try { await _tx.RollbackAsync(); } catch { } }
        await _tx.DisposeAsync();
        await _conn.DisposeAsync();
    }
}
