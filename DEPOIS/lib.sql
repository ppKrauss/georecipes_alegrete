--
-- PostgreSQL database dump
--

SET statement_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;

--
-- Name: lib; Type: SCHEMA; Schema: -; Owner: alegrete
--

CREATE SCHEMA lib;


ALTER SCHEMA lib OWNER TO alegrete;

SET search_path = lib, pg_catalog;

--
-- Name: column_exists(character varying, character varying, character varying); Type: FUNCTION; Schema: lib; Owner: alegrete
--

CREATE FUNCTION column_exists(p_colname character varying, p_tname character varying, p_schema character varying DEFAULT 'public'::character varying) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    AS $_$
  SELECT n::int::boolean
  FROM (
     SELECT COUNT(*) as n FROM information_schema.COLUMNS 
     WHERE column_name=$1 AND table_schema=$3 AND table_name=$2
  ) AS t;
$_$;


ALTER FUNCTION lib.column_exists(p_colname character varying, p_tname character varying, p_schema character varying) OWNER TO alegrete;

--
-- Name: gidvia2codlogr(integer[]); Type: FUNCTION; Schema: lib; Owner: alegrete
--

CREATE FUNCTION gidvia2codlogr(integer[]) RETURNS integer[]
    LANGUAGE sql IMMUTABLE
    AS $_$
   SELECT array_agg(distinct codlogr)::int[] as codlogrs
   FROM fonte.g_eixologr WHERE gid = ANY ($1)
$_$;


ALTER FUNCTION lib.gidvia2codlogr(integer[]) OWNER TO alegrete;

--
-- Name: kxrefresh_lote_seg(boolean); Type: FUNCTION; Schema: lib; Owner: alegrete
--

CREATE FUNCTION kxrefresh_lote_seg(boolean DEFAULT true) RETURNS text
    LANGUAGE plpgsql
    AS $_$
   BEGIN
	IF ($1) THEN
		DROP TABLE IF EXISTS kx.lote_seg;
		CREATE TABLE kx.lote_seg AS 
		  WITH prepared_lotes AS (
		      SELECT gid, chave, gid_quadrasc, geom,
			generate_series(1, ST_NPoints(geom)-1) AS s_s,
			generate_series(2, ST_NPoints(geom)  ) AS s_e
		      FROM (
			  SELECT gid, chave, kx_quadrasc_id as gid_quadrasc,
				(ST_Dump(ST_Boundary(geom))).geom -- sem simplifcar
				-- (ST_Dump(ST_Boundary(ST_SimplifyPreserveTopology(geom,0.1)))).geom
		  	  FROM fonte.g_lote
		      ) AS linestrings
		  ) SELECT dense_rank() over (ORDER BY gid,s_s) AS gid,
			  gid AS gid_lote, chave, gid_quadrasc, s_s AS id_seg, 
			  0::int AS id_via, false AS isexterno, -- a maioria é interno, exceto se fronteira com quadrasc
			  false AS isfronteira, ST_MakeLine(sp,ep) AS seg
		    FROM (
		       SELECT *, ST_PointN(geom, s_s) AS sp, ST_PointN(geom, s_e) AS ep
		       FROM prepared_lotes
		    ) AS t; -- 89515 registros. Sem uso no idvia.
	ELSE
		UPDATE kx.lote_seg SET isexterno=false; -- default
	END IF; -- kx.lote_seg criada
 
	UPDATE kx.lote_seg -- demora mais de 5min (200seg)
	SET isexterno=t.isexterno, id_via=t.id_via, isfronteira=true
	FROM (
	  SELECT s.gid, q.isexterno, q.id_via
	  FROM kx.lote_seg s INNER JOIN kx.quadrasc_simplseg q 
	     ON s.gid_quadrasc=q.gid_quadrasc AND q.seg && s.seg 
	  WHERE ST_Length( ST_Intersection(s.seg,ST_Buffer(q.seg,1.5)) )/ST_Length(s.seg) > 0.6
	) AS t
	WHERE t.gid=lote_seg.gid;

	RETURN 'OK';
   END;
$_$;


ALTER FUNCTION lib.kxrefresh_lote_seg(boolean) OWNER TO alegrete;

--
-- Name: kxrefresh_lote_viz(double precision, double precision, boolean, boolean); Type: FUNCTION; Schema: lib; Owner: alegrete
--

CREATE FUNCTION kxrefresh_lote_viz(p_addprox double precision DEFAULT 1.5, p_areapoeira double precision DEFAULT 2.0, p_out_errsig boolean DEFAULT false, p_out_verbose boolean DEFAULT false) RETURNS text
    LANGUAGE plpgsql
    AS $_$
   DECLARE
     n integer;
     ret  text;
   BEGIN
 
   -- faltam IFs para CREATE SCHEMA errsig; CREATE SCHEMA kx;
   ret:='';
   DROP TABLE IF EXISTS  kx.lote_viz;
   CREATE TABLE kx.lote_viz (
             id SERIAL,
             a_gid int, b_gid int, viz_tipo float, 
             relcod varchar(12), err varchar(64),
             CONSTRAINT pk PRIMARY KEY (a_gid,b_gid)
   );
   ret:=ret||E'\n-- Criada a tabela kx.lote_viz';
   -- FALTARIA verificar se refresh já foi recentemente realizado e dependencias não foram atualizadas
   -- .. ai nao perde tempo atualizando denovo!
   DELETE FROM kx.lote_viz;
   INSERT INTO kx.lote_viz (a_gid, b_gid, viz_tipo, relcod, err)
     WITH suspeitos AS (
     SELECT a.gid AS a_gid, b.gid AS b_gid, 0 AS viz_tipo,  -- 53724 itens conferidos
            ST_Relate(a.geom,b.geom) AS relcod, 
            a.geom AS a_geom, b.geom AS b_geom  -- para usar no CASE 
     FROM fonte.g_lote a INNER JOIN  fonte.g_lote b 
          ON a.gid>b.gid  AND  a.geom && b.geom  -- AND  ST_Intersects(a.geom,b.geom)
     ) 
       SELECT a_gid, b_gid, viz_tipo, relcod, 
              CASE WHEN ovlp IS NULL OR ovlp[1]=0.0 THEN NULL  -- NEW: conferir se "OR" fez efeito
              ELSE
                 'overlaps-'|| to_char(ovlp[1],'FM09%') || iif(ovlp[2]>p_areapoeira,'; overlap-area-'||round(ovlp[2],1),'')
              END AS err
       FROM (
         SELECT a_gid, b_gid, viz_tipo, relcod,
              CASE WHEN relcod ~ '2121[01]1212'  -- st_overlaps(area,area)..., não seria apenas '212111212'?
                      THEN lib.ST_Overlaps_perc2(a_geom,b_geom)
                      ELSE NULL 
              END AS ovlp
         FROM suspeitos 
         WHERE relcod ~ '^((([012])....)|(.([012])...)|(...([012]).)|(....([012])))' -- st_intersects
       ) AS t;   -- 32913 inseridos 
   UPDATE kx.lote_viz SET err=NULL WHERE err='overlaps-00%'; -- cuidado se reformatar
   ret:=ret||E'\n-- Atualizada a tabela kx.lote_viz com vizinhos topologicos';
 
   IF ($1>0.0) THEN
      INSERT INTO kx.lote_viz (a_gid, b_gid, viz_tipo, err) 
        WITH pares AS (
           SELECT a.gid AS a_gid, b.gid AS b_gid
           FROM fonte.g_lote a INNER JOIN  fonte.g_lote b 
      	  ON a.gid>b.gid AND a.geom && b.geom AND ST_DWithin(a.geom,b.geom,$1)
        ) 
        SELECT p.a_gid, p.b_gid, $1 AS viz_tipo, 'disjoint' AS err
        FROM pares p LEFT JOIN  kx.lote_viz v 
             ON p.a_gid=v.a_gid AND p.b_gid=v.b_gid
        WHERE v.a_gid IS NULL;  -- elimina os já selecionados por viz_tipo=0
        -- 1142 inseridos 
      ret:=ret||E'\n-- Atualizada a tabela kx.lote_viz com vizinhos de distancia '||$1;
   END IF;
 
   CREATE OR REPLACE VIEW kx.vw_lote_viz_err AS -- vai usar só no final
     -- gid dos lotes com sobreposicao de mais de 1% ou mais de 2m2 de area sobrepostos
     SELECT gid, array_to_string(  array_agg(iif(gid=a_gid,b_gid,a_gid) || ' ' || err)  ,  '; ') AS err
     FROM (
       SELECT unnest(array[a_gid, b_gid]) AS gid, a_gid, b_gid, err 
       FROM kx.lote_viz 
       WHERE err>'' AND viz_tipo=0 
       ORDER BY 1
     ) AS t
     GROUP BY gid
     ORDER BY 1;
   ret:=ret||E'\n-- View kx.vw_lote_viz_err';
   SELECT COUNT(*) INTO n FROM kx.vw_lote_viz_err;
   IF p_out_errsig AND n>0 THEN 
      DROP TABLE IF EXISTS errsig.lote_sobreposto_lotes;
      CREATE TABLE errsig.lote_sobreposto_lotes AS 
          SELECT v.gid, v.err, f.geom 
          FROM kx.vw_lote_viz_err v INNER JOIN fonte.g_lote f ON f.gid=v.gid;
      ALTER TABLE errsig.lote_sobreposto_lotes ADD PRIMARY KEY (gid);
 
      DROP TABLE IF EXISTS errsig.lote_sobreposto_erros;
      CREATE TABLE errsig.lote_sobreposto_erros AS
          WITH pares AS (
            SELECT a.gid AS a_gid, b.gid AS b_gid, 0 AS viz_tipo,  
                   a.geom AS a_geom, b.geom AS b_geom
            FROM fonte.g_lote a INNER JOIN  fonte.g_lote b ON a.gid>b.gid
          ) 
          SELECT v.id AS gid, v.err, ST_Intersection(a_geom, b_geom) AS geom
          FROM kx.lote_viz v INNER JOIN pares p ON v.a_gid=p.a_gid AND v.b_gid=p.b_gid;
      ALTER TABLE errsig.lote_sobreposto_erros ADD PRIMARY KEY (gid);
      ret:=ret||E'\n-- ERROS encontrados, mostrando em errsig.lote_sobreposto_lotes errsig.lote_sobreposto_erros';
   ELSE 
       ret:=ret||E'\n-- SEM ERROS!';
   END IF;
   RETURN ret;
   END;
