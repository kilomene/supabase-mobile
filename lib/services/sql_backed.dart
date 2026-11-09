/// SQL-ONLY features (report §3.8 / §4 #13-14): pgvector, Queues (pgmq),
/// Cron (pg_cron), RLS policies, extensions, storage policies.
/// There are NO dedicated REST endpoints — every one of these screens
/// runs live SQL through POST /v1/projects/{ref}/database/query.
/// The UI must label these screens "SQL-backed", never fake CRUD.
class SqlBacked {
  static const listCronJobs = 'SELECT jobid, jobname, schedule, command FROM cron.job ORDER BY jobname;';
  static const listExtensions = 'SELECT extname, extversion FROM pg_extension ORDER BY extname;';
  static const listQueues = "SELECT queue_name FROM pgmq.list_queues() ORDER BY 1;";
  static const enableVector = 'CREATE EXTENSION IF NOT EXISTS vector;';
  static const enablePgmq = 'CREATE EXTENSION IF NOT EXISTS pgmq;';
  static const enablePgCron = 'CREATE EXTENSION IF NOT EXISTS pg_cron;';
  static String scheduleCron(String name, String schedule, String sql) =>
      "SELECT cron.schedule('$name', '$schedule', \$\$$sql\$\$);";
  static String unscheduleCron(String name) => "SELECT cron.unschedule('$name');";
  static String vectorSearch(String table, String column, int limit) =>
      'SELECT * FROM $table ORDER BY $column <=> \$1 LIMIT $limit;';
}
