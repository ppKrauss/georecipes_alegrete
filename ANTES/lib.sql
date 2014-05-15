-- -- --
-- Criação do esquema LIB.
-- https://github.com/ppKrauss/georecipes_alegrete
-- -- --
DO
$DO$
BEGIN
  IF count( * ) = 0
    FROM information_schema.schemata
    WHERE
      schema_name = 'fonte' THEN
    RAISE EXCEPTION 'Esquema fonte ausente. Rodar fonte.sql antes deste script.';
  END IF;
  
  DROP SCHEMA IF EXISTS lib CASCADE;
  CREATE schema lib;

CREATE OR REPLACE FUNCTION lib.table_exists( p_tname character varying )
  RETURNS boolean AS
$BODY$
BEGIN
  BEGIN
    PERFORM p_tname::regclass;
    RETURN true;
  EXCEPTION
  WHEN SQLSTATE '3F000' THEN
  WHEN SQLSTATE '42P01' THEN
    RETURN false;
  END;
END;
$BODY$
LANGUAGE PLpgSQL IMMUTABLE;

CREATE OR REPLACE FUNCTION lib.column_exists(p_colname character varying, p_tname character varying, p_schema character varying )
  RETURNS boolean AS
$BODY$
  SELECT count(*) > 0
  FROM information_schema.COLUMNS
  WHERE column_name = $1 AND table_schema = $3 AND table_name = $2;
$BODY$
  LANGUAGE sql IMMUTABLE
  COST 100;

CREATE OR REPLACE FUNCTION lib.column_exists(p_colname character varying, p_tname character varying )
RETURNS boolean AS
$BODY$
  SELECT lib.column_exists( p_colname, p_tname, 'public'::varchar );
$BODY$
LANGUAGE sql;
-- -- --
-- especificas

CREATE FUNCTION lib.kxrefresh_lote()
RETURNS void AS $F$
	-- refresh do campo cache da tabela-fonte
	UPDATE fonte.g_lote 
	SET kx_quadra_gid = qgid
	FROM (
		  SELECT q.gid as qgid, l.gid as lgid 
		  FROM fonte.g_quadra q  INNER JOIN fonte.g_lote l ON l.geom && q.geom 
		  WHERE st_intersects(l.geom,q.geom)
	) AS quadra_lote 
	WHERE lgid=g_lote.gid;
$F$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION lib.r016_parallelroute_ofpolygon(
  p_geom     geometry, -- polygon,
  p_tvias  regclass DEFAULT NULL, -- tabela das vias
  p_raio float DEFAULT 30.0,
  p_pfactor int DEFAULT 60,  -- parallel factor, score dominado por percentual de cobertura dos trechos paralelos (60%)
  p_angular_factor float DEFAULT 2.5, -- maior que 1.45 (travessia a mais que 45 garauss), menor que 5.0
  p_step float DEFAULT 1.8,        -- tamanho das tiras de verificação (2m)
  p_droptemp BOOLEAN DEFAULT true  -- mantém por questão de debug
) RETURNS integer[] AS $F$  -- retorna lista de gids
DECLARE
  v_r          FLOAT; -- radius
  lenparallel  FLOAT; -- comprimento mínimo de um segmento paralelo
  v_numsteps    INT;   -- número máximo de steps
  anel          geometry; -- (annular strip) buffer cortado em forma de anel em torno do poligono 
  v_rbuff       geometry; --  buffrt fo loop r
  anel_cut      geometry := NULL; -- recebe cortes cumulativos dos segmentos eleitos
  v_cuts        geometry;
  v_perim       FLOAT;
  v_exeaux      text;
  v_stop BOOLEAN := false;  -- para fazer mais um loop depois de chegar ao fim