$_$;


ALTER FUNCTION lib.kxrefresh_lote_viz(p_addprox double precision, p_areapoeira double precision, p_out_errsig boolean, p_out_verbose boolean) OWNER TO alegrete;

--
-- Name: kxrefresh_quadrasc(double precision, integer, boolean, boolean, boolean, boolean, boolean); Type: FUNCTION; Schema: lib; Owner: alegrete
--

CREATE FUNCTION kxrefresh_quadrasc(p_distolviz double precision DEFAULT 1.0, p_alertrig integer DEFAULT 2, p_gerapol boolean DEFAULT true, p_redolote_viz boolean DEFAULT true, p_out_errsig boolean DEFAULT true, p_drop_lote_viz boolean DEFAULT false, p_listarvias boolean DEFAULT false) RETURNS text
    LANGUAGE plpgsql
    AS $$
   DECLARE
     aux int;
     ret text;
     p_addsolitarias BOOLEAN := TRUE; -- lotes isolados tb entram
   BEGIN
 
   IF p_redolote_viz THEN 
      SELECT lib.kxrefresh_lote_viz(p_distolviz,2.0,p_out_errsig) INTO ret; -- cria ou refaz kx.lote_viz e cia.
   END IF;
 
   ret:=ret||E'\n -- ... Rodando kxrefresh_quadrasc ...';
 
   -- rotulação: --
   DELETE FROM lib.trgr_labeler_in;
   INSERT INTO lib.trgr_labeler_in(id1,id2)
          SELECT a_gid, b_gid FROM kx.lote_viz;
   SELECT lib.trgr_labeler(p_alertrig) INTO aux;
   ret:=ret||E'\n -- Rotulação de lotes realizada, depois '||aux||' rotulos preliminares';
 
   UPDATE fonte.g_lote SET kx_quadrasc_id=0; -- nao pode ser null

   UPDATE fonte.g_lote SET kx_quadrasc_id=t.label
   FROM lib.trgr_labeler_out t 
   WHERE t.id=g_lote.gid;
   ret:=ret||E'\n -- Campo kx_quadrasc_id de fonte.g_lote atualizado com rotulos de quadra';
 
   IF (p_drop_lote_viz) THEN -- opcional
     DROP TABLE kx.lote_viz; -- já usou, mas pode querer usar com validações!
   END IF;
 
   IF p_gerapol THEN 
     -- geração dos polígonos de quadrasc: --
     DROP TABLE IF EXISTS kx.quadrasc;
     CREATE TABLE kx.quadrasc AS
       SELECT kx_quadrasc_id AS gid, 
              array_agg(gid) AS gid_lotes,  
              NULL::text AS err,
              NULL::integer[] AS gid_vias,
              array_agg(kx_quadra_gid) AS quadra_gids,
              ST_Buffer( ST_Union(ST_Buffer(geom,p_distolviz)), -p_distolviz) AS geom
       FROM fonte.g_lote
       WHERE kx_quadrasc_id >0
       GROUP BY kx_quadrasc_id;
     ALTER TABLE kx.quadrasc ADD PRIMARY KEY (gid);
     ret:=ret||E'\n -- tabela kx.quadrasc criada';
   END IF;

   IF p_addsolitarias THEN -- indiferente se correcao de buracos já realizada ou não
   -- incluindo quadras solitárias com gid diferenciado:
	INSERT INTO kx.quadrasc (gid,gid_lotes, quadra_gids, err, geom)
		SELECT t.gid0 + (row_number() OVER ()) as id,
		    array[gid], array[kx_quadra_gid], NULL, geom
		FROM fonte.g_lote, (SELECT 100*round((select max(gid) from kx.quadrasc)::float/100.0) + 200 AS gid0) t   
		WHERE st_area(geom)>1 AND gid NOT IN (
			SELECT unnest(gid_lotes) AS gid  FROM kx.quadrasc
		);  -- 60 rows (qq area seriam 227)
   END IF;

   -- remover daqui, sobrecarregando.
   IF p_listarvias THEN -- indiferente se correcao de buracos já realizada ou não
     UPDATE kx.quadrasc SET gid_vias=lib.r016_parallelroute_ofpolygon(geom,'fonte.g_eixologr') -- params default
     WHERE gid_vias IS NULL;
     ret:=ret||E'\n -- listas de vias paralelas criadas';
   END IF;

   RETURN ret;
   END;
$$;


ALTER FUNCTION lib.kxrefresh_quadrasc(p_distolviz double precision, p_alertrig integer, p_gerapol boolean, p_redolote_viz boolean, p_out_errsig boolean, p_drop_lote_viz boolean, p_listarvias boolean) OWNER TO alegrete;

--
-- Name: kxrefresh_quadrasc_aux(double precision, double precision, double precision, double precision, double precision); Type: FUNCTION; Schema: lib; Owner: alegrete
--

CREATE FUNCTION kxrefresh_quadrasc_aux(double precision DEFAULT 7.0, double precision DEFAULT (-4.5), double precision DEFAULT 4.0, double precision DEFAULT 0.2, double precision DEFAULT 2.0) RETURNS text
    LANGUAGE plpgsql
    AS $_$
   BEGIN
  -- 1. BuffDiff: annular strip da borda da quadra (tira em forma de anel)
  -- OLD: DROP TABLE IF EXISTS kx.quadra_buffdiff;

  -- 3. segmentação da quadrasc
  DROP TABLE IF EXISTS kx.quadrasc_simplseg;
  CREATE TABLE kx.quadrasc_simplseg AS 
    WITH prepared_quadras AS (  -- simplificando segmentos menores que 0.2m 
        SELECT gid, quadra_gids, geom,
    generate_series(1, ST_NPoints(geom)-1) AS s_s,
    generate_series(2, ST_NPoints(geom)  ) AS s_e
        FROM (SELECT gid, quadra_gids, (ST_Dump(ST_Boundary(ST_SimplifyPreserveTopology(geom,$4)))).geom
      FROM kx.quadrasc
        ) AS linestrings
    ) SELECT dense_rank() over (ORDER BY gid,s_s,s_e) AS gid,
       gid AS gid_quadrasc, -- unica por construcao
       quadra_gids, --  quadras, pode ser mais de uma quando bug
       s_s AS id_quadrasc_seg, -- id dentro da quadrasc
       NULL::BOOLEAN AS isexterno,
       NULL::integer AS isexterno_fator,
       NULL::integer AS id_via,
       ST_MakeLine(sp,ep) AS seg
      FROM (
         SELECT gid, quadra_gids, s_s, ST_PointN(geom, s_s) AS sp, ST_PointN(geom, s_e) AS ep, s_e
         FROM prepared_quadras
      ) AS t; -- 13373 (sem simplificação seriam dez vezes mais!)
  RETURN 'OK22';
  END;
$_$;


ALTER FUNCTION lib.kxrefresh_quadrasc_aux(double precision, double precision, double precision, double precision, double precision) OWNER TO alegrete;

--
-- Name: kxrefresh_quadrasc_auxbuffs(double precision, double precision, double precision, double precision, double precision); Type: FUNCTION; Schema: lib; Owner: alegrete
--

