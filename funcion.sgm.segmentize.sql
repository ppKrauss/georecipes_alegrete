CREATE OR REPLACE FUNCTION sgm.segmentize( geom geometry )
RETURNS SETOF geometry
AS
$$
DECLARE
  line geometry;
BEGIN
  geom := st_multi( geom );
  IF st_geometrytype( geom ) != 'ST_MultiLineString' THEN
    RAISE EXCEPTION 'Invalid geometry with type % received. Expected [ST_LineString|ST_MultiLineString].', st_geometrytype( geom );
  END IF;
  FOR i IN 1..st_NumGeometries( geom )
  LOOP
    line := st_geometryn( geom, i );
    FOR j IN 1..(st_npoints( line ) - 1)
    LOOP
      RETURN NEXT st_makeline( st_pointn( line, j ), st_pointn( line, j + 1  ) );
    END LOOP;
  END LOOP;
  RETURN;
END
$$
LANGUAGE plpgsql;
COMMENT ON FUNCTION sgm.segmentize( geometry ) IS 
'Converte uma linha em segmentos de linha';