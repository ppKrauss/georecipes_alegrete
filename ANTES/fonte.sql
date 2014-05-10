--
-- PostgreSQL database dump
--

SET statement_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;

--
-- Name: fonte; Type: SCHEMA; Schema: -; Owner: alegrete
--

CREATE SCHEMA fonte;


ALTER SCHEMA fonte OWNER TO alegrete;

SET search_path = fonte, pg_catalog;

--
-- Name: check_err_id(integer[], boolean); Type: FUNCTION; Schema: fonte; Owner: alegrete
--

CREATE FUNCTION check_err_id(integer[], boolean DEFAULT NULL::boolean) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    AS $_$
  SELECT COALESCE( array_Length($1,1) = ( 
     SELECT COUNT(*) 
     FROM fonte.tadm_error_type f INNER JOIN (SELECT unnest($1) AS ecod) t
       ON f.err_cod=t.ecod
  ), $2 );
$_$;


ALTER FUNCTION fonte.check_err_id(integer[], boolean) OWNER TO alegrete;

--
-- Name: merge_tadm_error(regclass, integer, integer, character varying, text); Type: FUNCTION; Schema: fonte; Owner: alegrete
--

CREATE FUNCTION merge_tadm_error(p_oid regclass, p_gid integer, p_err_cod integer, p_state character varying DEFAULT 'new'::character varying, p_details text DEFAULT NULL::text) RETURNS integer
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION fonte.merge_tadm_error(p_oid regclass, p_gid integer, p_err_cod integer, p_state character varying, p_details text) OWNER TO alegrete;

--
-- Name: tadm_haserror(regclass); Type: FUNCTION; Schema: fonte; Owner: alegrete
--

CREATE FUNCTION tadm_haserror(regclass) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    AS $_$
  SELECT COALESCE( 
    (SELECT true FROM fonte.tadm_error_row WHERE oid=$1 AND kx_open_error_cods IS NOT NULL), 
    false
  );
$_$;


ALTER FUNCTION fonte.tadm_haserror(regclass) OWNER TO alegrete;

--
-- Name: tadm_haserror(regclass, integer); Type: FUNCTION; Schema: fonte; Owner: alegrete
--

CREATE FUNCTION tadm_haserror(regclass, p_gid integer) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    AS $_$
  SELECT COALESCE( 
    ( SELECT true FROM fonte.vw_tadm_error 
      WHERE oid=$1 AND gid=$2 AND state!='closed'
    ), 
    false
  );
$_$;


ALTER FUNCTION fonte.tadm_haserror(regclass, p_gid integer) OWNER TO alegrete;

--
-- Name: tadm_haserror_byid(integer); Type: FUNCTION; Schema: fonte; Owner: alegrete
--

CREATE FUNCTION tadm_haserror_byid(p_id integer) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    AS $_$
  SELECT COALESCE( 
    ( SELECT true FROM fonte.vw_tadm_error 
      WHERE id=$1 AND state!='closed'
    ), 
    false
  );
$_$;


ALTER FUNCTION fonte.tadm_haserror_byid(p_id integer) OWNER TO alegrete;

--
-- Name: tadm_haserrorreason(regclass, integer); Type: FUNCTION; Schema: fonte; Owner: alegrete
--

CREATE FUNCTION tadm_haserrorreason(regclass, integer) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $_$  
       -- function name with "reason" like  ST_IsValidReason
    SELECT 'ERROR cod.'||err_cod||' in '||state||' at '||state_date||': '||details
    FROM fonte.vw_tadm_error 
    WHERE oid=$1 AND gid=$2 AND state!='closed'
$_$;


ALTER FUNCTION fonte.tadm_haserrorreason(regclass, integer) OWNER TO alegrete;

--
-- Name: tadm_isapproved(regclass, integer); Type: FUNCTION; Schema: fonte; Owner: alegrete
--

CREATE FUNCTION tadm_isapproved(regclass, integer DEFAULT NULL::integer) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    AS $_$
  SELECT CASE WHEN $2 IS NOT NULL THEN NOT(fonte.tadm_hasError($1,$2)) 
         ELSE NOT(fonte.tadm_hasError($1))
         END;
$_$;