CREATE FUNCTION kxrefresh_quadrasc_auxbuffs(double precision DEFAULT 10.0, double precision DEFAULT (-4.0), double precision DEFAULT 4.0, double precision DEFAULT 0.2, double precision DEFAULT 2.0) RETURNS text
    LANGUAGE plpgsql
    AS $_$
   BEGIN
	-- 1. ok BuffDiff: annular strip da borda da quadra (tira em forma de anel)
	DROP TABLE IF EXISTS kx.quadra_buffdiff;
	CREATE TABLE kx.quadra_buffdiff AS 
	  SELECT gid, st_difference(st_buffer(geom,$1),st_buffer(geom,$2)) AS geom 
	  FROM fonte.g_quadra;
	ALTER TABLE kx.quadra_buffdiff ADD PRIMARY KEY (gid);
 
	-- 2. segmentação da quadrasc
	DROP TABLE IF EXISTS kx.quadrasc_simplseg;
	CREATE TABLE kx.quadrasc_simplseg AS 
	  WITH prepared_quadras AS (  -- simplificando segmentos menores que 0.2m 
	      SELECT gid, quadra_gid, geom,
		generate_series(1, ST_NPoints(geom)-1) AS s_s,
		generate_series(2, ST_NPoints(geom)  ) AS s_e
	      FROM (SELECT gid, quadra_gid, (ST_Dump(ST_Boundary(ST_SimplifyPreserveTopology(geom,$4)))).geom
		  FROM kx.quadrasc
	      ) AS linestrings
	  ) SELECT dense_rank() over (ORDER BY gid,s_s,s_e) AS gid,
		   gid AS gid_quadrasc, -- unica por construcao
		   quadra_gid, --  quadra em que esta contido
		   s_s AS id_seg, 
		   NULL::BOOLEAN AS isexterno,
		   NULL::integer AS isexterno_fator,
		   NULL::integer AS id_via,
		   ST_MakeLine(sp,ep) AS seg
	    FROM (
	       SELECT gid, quadra_gid, s_s, ST_PointN(geom, s_s) AS sp, ST_PointN(geom, s_e) AS ep, s_e
	       FROM prepared_quadras
	    ) AS t; -- 13373 (sem simplificação seriam dez vezes mais!)
	    

	-- 3.1 classificando como externo quem realmente está no perímetro da quadra real (quadra_buffdiff)
	UPDATE kx.quadrasc_simplseg
	SET isexterno=true
	WHERE gid IN (
	    SELECT k.gid
	    FROM kx.quadra_buffdiff b INNER JOIN kx.quadrasc_simplseg  k 
		 ON b.gid=k.quadra_gid AND k.seg && b.geom
	     WHERE isexterno IS NULL AND ST_Length(ST_Intersection(k.seg,b.geom))/ST_Length(k.seg)>0.35);
	DROP TABLE kx.quadra_buffdiff; -- descartar exceto para debug

	-- 3.2 classificando como interno quem realmente está bem no interiorzao
	UPDATE kx.quadrasc_simplseg
	SET isexterno=NULL --false
	WHERE gid IN (
	    SELECT k.gid
	    FROM (SELECT gid, st_buffer(geom,$2*0.8) as geom FROM fonte.g_quadra) b INNER JOIN kx.quadrasc_simplseg  k 
		 ON b.gid=k.quadra_gid AND k.seg && b.geom
	     WHERE  ST_Length(ST_Intersection(k.seg,b.geom))/ST_Length(k.seg)>0.51);

	RETURN 'OK-BASICO quadrasc_simplseg';
   END;
$_$;


ALTER FUNCTION lib.kxrefresh_quadrasc_auxbuffs(double precision, double precision, double precision, double precision, double precision) OWNER TO alegrete;

--
-- Name: r008_assigncoddist(bigint, public.geometry, double precision, double precision); Type: FUNCTION; Schema: lib; Owner: alegrete
--

CREATE FUNCTION r008_assigncoddist(p_gid_qcc bigint, p_geom public.geometry, p_raio double precision DEFAULT 25.0, p_step double precision DEFAULT 1.8) RETURNS text
    LANGUAGE plpgsql
    AS $$ 
DECLARE
   r     integer;
   v_len float;
   v_w   float;
   face RECORD;
BEGIN
   v_len = ST_Length(p_geom);
   FOR r IN 1 .. round(p_raio/p_step)::int LOOP
      v_w = r*p_step;
      FOR face IN SELECT ST_Buffer(seg,v_w) AS geom, cod   -- scan das faces
                 FROM kx.quadraccvia_simplface WHERE gid_quadra=p_gid_qcc  
      LOOP
          IF st_length(ST_Intersection(face.geom,p_geom))/v_len > 0.51 THEN
                RETURN array[face.cod,v_w];
          END IF;
      END LOOP;
   END LOOP;
   RETURN NULL;
END;
$$;


ALTER FUNCTION lib.r008_assigncoddist(p_gid_qcc bigint, p_geom public.geometry, p_raio double precision, p_step double precision) OWNER TO alegrete;

--
-- Name: r008_assigncods(bigint, double precision, double precision, double precision, double precision, double precision); Type: FUNCTION; Schema: lib; Owner: alegrete
--

CREATE FUNCTION r008_assigncods(p_gidccvia bigint, p_raio double precision DEFAULT 25.0, p_step double precision DEFAULT 1.6, p_cobertura double precision DEFAULT 0.6, p_tolerance double precision DEFAULT 1.0, p_cobertfracadd double precision DEFAULT 0.1) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
   v_geom geometry;
   v_qsc_list bigint[];
   v_n int;
   v_nrecord int;
   v_aux int;
   v_extcobert float := p_cobertura + p_cobertfracadd*(1.0-p_cobertura); -- cobertura externa precisa ser mais exigente
   v_numsteps int;
BEGIN
   SELECT array_agg(gid) INTO v_qsc_list FROM kx.quadrasc WHERE quadraccvia_gid=p_gidccvia;
   IF v_qsc_list IS NULL OR array_length(v_qsc_list,1)=0  THEN 
	RETURN 'ccvia '||p_gidccvia||' sem quadrasc interna'; 
   END IF;

   v_geom:= ST_Difference(
          (SELECT geom from kx.quadraccvia where gid=p_gidccvia), -- obstáculos reduzidnos por buffer
          (SELECT ST_Collect(ST_Buffer(geom,-0.6)) FROM kx.quadrasc WHERE quadraccvia_gid=p_gidccvia)
        ) as geom;

   -- Alimenta com segmentos de quadraCCvia:
   DROP TABLE  IF EXISTS kx.temp_r008a;  -- poderia ser delete e insert
   CREATE table kx.temp_r008a AS  -- segmentos de ccvia e suas "máscaras de crescimento frontal"
	   SELECT cod, -- código da via que circunda esta quadraccvia
	       ST_Intersection(v_geom, ST_buffer(seg,p_step,'endcap=flat join=bevel')  ) as geom,
	       ST_Intersection(v_geom, ST_buffer(seg,p_raio,'endcap=flat join=bevel')  ) as mask,
	       seg
	   FROM kx.quadraccvia_simplface
	   WHERE gid_quadra=p_gidccvia;
   --UPDATE kx.temp_r008a SET mask = ST_Buffer(mask,-0.5*p_step); -- isolamento da mascara

   UPDATE kx.quadrasc_simplseg    -- tem seg
   SET id_via=NULL, isexterno_fator=NULL, isexterno=NULL
   WHERE gid_quadrasc=ANY(v_qsc_list);
   v_nrecord=0;
   v_numsteps := round(p_raio/p_step)::int; -- só primeira metade do p_raio
   -- 1. Atribuição forçada na região definida como "exterior":
   FOR v_n IN 1..v_numsteps LOOP
	  -- scan dos segmentos que estão st_within() num dos kx.temp_r008a.geom
	  IF v_n<(v_numsteps+1)/2 THEN -- primeira metada NAO confere paralelismo
		   UPDATE kx.quadrasc_simplseg    -- (força externos) com máxima cobertura, SEM vrificação de paralelismo
		   SET id_via=t.cod, isexterno=true, isexterno_fator=t.dist::int
		   FROM (
			WITH lista AS (
			  SELECT k.gid, r.cod , lib.r017_avgdistline_(k.seg,r.seg) as dist,
			         ST_Length(ST_Intersection(k.seg,r.geom)) / ST_Length(k.seg) as c
			  FROM kx.temp_r008a r INNER JOIN kx.quadrasc_simplseg k 
			    ON k.id_via IS NULL AND k.gid_quadrasc=ANY(v_qsc_list) AND ST_Intersects(k.seg,r.geom)
			) SELECT l.* 
			  FROM lista l INNER JOIN (
			          SELECT gid, max(c) as maxc FROM lista WHERE c>=v_extcobert GROUP BY gid 
			       ) m ON l.gid=m.gid AND l.c=m.maxc
		   ) t WHERE quadrasc_simplseg.gid=t.gid;
		   
	   ELSE  -- confere paralelismo, ponderada por critérios de proximimidade e paralelismo
		   UPDATE kx.quadrasc_simplseg    -- tem seg
		   SET id_via=t.cod, isexterno_fator=t.dist[1]::int
		   FROM (
			WITH lista AS (
			  SELECT k.gid, r.cod, ST_Length(k.seg) as len, lib.r017_avgdistline_abs(k.seg,r.seg) as dist
			  FROM kx.temp_r008a r INNER JOIN kx.quadrasc_simplseg k 
			    ON k.id_via IS NULL AND coalesce(k.isexterno,true)!=false AND k.gid_quadrasc=ANY(v_qsc_list) AND ST_Intersects(k.seg,r.geom) AND
			       ST_Length(ST_Intersection(k.seg,r.geom)) / ST_Length(k.seg) >= p_cobertura 
			) SELECT l.* 
			  FROM lista l INNER JOIN (
				 SELECT gid, min(dist[1]) as mind FROM lista WHERE dist[2]<=p_tolerance GROUP BY gid
			       ) m  ON l.gid=m.gid AND l.dist[1]=m.mind
		   ) t WHERE quadrasc_simplseg.gid=t.gid AND t.dist[1]<p_raio AND t.len/t.dist[1]>0.1 AND t.dist[2]<p_tolerance;
   	   END IF;
	   v_nrecord:=v_nrecord+1; -- precisa de record pois v_n fica null depois do loop
	   
	   UPDATE kx.temp_r008a  -- increases buffer
	   SET geom = ST_Intersection( ST_Buffer(geom,p_step,'quad_segs=2'),  mask );
	   
	   --SELECT  array[count(*),count(id_via)] INTO v_aux FROM kx.quadrasc_simplseg WHERE gid_quadrasc=ANY(v_qsc_list);
	   -- IF v_aux[1]=v_aux[2] THEN EXIT; END IF;  -- sai do loop com contagens do retorno
	   SELECT count(*) INTO v_aux FROM kx.quadrasc_simplseg WHERE gid_quadrasc=ANY(v_qsc_list) AND id_via IS NULL;
	   IF v_aux=0 THEN EXIT; END IF;  -- sai do loop
   END LOOP;
  
   RETURN 'Encerrou com '||v_nrecord||' loops e sobra de '||v_aux||' segmentos.';
