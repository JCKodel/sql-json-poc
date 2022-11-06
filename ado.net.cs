await using var cmd = new SqlCommand("Stored Procedure Name", con);

cmd.CommandType = CommandType.StoredProcedure;
cmd.Parameters.AddWithValue("userId", userId == null ? DBNull.Value : userId);
cmd.Parameters.AddWithValue("json", JSONString);

var rd = await cmd.ExecuteReaderAsync();
var sp = new StringBuilder();

if (rd.VisibleFieldCount > 0) {
  if (rd.VisibleFieldCount > 1 || rd.GetName(0).StartsWith("JSON") == false) {
    throw new DataException($"Stored procedures should return a JSON (did you forgot FOR JSON AUTO in {spName}?)");
  }

  while (await rd.ReadAsync()) {
    sb.Append(rd.GetString(0));
  }

  outputPayload.JSONPayload = sb.ToString();
}

await rd.CloseAsync();

return sb.ToString();