ALTER FUNCTION fonte.tadm_isapproved(regclass, integer) OWNER TO alegrete;

--
-- Name: g_eixologr_gid_seq; Type: SEQUENCE; Schema: fonte; Owner: alegrete
--

CREATE SEQUENCE g_eixologr_gid_seq
    START WITH 2629
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE fonte.g_eixologr_gid_seq OWNER TO alegrete;

SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: g_eixologr; Type: TABLE; Schema: fonte; Owner: alegrete; Tablespace: 
--

CREATE TABLE g_eixologr (
    gid integer DEFAULT nextval('g_eixologr_gid_seq'::regclass) NOT NULL,
    codlogr numeric,
    tipologr character varying(254),
    nomelogr character varying(254),
    n_ini_dir numeric,
    n_fim_dir numeric,
    n_ini_esq numeric,
    n_fim_esq numeric,
    corredor character varying(10),
    geom public.geometry(LineString) NOT NULL,
    CONSTRAINT chk_dimcia CHECK ((((public.st_ndims(geom) = 2) AND public.st_issimple(geom)) AND public.st_isvalid(geom)))
);


ALTER TABLE fonte.g_eixologr OWNER TO alegrete;

--
-- Name: g_lote_gid_seq; Type: SEQUENCE; Schema: fonte; Owner: alegrete
--

CREATE SEQUENCE g_lote_gid_seq
    START WITH 25912
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE fonte.g_lote_gid_seq OWNER TO alegrete;

--
-- Name: g_lote; Type: TABLE; Schema: fonte; Owner: alegrete; Tablespace: 
--

CREATE TABLE g_lote (
    gid integer DEFAULT nextval('g_lote_gid_seq'::regclass) NOT NULL,
    chave integer,
    area_geom numeric,
    lote smallint,
    edifica smallint,
    bci smallint,
    problemas smallint,
    operador character varying(2),
    geom public.geometry(Polygon) NOT NULL,
    kx_quadra_gid integer DEFAULT 0 NOT NULL,
    kx_quadrasc_id integer DEFAULT 0 NOT NULL,
    kx_temfalha boolean DEFAULT false,
    autorrected boolean DEFAULT false,
    CONSTRAINT chk_dimcia CHECK ((((public.st_ndims(geom) = 2) AND public.st_issimple(geom)) AND public.st_isvalid(geom)))
);


ALTER TABLE fonte.g_lote OWNER TO alegrete;

--
-- Name: g_quadra_gid_seq; Type: SEQUENCE; Schema: fonte; Owner: alegrete
--

CREATE SEQUENCE g_quadra_gid_seq
    START WITH 1011
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE fonte.g_quadra_gid_seq OWNER TO alegrete;

--
-- Name: g_quadra; Type: TABLE; Schema: fonte; Owner: alegrete; Tablespace: 
--

CREATE TABLE g_quadra (
    gid integer DEFAULT nextval('g_quadra_gid_seq'::regclass) NOT NULL,
    id integer,
    geom public.geometry(Polygon) NOT NULL,
    kx_temfalha boolean DEFAULT false,
    kx_gidvias bigint[],
    CONSTRAINT chk_dimcia CHECK ((((public.st_ndims(geom) = 2) AND public.st_issimple(geom)) AND public.st_isvalid(geom)))
);


ALTER TABLE fonte.g_quadra OWNER TO alegrete;

--
-- Name: tadm_catalog; Type: TABLE; Schema: fonte; Owner: alegrete; Tablespace: 
--

CREATE TABLE tadm_catalog (
    oid regclass NOT NULL,
    prj_id integer NOT NULL,
    created timestamp with time zone DEFAULT now() NOT NULL,
    last_update timestamp with time zone DEFAULT now() NOT NULL,
    last_refresh timestamp with time zone,
    refresh_mode integer DEFAULT 0 NOT NULL,
    geom_type character varying(32),
    ref_isrural boolean DEFAULT false NOT NULL,
    ref_snapgrid double precision,
    ref_pos_error double precision,
    ref_min double precision,
    validation_list integer[],
    mapfile xml,
    kx_ndims integer,
    kx_geom_srid integer
);