END;
$$;


ALTER FUNCTION lib.r008_assigncods(p_gidccvia bigint, p_raio double precision, p_step double precision, p_cobertura double precision, p_tolerance double precision, p_cobertfracadd double precision) OWNER TO alegrete;

--
-- Name: r008_err_exists(text); Type: FUNCTION; Schema: lib; Owner: alegrete
--

CREATE FUNCTION r008_err_exists(text) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    AS $_$  
   -- retorna interrompe processo ou retorna mensagem de count>0 sobre tabela
DECLARE
   v_n integer; -- counter
BEGIN
   IF lib.regclass_exists($1) THEN 
       EXECUTE ('SELECT count(*) FROM '|| $1) INTO v_n;
       IF v_n >0 THEN
           RETURN  E'\n Usando '|| v_n ||' registros de '||$1;
       ELSE  
           Raise Exception 'Preparar % não-vazio com lib.r008a_quadra()',$1;
       END IF;
   ELSE
       Raise Exception 'Falta criar % com lib.r008a_quadra()',$1;
   END IF;
END;
$_$;


ALTER FUNCTION lib.r008_err_exists(text) OWNER TO alegrete;

--
-- Name: r008_err_range(double precision, integer, double precision, double precision, text); Type: FUNCTION; Schema: lib; Owner: alegrete
--

CREATE FUNCTION r008_err_range(double precision, integer, double precision, double precision, text) RETURNS void
    LANGUAGE plpgsql IMMUTABLE
    AS $_$  
BEGIN
   IF $1<$3 OR $1>$4 THEN
        Raise Exception 'Parametro #% (=%), %, fora de intervalo seguro',$2,$1,$5;
   END IF;
END;
$_$;


ALTER FUNCTION lib.r008_err_range(double precision, integer, double precision, double precision, text) OWNER TO alegrete;

--
-- Name: r008_gidvia2cod(bigint); Type: FUNCTION; Schema: lib; Owner: alegrete
--

CREATE FUNCTION r008_gidvia2cod(bigint) RETURNS integer
    LANGUAGE sql IMMUTABLE
    AS $_$  
  SELECT cod FROM kx.eixologr_cod WHERE gid=$1 
$_$;


ALTER FUNCTION lib.r008_gidvia2cod(bigint) OWNER TO alegrete;

--
-- Name: r008_refresh_quadraccvia(double precision, double precision, double precision, double precision, double precision); Type: FUNCTION; Schema: lib; Owner: alegrete
--

CREATE FUNCTION r008_refresh_quadraccvia(p_width_via double precision DEFAULT 0.5, p_reduz double precision DEFAULT 0.5, p_area_min double precision DEFAULT 10.0, p_lendetect double precision DEFAULT 0.15, p_simplfactor double precision DEFAULT 0.2) RETURNS text
    LANGUAGE plpgsql
    AS $_$  -- retorna lista de gids
DECLARE
   v_msg text:=format('Parametros width_via=%s, reduz=%s, area_min=%s, lendet=%s, simplft=%s',$1,$2,$3,$4,$5);
BEGIN
   IF $1<0.0 OR $1>5.0 THEN
        Raise Exception 'Parametro #1 (=%), raio do buffer das vias, fora de intervalo seguro',$1;
   END IF;
   IF $2<0.0 OR $2>5.0 THEN
        Raise Exception 'Parametro #2 (=%), raio do buffer de redução, fora de intervalo seguro',$2;
   END IF;
   IF $3<0.001 OR $3>1000.0 THEN
        Raise Exception 'Parametro #3 (=%), area mínima da quadra, fora de intervalo seguro',$3;
   END IF;
 
   -- 1. PREPARO: divisores de quadracc, dado por "malha viária" completa e conexa
   DROP TABLE  IF EXISTS kx.eixologr_cod; -- TEMPORARY! Apagar logo depois de usar.
   CREATE TABLE kx.eixologr_cod AS -- todas as fronteiras de quadra e seus códigos 
     WITH vias AS (
   	(SELECT 0 AS gid, 	-- ## -- rodovias rotuladas, agregadas por código
   		codlogr AS cod,
   		'logr-ccod' AS tipo,  
   		array_agg(gid) AS gids,  -- para JOIN 
   		st_union(geom) AS geom   -- ou melhor st_collection? (ambos preservam buracos?)
   	 FROM fonte.g_eixologr
   	 WHERE codlogr>0 
   	 GROUP BY codlogr  -- agregação dos códigos em multilines (com buracos)
 
   	) UNION (      	 	-- ## -- rodovias não-rotuladas, individualizadas
   	 SELECT 0,
   		-1000-(row_number() OVER ()) AS cod, -- distinguivel 
   		'logr-scod' AS tipo,  
   		array[gid], -- para JOIN
   		geom 
   	 FROM fonte.g_eixologr
   	 WHERE codlogr=0 OR codlogr IS NULL
 
   	) UNION (       	-- ## -- ferrovias 
   	 SELECT 0,  
   		-10 AS cod, -- indistinguivel
   		'ferrovia' AS tipo,  
   		NULL,	    -- não faz JOIN
   	       ST_Collect(geom) AS geom 
   	 FROM public.g_ferrovia
 
   	) UNION (        	-- ## -- hidrovias
   	 SELECT 0,  
   		-100 AS cod, -- indistinguivel
   		'rio' AS tipo,  
   		NULL,	     -- não faz JOIN
   	       ST_Collect(geom) AS geom 
   	 FROM public.g_hidrografia_linha
   	)
      )  SELECT 	(row_number() OVER ()) AS gid, 
   			v.cod, tipo,
   			ST_Intersection(v.geom ,t.geom) AS geom 
         FROM vias v, (
   	       SELECT ST_setSRID( ST_Extent(geom), (SELECT ST_SRID(geom) FROM g_lote LIMIT 1) ) AS geom 
   	       FROM fonte.g_lote
   	   ) AS t;
   ALTER TABLE kx.eixologr_cod ADD PRIMARY KEY (gid);
   v_msg := v_msg || E'\n kx.eixologr_cod populada com '|| (SELECT count(*) FROM kx.eixologr_cod) ||' registros';
 
   -- 2. Construção principal: (old "quadracc_byvias")
   DROP TABLE  IF EXISTS kx.quadraccvia;
   CREATE TABLE kx.quadraccvia AS 
   SELECT (st_dump).path[1] AS gid, (st_dump).geom,
   	NULL::int[] AS cod_vias
   FROM (
        SELECT ST_Dump(ST_Polygonize(geom)) -- faz a magica
        FROM (SELECT ST_Union(geom) AS geom FROM kx.eixologr_cod) mergedlines
   ) polys;
   ALTER TABLE kx.quadraccvia ADD PRIMARY KEY (gid);
 
   DELETE FROM kx.quadraccvia WHERE ST_Area(geom)<=$3;
   v_msg := v_msg || E'\n Tabela kx.quadraccvia populada com '|| (SELECT count(*) FROM kx.quadraccvia) ||' registros';
 
   -- 3. lista códigos de via "condidatos" (para agilizar posterior scan):
   UPDATE kx.quadraccvia
    SET cod_vias=t.cods  -- temporário, precisa refazer depois com os segmentos
    FROM (
       SELECT q.gid, array_agg(e.cod) AS cods
       FROM kx.eixologr_cod e INNER JOIN kx.quadraccvia q 
                              -- old (SELECT *, ST_Buffer(geom,$4) as buff FROM kx.quadraccvia) q 
            ON e.geom && q.geom AND ST_Intersects(e.geom,q.geom)
       GROUP BY q.gid
    ) t
    WHERE t.gid=quadraccvia.gid;
 
    -- 4. segmentação da quadraccvia:
    DROP TABLE IF EXISTS kx.quadraccvia_simplseg;
    CREATE TABLE kx.quadraccvia_simplseg AS 
      WITH prepared_quadras AS (  -- simplificando segmentos menores que 0.2m 
          SELECT gid, cod_vias, geom,
    	generate_series(1, ST_NPoints(geom)-1) AS s_s,
    	generate_series(2, ST_NPoints(geom)  ) AS s_e
          FROM (SELECT gid, cod_vias, (ST_Dump(ST_Boundary(ST_SimplifyPreserveTopology(geom,p_simplfactor)))).geom
    	  FROM kx.quadraccvia
          ) AS linestrings
      ) SELECT dense_rank() over (ORDER BY gid,s_s,s_e) AS gid,
    	   gid AS gid_quadra, -- unica por construcao
    	   s_s AS id_seg,             cod_vias,
    	   NULL::bigint AS gid_via,   NULL::text AS tipo_via,
    	   NULL::bigint AS gid_marginal,  -- quando existor vizinha
    	   NULL::int AS cod,    -- eleger código da via (margil ou nao, nulo ou nao)
    	   ST_MakeLine(sp,ep) AS seg
        FROM (
           SELECT gid, cod_vias, s_s, ST_PointN(geom, s_s) AS sp, ST_PointN(geom, s_e) AS ep, s_e
           FROM prepared_quadras
        ) AS t;

  CREATE INDEX ON kx.quadraccvia_simplseg USING GIST(seg); -- IMPORTANTE!
 
   -- 5. Encontrando a via (cod) associada a cada segmento:
   UPDATE kx.quadraccvia_simplseg
      SET gid_via=t.egid, cod=t.cod, tipo_via=t.tipo
   FROM (
      SELECT s.gid AS sgid, e.gid AS egid, e.cod, e.tipo
      FROM kx.quadraccvia_simplseg s INNER JOIN (SELECT *, ST_Buffer(geom,1.5) AS buff FROM kx.eixologr_cod) e 
           ON e.cod=ANY(s.cod_vias) AND e.buff && s.seg AND ST_Intersects(e.buff,s.seg) 
              AND ST_Length(ST_Intersection(s.seg,e.buff))/ST_Length(s.seg)>0.4
   ) t 
   WHERE t.sgid=quadraccvia_simplseg.gid;
   -- 5.2 encontra marginal se houver
 
   -- 6. refazer por estatística o kx.quadraccvia.cod_vias... reunir segmentos para compor "face"
 
   RETURN v_msg;
