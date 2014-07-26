-- permissões para um usuário no esquema lib --
-- ajustar para o nome do usuário ou grupo o qual irá se conectar a base --
BEGIN;
SET SEARCH_PATH TO lib;
GRANT USAGE ON SCHEMA lib TO alegrete;
GRANT DELETE, INSERT, SELECT ON TABLE trgr_labeler_in TO alegrete;
GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE trgr_labeler_out TO alegrete;
--REVOKE EXECUTE ON FUNCTION lib.r008a_quadra( double precision, double precision, double precision, double precision ) frOm alegrete;
SET SEARCH_PATH TO DEFAULT;
COMMIT;