ALTER TABLE fonte.tadm_catalog OWNER TO alegrete;

--
-- Name: tadm_error_row; Type: TABLE; Schema: fonte; Owner: alegrete; Tablespace: 
--

CREATE TABLE tadm_error_row (
    id integer NOT NULL,
    oid regclass,
    gid integer,
    kx_last_state_date timestamp without time zone DEFAULT now(),
    kx_worst_state character varying(12),
    kx_open_error_cods integer[],
    CONSTRAINT tadm_error_row_kx_open_error_cods_check CHECK (check_err_id(kx_open_error_cods))
);


ALTER TABLE fonte.tadm_error_row OWNER TO alegrete;

--
-- Name: tadm_error_row_id_seq; Type: SEQUENCE; Schema: fonte; Owner: alegrete
--

CREATE SEQUENCE tadm_error_row_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE fonte.tadm_error_row_id_seq OWNER TO alegrete;

--
-- Name: tadm_error_row_id_seq; Type: SEQUENCE OWNED BY; Schema: fonte; Owner: alegrete
--

ALTER SEQUENCE tadm_error_row_id_seq OWNED BY tadm_error_row.id;


--
-- Name: tadm_error_track; Type: TABLE; Schema: fonte; Owner: alegrete; Tablespace: 
--

CREATE TABLE tadm_error_track (
    id_row integer NOT NULL,
    err_cod integer NOT NULL,
    state character varying(22),
    state_date timestamp without time zone DEFAULT now(),
    details text
);


ALTER TABLE fonte.tadm_error_track OWNER TO alegrete;

--
-- Name: tadm_error_type; Type: TABLE; Schema: fonte; Owner: alegrete; Tablespace: 
--

CREATE TABLE tadm_error_type (
    err_cod integer NOT NULL,
    err_cod_name character varying(64) NOT NULL,
    err_cod_description text
);


ALTER TABLE fonte.tadm_error_type OWNER TO alegrete;

--
-- Name: tadm_error_type_err_cod_seq; Type: SEQUENCE; Schema: fonte; Owner: alegrete
--

CREATE SEQUENCE tadm_error_type_err_cod_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE fonte.tadm_error_type_err_cod_seq OWNER TO alegrete;

--
-- Name: tadm_error_type_err_cod_seq; Type: SEQUENCE OWNED BY; Schema: fonte; Owner: alegrete
--

ALTER SEQUENCE tadm_error_type_err_cod_seq OWNED BY tadm_error_type.err_cod;


--
-- Name: tadm_prjcatalog; Type: TABLE; Schema: fonte; Owner: alegrete; Tablespace: 
--

CREATE TABLE tadm_prjcatalog (
    framework_prjname character varying(32) DEFAULT 'SGM'::character varying NOT NULL,
    framework_url character varying(255) DEFAULT 'http://gauss.serveftp.com/colabore/index.php/Prj:SGM'::character varying NOT NULL,
    prj_id integer NOT NULL,
    prj_geoname character varying(64) NOT NULL,
    prj_geoname_srid integer NOT NULL,
    prj_created timestamp with time zone DEFAULT now() NOT NULL,
    max_envelope public.geometry(Polygon),
    notes text,
    CONSTRAINT tadm_prjcatalog_check CHECK ((public.st_srid(max_envelope) = prj_geoname_srid))
);


ALTER TABLE fonte.tadm_prjcatalog OWNER TO alegrete;

--
-- Name: tadm_prjcatalog_prj_id_seq; Type: SEQUENCE; Schema: fonte; Owner: alegrete
--

CREATE SEQUENCE tadm_prjcatalog_prj_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE fonte.tadm_prjcatalog_prj_id_seq OWNER TO alegrete;

--
-- Name: tadm_prjcatalog_prj_id_seq; Type: SEQUENCE OWNED BY; Schema: fonte; Owner: alegrete
--

ALTER SEQUENCE tadm_prjcatalog_prj_id_seq OWNED BY tadm_prjcatalog.prj_id;


--
-- Name: vw_tadm_catalog_prj; Type: VIEW; Schema: fonte; Owner: alegrete
--