END;
$_$;


ALTER FUNCTION lib.r008_refresh_quadraccvia(p_width_via double precision, p_reduz double precision, p_area_min double precision, p_lendetect double precision, p_simplfactor double precision) OWNER TO alegrete;

--
-- Name: r008a_quadra(double precision, double precision, double precision, double precision); Type: FUNCTION; Schema: lib; Owner: alegrete
--

CREATE FUNCTION r008a_quadra(p_width_via double precision DEFAULT 0.5, p_reduz double precision DEFAULT 0.5, p_area_min double precision DEFAULT 10.0, p_lendetect double precision DEFAULT 0.15) RETURNS text
    LANGUAGE plpgsql
    AS $_$  -- retorna lista de gids
DECLARE
  v_msg    text:=format('Parametros width_via=%s, reduz=%s, area_min=%s',$1,$2,$3); -- mensagens de retorno
BEGIN
   PERFORM lib.r008_err_range($1, 1, 0.0,   5.0,    'meia largura da via');
   PERFORM lib.r008_err_range($2, 2, 0.0,   5.0,    'raio do buffer de redução');
   PERFORM lib.r008_err_range($3, 3, 0.001, 1000.0, 'area mínima da quadra');
   PERFORM lib.r008_err_range($4, 4, 0.001, 2.0,    'comprimento para detectar via como parte');

   -- 1. PREPARO: divisores de quadracc, dado por "malha viária" completa e conexa
   DROP TABLE  IF EXISTS kx.eixologr_cod;
   CREATE TABLE kx.eixologr_cod AS -- todas as fronteiras de quadra e seus códigos 
     WITH vias AS (
   	(SELECT 0 AS gid, 	-- ## -- rodovias rotuladas, agregadas por código
   		codlogr::integer AS cod,
   		'logr-ccod' AS tipo,  
   		array_agg(gid) AS gids,  -- para JOIN 
   		st_union(geom) AS geom   -- ou melhor st_collection? (ambos preservam buracos?)
   	 FROM fonte.g_eixologr
   	 WHERE codlogr>0 
   	 GROUP BY codlogr  -- agregação dos códigos em multilines (com buracos)
 
   	) UNION (      	 	-- ## -- rodovias não-rotuladas, individualizadas
   	 SELECT 0,
   		-1000-(row_number() OVER ()) AS cod, -- distinguivel 
   		'logr-scod' AS tipo,  
   		array[gid], -- para JOIN
   		geom 
   	 FROM fonte.g_eixologr
   	 WHERE codlogr=0 OR codlogr IS NULL
 
   	) UNION (       	-- ## -- ferrovias 
   	 SELECT 0,  
   		-10 AS cod, -- indistinguivel
   		'ferrovia' AS tipo,  
   		NULL,	    -- não faz JOIN
   	       ST_Collect(geom) AS geom 
   	 FROM public.g_ferrovia
 
   	) UNION (        	-- ## -- hidrovias
   	 SELECT 0,  
   		-100 AS cod, -- indistinguivel
   		'rio' AS tipo,  
   		NULL,	     -- não faz JOIN
   	       ST_Collect(geom) AS geom 
   	 FROM public.g_hidrografia_linha
   	)
      )  SELECT 	(row_number() OVER ()) AS gid, 
   			v.cod, tipo,
   			ST_Intersection(v.geom ,t.geom) AS geom 
         FROM vias v, (
   	       SELECT ST_setSRID( ST_Extent(geom), (SELECT ST_SRID(geom) FROM g_lote LIMIT 1) ) AS geom 
   	       FROM fonte.g_lote
   	   ) AS t;
   ALTER TABLE kx.eixologr_cod ADD PRIMARY KEY (gid);
   v_msg := v_msg || E'\n kx.eixologr_cod populada com '|| (SELECT count(*) FROM kx.eixologr_cod) ||' registros';

   -- 2. Construção principal: (old "quadracc_byvias")
   DROP TABLE  IF EXISTS kx.quadraccvia;
   CREATE TABLE kx.quadraccvia AS 
   SELECT (st_dump).path[1] AS gid, (st_dump).geom,
   	NULL::int[] AS cod_vias
   FROM (
        SELECT ST_Dump(ST_Polygonize(geom)) -- faz a magica
        FROM (SELECT ST_Union(geom) AS geom FROM kx.eixologr_cod) mergedlines
   ) polys;
   ALTER TABLE kx.quadraccvia ADD PRIMARY KEY (gid);
   
   -- 3. Obtenção dos códigos das vias de entorno, e redução dos polígnos:
   UPDATE kx.quadraccvia
    SET cod_vias=t.cods,
        geom = ST_Difference(quadraccvia.geom,t.geom)
    FROM (
       SELECT q.gid, array_agg(e.cod) AS cods, ST_Buffer(ST_Union(e.geom),$1) AS geom
       FROM kx.eixologr_cod e INNER JOIN (SELECT *, ST_Buffer(geom,$4) as buff FROM kx.quadraccvia) q 
            ON e.geom && q.geom AND ST_Intersects(e.geom,q.geom)
    	       AND ST_Length(ST_Intersection(q.buff,e.geom)) > 4.0*$4 -- elimina vizinhos e poeiras
       GROUP BY q.gid
    ) t
    WHERE t.gid=quadraccvia.gid;
   IF ($2>0.0) THEN 
       UPDATE kx.quadraccvia SET geom = ST_Buffer(geom, -1.0*$2); -- aplicar geral
   END IF;
   IF ($3>0.0) THEN 
       DELETE FROM kx.quadraccvia WHERE ST_Area(geom)<=$3;
   END IF;
   v_msg := v_msg || E'\n Tabela kx.quadraccvia populada com '|| (SELECT count(*) FROM kx.quadraccvia) ||' registros';
    
   RETURN v_msg;
END;
$_$;


ALTER FUNCTION lib.r008a_quadra(p_width_via double precision, p_reduz double precision, p_area_min double precision, p_lendetect double precision) OWNER TO alegrete;

