-- permissões para um usuário no esquema kx --
-- ajustar para o nome do usuário ou grupo o qual irá se conectar a base --
BEGIN;
SET SEARCH_PATH TO kx;
GRANT USAGE ON SCHEMA kx TO alegrete;
GRANT SELECT ON eixologr_cod TO alegrete;
GRANT DELETE, INSERT, SELECT, UPDATE ON lote_seg TO alegrete;
GRANT SELECT ON lote_viz TO alegrete;
GRANT DELETE, INSERT ON quadra_buffdiff TO alegrete;
GRANT SELECT ON quadraccvia TO alegrete;
GRANT INSERT, SELECT, UPDATE, TRUNCATE ON quadrasc TO alegrete;
GRANT INSERT, DELETE, SELECT, UPDATE ON quadrasc_simplseg TO alegrete;
GRANT DELETE, INSERT ON viabuff TO alegrete;

SET SEARCH_PATH TO DEFAULT;
COMMIT;