BEGIN
   IF p_tvias IS NULL THEN
      p_tvias :='kx.eixologr_cod'::regclass;
   END IF;
   IF p_raio<1.0 OR p_raio>100.0 THEN
        Raise Exception 'Raio de proximidade com ruas fora do intervalo 1.0 a 100.0 metros';
   END IF;
   IF p_pfactor<20 OR p_pfactor>95 THEN
        Raise Exception 'Percentual mínimo de cobertura das porções paralelas precisa estar entre 20 e 95';
   END IF;
   IF p_angular_factor <1.45 OR p_angular_factor>5.0 THEN
        Raise Exception 'Fator angular fora do intervalo de 1.42 (135 graus) a 5.0 (limiar de 180 graus).';
   END IF;
   IF p_step <0.5 OR p_step>5.0 THEN
        Raise Exception 'Largura de tira fora do intervalo seguro de 0.5m a 5.0m.';
   END IF;
 
   DROP TABLE IF EXISTS kx.temp_r016b; -- rever como TEMPORARY
   CREATE TABLE kx.temp_r016b AS SELECT ST_Buffer(p_geom,p_raio+p_step) AS geom; -- comunica p_* ao EXECUTE
 
   v_exeaux := ' SELECT * FROM ('||
   '   SELECT e.gid, e.cod,'||
   '  ST_Intersection(e.geom,t.geom) AS geom, '|| -- corta: espaço restrito à vizinhança considerada
   '  NULL::geometry AS seg, '||  -- segmento que será cortado conforme uso
   '    0.0 AS lsoma,  0.0 AS lcada, '||
   '    0::int AS nparts,  0::int AS parallel_factor,'||
   '    false AS isparalelo'
   '  FROM '|| p_tvias ||' e INNER JOIN kx.temp_r016b AS t'||
   '    ON t.geom && e.geom'||
   '   ) AS t2 WHERE geom IS NOT NULL AND st_length(geom)>'|| p_step;
   IF lib.table_exists('kx.temp_r016a') THEN
       DELETE FROM kx.temp_r016a;
       EXECUTE 'INSERT INTO kx.temp_r016a '||v_exeaux;
   ELSE
    EXECUTE 'CREATE TABLE kx.temp_r016a AS'||v_exeaux;
  END IF;
   v_numsteps := round(p_raio/p_step)::int; -- ou floor()?
   FOR r IN 1..v_numsteps LOOP
      IF anel_cut IS NOT NULL THEN
        SELECT ST_Buffer(ST_Collect(seg),2.5*p_step) INTO v_cuts  
        FROM kx.temp_r016a
        WHERE seg IS NOT NULL AND nparts>0; -- AND ( lcada/lsoma + 8.0 )::int>p_pfactor;
        -- subtrai todos os segmentos já contemplados do caso anterior
        anel_cut:=ST_Difference( ST_Buffer(anel_cut,p_step), ST_Union(v_rbuff,v_cuts) ); -- cresce só para fora
      END IF;
      v_rbuff := ST_Buffer(p_geom,r*p_step); -- usa anterior no anel_cut e atual no anel puro
      IF anel_cut IS NULL THEN
        anel_cut:=ST_Difference( v_rbuff, ST_Buffer(p_geom,r*(p_step-1)) ); -- anel puro
      END IF;
      lenparallel := p_angular_factor*p_step; -- garante minimo de paralelismo
      UPDATE kx.temp_r016a 
      SET  
        nparts = nparts + isparallel,     -- conta pedaços
        lcada = lcada +isparallel*t.len,  -- soma dos pedaços paralelos 
        lsoma = lsoma + t.len,             -- soma de todos os pedaços
        seg   = CASE WHEN temp_r016a.seg IS NULL THEN t.seg 
                ELSE ST_Union(temp_r016a.seg,ST_Intersection(t.seg,anel_cut)) END  -- ou collect?
      FROM (
           WITH seg_do_anel AS (
               SELECT gid, ST_Intersection(geom,anel_cut) AS seg 
               FROM kx.temp_r016a
           ) SELECT *, (len>lenparallel)::int AS isparallel
             FROM ( SELECT *, ST_Length(seg) AS len FROM seg_do_anel ) AS tmp
      ) AS t
      WHERE t.gid=temp_r016a.gid AND t.seg IS NOT NULL AND ST_Length(t.seg)>p_step;
      v_perim := ST_Perimeter(v_rbuff);
      IF v_stop THEN
              EXIT;  -- exit 1 loop after fineshed
      ELSIF (SELECT st_length(st_intersection(st_collect(geom),v_rbuff)) FROM kx.temp_r016a WHERE nparts>0) >= v_perim THEN
        v_stop :=true;
      END IF;
   END LOOP;  
 
   UPDATE kx.temp_r016a 
   SET  isparalelo=true, parallel_factor=pfat
   FROM (
      SELECT gid, ( 76.0*lcada/lsoma + 8.0*ln(lsoma/(p_step*nparts::float)) )::int AS pfat
  -- fator primário (cobertura) tem peso ~0.8, secundário (penaliza nparts) peso ~0.2, somados precisam dar ~100.
      FROM kx.temp_r016a  WHERE nparts>0 -- AND lsoma>0.0
   ) AS t 
   WHERE temp_r016a.gid=t.gid AND t.pfat>p_pfactor;
 
   RETURN ( SELECT array_agg(gid ORDER BY parallel_factor DESC)
            FROM kx.temp_r016a WHERE isparalelo
   );
   -- IF p_droptemp THEN DROP TABLE kx.temp_r016a
END;
$F$ LANGUAGE PLpgSQL;


-----------

 --- funcao auxiliar (ver também extra-func lib.ST_LineOverlaps_perc)
CREATE OR REPLACE FUNCTION lib.ST_Overlaps_perc2(
    p_geom1 geometry,                       -- 1
    p_geom2 geometry,                       -- 2
    p_notcheckoverlap BOOLEAN DEFAULT true, -- 3. para nao perder tempo
    p_factor float DEFAULT 100.0 -- 4. changes percent to other factor
) RETURNS float[] AS $func$
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
$func$ language SQL IMMUTABLE;
CREATE OR REPLACE FUNCTION lib.ST_Overlaps_perc(
    geometry, geometry,
    BOOLEAN DEFAULT true, -- 3
    float DEFAULT 100.0   -- 4
) RETURNS integer AS $func$
   SELECT (lib.ST_Overlaps_perc2($1,$2,$3,$4))[1]::integer;
$func$ language SQL IMMUTABLE;


-- -- -- -- -- -- -- -- -- 
-- -- -- -- -- -- -- -- -- 
-- --  LABELER, BEGIN   --
-- -- -- -- -- -- -- -- -- 
-- see http://stackoverflow.com/a/20608421/287948
-- Examples:
-- Charge of input data:
-- DELETE FROM lib.trgr_labeler_in;
-- INSERT INTO lib.trgr_labeler_in(id1,id2)
-- SELECT a_gid, b_gid FROM peter.kx_lote_viz;
-- -- or VALUES (1, 2), (1, 5), (4, 7), (7, 8), (9, 1);
-- -- or , (1,1),(12,12),(1, 2), (1, 5), (4, 7), (7, 8), (9, 1), (1,1),(12,12);
 
-- Run, and show output data:
-- SELECT lib.trgr_labeler(1); 
-- SELECT * FROM lib.trgr_labeler_out;
 
