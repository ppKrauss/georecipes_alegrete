-- -- --
-- Inicializaçao do esquema fonte.
-- https://github.com/ppKrauss/georecipes_alegrete
-- -- --

SET statement_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;
-- DROP SCHEMA fonte CASCADE; 
-- DROP SCHEMA errsig CASCADE;

DO
$DO$
DECLARE
  query_integer integer NOT NULL := 0;
BEGIN

  IF NOT current_setting( 'is_superuser' )::boolean THEN
    RAISE EXCEPTION 'Conta de super usuário requerida.';
  END IF;
  -- as requested by peter --
  DROP SCHEMA IF EXISTS fonte CASCADE;

  BEGIN
    CREATE SCHEMA fonte;
  EXCEPTION
  WHEN SQLSTATE '42P06' THEN
  END;
  --precisa? CREATE SCHEMA errsig
  --ALTER SCHEMA fonte OWNER TO alegrete;
  -- nao usar SET search_path = fonte, pg_catalog;


  -- -- --

  --
  -- -- tadm PARTE 0: tabelas e funções de check
  --
  CREATE TABLE fonte.tadm_error_type ( -- err_cods description
     err_cod serial PRIMARY KEY, -- using hash
     err_cod_name varchar(64) NOT NULL,
     err_cod_description text
  );
 
CREATE OR REPLACE FUNCTION fonte.check_err_id(integer[],BOOLEAN DEFAULT NULL) RETURNS BOOLEAN AS $$
  -- funcao fora de uso ... precisa?
  SELECT COALESCE( array_Length($1,1) = ( 
     SELECT COUNT(*) 
     FROM fonte.tadm_error_type f INNER JOIN (SELECT unnest($1) AS ecod) t
       ON f.err_cod=t.ecod
  ), $2 );
$$ LANGUAGE SQL immutable;
 
--
-- -- tadm PARTE 1
--
 
CREATE TABLE fonte.tadm_prjcatalog ( 
   framework_prjname varchar(32) NOT NULL DEFAULT 'SGM', -- nome Wiki
   framework_url varchar(255) NOT NULL DEFAULT 'http://gauss.serveftp.com/colabore/index.php/Prj:SGM',
 
   prj_id serial PRIMARY KEY, 
   prj_geoname varchar(64) NOT NULL, -- Ex. 'São Carlos'
   prj_geoname_srid integer NOT NULL,  -- indicar 
 
   prj_created timestamp WITH time zone NOT NULL DEFAULT now(),
   max_envelope geometry('POLYGON'), -- optional BBOX for within(geom) , for validation and for cut OpenStreetMaps
   notes text,
   UNIQUE(framework_prjname,prj_geoname),
   UNIQUE(framework_prjname,prj_geoname_srid),
   CHECK (ST_SRID(max_envelope)=prj_geoname_srid)
);
-- BASTA UM REGISTRO, por exemplo:
INSERT INTO fonte.tadm_prjcatalog (prj_geoname,prj_geoname_srid) 
VALUES ('Montenegro/RS', 31997), ('Alegrete/RS', 31996);
 
CREATE TABLE fonte.tadm_catalog ( -- apenas tabelas-fonte, cada esquema com seu catalog complementar.
   oid regclass PRIMARY KEY,
   prj_id integer NOT NULL REFERENCES fonte.tadm_prjcatalog(prj_id),
   created      timestamp WITH time zone NOT NULL DEFAULT now(), -- with zone as pg_catalog.pg_stat_user_tables
   last_update  timestamp WITH time zone NOT NULL DEFAULT now(), -- vale como refreshed em KX?
   last_refresh   timestamp WITH time zone,    -- para campos kx_*, instante de refresh, ver função lib.tadm_refreshsetor() obrigatória
   refresh_mode  integer NOT NULL DEFAULT 0,  --0=indefinido, 1=sem triggers, 2=apenas trgger campos, 8=campos e tadm-isolated, 16=all 
   geom_type varchar(32), -- fixing the type returned by GeometryType
   ref_isrural BOOLEAN NOT NULL DEFAULT false, -- em geral tudo tratado como urbano
   ref_snapgrid float, -- grid accuracy, ex. 1 = 1 meter
   ref_pos_error float, -- radious spheric position-error 
   ref_min float, -- minimal area for polygon, minimal length for lines. See "digital dust"
   validation_list integer[], -- ref to fonte.tadm_error_type
   mapfile xml,
   kx_ndims integer, -- dimensões da geometria da geom_stype, ou prevista
   kx_geom_srid integer -- copy from fonte.tadm_prjcatalog srid
 
   -- ,CHECK (fonte.check_err_id(validation_list))
);
 
