-- Function: lib.r008b_seg(double precision, double precision, double precision, double precision, double precision)

-- DROP FUNCTION lib.r008b_seg(double precision, double precision, double precision, double precision, double precision);

CREATE OR REPLACE FUNCTION lib.r008b_seg(p_width_via double precision DEFAULT 0.5, p_reduz double precision DEFAULT 0.5, p_area_min double precision DEFAULT 10.0, p_cobertura double precision DEFAULT 0.51, p_simplfactor double precision DEFAULT 0.2)
  RETURNS text AS
$BODY$  -- retorna mensagem de erro
DECLARE
   v_msg text := format('Parametros width_via=%s, reduz=%s, area_min=%s, cobertura=%s, simplft=%s',$1,$2,$3,$4,$5);
BEGIN
   PERFORM lib.r008_err_range($1, 1, 0.0, 5.0,    'largura da via');
   PERFORM lib.r008_err_range($2, 2, 0.0, 5.0,    'raio do buffer de redução');
   PERFORM lib.r008_err_range($3, 3, 0.0, 1000.0, 'area mínima da quadra');
   PERFORM lib.r008_err_range($4, 4, 0.001, 1.0,  'fator de cobertura mínima');
   PERFORM lib.r008_err_range($5, 5, 0.0, 10.0,   'step na simplificação dos segmentos');
   v_msg := v_msg || lib.r008_err_exists('kx.eixologr_cod');
   v_msg := v_msg || lib.r008_err_exists('kx.quadraccvia');
 
   -- 1. segmentação da quadraccvia:
  BEGIN
    DROP TABLE IF EXISTS kx.quadraccvia_simplseg;
    CREATE TABLE kx.quadraccvia_simplseg AS
      SELECT -- simplificando segmentos menores que 0.2m
        row_number() OVER() AS gid
      , gid AS gid_quadra
      , cod_vias
      , (sgm.segmentizei( ST_Boundary( ST_SimplifyPreserveTopology( geom, p_simplfactor ) ) )).path AS id_seg
      , NULL::bigint AS gid_via
      , NULL::text AS tipo_via
      , NULL::bigint AS gid_marginal  -- quando existor vizinha
      , NULL::int AS cod
      , (sgm.segmentizei( ST_Boundary( ST_SimplifyPreserveTopology( geom, p_simplfactor ) ) )).geom AS seg
      FROM kx.quadraccvia;
  EXCEPTION
  WHEN SQLSTATE '42501' THEN
    TRUNCATE kx.quadraccvia_simplseg;
    INSERT INTO kx.quadraccvia_simplseg
      SELECT -- simplificando segmentos menores que 0.2m
        row_number() OVER() AS gid
      , gid AS gid_quadra
      , cod_vias
      , (sgm.segmentizei( ST_Boundary( ST_SimplifyPreserveTopology( geom, p_simplfactor ) ) )).path AS id_seg
      , NULL::bigint AS gid_via
      , NULL::text AS tipo_via
      , NULL::bigint AS gid_marginal  -- quando existor vizinha
      , NULL::int AS cod
      , (sgm.segmentizei( ST_Boundary( ST_SimplifyPreserveTopology( geom, p_simplfactor ) ) )).geom AS seg
      FROM kx.quadraccvia;
  END;

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
$BODY$ LANGUAGE plpgsql VOLATILE  COST 100;






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
----
    CREATE TABLE kx.quadraccvia_simplseg AS
      SELECT -- simplificando segmentos menores que 0.2m
        row_number() OVER() AS gid
      , gid AS gid_quadra
      , cod_vias
      , (sgm.segmentizei( ST_Boundary( ST_SimplifyPreserveTopology( geom, p_simplfactor ) ) )).path AS id_seg
      , NULL::bigint AS gid_via
      , NULL::text AS tipo_via
      , NULL::bigint AS gid_marginal  -- quando existor vizinha
      , NULL::int AS cod
      , (sgm.segmentizei( ST_Boundary( ST_SimplifyPreserveTopology( geom, p_simplfactor ) ) )).geom AS seg
      FROM kx.quadraccvia;
  EXCEPTION
  WHEN SQLSTATE '42501' THEN
    TRUNCATE kx.quadraccvia_simplseg;
    INSERT INTO kx.quadraccvia_simplseg
      SELECT -- simplificando segmentos menores que 0.2m
        row_number() OVER() AS gid
      , gid AS gid_quadra
      , cod_vias
      , (sgm.segmentizei( ST_Boundary( ST_SimplifyPreserveTopology( geom, p_simplfactor ) ) )).path AS id_seg
      , NULL::bigint AS gid_via
      , NULL::text AS tipo_via
      , NULL::bigint AS gid_marginal  -- quando existor vizinha
      , NULL::int AS cod
      , (sgm.segmentizei( ST_Boundary( ST_SimplifyPreserveTopology( geom, p_simplfactor ) ) )).geom AS seg
      FROM kx.quadraccvia;
  END;



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