CREATE VIEW vw_tadm_catalog_prj AS
    SELECT c.oid, c.prj_id, c.created, c.last_update, c.last_refresh, c.refresh_mode, c.geom_type, c.ref_isrural, c.ref_snapgrid, c.ref_pos_error, c.ref_min, c.validation_list, c.mapfile, c.kx_ndims, c.kx_geom_srid, (((p.framework_prjname)::text || '/'::text) || (p.prj_geoname)::text) AS prjname, p.prj_geoname_srid, p.prj_created FROM (tadm_catalog c JOIN tadm_prjcatalog p ON ((c.prj_id = p.prj_id)));


ALTER TABLE fonte.vw_tadm_catalog_prj OWNER TO alegrete;

--
-- Name: vw_tadm_catalog_full; Type: VIEW; Schema: fonte; Owner: alegrete
--

CREATE VIEW vw_tadm_catalog_full AS
    SELECT f.oid, f.prj_id, f.created, f.last_update, f.last_refresh, f.refresh_mode, f.geom_type, f.ref_isrural, f.ref_snapgrid, f.ref_pos_error, f.ref_min, f.validation_list, f.mapfile, f.kx_ndims, f.kx_geom_srid, f.prjname, f.prj_geoname_srid, f.prj_created, (current_database())::character varying(256) AS f_table_catalog, (n.nspname)::character varying(256) AS f_table_schema, (c.relname)::character varying(256) AS f_table_name, (a.attname)::character varying(256) AS f_geometry_column, COALESCE(NULLIF(public.postgis_typmod_dims(a.atttypmod), 2), public.postgis_constraint_dims((n.nspname)::text, (c.relname)::text, (a.attname)::text), 2) AS coord_dimension, (replace(replace(COALESCE(NULLIF(upper(public.postgis_typmod_type(a.atttypmod)), 'GEOMETRY'::text), (public.postgis_constraint_type((n.nspname)::text, (c.relname)::text, (a.attname)::text))::text, 'GEOMETRY'::text), 'ZM'::text, ''::text), 'Z'::text, ''::text))::character varying(30) AS type FROM pg_class c, pg_attribute a, pg_type t, pg_namespace n, vw_tadm_catalog_prj f WHERE ((((((((((c.oid = (f.oid)::oid) AND (t.typname = 'geometry'::name)) AND (a.attisdropped = false)) AND (a.atttypid = t.oid)) AND (a.attrelid = c.oid)) AND (c.relnamespace = n.oid)) AND ((c.relkind = 'r'::"char") OR (c.relkind = 'v'::"char"))) AND (NOT pg_is_other_temp_schema(c.relnamespace))) AND (NOT ((n.nspname = 'public'::name) AND (c.relname = 'raster_columns'::name)))) AND has_table_privilege(c.oid, 'SELECT'::text));


ALTER TABLE fonte.vw_tadm_catalog_full OWNER TO alegrete;

--
-- Name: vw_tadm_error; Type: VIEW; Schema: fonte; Owner: alegrete
--

CREATE VIEW vw_tadm_error AS
    SELECT r.id, r.oid, r.gid, k.err_cod, t.err_cod_name, k.state, k.state_date, k.details FROM ((tadm_error_row r JOIN tadm_error_track k ON ((r.id = k.id_row))) JOIN tadm_error_type t ON ((k.err_cod = t.err_cod)));


ALTER TABLE fonte.vw_tadm_error OWNER TO alegrete;

--
-- Name: id; Type: DEFAULT; Schema: fonte; Owner: alegrete
--

ALTER TABLE ONLY tadm_error_row ALTER COLUMN id SET DEFAULT nextval('tadm_error_row_id_seq'::regclass);


--
-- Name: err_cod; Type: DEFAULT; Schema: fonte; Owner: alegrete
--

ALTER TABLE ONLY tadm_error_type ALTER COLUMN err_cod SET DEFAULT nextval('tadm_error_type_err_cod_seq'::regclass);


--
-- Name: prj_id; Type: DEFAULT; Schema: fonte; Owner: alegrete
--

ALTER TABLE ONLY tadm_prjcatalog ALTER COLUMN prj_id SET DEFAULT nextval('tadm_prjcatalog_prj_id_seq'::regclass);


