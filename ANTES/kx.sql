-- -- --
-- Inicializaçao do esquema KX (cache de tabelas)
-- Pode-se fazer DROP SCHEMA kx CASCADE a qualquer momento, depois refresh por esse script.
-- https://github.com/ppKrauss/georecipes_alegrete
-- -- --

SET statement_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;

BEGIN;
  DROP SCHEMA IF EXISTS kx CASCADE;
  CREATE SCHEMA kx;

  CREATE TABLE kx.eixologr_cod
  (
    gid bigint NOT NULL
  , cod bigint
  , tipo text
  , geom geometry
  , PRIMARY KEY ( gid )
  );
  CREATE INDEX ON kx.eixologr_cod USING GIST( geom );

  CREATE TABLE kx.lote_seg
  (
    gid integer
  , gid_lote integer
  , chave integer
  , gid_quadrasc integer
  , id_seg integer
  , id_via integer NOT NULL DEFAULT 0
  ,	isexterno boolean DEFAULT false -- a maioria é interno, exceto se fronteira com quadrasc
  , seg geometry -- TODO discover geometry type and srid
  , PRIMARY KEY ( gid )
  );
  CREATE INDEX ON kx.lote_seg USING GIST( seg );

  CREATE TABLE kx.lote_viz
  (
    id serial
  , a_gid integer
  , b_gid integer
  , viz_tipo float
  , relcod varchar
  , err varchar
  , PRIMARY KEY ( a_gid, b_gid )
  );

  CREATE TABLE kx.quadraccvia
  (
    gid integer NOT NULL
  , geom geometry
  , cod_vias integer[]
  , quadraccvia_gid bigint DEFAULT NULL
  , PRIMARY KEY ( gid )
  );
  COMMENT ON COLUMN kx.quadraccvia.quadraccvia_gid IS 'Atributo auxiliar do cache de quadras.';
  CREATE INDEX ON kx.quadraccvia USING GIST( geom );

  CREATE TABLE kx.quadraccvia_simplseg
  (
    gid integer
  , gid_quadra integer -- unica por construcao
  , id_seg integer
  , cod_vias integer
  , gid_via bigint DEFAULT NULL
  , tipo_via text DEFAULT NULL
  , gid_marginal bigint DEFAULT NULL  -- quando existor vizinha
  , cod integer DEFAULT NULL -- eleger código da via (marginal ou nao, nulo ou nao)
  , seg geometry
  , PRIMARY KEY ( gid )
  , UNIQUE ( gid_quadra )
  );
  CREATE INDEX ON kx.quadraccvia_simplseg USING GIST( seg );

  CREATE TABLE kx.quadrasc
  (
    gid integer
  , gid_lotes integer[]
  , err text DEFAULT NULL
  , quadraccvia_gid bigint DEFAULT NULL
  , geom geometry
  , PRIMARY KEY ( gid )
  );
  CREATE INDEX ON kx.quadrasc USING GIST( geom );

  CREATE TABLE kx.quadrasc_simplseg (
    gid integer
  , gid_quadrasc integer -- unica por construcao
  , quadra_gids integer--  quadras, pode ser mais de uma quando bug
  , id_seg integer
  , isexterno boolean DEFAULT NULL
  , isexterno_fator integer DEFAULT NULL
  , id_via integer DEFAULT NULL
  , seg geometry -- TODO discover type srid
  , PRIMARY KEY ( gid )
  , UNIQUE ( gid_quadrasc )
  );
  CREATE INDEX ON kx.quadrasc_simplseg USING GIST( seg );

  CREATE OR REPLACE VIEW kx.vw_lote_viz_err AS
    SELECT gid, array_to_string( array_agg( CASE WHEN gid = a_gid THEN b_gid ELSE a_gid END || ' ' || err ), '; ' ) AS err
    FROM (
      SELECT unnest( ARRAY[ a_gid, b_gid ] ) AS gid, a_gid, b_gid, err 
      FROM kx.lote_viz 
      WHERE err > '' AND viz_tipo = 0 
      ORDER BY 1
    ) AS t
    GROUP BY gid
    ORDER BY 1;
  -- Receita 008, obtenção de quadras a partir da malha viária:
  SELECT lib.r008a_quadra(); -- (receita A) demora alguns minutos
  -- roda a receita B