--
-- Name: r008b_seg(double precision, double precision, double precision, double precision, double precision); Type: FUNCTION; Schema: lib; Owner: alegrete
--

CREATE FUNCTION r008b_seg(p_width_via double precision DEFAULT 0.5, p_reduz double precision DEFAULT 0.5, p_area_min double precision DEFAULT 10.0, p_cobertura double precision DEFAULT 0.51, p_simplfactor double precision DEFAULT 0.2) RETURNS text
    LANGUAGE plpgsql
    AS $_$  -- retorna mensagem de erro
DECLARE
   v_msg text := format('Parametros width_via=%s, reduz=%s, area_min=%s, cobertura=%s, simplft=%s',$1,$2,$3,$4,$5);
BEGIN
   PERFORM lib.r008_err_range($1, 1, 0.0, 5.0,    'largura da via');
   PERFORM lib.r008_err_range($2, 2, 0.0, 5.0,    'raio do buffer de redução');
   PERFORM lib.r008_err_range($3, 3, 0.0, 1000.0, 'area mínima da quadra');
   PERFORM lib.r008_err_range($4, 4, 0.001, 1.0, 'fator de cobertura mínima');
   PERFORM lib.r008_err_range($5, 5, 0.0, 10.0, 'step na simplificação dos segmentos');
   v_msg := v_msg || lib.r008_err_exists('kx.eixologr_cod');
   v_msg := v_msg || lib.r008_err_exists('kx.quadraccvia');
 
   -- 1. segmentação da quadraccvia:
   DROP TABLE IF EXISTS kx.quadraccvia_simplseg;
   CREATE TABLE kx.quadraccvia_simplseg AS 
      WITH prepared_quadras AS (  -- simplificando segmentos menores que 0.2m 
          SELECT gid, cod_vias, geom,
    	generate_series(1, ST_NPoints(geom)-1) AS s_s,
    	generate_series(2, ST_NPoints(geom)  ) AS s_e
          FROM (SELECT gid, cod_vias, (ST_Dump(ST_Boundary(ST_SimplifyPreserveTopology(geom,p_simplfactor)))).geom
    	  FROM kx.quadraccvia
          ) AS linestrings
      ) SELECT dense_rank() over (ORDER BY gid,s_s,s_e) AS gid,
    	   gid AS gid_quadra, -- unica por construcao
    	   s_s AS id_seg,             cod_vias,
    	   NULL::bigint AS gid_via,   NULL::text AS tipo_via,
    	   NULL::bigint AS gid_marginal,  -- quando existor vizinha
    	   NULL::int AS cod,    -- eleger código da via (marginal ou nao, nulo ou nao)
    	   ST_MakeLine(sp,ep) AS seg
        FROM (
           SELECT gid, cod_vias, s_s, ST_PointN(geom, s_s) AS sp, ST_PointN(geom, s_e) AS ep, s_e
           FROM prepared_quadras
        ) AS t;
 
   -- 2. Encontrando a via (cod) associada a cada segmento:
   UPDATE kx.quadraccvia_simplseg
      SET gid_via=t.egid, cod=t.cod, tipo_via=t.tipo
   FROM (
      SELECT s.gid AS sgid, e.gid AS egid, e.cod, e.tipo
      FROM kx.quadraccvia_simplseg s INNER JOIN (SELECT *, ST_Buffer(geom,2*$1) AS buff FROM kx.eixologr_cod) e 
           ON e.cod=ANY(s.cod_vias) AND e.buff && s.seg AND ST_Intersects(e.buff,s.seg) 
              AND ST_Length(ST_Intersection(s.seg,e.buff))/ST_Length(s.seg) > p_cobertura
   ) t 
   WHERE t.sgid=quadraccvia_simplseg.gid;
   -- 3.2 encontra marginal se houver
 
   -- 4. refazer por estatística o kx.quadraccvia.cod_vias... reunir segmentos para compor "face"
 
   -- 5. finalizacoes opcionais de quadraccvia:
   IF p_reduz>0.0 THEN 
     UPDATE kx.quadraccvia SET geom = ST_Buffer(geom, -1.0*p_reduz);  -- reduzir por último
     DELETE FROM kx.quadraccvia WHERE ST_Area(geom) <= p_area_min;    -- resíduos e poeiras
   END IF;
   RETURN v_msg;
END;
$_$;


ALTER FUNCTION lib.r008b_seg(p_width_via double precision, p_reduz double precision, p_area_min double precision, p_cobertura double precision, p_simplfactor double precision) OWNER TO alegrete;

--
-- Name: r017_avgdistline(public.geometry, public.geometry, integer); Type: FUNCTION; Schema: lib; Owner: alegrete
--

CREATE FUNCTION r017_avgdistline(p_seggeom public.geometry, p_refgeom public.geometry, p_npoints integer DEFAULT 5) RETURNS double precision[]
    LANGUAGE sql IMMUTABLE
    AS $_$ 
	SELECT array[Avg(d), Stddev_samp(d)] -- Stddev_pop() seria para amostragem completa
	FROM (SELECT unnest(lib.r017_distsline($1,$2,$3)) AS d) t;
$_$;


ALTER FUNCTION lib.r017_avgdistline(p_seggeom public.geometry, p_refgeom public.geometry, p_npoints integer) OWNER TO alegrete;

--
-- Name: r017_avgdistline_(public.geometry, public.geometry, integer); Type: FUNCTION; Schema: lib; Owner: alegrete
--

CREATE FUNCTION r017_avgdistline_(p_seggeom public.geometry, p_refgeom public.geometry, p_npoints integer DEFAULT 5) RETURNS double precision
    LANGUAGE sql IMMUTABLE
    AS $_$ 
	SELECT Avg(d)
	FROM (SELECT unnest(lib.r017_distsline($1,$2,$3)) as d) t;
$_$;


ALTER FUNCTION lib.r017_avgdistline_(p_seggeom public.geometry, p_refgeom public.geometry, p_npoints integer) OWNER TO alegrete;

--
-- Name: r017_avgdistline_abs(public.geometry, public.geometry, integer); Type: FUNCTION; Schema: lib; Owner: alegrete
--

CREATE FUNCTION r017_avgdistline_abs(p_seggeom public.geometry, p_refgeom public.geometry, p_npoints integer DEFAULT 5) RETURNS double precision[]
    LANGUAGE sql IMMUTABLE
    AS $_$ 
        WITH dists AS (SELECT unnest(lib.r017_distsline($1,$2,$3)) AS d)
	 SELECT array[ v, (SELECT Avg(Abs(v-d)) FROM dists) ]
         FROM (SELECT Avg(d) AS v FROM dists) t;
$_$;


ALTER FUNCTION lib.r017_avgdistline_abs(p_seggeom public.geometry, p_refgeom public.geometry, p_npoints integer) OWNER TO alegrete;

--
-- Name: r017_distsline(public.geometry, public.geometry, double precision[]); Type: FUNCTION; Schema: lib; Owner: alegrete
--

CREATE FUNCTION r017_distsline(p_seggeom public.geometry, p_refgeom public.geometry, p_frac double precision[]) RETURNS double precision[]
    LANGUAGE sql IMMUTABLE
    AS $_$ 
	SELECT array_agg( ST_Distance(ST_Line_Interpolate_Point($1,f),$2) ) 
	FROM (SELECT unnest($3) AS f) t;
$_$;


ALTER FUNCTION lib.r017_distsline(p_seggeom public.geometry, p_refgeom public.geometry, p_frac double precision[]) OWNER TO alegrete;

--
-- Name: r017_distsline(public.geometry, public.geometry, integer); Type: FUNCTION; Schema: lib; Owner: alegrete
--

CREATE FUNCTION r017_distsline(p_seggeom public.geometry, p_refgeom public.geometry, p_npoints integer DEFAULT 5) RETURNS double precision[]
    LANGUAGE sql IMMUTABLE
    AS $_$  
	SELECT CASE 
	      WHEN $3 IS NULL OR $3<=1 THEN array[
		ST_Distance(ST_Line_Interpolate_Point($1,0.5),$2)
		]
	      WHEN $3=2 THEN lib.r017_distsline($1,$2,array[0.333, 0.666])
	      WHEN $3=3 THEN lib.r017_distsline($1,$2,array[0.0, 0.5, 1.0])
	      WHEN $3=4 THEN lib.r017_distsline($1,$2,array[0.0, 0.33, 0.66, 1.0])
	      WHEN $3=5 THEN array[
		ST_Distance(ST_Line_Interpolate_Point($1,0.0),$2),
		ST_Distance(ST_Line_Interpolate_Point($1,0.25),$2),
		ST_Distance(ST_Line_Interpolate_Point($1,0.5),$2),
		ST_Distance(ST_Line_Interpolate_Point($1,0.75),$2),
		ST_Distance(ST_Line_Interpolate_Point($1,1.0),$2)
		]
	      ELSE lib.r017_distsline($1,$2,array[0.0, 0.2, 0.4, 0.6, 0.8, 1.0])
	END;
$_$;


