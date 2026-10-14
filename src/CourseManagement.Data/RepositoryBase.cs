using Npgsql;

namespace CourseManagement.Data;


public abstract class RepositoryBase
{
    private readonly NpgsqlConnection _conn;
    private readonly NpgsqlTransaction _tx;
    protected readonly int ActorId;

    protected RepositoryBase(NpgsqlConnection conn, NpgsqlTransaction tx, int actorId)
        => (_conn, _tx, ActorId) = (conn, tx, actorId);

  
    protected NpgsqlCommand Cmd(string sql, params (string Name, object? Value)[] args)
    {
        var cmd = new NpgsqlCommand(sql, _conn, _tx);
        foreach (var (name, value) in args)
            cmd.Parameters.AddWithValue(name, value ?? DBNull.Value);
        return cmd;
    }

    protected static T? Get<T>(NpgsqlDataReader r, string col)
    {
        var o = r[col];
        return o is DBNull ? default : (T)o;
    }
}
