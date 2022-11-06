CREATE PROCEDURE [dbo].[ListAllPosts](@userId CHAR(28), @json NVARCHAR(MAX)) AS BEGIN
 SELECT
   p.id,
   p.createdAt,
   p.title,
   p.message,
   JSON_QUERY((
     SELECT CONCAT('[', STRING_AGG(CONCAT('"', tag, '"'), ','), ']')
     FROM Posts_Tags AS t
     WHERE t.postId = p.id
   )) AS tags,
   JSON_QUERY((
     SELECT TOP 1 u.id, u.name
     FROM Users AS u
     WHERE u.id = p.ownerId
     FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
   )) AS owner
 FROM Posts AS p
 ORDER BY p.createdAt DESC
 FOR JSON PATH;
END