-- 
-- INITIALIZATIONS AND FUNCION DEF.
--

DROP TABLE IF EXISTS lib.trgr_labeler_in CASCADE;
CREATE TABLE lib.trgr_labeler_in (
  id1 integer, id2 integer
);
DROP TABLE IF EXISTS lib.trgr_labeler_out CASCADE;
CREATE TABLE lib.trgr_labeler_out (
  id integer NOT NULL PRIMARY KEY,
  label integer NOT NULL DEFAULT 0
);
 
 
  CREATE OR REPLACE FUNCTION lib.trgr_labeler(integer DEFAULT 100) RETURNS integer AS $funcBody$
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
 $funcBody$ language plpgsql VOLATILE;
 
-- refs: ver também "graph theory", "collect clusters"
 
-- -- -- -- -- -- -- -- -- 
-- -- -- -- -- -- -- -- --
-- --  LABELER, END     --
-- -- -- -- -- -- -- -- -- 


-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- 
-- -- Cache-refresh lote vizinho | BEGIN  --
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- 
-- Pode demorar de minutos a horas, O(n^2).
 
CREATE OR REPLACE FUNCTION lib.kxrefresh_lote_viz(
   p_addprox float DEFAULT 1.5,     -- >0 considera lotes como vizinhos mesmo se disjuntos
   p_areapoeira float DEFAULT 2.0,  -- define poeira digital em m2
   p_out_verbose BOOLEAN DEFAULT false -- true cria NOTICEs relatando quantidades inseridas e demoras
) RETURNS text AS $func$
   DECLARE
     n integer;
     ret  text;
   BEGIN
 
   -- faltam IFs para CREATE SCHEMA errsig; CREATE SCHEMA kx;
   ret := E'\n-- Reiniciando a tabela kx.lote_viz';
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
 
  ret:=ret||E'\n-- View kx.vw_lote_viz_err';
  SELECT COUNT(*) INTO n FROM kx.vw_lote_viz_err;
    IF n > 0 THEN 
      DELETE FROM errsig.lote_sobreposto_lotes;
      INSERT INTO errsig.lote_sobreposto_lotes ( gid, err, geom )
        SELECT v.gid, v.err, f.geom 
        FROM kx.vw_lote_viz_err v INNER JOIN fonte.g_lote f ON f.gid = v.gid;
 
      DELETE FROM errsig.lote_sobreposto_erros;
      INSERT INTO errsig.lote_sobreposto_erros ( gid, err, geom )
        WITH pares AS (
          SELECT a.gid AS a_gid, b.gid AS b_gid, 0 AS viz_tipo,  
                 a.geom AS a_geom, b.geom AS b_geom
          FROM fonte.g_lote a INNER JOIN  fonte.g_lote b ON a.gid>b.gid
        ) 
        SELECT v.id AS gid, v.err, ST_Intersection(a_geom, b_geom) AS geom
        FROM kx.lote_viz v INNER JOIN pares p ON v.a_gid=p.a_gid AND v.b_gid=p.b_gid;
      ret:=ret||E'\n-- ERROS encontrados, mostrando em errsig.lote_sobreposto_lotes errsig.lote_sobreposto_erros';
    ELSE 
      ret:=ret||E'\n-- SEM ERROS!';
    END IF;
   RETURN ret;
   END;
$func$ language PLpgSQL VOLATILE;

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- 
-- -- Cache-refresh lote vizinho | END  --
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- 

CREATE FUNCTION lib.gidvia2codlogr(
	int[] -- lista de gid's
) RETURNS int[] -- lista de codlogr's
AS $f$
   SELECT array_agg(distinct codlogr)::int[] 
   FROM fonte.g_eixologr WHERE gid = ANY ($1)
$f$ language SQL IMMUTABLE;


--- OFICIAL
CREATE OR REPLACE FUNCTION lib.kxrefresh_quadrasc(
  -- Ver documentação em
  -- http://gauss.serveftp.com/colabore/index.php/Prj:Geoprocessing_Recipes/R009
  --
  p_distolviz float DEFAULT 1.0,  -- distância (m) del tol. para vizinho. (0 para não tolerar)
  p_alertrig integer DEFAULT 2,   -- parâmetro de alert no trgr_labeler()
  p_gerapol BOOLEAN DEFAULT true, -- true se for para gerar kx.quadrasc com polígonos
  p_redolote_viz BOOLEAN DEFAULT true, -- true para refazer tudo (ver tambem esquema errsig) em kx.lote_viz
  p_out_errsig   BOOLEAN DEFAULT true -- true se for para, junto com kx.lote_viz, gerar erros em errsig 
) RETURNS text AS $func$
  DECLARE
    aux int;
    ret text := '';
  BEGIN 
   IF p_redolote_viz THEN 
      SELECT lib.kxrefresh_lote_viz( p_distolviz, 2.0 ) INTO ret;
   END IF;
   ret := ret || E'\n -- ... Rodando kxrefresh_quadrasc ...';
 
   -- rotulação: --
  DELETE FROM lib.trgr_labeler_in;
  INSERT INTO lib.trgr_labeler_in(id1,id2)
    SELECT a_gid, b_gid FROM kx.lote_viz;
  SELECT lib.trgr_labeler(p_alertrig) INTO aux;
  ret := ret || E'\n -- Rotulação de lotes realizada, depois '||aux||' rotulos preliminares';
 
  UPDATE fonte.g_lote SET kx_quadrasc_id= 0;
  UPDATE fonte.g_lote SET kx_quadrasc_id=t.label
  FROM lib.trgr_labeler_out t 
  WHERE t.id= gid;
  ret := ret || E'\n -- Campo kx_quadrasc_id de fonte.g_lote atualizado com rotulos de quadra';
  
  IF (p_gerapol) THEN 
    -- geração dos polígonos de quadrasc: --
    TRUNCATE kx.quadrasc;
    INSERT INTO kx.quadrasc ( gid, gid_lotes, geom )
    SELECT kx_quadrasc_id, array_agg(gid), ST_Buffer( ST_Union(ST_Buffer(geom,p_distolviz)), -p_distolviz)
    FROM fonte.g_lote
    WHERE kx_quadrasc_id IS NOT NULL
    GROUP BY kx_quadrasc_id;
    ret := ret || E'\n -- tabela kx.quadrasc iniciada';
  END IF;
 
  UPDATE kx.quadrasc SET quadraccvia_gid = NULL;
  -- QuadraSC com área 80% contida em QuadraCCvia:
  UPDATE kx.quadrasc SET quadraccvia_gid = t.quadraccvia_gid
  FROM (
     SELECT q.gid, cc.gid AS quadraccvia_gid
     FROM kx.quadrasc q INNER JOIN kx.quadraccvia cc ON cc.geom && q.geom 
          AND ST_Intersects(cc.geom,q.geom) AND ST_Area(ST_Intersection(cc.geom,q.geom))/ST_Area(q.geom)>0.8
  ) t 
  WHERE t.gid = quadrasc.gid;
 
  RETURN ret;
 END;