----------
 
CREATE TABLE fonte.tadm_error_row ( -- registro da linha de tabela com evento de erro
   id serial PRIMARY KEY, -- precisava ser bigint!
   oid regclass, -- esquema e nome da tabela
   gid integer,  -- gid do registro (tabela de geometria) onde ocorreu o erro
   kx_last_state_date timestamp without time zone DEFAULT now(),   -- controls last modifications  
   kx_worst_state varchar(12), -- worst case of non-closed bugs 
   kx_open_error_cods int[],   -- list of all non-closed bugs
   UNIQUE(oid,gid),
   CHECK( fonte.check_err_id(kx_open_error_cods) )  -- ops, conferir se "fora de uso" mesmo!
   -- old CHECK( fonte.check_err_id(kx_open_error_cods,false) AND coalesce(array_length(lasterr_cods)=array_length(lasterr_dates),false) )
);
 
CREATE TABLE fonte.tadm_error_track (  -- histórico com ciclo bug-tracking
  id_row int NOT NULL REFERENCES fonte.tadm_error_row(id) ON DELETE CASCADE,
  err_cod int NOT NULL REFERENCES fonte.tadm_error_type(err_cod),
  state varchar(22), -- state in a bug lifecycle 
  state_date timestamp without time zone DEFAULT now(),   -- last change of this record  
  details text -- (only last) friendly message detailing/subtyping the problem of err_cod
  -- user_id  of the last changed state
  -- error_log: log of <date, state, user> changes for audit
);
 
INSERT INTO fonte.tadm_error_type (err_cod_name,err_cod_description) VALUES
-- ver Prj:Geoprocessing_Recipes/I007/tadm-error-types
  ('geometria nula', 'quando dados cadastrais precisam ser armazenados como dado-fonte mas geometria ficou nula'),
  ('tipo errado', 'ver CHECKs de tipo ou sub-tipo de dado'),
  ('poeira digital', 'ver http://gauss.serveftp.com/colabore/index.php/Rec:Normaliza%C3%A7%C3%A3o_geometrias#N.C3.A3o-poeira'),
  ('sobreposicao com vizinho', 'ver por ex. kx.vw_lote_viz_err em http://gauss.serveftp.com/colabore/index.php/Prj:Geoprocessing_Recipes/lib/kxrefresh_lote_viz'),
  ('duplicidade', 'ver http://gauss.serveftp.com/colabore/index.php/Rec:Normaliza%C3%A7%C3%A3o_geometrias#N.C3.A3o-duplicidade'),
  ('buraco com vizinho', 'Poligono apresentando vizinho-de-mosaico grudado porém com buraco entre eles.');
 
 
--
-- -- tamd Parte 2: views e functions que não podem sair daqui, perigo
--
 
CREATE VIEW fonte.vw_tadm_catalog_prj AS 
   SELECT c.*, p.framework_prjname||'/'||p.prj_geoname AS prjname, 
          p.prj_geoname_srid, p.prj_created
   FROM fonte.tadm_catalog c INNER JOIN fonte.tadm_prjcatalog p
   ON   c.prj_id=p.prj_id;
 
CREATE VIEW fonte.vw_tadm_catalog_full AS 
SELECT 
    f.*, 
    current_database()::character varying(256) AS f_table_catalog, 
    n.nspname::character varying(256) AS f_table_schema, 
    c.relname::character varying(256) AS f_table_name, 
    a.attname::character varying(256) AS f_geometry_column,
    COALESCE(NULLIF(postgis_typmod_dims(a.atttypmod), 2), postgis_constraint_dims(n.nspname::text, c.relname::text, a.attname::text), 2) AS coord_dimension,
    REPLACE(REPLACE(COALESCE(NULLIF(upper(postgis_typmod_type(a.atttypmod)), 'GEOMETRY'::text), postgis_constraint_type(n.nspname::text, c.relname::text, a.attname::text)::text, 'GEOMETRY'::text), 'ZM'::text, ''::text), 'Z'::text, ''::text)::character varying(30) AS type
 
