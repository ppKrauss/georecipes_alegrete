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

-- -- -- --
-- Receita 008, obtenção de quadras a partir da malha viária:
-- http://gauss.serveftp.com/colabore/index.php?title=Prj:Geoprocessing_Recipes/R008
SELECT lib.r008a_quadra(); -- (receita A) demora alguns minutos
--  Tabela kx.eixologr_cod populada com 624 registros
--  Tabela kx.quadraccvia populada com 941 registros"

-- roda a receita B
SELECT lib.r008b_seg(); -- (receita B) demora mais de 20 minutos

-- falta gerador de quadraccvia_simplface??

-- -- -- --
-- Receita 008, obtenção de quadra sem calçada e sua rotulação nos lotes:
-- http://gauss.serveftp.com/colabore/index.php?title=Prj:Geoprocessing_Recipes/R009
SELECT lib.kxrefresh_quadrasc(); -- demora ??
-- pode rodar com 
--   [19757] psql -U alegrete -h localhost -c "SELECT lib.r008b_seg(0.15,1.0);" &

-- DEPOIS
---  ... select lib.r008_refresh_quadraccvia? mudou de nome?
--   ?psql -U alegrete -h localhost -c "SELECT lib.kxrefresh_lote_seg();" &
--   psql -U alegrete -h localhost -c "SELECT lib.kxrefresh_quadrasc(1.0);"  &

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