$func$ LANGUAGE plpgsql VOLATILE;

-- -- -- --
-- EXTRA FUNCTIONS
-- -- -- --


CREATE FUNCTION lib.shapedescr_sizes(
    -- Shape-descriptor "as rectangle" for geometry description by sizes. 
    -- RETURN array[L_estim,H_estim,a0,per,dw,errcod];
    gbase geometry,              -- input
    -- p_seqs integer DEFAULT 8,    -- deprecated? for st_buffer(g,w,p_seqs) or point-buffer inference 
    -- p_shape varchar DEFAULT '',  -- will be endcap indicator
    p_decplacesof_zero integer DEFAULT 6, -- precision of zero when rounding delta
    p_dwmin float DEFAULT 99999999.0,     -- change to ex. 0.0001, if to use.
    p_deltaimpact float DEFAULT 9999.0    -- internal (maximized by probability of negative delta)
)  RETURNS float[] AS $f$
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
$f$ language plpgsql IMMUTABLE;
 
 
CREATE or replace FUNCTION lib.shapedescr_sizes_tr(
    -- Translator for lib.shapedescr_sizes(). Uses ROUND(float).
    float[],               -- lib.shapedescr_sizes() returned vector
    integer DEFAULT 0,     -- general round parameter
    integer DEFAULT 3      -- number of "decimal warnings" 
) RETURNS varchar[] -- length, height, area, perimeter, dw, radius, err_message
AS $f$
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
$f$ language SQL IMMUTABLE;


CREATE FUNCTION lib.shapedescr_sizes_tr(geometry, integer DEFAULT 0, integer DEFAULT 3) 
RETURNS varchar[] AS $f$
   SELECT lib.shapedescr_sizes_tr(lib.shapedescr_sizes($1),$2,$3);
$f$ language SQL IMMUTABLE;

-- check near paralel lines
--overlap by strip = usar função que deduz melhor retângulo, retornando comprimento e largura da strip,
-- ou seja, confere se a linha está paralela ao vizinho quando seu buffer 
-- function(linha,poli) = comprimento_strip(buffer_linha,poli)/st_Length(linha)

CREATE OR REPLACE FUNCTION lib.ST_LineOverlaps_perc(
    p_geom_line geometry,           -- 1
    p_geom_poly geometry,           -- 2
    p_bufradius float DEFAULT 1.0,   -- 3. tamanho do buffer
    p_factor float DEFAULT 100.0    -- 4. changes percent to other factor
) RETURNS float AS $func$
   SELECT $4*( lib.shapedescr_sizes(ST_Intersection(ST_Buffer($1,$3),$2)) )[1] / ST_Length($1);
$func$ language SQL IMMUTABLE;


--- ----
----------------------------



-- FALTA revisar ABAIXO, pois agora temos o campo gids_via das vias paralelas.
-- o problema agora se reduz a eleger os paralelos mais próximos.
-- ... criar função que determina a via paralela mais próxima de um segmento de quadra.

