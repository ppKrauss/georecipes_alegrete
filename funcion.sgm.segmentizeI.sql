DROP FUNCTION IF EXISTS sgm.segmentizeI( geom geometry );
CREATE OR REPLACE FUNCTION sgm.segmentizeI( geo geometry )
RETURNS TABLE( path integer, geom geometry )
AS
$$
DECLARE
  line geometry;
  counter integer NOT NULL := 1;
BEGIN
  geo := st_multi( geo );
  IF st_geometrytype( geo ) != 'ST_MultiLineString' THEN
    RAISE EXCEPTION 'Invalid geometry with type % received. Expected [ST_LineString|ST_MultiLineString].', st_geometrytype( geo );
  END IF;
  FOR i IN 1..st_NumGeometries( geo )
  LOOP
    line := st_geometryn( geo, i );
    FOR j IN 1..(st_npoints( line ) - 1)
    LOOP
      RETURN QUERY SELECT counter, st_makeline( st_pointn( line, j ), st_pointn( line, j + 1  ) );
      counter := counter + 1;
    END LOOP;
  END LOOP;
END
$$
LANGUAGE plpgsql;
COMMENT ON FUNCTION sgm.segmentize( geometry ) IS 
'Converte uma linha em segmentos de linha';