--  SELECT lib.r008b_seg(); -- (receita B) demora mais de 20 minutos

-- falta gerador de quadraccvia_simplface??

-- -- -- --
-- Receita 008, obtenção de quadra sem calçada e sua rotulação nos lotes:
-- http://gauss.serveftp.com/colabore/index.php?title=Prj:Geoprocessing_Recipes/R009
--select lib.kxrefresh_lote_viz();
  SELECT lib.kxrefresh_quadrasc( 1.0, 2, true, false, true ); -- demora ??
--SELECT lib.kxrefresh_quadrasc();
-- pode rodar com 
--   [19757] psql -U alegrete -h localhost -c "SELECT lib.r008b_seg(0.15,1.0);" &

---  ... select lib.r008_refresh_quadraccvia? mudou de nome?
  SELECT lib.kxrefresh_lote_seg();
  SELECT lib.kxrefresh_quadrasc( 1.0 );

/* complementos da funcao 008b incompleta: precisa testar e incluir na função devagar até fazer funcionar.

   -- 4. refazer por estatística o kx.quadraccvia.cod_vias... reunir segmentos para compor "face"
 
   -- 5. finalizacoes opcionais de quadraccvia:
   IF p_reduz>0.0 THEN 
     UPDATE kx.quadraccvia SET geom = ST_Buffer(geom, -1.0*p_reduz);  -- reduzir por último
     DELETE FROM kx.quadraccvia WHERE ST_Area(geom) <= p_area_min;    -- resíduos e poeiras
   END IF;
 
   -- 7. limpeza:
   ALTER TABLE kx.quadraccvia_simplseg DROP COLUMN cod_vias; -- remove cache inutil
   UPDATE kx.quadraccvia 
   SET cod_vias=t.vias  -- reduz em casos ambiguos (atencao item nulo em caso de mix de segmentos de cod nulo)
   FROM (
     SELECT c.gid, c.cod_vias, 
    	(SELECT array_agg(DISTINCT lib.r008_gidvia2cod(gid_via)) FROM kx.quadraccvia_simplseg s WHERE c.gid=s.gid_quadra) AS vias
     FROM kx.quadraccvia c
    ) t
   WHERE t.gid=quadraccvia.gid;
 
   -- 8. tabela de faces!
   DROP TABLE IF EXISTS kx.quadraccvia_simplface;
   CREATE TABLE kx.quadraccvia_simplface AS 
     SELECT gid_quadra, cod2 AS cod, max(id_seg), array_agg(gid) AS gids, ST_union(seg) AS seg
     FROM (SELECT *, lib.r008_gidvia2cod(gid_via) AS cod2 FROM kx.quadraccvia_simplseg) t
     GROUP BY gid_quadra, cod2;
   ALTER TABLE  kx.quadraccvia_simplface ADD CONSTRAINT uk UNIQUE (gid_quadra,cod);
 
   -- DROP TABLE kx.quadraccvia_simplseg (nao precisa mais!?)
 
   -- precisa? ALTER TABLE kx.quadrasc ADD column id_via_dist float;
 
   -- 9. classifica faces de quadrasc  
   UPDATE kx.quadrasc_simplseg SET id_via=NULL;
   UPDATE kx.quadrasc_simplseg
   SET id_via=codDist[1], id_via_dist=codDist[2]
   FROM (
      SELECT s.gid, lib.r008_assigncoddist(q.quadraccvia_gid,s.seg) AS codDist
      FROM kx.quadrasc_simplseg s INNER JOIN kx.quadrasc q ON q.gid=s.gid_quadrasc
   ) t
   WHERE t.gid = quadrasc_simplseg.gid;
 
**/

COMMIT;