-- -- -- -- -- -- --
-- -- -- -- -- -- --
-- Segmentação e classificação de quadrasc, gera kx.quadrasc_simplseg
-- -- -- -- -- -- --
-- -- -- -- -- -- --
CREATE OR REPLACE FUNCTION lib.kxrefresh_quadrasc_auxbuffs_lixoold(
	float DEFAULT 7.0,   -- p1 buffer externo de kx.quadra_buffdiff
	float DEFAULT -4.5,  -- p2 buffer interno de kx.quadra_buffdiff
	float DEFAULT 4.0,   -- p3 buffer das vias (meia largura média da rua)
	float DEFAULT 0.2,   -- p4 fator de simplify no segmento de quadrasc_seg
	float DEFAULT 2.0    -- p5 buffer do segmento de quadra para identificar paralelas
) RETURNS text AS $func$
   BEGIN
	-- 1. BuffDiff: annular strip da borda da quadra (tira em forma de anel)
	DROP TABLE IF EXISTS kx.quadra_buffdiff;
	CREATE TABLE kx.quadra_buffdiff AS 
	  SELECT gid, st_difference(st_buffer(geom,$1),st_buffer(geom,$2)) AS geom 
	  FROM fonte.g_quadra;
	ALTER TABLE kx.quadra_buffdiff ADD PRIMARY KEY (gid);
 
	-- 2. viaBuff:	 (1 segundo) (revisar se precisa ou se melhor direto segmentos)
	DROP TABLE IF EXISTS kx.viabuff;
	CREATE TABLE kx.viabuff AS -- todas as fronteiras de quadra e seus códigos 
	  WITH viasbuf4 AS (
		(SELECT 0 AS gid, codlogr AS cod
		       ,st_buffer(ST_Collect(geom),$3) AS geom 
		FROM fonte.g_eixologr 
		WHERE codlogr>0
		GROUP BY codlogr
		ORDER BY codlogr)
	 
		UNION
	 
		(SELECT 0 AS gid, -1 AS cod
		       ,st_buffer(ST_Collect(geom),$3) AS geom 
		FROM public.g_hidrografia_linha)
	 
		UNION
	 
		(SELECT 0 AS gid, -2 AS cod,
		       st_buffer(ST_Collect(geom),$3) AS geom 
		FROM public.g_ferrovia 
		)
	  ) SELECT v.gid + (row_number() OVER ()) as gid, v.cod, ST_Intersection(v.geom ,t.geom) AS geom 
	    FROM viasbuf4 v, (
	       SELECT ST_Envelope(
		  (SELECT ST_Collect(geom) FROM fonte.g_lote)
	       ) AS geom
	    ) AS t;
	ALTER TABLE kx.viabuff ADD PRIMARY KEY (gid);

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
		   s_s AS id_seg, 
		   NULL::BOOLEAN AS isexterno,
		   NULL::integer AS isexterno_fator,
		   NULL::integer AS id_via,
		   ST_MakeLine(sp,ep) AS seg
	    FROM (
	       SELECT gid, quadra_gids, s_s, ST_PointN(geom, s_s) AS sp, ST_PointN(geom, s_e) AS ep, s_e
	       FROM prepared_quadras
	    ) AS t; -- 13373 (sem simplificação seriam dez vezes mais!)
	    

	-- 4.1 classificando como externo quem realmente está no perímetro da quadra real (quadra_buffdiff)
	UPDATE kx.quadrasc_simplseg  -- (demora 10 segundos)
	SET isexterno=true
	WHERE gid IN (
	    SELECT k.gid
	    FROM kx.quadra_buffdiff b INNER JOIN kx.quadrasc_simplseg  k 
		 ON array[b.gid] && k.quadra_gids AND k.seg && b.geom 
	     WHERE isexterno IS NULL AND ST_Length(ST_Intersection(k.seg,b.geom))/ST_Length(k.seg)>0.45); -- 45% ok

	DROP TABLE kx.quadra_buffdiff; -- descartar exceto para debug

	-- 4.2 classificando como externo E atribuindo id_via   aos externos, no escopo de viabuff (apenas ruas)
