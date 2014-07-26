-- permissões para um usuário no esquema fonte --
-- ajustar para o nome do usuário ou grupo o qual irá se conectar a base --
BEGIN;
GRANT USAGE ON SCHEMA fonte TO alegrete;
GRANT SELECT ON fonte.g_eixologr TO alegrete;
GRANT SELECT, UPDATE ON fonte.g_lote TO alegrete;
GRANT SELECT ON fonte.g_quadra TO alegrete;
COMMIT;