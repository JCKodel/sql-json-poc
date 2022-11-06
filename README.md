# Usando SQL Server com JSON para APIs sem código
## Sobre mim

Auto-didata em programação desde 1986, em diferentes plataformas e linguagens, incluindo Assembly, C e Pascal. Agora dedicado a construir aplicativos móveis e sistemas web utilizando o framework [Google Flutter](https://flutter.dev/) com [Dart](https://dart.dev/) e backend em [Microsoft C#](https://learn.microsoft.com/en-us/dotnet/csharp/), com o mínimo de código possível.

Autor do [Meu Cronograma Capilar](https://mcc.code.art.br), aplicativo com mais de 6 milhões de downloads para [Android](https://play.google.com/store/apps/details?id=br.art.code.meucronogramacapilar) e [iOS](https://apps.apple.com/br/app/meu-cronograma-capilar/id1208584232) operando no [Microsoft Azure](https://azure.com) com um custo inferior a US$ 70/mês.

## O porquê

Durante toda a minha vida profissional, a grande maioria das aplicações foram escritas na forma de obtenção de dados de uma base de dados para um output qualquer, em sua maioria, páginas web ou aplicativos móveis, e sempre escrevendo APIs que apenas retornam dados destes banco de dados. Centenas de linhas de código para pegar dados de um banco de dados, converter em JSON para enviar para uma página web ou um aplicativo móvel. Isso sem contar as sandices de se usar Entity Framework, nHibernate, Dapper, etc...

Não seria mais fácil se apenas então pudessemos disponibilizar o banco de dados diretamente ao client, de forma segura (no sentido de não fornecer mais informações do que o necessário ou informações que não pertencem ao usuário utilizando o app) e, principalmente, que esta API fosse escrita apenas uma vez e pudesse ser utilizada em qualquer aplicativo com o mesmo backend?

## Investigando as possibilidades

Sempre tive afinidade com os produtos de desenvolvimento da Microsoft (talvez por que comecei com MSX Basic em 87?) e, dentre os banco de dados existentes, sempre tive uma afinidade maior com o SQL Server. Sim, nem sempre foi bom (SQL Server 2000) e nem sempre é barato (embora eu consiga viver bem com os 10Gb da versão Express para alguns aplicativos), mas a Microsoft tem o dom de deixar as coisas simples e isso não é diferente no SQL Server.

O suporte a JSON de forma nativa dentro do RDBMS e, principalmente, de forma muito fácil, me fizeram escrever este artigo usando o SQL Server, mas nada impede de que outros RDBMS possam utilizar o mesmo conceito (sei que a maioria dos RDBMS possuem suporte a JSON, mas sei que alguns, como PostgreSQL, possuem uma sintaxe tão verbosa e complicada que acabariam deixando a coisa toda mais complicada do que escrever APIs). Adoraria ver alguém com conhecimento em outros RDBMS traduzirem esta teoria.

## Cada macaco no seu galho

Eu acredito que cada ferramenta existente serve um determinado propósito, ou seja, usar LINQ em C# para acesso a dados é como usar um martelo para parafusar um parafuso. A melhor ferramenta para se usar com um banco de dados relacional é ele mesmo.

A grande maioria dos RDBMS possuem suporte à execução de scripts (chamados, no SQL Server, de Stored Procedures). Já ouvi gente falar que isso é *"coisa antiga"* (nem vou comentar a estupidez deste comentário), mas o fato é que stored procedures podem manipular dados diretamente dentro do RDBMS de forma bem eficiente e eficaz, inclusive fornecendo ferramentas poderosas para otimização, como gráficos mostrando planos de execução e profilers que podem monitorar a execução de queries e sugerir índices e outros artefatos para melhorias na performance. Não há sentido em transportar dados pela camada mais lenta de uma aplicação (rede), sendo que tudo pode ser resolvido diretamente no banco de dados (que já vai ter que realizar as queries de uma forma ou de outra, então não estamos adicionando carga a mais!).

Não sei se isso é possível em todos os RDBMS, mas o SQL Server mantém tabelas internas da data de escrita de cada tabela do banco de dados, além de fornecer de forma simples todas as tabelas envolvidas em um stored procedure, ou seja, é possível até mesmo saber se o resultado de um stored procedure retornará o mesmo conteúdo de uma execução passada, baseado na data de escrita das tabelas envolvidas. Esta informação pode ser valiosa para não executar stored procedures somente de leitura se o client já possuir uma resposta (para isso existe os headers `Last-Modified` e `If-Modified-Since` e a resposta `304: Not Modified` da [RFC 9110 - HTTP Semantics](https://httpwg.org/specs/rfc9110.html#field.if-modified-since).

A query para obter estes dados é:

```sql
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
```

(daria para fazer com JOIN, porém `LEFT JOIN` no SQL Server 2022 Linux tem uma performance absurdamente baixa, então, retornar um JSON resolve).

## Segurança

Não é nada legal uma API que retorne dados de outros usuários com uma simples manipulação de URL (por exemplo, se uma API faz uma query de uma compra em um banco de dados, baseado no id desta compra, geralmente não há muita preocupação em não retornar outras compras apenas alterando o id da url).

Já vi certos absurdos como "vamos usar um GUID aleatório para que não seja tão óbvio que o registro anterior pode ser obtido, chamando id - 1" ¬¬

A teoria sendo apresentada aqui fornece uma forma simples de validar este tipo de falha de segurança, considerando que o desenvolvedor que esteja escrevendo o stored procedure tome o cuidado de seguir este padrão e que o id do usuário seja seguro, ou seja, que venha de uma fonte segura, como um token JWT validado.

## Separação de leitura e escrita

A separação entre leitura e escrita é muito importante por uma série de motivos que não vem ao caso discutir aqui. Para esta teoria, essa separação é fundamental para o funcionamento do cache descrito acima, que sequer executaria um stored procedure somente-leitura caso o client já possua o conteúdo e que este conteúdo não tenha sido alterado no banco de dados (se não houve escrita no banco de dados, a execução de uma leitura deveria emitir exatamente o mesmo resultado).

Então, se conseguirmos separar todas as APIs de uma aplicação entre leitura e escrita, conseguimos também determinar com precisão duas coisas: a invalidação do cache (que só acontece na escrita) e a não execução do stored procedure caso nada tenha mudado no banco. Claro que isso só funciona se ninguém mais tiver acesso ao banco de dados ou se tivermos uma forma de invalidar o cache de forma externa. De qualquer forma, é uma feature extra para um boost de performance e redução de custos (especialmente para Azure SQL).

## Esquema de teste

Para testar nossa API, iremos criar um esquema com tabelas de usuários, posts e tags. Stored procedures irão ser criados para manipular estes itens.

Tanto a entrada de dados quanto a saída será na forma de documentos JSON (não será algo 1:1 com as tabelas, ou seja, tanto na entrada quanto na saída conseguiremos criar documentos com diferentes níveis de informação para que tudo seja feito com 1 chamada apenas, algo até então só possível com bancos de dados baseados em documentos, como MongoDB, mas aqui faremos **sem** precisar abrir mão de relacionamentos).

O esquema de dados é este:

![](https://i.ibb.co/L0FDqMx/SQL.jpg)

PKs int identity simples, campos de data em UTC (afinal, [nunca sabemos qual a timezone do usuário](https://pt.wikipedia.org/wiki/Fusos_hor%C3%A1rios_no_Brasil#:~:text=O%20Brasil%20observa%20quatro%20fusos,UTC%2D05%3A00).), não é mesmo?), campos textos em Unicode (para suportar 🤬 e 🤮, por exemplo), tudo bem simples.

Graças ao fantástico SQL Managment Studio, eu consigo extrair o código T-SQL para gerar isso tudo com apenas 1 click, já com as FKs, índices e tudo mais:

```sql
CREATE TABLE [dbo].[Posts](
	[id] [int] IDENTITY(1,1) NOT NULL,
	[ownerId] [char(28)] NOT NULL,
	[createdAt] [datetimeoffset](2) NOT NULL,
	[updatedAt] [datetimeoffset](2) NOT NULL,
	[title] [nvarchar](32) NOT NULL,
	[message] [nvarchar](max) NOT NULL,
 CONSTRAINT [PK_Posts] PRIMARY KEY CLUSTERED 
(
	[id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO

CREATE TABLE [dbo].[Posts_Tags](
	[postId] [int] NOT NULL,
	[tag] [varchar](16) NOT NULL,
 CONSTRAINT [PK_Posts_Tags] PRIMARY KEY CLUSTERED 
(
	[postId] ASC,
	[tag] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO

CREATE TABLE [dbo].[Users](
	[id] [char(28)] NOT NULL,
	[name] [nvarchar](32) NOT NULL,
	[email] [varchar](128) NOT NULL,
	[created] [datetimeoffset](2) NOT NULL,
	[lastLogin] [datetimeoffset](2) NOT NULL,
 CONSTRAINT [PK_Users] PRIMARY KEY CLUSTERED 
(
	[id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO

CREATE NONCLUSTERED INDEX [IX_Posts_ownerId] ON [dbo].[Posts]
(
	[ownerId] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO
ALTER TABLE [dbo].[Posts]  WITH CHECK ADD  CONSTRAINT [FK_Posts_Users] FOREIGN KEY([ownerId])
REFERENCES [dbo].[Users] ([id])
ON DELETE CASCADE
GO

ALTER TABLE [dbo].[Posts] CHECK CONSTRAINT [FK_Posts_Users]
GO

ALTER TABLE [dbo].[Posts_Tags]  WITH CHECK ADD  CONSTRAINT [FK_Posts_Tags_Posts] FOREIGN KEY([postId])
REFERENCES [dbo].[Posts] ([id])
ON DELETE CASCADE

GO
ALTER TABLE [dbo].[Posts_Tags] CHECK CONSTRAINT [FK_Posts_Tags_Posts]
GO
```

## Stored procedures

Todos nossos stored procedures irão receber os mesmos argumentos e irão sempre retornar um stream de texto. Isso é a parte mais importante da coisa toda, por que não precisamos escrever absolutamente nenhum código fora do SQL Server que seja específico para a aplicação. Apenas precisamos saber de alguns itens:

* String de conexão (com qual banco de dados estamos querendo nos conectar e com quais credenciais)
* Nome do stored procedure
* Usuário autenticado (que pode ser NULL, caso você realmente tenha dados que não precisem de segurança a nível de usuário)
* JSON de entrada (o que a aplicação envia ao stored procedure como argumentos)

Então, se um servidor for construído em, por exemplo, C#, o código C# *sempre* será o mesmo, independente da aplicação, dos argumentos de entrada, do stored procedure ou da saída. Quer usar Go, Rust ou PHP? Sem problemas! Escreva uma vez, rode sempre (de verdade, desta vez). A linguagem utilizada no backend realmente não tem mais importância.

Todos stored procedures terão a mesma assinatura:

```sql
CREATE PROCEDURE [schema].[stored procedure name](@userId CHAR(28), @json NVARCHAR(MAX)) AS BEGIN
...
END
```

Infelizmente, não há uma forma automática de garantir que o `@userId` seja utilizado (digo: sempre há a possibilidade de um desenvolvedor desatento resolver retornar dados das tabelas ignorando se tais dados realmente pertencem ao `@userId` informado, o que é uma falha de segurança), então, este é um ponto de cuidado (que pode ser facilmente resolvido com Code Review).

Outro ponto é que tal stored procedure **deve** retornar um stream de texto e não um ou mais result sets, ou seja, todo comando `SELECT` deve retornar um `TEXT` (isso é bem simples e é, na verdade, grande parte da mágica, porém, o servidor deve ter uma forma de garantir que isso não seja esquecido, ou seja, o result set de todo stored procedure deve retornar um e apenas um campo stream de `TEXT` cujo nome se inicie com `JSON`).

Isso é bem simples, em ADO.net puro, basta executar um `DataReader` em loop, como segue:

(Estou considerando que você já saiba utilizar ADO.net e que os trechos abaixo já sejam suficientes para passar a idéia sendo executada).

```csharp
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
```

Alguns ORM, como o [Belgrade SqlClient](https://github.com/JocaPC/Belgrade-SqlClient) deixam isso até mais automatizado e fácil de ler, já jogando o resultado diretamente no stream de saída do HTTP:

```csharp
var cmd = new Command(connectionString);

cmd.Sql("EXEC [NomeStoredProcedure], @userId, @json")
   .Param("userId", userId)
   .Param("json", jsonString)
   .Stream(Response.Body);
```

Note que não existe absolutamente nenhum tipo de manipulação do JSON de entrada (que no exemplo acima é passado o JSON original do request, obtido do body do request e o resultado do banco é jogado diretamente no body do response). Isso é essencial para que o código C# não tenha absolutamente nenhum conhecimento sobre os dados (assim, você consegue utilizar exatamente o mesmo servidor, sem alterações, para qualquer aplicativo).

Como não é nada legal passar JSON via query string, eu utilizo `POST` até mesmo para queries somente de leitura (embora os headers de cache `If-Modified-Since` sejam mais utilizados para `GET`, nada impede de se usar isso para `POST` também, afinal, header é header, dado é dado).

Então agora é só questão mesmo de escrever nossas regras de negócios de dados, na ferramenta mais apropriada para isso:

## Inserindo o usuário

Aqui, estamos considerando que o teu usuário já esteja autenticado e é válido, então você já tem um id qualquer, fornecido pelo seu provedor de autenticação. Para este exemplo, usei um `CHAR(28)` por que, geralmente, uso o fantástico Firebase Authentication que me permite autenticar usuários via E-mail, Google, Apple e Microsoft me retornando um usuário comum independente da plataforma utilizada (cujo id é uma string de 28 caracteres).

Se você estiver usando um provedor OAUTH qualquer, este com certeza te retornará um id de usuário que ele considera válido (ou seja, o identificador do usuário é resposabilidade do provedor de autenticação, não do banco de dados, por isso não estamos usando um id int identity para isso).

No pior caso, você pode pegar uma informação única do usuário, como o e-mail, e criar um hash disso.

Considerando que sempre temos um `@userId` preenchido com um identificador devidamente validado pelo nosso provedor de autenticação, o resto é fácil:

```sql
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
```

Para executar este stored procedure, tudo o que o client precisa enviar é um JSON contendo as informações requeridas, com o id validado do usuário autenticado:

```json
{
  "name": "Júlio César Ködel ",
  "email": "email-do-julio@servidor.com.br"
}
```

O resultado da execução deste stored procedure é este:

```json
{
  "id": "a1b2c3", // código gerado pelo Firebase Authentication, neste exemplo
  "name": "Júlio César Ködel",
  "email": "email-do-julio@servidor.com.br",
  "created": "2022-11-05T20:35:00.0Z",
  "lastLogin": "2022-1105T20:35:00.0Z"
}
```

## Lendo sub-documentos na entrada

Em muitos casos, enviamos argumentos mais complexos para serem gravados em diversas tabelas no banco de dados. Neste exemplo, imagine um post contendo um array de tags que deverão ser gravados cada qual em sua respectiva tabela (afinal, não há absolutamente nenhum motivo de abrir mão de relacionamentos, não é mesmo?)

O `OPENJSON` é capaz de abrir diferentes níveis de JSON, bastando fornecer um root diferente. Então, para um json contendo o esquema abaixo, é possível obter qualquer parte de forma simples:

```json
{
  "propriedade1": "a1",
  "propriedade2": "b2",
  "arrayDeObjetos": [
    {"id": 1, "nome": "a"},
    {"id": 2, "nome": "b"}
  ],
  "arrayDePrimitivos": ["a", "b", "c"],
  "objeto": {
    "outro": "objeto"
  }
}
```

Posso extrair facilmente qualquer dado deste JSON de forma simples:

```sql
SELECT propriedade1, propriedade2 
FROM OPENJSON(@json, '$') WITH (
  propriedade1 VARCHAR(2) '$.propriedade1',
  propriedade2 VARCHAR(2) '$.propriedade2'
);

SELECT id, nome
FROM OPENJSON(@json, '$.arrayDeObjetos') WITH (
  id INT '$.id',
  nome VARCHAR(16) '$.nome'
);

SELECT value
FROM OPENJSON(@json, '$.arrayDePrimitivos');

SELECT outro
FROM OPENJSON(@json, '$.objeto') WITH (
  outro VARCHAR(32) '$.outro'
);
```

Que resulta em:

| propriedade1 | propriedade2 |
| ------------ | ------------ |
| a1           | b2           |

| id | nome |
| -- | ---- |
| 1  | a    |
| 2  | b    |
| 3  | c    |

| value |
| ----- |
| a     |
| b     |
| c     |

| outro  |
| ------ |
| objeto |

Considerando que podemos colocar todos estes dados em variáveis, tabelas temporárias, INSERT FROM SELECT ou mesmo UPDATE e DELETE com JOIN, a manipulação destes argumentos de entrada são bem simples (e nem precisamos de cursores). `CROSS APPLY` também é teu amigo (afinal, nem só de `LEFT/INNER JOIN` vive um desenvolvedor).

Baseado nisso, podemos criar a procedure que inclui posts de um usuário, dado este JSON:

```json
{
  "id": null, // null para insert, valor para update
  "title": "Título do meu post",
  "message": "Texto do meu post",
  "tags": [ // Este array irá na tabela apropriada
    "#tag1",
    "#tag2",
    "#tag3"
  ]
}
```

O esquema é exatamente o mesmo do procedure de login:

```sql
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
```

Observação: 

Por que o `value` na query acima? Bom, um `OPEN_JSON` sem `WITH` retorna uma tabela contendo a estrutura do JSON, como no exemplo abaixo:

```json
{
  "id": 1,
  "nome": "João"
}
```

```sql
SELECT OPENJSON(@json);
```

retorna

| key  | value | type |
| ---- | ----- | ---- |
| id   | 1     | 2    |
| nome | João  | 1    |

Por isso, pegamos a coluna `value`, que contém o valor de cada chave JSON (ou de cada item de um array, onde `key` é o índice do array)

Anyways...

O stored procedure que retorna o post completo, incluindo dados do usuário que postou bem como a lista de tags da forma como o client espera (array de string), recebendo um JSON do tipo `{"id": 1}`:

 ```sql
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
 ```

Este stored procedure devolve um stream de `TEXT` com o seguinte conteúdo:

```json
{
  "id": 1,
  "createdAt": "2022-11-05T21:19:32.10-03:00",
  "title": "Título do Post",
  "message": "Corpo do Post",
  "tags": [
    "#tag1",
    "#tag2",
    "#tag3"
  ],
  "owner": {
    "id": "a1b2c3",
    "name": "Júlio César Ködel"
  }
}
```

Um JSON prontinho para ser usado no client, no formato de um documento, como os amantes de no-SQL adoram, feito com 0 linha de código não genérico (e, melhor: com um serializador JSON com performance de C++ ao invés de C#, embora, sinceramente, eu não tenha feito nenhum tipo de benchmark para verificar performance).

A formatação nem é tanto um problema, por que, afinal, você está usando compactação na tua API né (Brotli, Gzip, etc)? Os espaços extras e quebras de linha não farão muita diferença no resultado comprimido.

O plano de execução gerado pelo SQL Server foi este:

![](https://i.ibb.co/F6C2q3G/pe.jpg)

## Comentários

Então, temos aqui a base para a criação de um servidor genérico que utiliza as funções nativas do SQL Server para ler e escrever JSON, sem precisar escrever nenhuma linha de código no backend em si.

Fiquem à vontade em comentar (caso você esteja lendo isso no LinkedIn) ou discutir nos Issues caso você esteja no [GitHub](https://github.com/JCKodel/sql-json-poc)) sobre esta teoria.

E adoraria ver forks deste repositório com exemplos para outros RDBMS, como MySQL ou PostgreSQL, se for possível.

# Licença
GNU Affero General Public License v3.0

As permissões dessa licença copyleft mais forte estão condicionadas à disponibilização do código-fonte completo de obras e modificações licenciadas, que incluem trabalhos maiores usando um trabalho licenciado, com a mesma licença.

**Os avisos de direitos autorais e licenças devem ser preservados**.

Os colaboradores fornecem uma concessão expressa de direitos de patente.

Quando uma versão modificada é usada para fornecer um serviço em uma rede, o código-fonte completo da versão modificada deve ser disponibilizado.