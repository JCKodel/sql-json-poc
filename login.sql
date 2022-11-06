CREATE PROCEDURE [dbo].[Login](@userId CHAR(28), @json NVARCHAR(MAX)) AS BEGIN
  -- Aqui iremos obter os dados que vem do corpo da requisição, em JSON:
  -- Só faz sentido obter o nome e e-mail do usuário, já que os outros dados
  -- podem ser "server-side" ou nunca sofrerão update:
  DECLARE @name NVARCHAR(32);
  DECLARE @email VARCHAR(128);

  -- Para ler o JSON e preencher as variáveis acima, usamos um SELECT:
  SELECT @name = TRIM(name), @email = TRIM(email)
  FROM OPENJSON(@json, '$') WITH (
    name NVARCHAR(32) '$.name',
    email VARCHAR(128) '$.email'
  );

  -- O select acima basicamente lê o JSON usando o $ como root, ou seja:
  -- {"name": "Nome", "email": "e@mail"}

  -- Se quisermos, podemos fazer algum tipo de validação aqui, mas eu pessoalmente
  -- acho desnecessário repetir o que já está validado no client, ainda mais em se
  -- tratando de aplicativos móveis com código em linguagem de máquina, que é o caso
  -- de Dart =P

  -- Os dados de data de criação e último login podemos deixar aqui mesmo, já que estes
  -- dados não são confiáveis no client:
  DECLARE @now DATETIMEOFFSET(2) = SYSDATETIMEOFFSET();

  -- Agora determinamos se é um INSERT ou um UPDATE verificando se o registro já existe
  -- e aproveitando para trancar a linha em que tal registro se encontra (o que faz sentido
  -- com uma transação do tipo serializable)

  -- Note que utilizamos sempre o id do usuário vindo dos argumentos do stored procedure e
  -- não do JSON (por que o argumento foi validado com um token JWT ou coisa parecida e então
  -- está garantido de ser uma identidade válida)
  IF NOT EXISTS(SELECT 1 FROM Users WITH(XLOCK, ROWLOCK) WHERE id = @userId) BEGIN
    -- Usuário não existe? Vamos inserí-lo
    INSERT INTO Users(id, name, email, crated, lastLogin)
    VALUES(@userId, @name, @email, @now, @now);
  END ELSE BEGIN
    -- Caso o usuário exista, vamos apenas atualizar o campo que interessa
    UPDATE Users
    SET lastLogin = @now
    WHERE id = @userId;
  END

  -- Por ser um stored procedure de mutação, nem precisamos retornar nada, porém, nada
  -- impede de retornar o registro que acabou de ser salvo, afinal, o client não tem
  -- as informações corretas de ids gerados, datas geradas aqui, etc.

  -- A mágica de retorno acontece assim: você retorna apenas um result set (ou seja, um
  -- SELECT somente), convertido para JSON (usando FOR JSON PATH). Mais para frente veremos
  -- como retornar vários SELECT no mesmo documento.
  SELECT TOP 1 id, name, email, created, lastLogin
  FROM Users
  WHERE id = @userId
  FOR JSON PATH, WITHOUT_ARRAY_WRAPPER -- <- isso é para retornar um JSON sem [ e ];
END