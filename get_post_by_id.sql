CREATE PROCEDURE [dbo].[GetPostById](@userId CHAR(28), @json NVARCHAR(MAX)) AS BEGIN
 -- Como só temos um valor a ser lido, podemos simplificar:  
 DECLARE @id INT = JSON_VALUE(@json, '$.id');

 -- JOIN não funciona bem aqui, mas podemos fazer sub-queries que retornam mais de
 -- um resultado, coisa impossível de se fazer com queries comuns (ou seja, você pode
 -- retornar um documento completo com N níveis, mesmo que a sub-query retorne um 
 -- conjunto de várias linhas)

 -- Infelizmente, transformar uma tabela em um array de primitivos não é algo
 -- bonito de se ver =( (temos que utilizar CONCAT e STRING_AGG)
 SELECT TOP 1
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
 WHERE id = @id AND ownerId = @userId
 FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;
 -- WITHOUT_ARRAY_WRAPPER remove o [] do resultado, já que estamos
 -- falando apenas de 0 ou 1 registro de retorno

 -- O JSON_QUERY garante que tais sub-queries sejam interpretadas como JSON
 -- Não é absolutamente requerido, especialmente em queries simples, mas é
 -- bom sempre escrevê-lo.
 -- Esta função, por exemplo, faz com que a string gerada pelo CONCAT na lista
 -- de tags seja considerada como JSON (sem o JSON_QUERY, a propriedade tag do 
 -- JSON resultante seria uma string "[\"#tag1\",\"#tag2\"]")
END