FROM pg_class c, pg_attribute a, pg_type t, pg_namespace n, fonte.vw_tadm_catalog_prj f
 
WHERE c.oid=f.oid AND t.typname = 'geometry'::name AND a.attisdropped = false 
  AND a.atttypid = t.oid AND a.attrelid = c.oid AND c.relnamespace = n.oid 
  AND (c.relkind = 'r'::"char" OR c.relkind = 'v'::"char") AND NOT pg_is_other_temp_schema(c.relnamespace) 
  AND NOT (n.nspname = 'public'::name AND c.relname = 'raster_columns'::name) 
  AND has_table_privilege(c.oid, 'SELECT'::text);
 
CREATE VIEW fonte.vw_tadm_error AS
  SELECT r.id, r.oid, r.gid, k.err_cod, t.err_cod_name, k.state, k.state_date, k.details
  FROM (fonte.tadm_error_row r INNER JOIN fonte.tadm_error_track k ON r.id=k.id_row) 
       INNER JOIN fonte.tadm_error_type t ON k.err_cod=t.err_cod;
 
-- Functions to simplify audit procedure:
CREATE OR REPLACE FUNCTION  fonte.tadm_hasError(regclass) returns BOOLEAN AS $$
  SELECT COALESCE( 
    (SELECT true FROM fonte.tadm_error_row WHERE oid=$1 AND kx_open_error_cods IS NOT NULL), 
    false
  );
$$ LANGUAGE SQL immutable;
CREATE OR REPLACE FUNCTION  fonte.tadm_hasError(regclass, p_gid integer) returns BOOLEAN AS $$
  SELECT COALESCE( 
    ( SELECT true FROM fonte.vw_tadm_error 
      WHERE oid=$1 AND gid=$2 AND state!='closed'
    ), 
    false
  );
$$ LANGUAGE SQL immutable;
CREATE FUNCTION  fonte.tadm_hasError_byid(p_id integer)  returns BOOLEAN AS $$
  SELECT COALESCE( 
    ( SELECT true FROM fonte.vw_tadm_error 
      WHERE id=$1 AND state!='closed'
    ), 
    false
  );
$$ LANGUAGE SQL immutable;
CREATE FUNCTION  fonte.tadm_isApproved(regclass,integer DEFAULT NULL)  returns BOOLEAN AS $$
  SELECT CASE WHEN $2 IS NOT NULL THEN NOT(fonte.tadm_hasError($1,$2)) 
         ELSE NOT(fonte.tadm_hasError($1))
         END;
$$ LANGUAGE SQL immutable;
 
-- Comunica mensagens:
CREATE FUNCTION fonte.tadm_hasErrorReason(regclass,integer) returns text AS $$  
       -- function name with "reason" like  ST_IsValidReason
    SELECT 'ERROR cod.'||err_cod||' in '||state||' at '||state_date||': '||details
    FROM fonte.vw_tadm_error 
    WHERE oid=$1 AND gid=$2 AND state!='closed'
$$ LANGUAGE SQL immutable;
 
-------
 
-- TODO manter isso --
/*
CREATE FUNCTION check_err_id(integer[], boolean DEFAULT NULL::boolean) RETURNS boolean AS $_$
  -- funcao fora de uso, nao precisa
  SELECT COALESCE( array_Length($1,1) = ( 
     SELECT COUNT(*) 
     FROM fonte.tadm_error_type f INNER JOIN (SELECT unnest($1) AS ecod) t
       ON f.err_cod=t.ecod
  ), $2 );
$_$ LANGUAGE sql IMMUTABLE; 
*/

 
 
