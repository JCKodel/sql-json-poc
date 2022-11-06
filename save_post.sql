CREATE PROCEDURE [dbo].[SavePost](@userId CHAR(28), @json NVARCHAR(MAX)) AS BEGIN
  DECLARE @id INT;
  DECLARE @title NVARCHAR(32);
  DECLARE @message NVARCHAR(MAX);

  SELECT @id = id, @title = TRIM(title), @message = TRIM(message)
  FROM OPENJSON(@json, '$') WITH (
    id INT '$.id',
    title NVARCHAR(32) '$.title',
    message VARCHAR(128) '$.message'
  );

  DECLARE @now DATETIMEOFFSET(2) = SYSDATETIMEOFFSET();

  -- Como estamos criando um stored procedure para SALVAR o item, iremos considerar
  -- id NULL para novo post, id com valor para edição de um post, mas nada impede-o
  -- de usar 2 stored procedures separados para cada caso de uso
  IF @id IS NULL BEGIN
    INSERT INTO Posts(ownerId, createdAt, updatedAt, title, message)
    VALUES(@userId, @now, @now, @title, @message);

    -- Pegamos agora o último ID inserido para retornarmos o post recém-criado
    SET @id = SCOPE_IDENTITY();
  END ELSE BEGIN
    UPDATE Posts
    SET updatedAt = @now, title = @title, message = @message
    WHERE id = @id AND ownerId = @userId;
    -- Note como verificamos a propriedade do post sendo editado pelo usuário já
    -- devidamente autenticado e validado
  END

  -- Uma vez o post criado, podemos agora inserir as tags, traduzindo o json para
  -- as tabelas criadas. Poderiamos claro excluir todas as tags existentes (no caso
  -- de um update) e recriá-las, mas podemos fazer melhor:

  -- Primeiro, vamos apagar todas as tags que não existem no documento:
  DELETE 
  FROM Posts_Tags
  WHERE postId = @id 
    AND tag NOT IN (SELECT value FROM OPENJSON(@json, '$.tags'));

  -- Agora, iremos inserir todas as tags que já não existem:
  INSERT INTO Posts_Tags(postId, tag)
  SELECT @id, value
  FROM OPENJSON(@json, '$.tags')
  WHERE NOT EXISTS (
    SELECT 1
    FROM Posts_Tags
    WHERE postId = @id AND tag = value
  );

  -- E, pronto, podemos finalmente retornar o post que acabou de ser
  -- criado, mas vamos fazer chamando um stored procedure criado para
  -- retornar o post completo, como requerido pelo client:
  SET @json = FORMATMESSAGE('{"id": %i}', @id);

  EXEC dbo.GetPostById @userId, @json;
END