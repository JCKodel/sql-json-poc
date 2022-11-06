var cmd = new Command(connectionString);

cmd.Sql("EXEC [NomeStoredProcedure], @userId, @json")
   .Param("userId", userId)
   .Param("json", jsonString)
   .Stream(Response.Body);