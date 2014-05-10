-- -- --
-- Funções do esquema default (PUBLIC).
-- Cuidado (!), ficam "impregnadas" no esquema default.
-- https://github.com/ppKrauss/georecipes_alegrete
-- Ver também http://gauss.serveftp.com/colabore/index.php/Prj:Geoprocessing_Recipes/lib/sql-complement
-- -- --

CREATE FUNCTION array_sort(anyarray, boolean default false) RETURNS anyarray AS $$
   SELECT CASE WHEN $2 THEN ARRAY(SELECT DISTINCT unnest($1) ORDER BY 1)
               ELSE ARRAY(SELECT unnest($1) ORDER BY 1)
               END;
$$ language SQL IMMUTABLE;
 
CREATE OR REPLACE FUNCTION array_distinct(anyarray)
RETURNS anyarray AS $$
  SELECT ARRAY(SELECT DISTINCT unnest($1))
$$ language SQL IMMUTABLE;


-- non-lib, direct extension:
 CREATE FUNCTION ROUND(float,int) RETURNS NUMERIC AS $$
    SELECT ROUND($1::numeric,$2);
 $$ language SQL IMMUTABLE;

 CREATE FUNCTION ROUND(float, text, int DEFAULT 0) 
 RETURNS FLOAT AS $$
    SELECT CASE WHEN $2='dec'
                THEN ROUND($1::numeric,$3)::float
                -- ... WHEN $2='hex' THEN ... WHEN $2='bin' THEN... complete!
                ELSE 'NaN'::float  -- like an error message 
            END;
 $$ language SQL IMMUTABLE;
-- synonymous for CASE (like MS-Acccess):
CREATE OR REPLACE FUNCTION iif(BOOLEAN, anyelement, anyelement) RETURNS anyelement AS $$
    -- input ($2,$3) as pair of integers, texts, floats, booleans, etc. 
    SELECT CASE $1 WHEN true THEN $2 else $3 END;
$$ language SQL IMMUTABLE;
 

CREATE OR REPLACE FUNCTION lib.regclass_exists(p_tname character varying)
  RETURNS boolean AS
$BODY$
   -- verifica se uma tabela existe
DECLARE
  tmp regclass;
BEGIN
	tmp := p_tname::regclass; -- do nothing, only parsing regclass
	RETURN true;
        EXCEPTION WHEN SQLSTATE '3F000' THEN
	RETURN false;
END;
$BODY$  language PLpgSQL IMMUTABLE;


CREATE OR REPLACE FUNCTION lib.column_exists( -- NEW
  -- 
  -- Check if a column exists in a table. 
  -- 
  p_colname varchar,  -- column name
  p_tname varchar,             -- table name
  p_schema varchar DEFAULT 'public'  -- schema name
) RETURNS BOOLEAN AS $func$
  SELECT n::int::BOOLEAN
  FROM (
     SELECT COUNT(*) AS n FROM information_schema.COLUMNS -- coalesce pau, contaminado por null
     WHERE column_name=$1 AND table_schema=$3 AND table_name=$2
  ) AS t;
$func$ LANGUAGE SQL IMMUTABLE;