CREATE OR REPLACE FUNCTION  fonte.merge_tadm_error(
   p_oid regclass, 
   p_gid int, 
   p_err_cod integer, 
   p_state varchar DEFAULT 'new',
   p_details text  DEFAULT NULL
) RETURNS integer AS  -- future bigint
$$
-- pode usar sem details para apenas atualizar p_state ou sem state para atualizar details 
-- FALTA função de "worst state" para substituir max(state). Usar SELECT CASE WHEN.. estados bug lifecycle.
DECLARE
   errid integer; -- future bigint
BEGIN
 
    IF p_state IS NULL AND p_details IS NULL THEN 
      RAISE EXCEPTION 'invalid NULL parameters p_state and  p_details'
            USING HINT = 'Only one can br null, for updates the another';
    END IF;
    SELECT id INTO errid FROM fonte.tadm_error_row WHERE oid=p_oid AND gid=p_gid;
 
    IF errid IS NULL THEN
        INSERT INTO fonte.tadm_error_row (oid, gid) VALUES (p_oid, p_gid) 
               RETURNING id INTO errid;
    END IF;
 
    IF EXISTS (SELECT 1 FROM fonte.tadm_error_track WHERE id_row=errid AND err_cod=p_err_cod) THEN
        IF p_details IS NULL THEN -- only changes states (using for audit)
          UPDATE fonte.tadm_error_track 
          SET state=p_state, state_date=now() 
          WHERE id_row=errid AND err_cod=p_err_cod;
        ELSEIF p_state IS NULL THEN -- only changes details (using for refresh details)
          UPDATE fonte.tadm_error_track 
          SET details=p_details 
          WHERE id_row=errid AND err_cod=p_err_cod;
        ELSE  -- same, adding details
          UPDATE fonte.tadm_error_track 
          SET state=p_state, state_date=now(), details=p_details 
          WHERE id_row=errid AND err_cod=p_err_cod;
        END IF;
    ELSE
        INSERT INTO fonte.tadm_error_track (id_row, err_cod, state, details) 
        VALUES (errid, p_err_cod, p_state, p_details);
    END IF;
 
    UPDATE fonte.tadm_error_row 
    SET  kx_last_state_date = (SELECT max(state_date) FROM fonte.tadm_error_track WHERE id_row=errid), 
         kx_worst_state = (SELECT max(state) FROM fonte.tadm_error_track WHERE id_row=errid),
         kx_open_error_cods = (SELECT array_agg(err_cod) FROM fonte.tadm_error_track WHERE id_row=errid) -- and isopenstate(state)
    WHERE id=errid;
 
    RETURN errid;