ALTER FUNCTION lib.r017_distsline(p_seggeom public.geometry, p_refgeom public.geometry, p_npoints integer) OWNER TO alegrete;

--
-- Name: regclass_exists(character varying); Type: FUNCTION; Schema: lib; Owner: alegrete
--

CREATE FUNCTION regclass_exists(p_tname character varying) RETURNS boolean
    LANGUAGE plpgsql IMMUTABLE
    AS $$
   -- verifica se uma tabela existe
DECLARE
  tmp regclass;
BEGIN
	tmp := p_tname::regclass; -- do nothing, only parsing regclass
	RETURN true;
        EXCEPTION WHEN SQLSTATE '3F000' THEN
	RETURN false;
END;
$$;


ALTER FUNCTION lib.regclass_exists(p_tname character varying) OWNER TO alegrete;

--
-- Name: shapedescr_sizes(public.geometry, integer, double precision, double precision); Type: FUNCTION; Schema: lib; Owner: alegrete
--

CREATE FUNCTION shapedescr_sizes(gbase public.geometry, p_decplacesof_zero integer DEFAULT 6, p_dwmin double precision DEFAULT 99999999.0, p_deltaimpact double precision DEFAULT 9999.0) RETURNS double precision[]
    LANGUAGE plpgsql IMMUTABLE
    AS $$
  DECLARE
    ret float[];
    dw float;
    b float;
    L_estim float;
    H_estim float;
    aorig float;
    gaux geometry;
    g1 geometry;
    A0 float;
    A1 float;
    c float;
    delta float;
    per float;
    errcod float;
  BEGIN
    errcod=0.0;
    IF gbase IS NULL OR NOT(ST_IsClosed(gbase)) THEN
        errcod=1;                  -- ERROR1 (die)
        RAISE EXCEPTION 'error %: invalid input geometry',errcod;
    END IF;
    A0 := ST_Area(gbase);
    per := st_perimeter(gbase);
    dw := sqrt(A0)/p_deltaimpact;
    IF dw>p_dwmin THEN dw:=p_dwmin; END IF;
    g1 = ST_Buffer(gbase,dw);
    A1 = ST_area(g1);
    IF A0>A1 THEN 
        errcod=10;                 -- ERROR2 (die)
        RAISE EXCEPTION 'error %: invalid buffer/geometry with A0=% g.t. A1=%',errcod,A0,A1;
    END IF;
    IF (A1-A0)>1.001*dw*per THEN 
        gaux := ST_Buffer(g1,-dw);  -- closing operation.
        A0 = ST_Area(gaux);         -- changed area
        per := ST_Perimeter(gaux);  -- changed
        errcod:=errcod + 0.1;       -- Warning3
    END IF;
    C := 2.0*dw;
    b := -(A1-A0)/C+C;
    delta := b^2-4.0*A0;
    IF delta<0.0 AND round(delta,p_decplacesof_zero)<=0.0 THEN
           delta=0.0; -- for regular shapes like the square
           errcod:=errcod + 0.01;  -- Warning2
    END IF;
    IF delta<0.0 THEN
        L_estim := NULL; 
        H_estim := NULL;
        errcod:=errcod+100;        -- ERROR3
    ELSE
        L_estim := (-b + sqrt(delta))/2.0; 
        H_estim := (-b - sqrt(delta))/2.0;
    END IF;
    IF abs(A0-L_estim*H_estim)>0.001 THEN 
        errcod:=errcod + 0.001;    -- Warning1
    END IF;
    ret := array[L_estim,H_estim,a0,per,dw,errcod];
    return ret;
  END
$$;


ALTER FUNCTION lib.shapedescr_sizes(gbase public.geometry, p_decplacesof_zero integer, p_dwmin double precision, p_deltaimpact double precision) OWNER TO alegrete;

--
-- Name: shapedescr_sizes_tr(double precision[], integer, integer); Type: FUNCTION; Schema: lib; Owner: alegrete
--

CREATE FUNCTION shapedescr_sizes_tr(double precision[], integer DEFAULT 0, integer DEFAULT 3) RETURNS character varying[]
    LANGUAGE sql IMMUTABLE
    AS $_$
   SELECT array[
      round(L,$2+1)::varchar, round(H,$2+1)::varchar, round(area,$2)::varchar,
      round(perim,$2+1)::varchar, round(dw,$2+3)::varchar,
      round(sqrt(L*H/pi()),$2+1)::varchar,  -- radius for "shape as circle" 
      CASE WHEN errcod>3.0 THEN 'ERROR '  ||round(errcod-$3) 
           WHEN errcod>0.0  THEN 'WARNING '||round(errcod)||CASE
                   WHEN round(10^(-errcod),$3-1)!=($1)[6] THEN '.'|| ($1)[6]*10^$3
                   ELSE ''
		END
           ELSE '' 
      END::varchar
   ]
   FROM (
        SELECT ($1)[1] as L, ($1)[2] as H, ($1)[3] as area, ($1)[4] as perim, 
               ($1)[5] as dw, log(($1)[6]*10.0^($3+1)+1.0) as errcod
   ) as t; 
$_$;


ALTER FUNCTION lib.shapedescr_sizes_tr(double precision[], integer, integer) OWNER TO alegrete;

--
-- Name: shapedescr_sizes_tr(public.geometry, integer, integer); Type: FUNCTION; Schema: lib; Owner: alegrete
--

CREATE FUNCTION shapedescr_sizes_tr(public.geometry, integer DEFAULT 0, integer DEFAULT 3) RETURNS character varying[]
    LANGUAGE sql IMMUTABLE
    AS $_$
   SELECT lib.shapedescr_sizes_tr(lib.shapedescr_sizes($1),$2,$3);
$_$;


ALTER FUNCTION lib.shapedescr_sizes_tr(public.geometry, integer, integer) OWNER TO alegrete;

--
-- Name: st_avgdist_line(public.geometry, public.geometry); Type: FUNCTION; Schema: lib; Owner: alegrete
--

CREATE FUNCTION st_avgdist_line(p_seggeom public.geometry, p_refgeom public.geometry) RETURNS double precision
    LANGUAGE sql IMMUTABLE
    AS $_$  
  SELECT ( ST_Distance(ST_Line_Interpolate_Point($1,0.0),$2)
	  + ST_Distance(ST_Line_Interpolate_Point($1,0.25),$2) 
	  + ST_Distance(ST_Line_Interpolate_Point($1,0.5),$2)
	  + ST_Distance(ST_Line_Interpolate_Point($1,0.75),$2) 
	  + ST_Distance(ST_Line_Interpolate_Point($1,1.0),$2) 
	)/5.0
$_$;


ALTER FUNCTION lib.st_avgdist_line(p_seggeom public.geometry, p_refgeom public.geometry) OWNER TO alegrete;

--
-- Name: st_avgdistline(public.geometry, public.geometry, integer); Type: FUNCTION; Schema: lib; Owner: alegrete
--

CREATE FUNCTION st_avgdistline(p_seggeom public.geometry, p_refgeom public.geometry, p_npoints integer DEFAULT 5) RETURNS double precision[]
    LANGUAGE sql IMMUTABLE
    AS $_$ 
	SELECT array[Avg(d), Stddev_samp(d)] -- Stddev_pop() seria para amostragem completa
	FROM (SELECT unnest(lib.st_distsline($1,$2,$3)) as d) t;
$_$;


ALTER FUNCTION lib.st_avgdistline(p_seggeom public.geometry, p_refgeom public.geometry, p_npoints integer) OWNER TO alegrete;

--
-- Name: st_avgdistline(public.geometry, public.geometry, double precision[]); Type: FUNCTION; Schema: lib; Owner: alegrete
--

CREATE FUNCTION st_avgdistline(p_seggeom public.geometry, p_refgeom public.geometry, p_frac double precision[]) RETURNS double precision[]
    LANGUAGE sql IMMUTABLE
    AS $_$ 
	SELECT array[Avg(d), Stddev_pop(d)]
	FROM (SELECT unnest(lib.st_distsline($1,$2,$3)) as d) t;
$_$;


ALTER FUNCTION lib.st_avgdistline(p_seggeom public.geometry, p_refgeom public.geometry, p_frac double precision[]) OWNER TO alegrete;

--
-- Name: st_distsline(public.geometry, public.geometry, double precision[]); Type: FUNCTION; Schema: lib; Owner: alegrete
--

CREATE FUNCTION st_distsline(p_seggeom public.geometry, p_refgeom public.geometry, p_frac double precision[]) RETURNS double precision[]
    LANGUAGE sql IMMUTABLE
    AS $_$ 
	SELECT array_agg( ST_Distance(ST_Line_Interpolate_Point($1,f),$2) ) 
	FROM (SELECT unnest($3) as f) t;
$_$;


ALTER FUNCTION lib.st_distsline(p_seggeom public.geometry, p_refgeom public.geometry, p_frac double precision[]) OWNER TO alegrete;

--
-- Name: st_distsline(public.geometry, public.geometry, integer); Type: FUNCTION; Schema: lib; Owner: alegrete
--

