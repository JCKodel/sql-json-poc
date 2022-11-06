DECLARE @json NVARCHAR(MAX) = N'{
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
}';

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