-- !!AQUI USAR quadrasc.gid_vias !!  agora muda a estratégia, a busca é pelo mais próximo!
	UPDATE kx.quadrasc_simplseg
	SET isexterno=true, isexterno_fator=round(t2.fator*100.0), id_via=t2.cod  -- curioso, deu sempre 100%
	FROM  (
		WITH varios AS (
			SELECT gid, cod, ST_Length(geom) / ST_Length(seg) AS fator
			FROM (
			    SELECT k.gid, b.cod, ST_Intersection(k.seg,b.geom) as geom, k.seg
			    FROM kx.viabuff b INNER JOIN kx.quadrasc_simplseg  k 
				 ON k.id_via IS NULL AND ST_Length(k.seg)>1.0 AND b.cod>0 AND k.isexterno AND k.seg && b.geom 
			) as t1
			WHERE geom IS NOT NULL 
		) SELECT v.gid, v.cod, v.fator
		  FROM varios as v INNER JOIN (SELECT gid, MAX(fator) as mxfat FROM varios GROUP BY gid) as t
		    ON v.gid=t.gid AND t.mxfat=v.fator
		  WHERE v.fator > 0.25 
	) t2
	WHERE t2.gid = quadrasc_simplseg.gid; -- ~1700 rows, apenas ~15%

	-- 4.3 classificando como externo quem esta próximo ($5) do viabuff de ruas (não rios)
	UPDATE kx.quadrasc_simplseg 
	SET isexterno=true
	WHERE gid IN (
		SELECT gid
		FROM (
		    SELECT k.gid, ST_Intersection(ST_Buffer(k.seg,$5),b.geom) as geom, k.seg
		    FROM kx.viabuff b INNER JOIN kx.quadrasc_simplseg  k 
			 ON isexterno IS NULL  AND b.cod>0 AND k.seg && b.geom 
		) as t
		WHERE geom IS NOT NULL AND ST_Length(seg)>(1.0+$5) AND st_perimeter(geom)>$5 AND st_area(geom)>0.1 -- poeira
		      AND (lib.shapedescr_sizes(geom))[1] / ST_Length(seg) > 0.51
	);

	-- 4.4 classificando como externo quem esta próximo (2*$5) do viabuff (incluindo rios!)
	UPDATE kx.quadrasc_simplseg  -- complementa a classificação 
	SET isexterno=true, isexterno_fator=70 -- só para debug 
	WHERE gid IN (
		SELECT gid
		FROM (
		    SELECT k.gid, ST_Intersection(ST_Buffer(k.seg,2*$5),b.geom) as geom, k.seg
		    FROM kx.viabuff b INNER JOIN kx.quadrasc_simplseg  k 
			 ON isexterno IS NULL AND k.seg && b.geom 
		) as t  -- perimetro superior a 2*pi()*radiusBuffer de um ponto = 2*pi()*(2*$5)
		WHERE geom IS NOT NULL AND ST_Length(seg)>(1.0+$5) AND st_perimeter(geom)>12.5*$5 AND st_area(geom)>0.1 -- poeira
		      AND (lib.shapedescr_sizes(geom))[1] / ST_Length(seg) > 0.51
	);

	-- conferir se stop aqui ou se mais...
	-- 5 classificando como interno quem restou no interior da quadra!
	UPDATE kx.quadrasc_simplseg
	SET isexterno=false  -- interior!
	WHERE gid IN (
	    SELECT k.gid
	    FROM fonte.g_quadra b INNER JOIN kx.quadrasc_simplseg  k 
		 ON isexterno IS NULL AND array[b.gid] && k.quadra_gids AND k.seg && b.geom 
	    WHERE ST_Length(ST_Intersection(k.seg,st_buffer(b.geom,-1.5)))/ST_Length(k.seg)>0.51
	);

	-- 4.5 classificando como externo quem esta próximo (2*$5) do viabuff (incluindo rios!)
	-- perigo, ver se shapedescr_sizes confiavel!
	UPDATE kx.quadrasc_simplseg  -- complementa a classificação 
	SET isexterno=true, isexterno_fator=73 -- só para debug 
	WHERE gid IN (
		SELECT gid
		FROM (
		    SELECT k.gid, ST_Intersection(ST_Buffer(k.seg,3*$5),b.geom) as geom, k.seg
		    FROM kx.viabuff b INNER JOIN kx.quadrasc_simplseg  k 
			 ON isexterno IS NULL AND k.seg && b.geom 
		) as t  -- perimetro superior a 2*pi()*radiusBuffer de um ponto = 2*pi()*(3*$5)
		WHERE geom IS NOT NULL AND ST_Length(seg)>(1.0+$5) AND st_perimeter(geom)>18.0*$5 AND st_area(geom)>0.1 -- poeira
		      AND (lib.shapedescr_sizes(geom))[1] / ST_Length(seg) > 0.51
	); -- ...

	-- FALTA pre-classificar ruas das quadrasc para otimizar e limitar! elas determinam as ruas vizinhas e talvez os recortes
	--  a melhor seleção está em pre-selecionar id_via pela quadra, e depois usar ST_OffsetCurve para calculo de percentual

	-- 6.1 classificando como externo E atribuindo id_via   aos externos, no escopo de viabuff (apenas ruas)
	UPDATE kx.quadrasc_simplseg
	SET isexterno=true, isexterno_fator=round(t2.fator*100.0), id_via=t2.cod  -- curioso, deu sempre 100%
	FROM  (
		WITH varios AS (
			SELECT gid, cod, ST_Length(geom) / ST_Length(seg) AS fator
			FROM (
			    SELECT k.gid, b.cod, ST_Intersection(k.seg,ST_Buffer(b.geom,2.5)) as geom, k.seg
			    FROM kx.viabuff b INNER JOIN kx.quadrasc_simplseg  k 
				 ON k.id_via IS NULL AND ST_Length(k.seg)>1.0 AND b.cod>0 AND (k.isexterno OR k.isexterno IS NULL) AND k.seg && ST_Buffer(b.geom,2.5) 
			) as t1
			WHERE geom IS NOT NULL 
		) SELECT v.gid, v.cod, v.fator
		  FROM varios as v INNER JOIN (SELECT gid, MAX(fator) as mxfat FROM varios GROUP BY gid) as t
		    ON v.gid=t.gid AND t.mxfat=v.fator
		  WHERE v.fator > 0.3
	) t2
	WHERE t2.gid = quadrasc_simplseg.gid; -- ~3768 rows


	-- 6.2 classificando como externo E atribuindo id_via   aos externos, no escopo de viabuff (apenas ruas)
	UPDATE kx.quadrasc_simplseg
	SET isexterno=true, isexterno_fator=round(t2.fator*100.0), id_via=t2.cod  -- curioso, deu sempre 100%
	FROM  (
		WITH varios AS (
			SELECT gid, cod, ST_Length(geom) / ST_Length(seg) AS fator
			FROM (
			    SELECT k.gid, b.cod, ST_Intersection(k.seg,ST_Buffer(b.geom,4.5)) as geom, k.seg
			    FROM kx.viabuff b INNER JOIN kx.quadrasc_simplseg  k 
				 ON k.id_via IS NULL AND ST_Length(k.seg)>1.0 AND b.cod>0 AND (k.isexterno OR k.isexterno IS NULL) AND k.seg && ST_Buffer(b.geom,4.5) 
			) as t1
			WHERE geom IS NOT NULL 
		) SELECT v.gid, v.cod, v.fator
		  FROM varios as v INNER JOIN (SELECT gid, MAX(fator) as mxfat FROM varios GROUP BY gid) as t
		    ON v.gid=t.gid AND t.mxfat=v.fator
		  WHERE v.fator > 0.35
	) t2
	WHERE t2.gid = quadrasc_simplseg.gid; -- ~2592 rows

	-- 6.3 classificando como externo E atribuindo id_via   aos externos, no escopo de viabuff (apenas ruas)
	UPDATE kx.quadrasc_simplseg
	SET isexterno=true, isexterno_fator=round(t2.fator*100.0), id_via=t2.cod  -- curioso, deu sempre 100%
	FROM  (
		WITH varios AS (
			SELECT gid, cod, ST_Length(geom) / ST_Length(seg) AS fator
			FROM (
			    SELECT k.gid, b.cod, ST_Intersection(k.seg,ST_Buffer(b.geom,11.0)) as geom, k.seg
			    FROM kx.viabuff b INNER JOIN kx.quadrasc_simplseg  k 
				 ON k.id_via IS NULL AND ST_Length(k.seg)>1.0 AND b.cod>0 AND (k.isexterno OR k.isexterno IS NULL) AND k.seg && ST_Buffer(b.geom,11.0) 
			) as t1
			WHERE geom IS NOT NULL 
		) SELECT v.gid, v.cod, v.fator
		  FROM varios as v INNER JOIN (SELECT gid, MAX(fator) as mxfat FROM varios GROUP BY gid) as t
		    ON v.gid=t.gid AND t.mxfat=v.fator
		  WHERE v.fator > 0.45
	) t2
	WHERE t2.gid = quadrasc_simplseg.gid; -- ~xxx rows


	RETURN 'OK22';
   END;