END;
$$ LANGUAGE plpgsql;

  -- carga das fontes PARTE 1: tabelas g_lote, g_quadra e g_eixologr

  CREATE TABLE fonte.g_lote AS
  SELECT * FROM public.g_lote WHERE ST_NumGeometries(geom)=1 AND ST_IsSimple(geom) AND ST_IsValid(geom);
  -- fonte.g_lote -- ver lib.tadm_add_stdconstraints()
  ALTER TABLE fonte.g_lote ADD PRIMARY KEY (gid);
  ALTER TABLE fonte.g_lote ALTER COLUMN geom SET NOT NULL; 
  BEGIN
    SELECT max(gid) FROM fonte.g_lote INTO query_integer; --25911
    EXECUTE format( 'CREATE SEQUENCE fonte.g_lote_gid_seq START %1$s', query_integer );
  END;
  ALTER TABLE fonte.g_lote ALTER COLUMN gid SET DEFAULT nextval('fonte.g_lote_gid_seq'::regclass);
  ALTER TABLE fonte.g_lote ADD CONSTRAINT chk_dimcia CHECK ( st_ndims( geom ) = 2 AND ST_IsSimple( geom ) AND ST_IsValid( geom ) );
  ALTER TABLE fonte.g_lote ALTER COLUMN geom TYPE geometry(POLYGON) USING st_geometryn(geom, 1);
  ALTER TABLE fonte.g_lote ADD COLUMN kx_quadra_gid integer NOT NULL DEFAULT 0;
  ALTER TABLE fonte.g_lote ADD COLUMN kx_quadrasc_id integer NOT NULL DEFAULT 0;
  RAISE NOTICE '% Gerando índice em fonte.g_lote.', now();
  CREATE INDEX ON fonte.g_lote USING GIST( geom );
  RAISE NOTICE '% Índice concluído em fonte.g_lote.', now();
  
  CREATE TABLE fonte.g_quadra AS
  SELECT * FROM public.g_quadra WHERE ST_NumGeometries(geom)=1 AND ST_IsSimple(geom) AND ST_IsValid(geom);
  -- fonte.g_quadra -- ver lib.tadm_add_stdconstraints()
  ALTER TABLE fonte.g_quadra ADD PRIMARY KEY (gid);
  ALTER TABLE fonte.g_quadra ALTER COLUMN geom SET NOT NULL; 
  BEGIN
    SELECT max(gid) FROM fonte.g_quadra INTO query_integer;
    EXECUTE format( 'CREATE SEQUENCE fonte.g_quadra_gid_seq START %1$s', query_integer );
  END;
  ALTER TABLE fonte.g_quadra ALTER COLUMN gid SET DEFAULT nextval('fonte.g_quadra_gid_seq'::regclass);
  ALTER TABLE fonte.g_quadra ADD CONSTRAINT chk_dimcia CHECK (st_ndims(geom)=2 AND ST_IsSimple(geom) AND ST_IsValid(geom));
  ALTER TABLE fonte.g_quadra ALTER COLUMN geom TYPE geometry(POLYGON) USING st_geometryn(geom, 1);
  RAISE NOTICE '% Gerando índice em fonte.g_quadra.', now();
  CREATE INDEX ON fonte.g_quadra USING GIST( geom );
  RAISE NOTICE '% Índice concluído em fonte.g_quadra.', now();

  CREATE TABLE fonte.g_eixologr AS
  SELECT * FROM public.g_eixologr WHERE ST_NumGeometries(geom)=1 AND ST_IsSimple(geom) AND ST_IsValid(geom);
  -- -- --
  -- fonte.g_eixologr -- ver lib.tadm_add_stdconstraints()
  ALTER TABLE fonte.g_eixologr ADD PRIMARY KEY (gid);
  ALTER TABLE fonte.g_eixologr ALTER COLUMN geom SET NOT NULL;
  BEGIN
    SELECT max(gid) FROM fonte.g_eixologr INTO query_integer;
    EXECUTE format( 'CREATE SEQUENCE fonte.g_eixologr_gid_seq START %1$s', query_integer );
  END;
  ALTER TABLE fonte.g_eixologr ALTER COLUMN gid SET DEFAULT nextval('fonte.g_eixologr_gid_seq'::regclass);
  ALTER TABLE fonte.g_eixologr ADD CONSTRAINT chk_dimcia CHECK (st_ndims(geom)=2 AND ST_IsSimple(geom) AND ST_IsValid(geom));
  ALTER TABLE fonte.g_eixologr ALTER COLUMN geom TYPE geometry(linestring) USING st_geometryn(geom, 1);

-- ex. de pau:
--select  gid,ST_NumGeometries(geom),  st_area(st_geometryn(geom, 1)) as a1, st_area(st_geometryn(geom, 2)) as a2 
--from fonte.g_quadra where ST_NumGeometries(geom)>1;
-- gid=747;2;0.0294970074163704;4757.12811915715 .. poeira


INSERT INTO fonte.tadm_catalog(oid,prj_id,refresh_mode,geom_type, ref_isrural,ref_snapgrid,ref_pos_error,ref_min, validation_list) 
VALUES 
  ('fonte.g_lote'::regclass,     1, 0, 'POLYGON', false, 0.5, 1.0, 100.0, array[1,2,3]),
  ('fonte.g_quadra'::regclass,   1, 0, 'POLYGON', false, 1, 1.0, 100.0, array[1,2,3]),
  ('fonte.g_eixologr'::regclass, 1, 0, 'LINESTRING', false, 0.5, 1.0, 100.0, array[1,2,3]);

-- SELECT COUNT(DISTINCT kx_quadra_gid) as nquadras, COUNT(DISTINCT kx_quadrasc_id) as ngviz, 
--        COUNT(*) as nlotes 
-- FROM fonte.g_lote;

END
$DO$;