CREATE FUNCTION st_distsline(p_seggeom public.geometry, p_refgeom public.geometry, p_npoints integer DEFAULT 5) RETURNS double precision[]
    LANGUAGE sql IMMUTABLE
    AS $_$  
	SELECT CASE 
	      WHEN $3 IS NULL OR $3<=1 THEN array[
		ST_Distance(ST_Line_Interpolate_Point($1,0.5),$2)
		]
	      WHEN $3=2 THEN lib.st_distsline($1,$2,array[0.333, 0.666])
	      WHEN $3=3 THEN lib.st_distsline($1,$2,array[0.0, 0.5, 1.0])
	      WHEN $3=4 THEN lib.st_distsline($1,$2,array[0.0, 0.33, 0.66, 1.0])
	      WHEN $3=5 THEN array[
		ST_Distance(ST_Line_Interpolate_Point($1,0.0),$2),
		ST_Distance(ST_Line_Interpolate_Point($1,0.25),$2),
		ST_Distance(ST_Line_Interpolate_Point($1,0.5),$2),
		ST_Distance(ST_Line_Interpolate_Point($1,0.75),$2),
		ST_Distance(ST_Line_Interpolate_Point($1,1.0),$2)
		]
	      ELSE lib.st_distsline($1,$2,array[0.0, 0.2, 0.4, 0.6, 0.8, 1.0])
	END;
$_$;


ALTER FUNCTION lib.st_distsline(p_seggeom public.geometry, p_refgeom public.geometry, p_npoints integer) OWNER TO alegrete;

--
-- Name: st_lineoverlaps_perc(public.geometry, public.geometry, double precision, double precision); Type: FUNCTION; Schema: lib; Owner: alegrete
--

CREATE FUNCTION st_lineoverlaps_perc(p_geom_line public.geometry, p_geom_poly public.geometry, p_bufradius double precision DEFAULT 1.0, p_factor double precision DEFAULT 100.0) RETURNS double precision
    LANGUAGE sql IMMUTABLE
    AS $_$
   SELECT $4*( lib.shapedescr_sizes(ST_Intersection(ST_Buffer($1,$3),$2)) )[1] / ST_Length($1);
$_$;


ALTER FUNCTION lib.st_lineoverlaps_perc(p_geom_line public.geometry, p_geom_poly public.geometry, p_bufradius double precision, p_factor double precision) OWNER TO alegrete;

--
-- Name: st_overlaps_perc(public.geometry, public.geometry, boolean, double precision); Type: FUNCTION; Schema: lib; Owner: alegrete
--

CREATE FUNCTION st_overlaps_perc(public.geometry, public.geometry, boolean DEFAULT true, double precision DEFAULT 100.0) RETURNS integer
    LANGUAGE sql IMMUTABLE
    AS $_$
   SELECT (lib.ST_Overlaps_perc2($1,$2,$3,$4))[1]::integer;
$_$;


ALTER FUNCTION lib.st_overlaps_perc(public.geometry, public.geometry, boolean, double precision) OWNER TO alegrete;

--
-- Name: st_overlaps_perc2(public.geometry, public.geometry, boolean, double precision); Type: FUNCTION; Schema: lib; Owner: alegrete
--

CREATE FUNCTION st_overlaps_perc2(p_geom1 public.geometry, p_geom2 public.geometry, p_notcheckoverlap boolean DEFAULT true, p_factor double precision DEFAULT 100.0) RETURNS double precision[]
    LANGUAGE sql IMMUTABLE
    AS $_$
	-- retorna array[0 ou fator de interseção das áreas, 0.0 ou area de intersecao]
  SELECT CASE 
      WHEN $3 OR ST_Overlaps($1,$2) THEN (
         SELECT array[ (  $4*aint/LEAST(a1,a2)  ), aint ] 
         FROM ( SELECT 
           ST_Area(ST_Intersection($1,$2)) AS aint, 
           ST_Area($1) AS a1, ST_Area($2) AS a2
         ) AS t
      ) ELSE array[0.0,0.0]
  END;
$_$;


ALTER FUNCTION lib.st_overlaps_perc2(p_geom1 public.geometry, p_geom2 public.geometry, p_notcheckoverlap boolean, p_factor double precision) OWNER TO alegrete;

--
-- Name: trgr_labeler(integer); Type: FUNCTION; Schema: lib; Owner: alegrete
--

CREATE FUNCTION trgr_labeler(integer DEFAULT 100) RETURNS integer
    LANGUAGE plpgsql
    AS $_$
   -- TRansitive-GRoups LABELER: clusterize graphs of transitive relationships.
   -- input lib.trgr_labeler_in, output lib.trgr_labeler_out
   -- PARAMETER $1: table length that affects performance, to trigger of the NOTICE alert for performance. Use 0 to ever alert. 
   -- RETURNS 0 if no work doed, or the number of label demands (grater than distinct labels).
   -- group trgr_labeler SEE http://stackoverflow.com/a/20608421/287948
   -- Geo-Recipes, http://gauss.serveftp.com/colabore/index.php/Prj:Geoprocessing_Recipes/R009
   DECLARE
      label1 int;
      label2 int;
      newlabel int;
      t lib.trgr_labeler_in%rowtype;
      mergecount int;
      itemscount int;
      idcount int;
   BEGIN
      DELETE FROM lib.trgr_labeler_out;
      INSERT INTO lib.trgr_labeler_out(id) 
         SELECT DISTINCT unnest(array[id1,id2]) 
         FROM lib.trgr_labeler_in ORDER BY 1;
      newlabel:=0;
      mergecount:=0;
      itemscount:=0;
      FOR t IN SELECT * FROM lib.trgr_labeler_in
      LOOP   -- --  BASIC LABELING:  -- --
         SELECT label INTO label1 FROM lib.trgr_labeler_out WHERE id=t.id1;
         SELECT label INTO label2 FROM lib.trgr_labeler_out WHERE id=t.id2;
         IF label1=0 AND label2=0 THEN 
              newlabel:=newlabel+1;
              UPDATE lib.trgr_labeler_out SET label=newlabel WHERE ID IN (t.id1,t.id2);
         ELSIF label1=0 AND label2!=0 THEN 
              UPDATE lib.trgr_labeler_out SET label=label2 WHERE ID=t.id1;
         ELSIF label1!=0 AND label2=0 THEN 
              UPDATE lib.trgr_labeler_out SET label=label1 WHERE ID=t.id2;
         ELSIF label1!=label2  THEN -- pode armazenar em array de pares!
              mergecount:=mergecount+1; -- nao estava somando!
         END IF;
         itemscount:=itemscount+1;
      END LOOP;
      SELECT COUNT(*) INTO idcount FROM lib.trgr_labeler_out;
      IF $1=0 THEN -- debug/verbose condition
         RAISE NOTICE 'Counts: % mergings, % items, % IDs', mergecount, itemscount, idcount;
      END IF;
      IF mergecount>0 THEN
         IF idcount>$1 OR itemscount>$1 OR mergecount>(newlabel/3) THEN
             RAISE NOTICE 'Time-consumig: will update % times (and check by a loop of %)', mergecount, itemscount;
         END IF;
         FOR t IN SELECT * FROM lib.trgr_labeler_in 
         LOOP   -- --  MERGING LABELS:  -- --
            SELECT label INTO label1 FROM lib.trgr_labeler_out WHERE id=t.id1;
            SELECT label INTO label2 FROM lib.trgr_labeler_out WHERE id=t.id2;
            IF label1!=0 AND label1!=label2 THEN
                 UPDATE lib.trgr_labeler_out SET label=label1 WHERE label = label2; 
            END IF;
         END LOOP;
      END IF;
      UPDATE lib.trgr_labeler_out SET label=t2.g -- only for beautify
      FROM ( SELECT *, dense_rank() over (ORDER BY label) AS g FROM lib.trgr_labeler_out ) AS t2
      WHERE t2.id=trgr_labeler_out.id;
      RETURN newlabel;
    END;
 $_$;


ALTER FUNCTION lib.trgr_labeler(integer) OWNER TO alegrete;

SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: trgr_labeler_in; Type: TABLE; Schema: lib; Owner: alegrete; Tablespace: 
--

CREATE TABLE trgr_labeler_in (
    id1 integer,
    id2 integer
);


ALTER TABLE lib.trgr_labeler_in OWNER TO alegrete;

--
-- Name: trgr_labeler_out; Type: TABLE; Schema: lib; Owner: alegrete; Tablespace: 
--

CREATE TABLE trgr_labeler_out (
    id integer NOT NULL,
    label integer DEFAULT 0 NOT NULL
);


ALTER TABLE lib.trgr_labeler_out OWNER TO alegrete;

--
-- Name: trgr_labeler_out_pkey; Type: CONSTRAINT; Schema: lib; Owner: alegrete; Tablespace: 
--

ALTER TABLE ONLY trgr_labeler_out
    ADD CONSTRAINT trgr_labeler_out_pkey PRIMARY KEY (id);


--
-- PostgreSQL database dump complete
--