$func$ language PLpgSQL VOLATILE;

 
-- select count(*) from kx.quadrasc_simplseg where isexterno is null; --985 em 13373
-- falta avaliar com ruas!
 
-- ai o que fica em null perde a confiança (avisar na listagem de erros!)
-- mas pode setar em externo que é o mais provavel
-----
 
---- para retomar casos NULL usar a tabela backup abaixo,
-- lixo, create table  kx.quadrasc_simplseg_claudio1 AS select * from  kx.quadrasc_simplseg;
 


 
CREATE OR REPLACE FUNCTION lib.kxrefresh_lote_seg(
	BOOLEAN DEFAULT true  -- requisita refazimento de kx.lote_seg
) RETURNS text AS $func$
   BEGIN
	IF ($1) THEN
		DROP TABLE IF EXISTS kx.lote_seg;
		CREATE TABLE kx.lote_seg AS 
		  WITH prepared_lotes AS (
		      SELECT gid, chave, gid_quadrasc, geom,
			generate_series(1, ST_NPoints(geom)-1) AS s_s,
			generate_series(2, ST_NPoints(geom)  ) AS s_e
		      FROM (
			  SELECT gid, chave, kx_quadrasc_id AS gid_quadrasc,
				(ST_Dump(ST_Boundary(geom))).geom -- sem simplifcar
				-- (ST_Dump(ST_Boundary(ST_SimplifyPreserveTopology(geom,0.1)))).geom
		  	  FROM fonte.g_lote
		      ) AS linestrings
		  ) SELECT dense_rank() over (ORDER BY gid,s_s) AS gid,
			  gid AS gid_lote, chave, gid_quadrasc, s_s AS id_seg, 
			  0::int AS id_via, 
			  false AS isexterno, -- a maioria é interno, exceto se fronteira com quadrasc
			  ST_MakeLine(sp,ep) AS seg
		    FROM (
		       SELECT *, ST_PointN(geom, s_s) AS sp, ST_PointN(geom, s_e) AS ep
		       FROM prepared_lotes
		    ) AS t; -- 89515 registros. Sem uso no idvia.
	ELSE
		UPDATE kx.lote_seg SET isexterno=false; -- default
	END IF; -- kx.lote_seg criada
 
	UPDATE kx.lote_seg -- demora!
	SET isexterno=t.isexterno, id_via=t.id_via
	FROM (
	  SELECT s.gid, q.isexterno, q.id_via
	  FROM kx.lote_seg s INNER JOIN kx.quadrasc_simplseg q 
	     ON s.gid_quadrasc=q.gid_quadrasc AND  s.seg && ST_Buffer(q.seg,0.4) -- 0.4 é 2*simplify_factor
	  WHERE ST_Length( ST_Intersection(s.seg,ST_Buffer(q.seg,0.4)) )/ST_Length(s.seg) > 0.6
	) AS t
	WHERE t.gid=lote_seg.gid;

	RETURN 'ok';
   END;
$func$ language PLpgSQL VOLATILE;
 

--------------
--------------
-- receitas de http://gauss.serveftp.com/colabore/index.php?title=Prj:Geoprocessing_Recipes/R008
--

CREATE FUNCTION lib.in_range(float,integer,float,float,text) RETURNS void AS $F$  
BEGIN
   IF $1<$3 OR $1>$4 THEN
        Raise Exception 'Parametro #% (=%), %, fora de intervalo seguro',$2,$1,$5;
   END IF;
END;
$F$ LANGUAGE PLpgSQL IMMUTABLE;
 
CREATE OR REPLACE FUNCTION lib.r008a_quadra(
  -- Cria kx.eixologr_cod e a partir dela a kx.quadraccvia
  p_width_via  float DEFAULT 0.5,  -- meia largura das vias (somar a p_reduz)
  p_reduz      float DEFAULT 0.5,  -- raio para o buffer de redução
  p_area_min   float DEFAULT 10.0, -- área minima da quadra
  p_lendetect float DEFAULT 0.15   -- comprimento para detectar via como parte (com porção mínima de 4*len)
) RETURNS text AS $F$  -- retorna lista de gids
DECLARE
  v_msg    text:=format('Parametros width_via=%s, reduz=%s, area_min=%s',$1,$2,$3); -- mensagens de retorno
