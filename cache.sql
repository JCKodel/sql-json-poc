SELECT DISTINCT
  s.name AS storedProcedureSchema,
  p.name AS storedProcedureName,
  JSON_QUERY((
    SELECT 
      ts.name AS tableSchema,
      t.name AS tableName,
      (
        SELECT CONCAT(
            COALESCE(
              CONVERT(VARCHAR(24), MAX(DATEADD(MINUTE, -DATEPART(TZoffset, SYSDATETIMEOFFSET()), ius.last_user_update)), 126),
              CONVERT(VARCHAR(24), SYSDATETIMEOFFSET(), 126)
            ), 
            'Z'
          )
        FROM sys.dm_db_index_usage_stats AS ius
        WHERE ius.object_id = t.object_id
      ) AS lastWrite
    FROM sys.tables AS t
    INNER JOIN sys.sql_expression_dependencies AS d ON d.referencing_id = p.object_id
    INNER JOIN sys.schemas AS ts ON ts.schema_id = t.schema_id
    WHERE t.object_id = d.referenced_id
    FOR JSON PATH
  )) AS tables
FROM sys.procedures AS p
INNER JOIN sys.schemas AS s ON s.schema_id = p.schema_id
ORDER BY s.name, p.name
FOR JSON PATH;