--
-- Name: g_eixologr_pkey; Type: CONSTRAINT; Schema: fonte; Owner: alegrete; Tablespace: 
--

ALTER TABLE ONLY g_eixologr
    ADD CONSTRAINT g_eixologr_pkey PRIMARY KEY (gid);


--
-- Name: g_lote_pkey; Type: CONSTRAINT; Schema: fonte; Owner: alegrete; Tablespace: 
--

ALTER TABLE ONLY g_lote
    ADD CONSTRAINT g_lote_pkey PRIMARY KEY (gid);


--
-- Name: g_quadra_pkey; Type: CONSTRAINT; Schema: fonte; Owner: alegrete; Tablespace: 
--

ALTER TABLE ONLY g_quadra
    ADD CONSTRAINT g_quadra_pkey PRIMARY KEY (gid);


--
-- Name: tadm_catalog_pkey; Type: CONSTRAINT; Schema: fonte; Owner: alegrete; Tablespace: 
--

ALTER TABLE ONLY tadm_catalog
    ADD CONSTRAINT tadm_catalog_pkey PRIMARY KEY (oid);


--
-- Name: tadm_error_row_oid_gid_key; Type: CONSTRAINT; Schema: fonte; Owner: alegrete; Tablespace: 
--

ALTER TABLE ONLY tadm_error_row
    ADD CONSTRAINT tadm_error_row_oid_gid_key UNIQUE (oid, gid);


--
-- Name: tadm_error_row_pkey; Type: CONSTRAINT; Schema: fonte; Owner: alegrete; Tablespace: 
--

ALTER TABLE ONLY tadm_error_row
    ADD CONSTRAINT tadm_error_row_pkey PRIMARY KEY (id);


--
-- Name: tadm_error_type_pkey; Type: CONSTRAINT; Schema: fonte; Owner: alegrete; Tablespace: 
--

ALTER TABLE ONLY tadm_error_type
    ADD CONSTRAINT tadm_error_type_pkey PRIMARY KEY (err_cod);


--
-- Name: tadm_prjcatalog_framework_prjname_prj_geoname_key; Type: CONSTRAINT; Schema: fonte; Owner: alegrete; Tablespace: 
--

ALTER TABLE ONLY tadm_prjcatalog
    ADD CONSTRAINT tadm_prjcatalog_framework_prjname_prj_geoname_key UNIQUE (framework_prjname, prj_geoname);


--
-- Name: tadm_prjcatalog_framework_prjname_prj_geoname_srid_key; Type: CONSTRAINT; Schema: fonte; Owner: alegrete; Tablespace: 
--

ALTER TABLE ONLY tadm_prjcatalog
    ADD CONSTRAINT tadm_prjcatalog_framework_prjname_prj_geoname_srid_key UNIQUE (framework_prjname, prj_geoname_srid);


--
-- Name: tadm_prjcatalog_pkey; Type: CONSTRAINT; Schema: fonte; Owner: alegrete; Tablespace: 
--

ALTER TABLE ONLY tadm_prjcatalog
    ADD CONSTRAINT tadm_prjcatalog_pkey PRIMARY KEY (prj_id);


--
-- Name: tadm_catalog_prj_id_fkey; Type: FK CONSTRAINT; Schema: fonte; Owner: alegrete
--

ALTER TABLE ONLY tadm_catalog
    ADD CONSTRAINT tadm_catalog_prj_id_fkey FOREIGN KEY (prj_id) REFERENCES tadm_prjcatalog(prj_id);


--
-- Name: tadm_error_track_err_cod_fkey; Type: FK CONSTRAINT; Schema: fonte; Owner: alegrete
--

ALTER TABLE ONLY tadm_error_track
    ADD CONSTRAINT tadm_error_track_err_cod_fkey FOREIGN KEY (err_cod) REFERENCES tadm_error_type(err_cod);


--
-- Name: tadm_error_track_id_row_fkey; Type: FK CONSTRAINT; Schema: fonte; Owner: alegrete
--

ALTER TABLE ONLY tadm_error_track
    ADD CONSTRAINT tadm_error_track_id_row_fkey FOREIGN KEY (id_row) REFERENCES tadm_error_row(id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