BEGIN
   PERFORM lib.in_range($1, 1, 0.0,   5.0,    'meia largura da via');
   PERFORM lib.in_range($2, 2, 0.0,   5.0,    'raio do buffer de redução');
   PERFORM lib.in_range($3, 3, 0.001, 1000.0, 'area mínima da quadra');
   PERFORM lib.in_range($4, 4, 0.001, 2.0,    'comprimento para detectar via como parte');
 
   -- 1. PREPARO: divisores de quadracc, dado por "malha viária" completa e conexa
   TRUNCATE kx.eixologr_cod;
   INSERT INTO kx.eixologr_cod -- todas as fronteiras de quadra e seus códigos 
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
   v_msg := v_msg || E'\n kx.eixologr_cod populada com '|| (SELECT count(*) FROM kx.eixologr_cod) ||' registros';
  -- 2. Construção principal: (old "quadracc_byvias")
  TRUNCATE kx.quadraccvia;
  INSERT INTO kx.quadraccvia
    SELECT (st_dump).path[1] AS gid, (st_dump).geom, NULL::int[] AS cod_vias
    FROM (
      SELECT ST_Dump( ST_Polygonize( geom ) )
      FROM ( SELECT ST_Union(geom) AS geom FROM kx.eixologr_cod ) mergedlines
    ) polys;
   -- 3. Obtenção dos códigos das vias de entorno, e redução dos polígnos:
   UPDATE kx.quadraccvia
    SET cod_vias=t.cods,
        geom = ST_Difference(quadraccvia.geom,t.geom)
    FROM (
       SELECT q.gid, array_agg(e.cod) AS cods, ST_Buffer(ST_Union(e.geom),$1) AS geom
       FROM kx.eixologr_cod e INNER JOIN (SELECT *, ST_Buffer(geom,$4) AS buff FROM kx.quadraccvia) q 
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
$F$ LANGUAGE PLpgSQL;
 
CREATE FUNCTION lib.r008_gidvia2cod(bigint) RETURNS int AS
$F$
BEGIN
  RETURN cod::integer FROM kx.eixologr_cod WHERE gid=$1;
END;
$F$ LANGUAGE plpgsql IMMUTABLE;

---- receita b
CREATE FUNCTION lib.table_not_empty(text) RETURNS text 
AS $F$  
DECLARE
   v_n integer;
BEGIN
  IF lib.table_exists($1) THEN 
    EXECUTE 'SELECT count(*) FROM ' || $1 INTO v_n;
    IF v_n > 0 THEN
      RETURN  E'\n Usando '|| v_n ||' registros de '||$1;
    ELSE  
      RAISE EXCEPTION 'Preparar % não-vazio com lib.r008a_quadra()',$1;
    END IF;
  ELSE
    RAISE EXCEPTION 'Falta criar % com lib.r008a_quadra()',$1;
  END IF;
END;
$F$ LANGUAGE PLpgSQL VOLATILE;
COMMENT ON FUNCTION lib.table_not_empty(text) IS 'Check if given table name exists and is not empty.

Throws EXCEPTION if table name does not exists on current database or if table has no rows.';

CREATE OR REPLACE  FUNCTION lib.r008b_seg(
	p_width_via double precision DEFAULT 0.5, 
	p_reduz double precision DEFAULT 0.5, 
	p_area_min double precision DEFAULT 10.0, 
	p_cobertura double precision DEFAULT 0.51, 
	p_simplfactor double precision DEFAULT 0.2
) RETURNS text LANGUAGE plpgsql
    AS $_$  -- retorna mensagem de erro
DECLARE
   v_msg text := format('Parametros width_via=%s, reduz=%s, area_min=%s, cobertura=%s, simplft=%s',$1,$2,$3,$4,$5);
BEGIN
   PERFORM lib.in_range($1, 1, 0.0, 5.0,    'largura da via');
   PERFORM lib.in_range($2, 2, 0.0, 5.0,    'raio do buffer de redução');
   PERFORM lib.in_range($3, 3, 0.0, 1000.0, 'area mínima da quadra');
   PERFORM lib.in_range($4, 4, 0.001, 1.0,  'fator de cobertura mínima');
   PERFORM lib.in_range($5, 5, 0.0, 10.0,   'step na simplificação dos segmentos');
   v_msg := v_msg || lib.table_not_empty('kx.eixologr_cod');
   v_msg := v_msg || lib.table_not_empty('kx.quadraccvia');
 
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
      )
      SELECT 
        row_number() OVER () AS gid,
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
   ALTER TABLE kx.quadraccvia_simplseg ADD  primary key (gid); -- 73ms
   -- NAO USAR CREATE INDEX ON kx.quadraccvia_simplseg USING GIST(seg); deu pau 
 
   -- 2. Encontrando a via (cod) associada a cada segmento:  (OTIMIZAR!)
   UPDATE kx.quadraccvia_simplseg
      SET gid_via=t.egid, cod=t.cod, tipo_via=t.tipo
   FROM (
      SELECT s.gid AS sgid, e.gid AS egid, e.cod, e.tipo
      FROM kx.quadraccvia_simplseg s INNER JOIN (SELECT *, ST_Buffer(geom,2*($1+$2+$5)) AS buff FROM kx.eixologr_cod) e 
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
 
 
CREATE OR REPLACE FUNCTION lib.r008_assigncoddist(
   --
   -- usa kx.quadraccvia_simplface de quadraccvia_gid para classificar via de segmento dado
   --
  p_gid_qcc  bigint,  -- gid da quadraccvia em questao
  p_geom     geometry, -- segmento de quadrasc,
  p_raio float DEFAULT 25.0,
  p_step float DEFAULT 1.8       -- tamanho das tiras de verificação (2m)
) RETURNS text AS $F$ 
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
END;
$F$ LANGUAGE PLpgSQL;

END
$DO$;
