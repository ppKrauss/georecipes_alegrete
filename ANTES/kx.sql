--
-- PostgreSQL database dump
--

SET statement_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;

--
-- Name: kx; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA kx;


ALTER SCHEMA kx OWNER TO postgres;

SET search_path = kx, pg_catalog;

--
-- Name: f_quadrasc_simplseg_cods(integer); Type: FUNCTION; Schema: kx; Owner: alegrete
--

CREATE FUNCTION f_quadrasc_simplseg_cods(p_gid_seg integer) RETURNS integer
    LANGUAGE sql IMMUTABLE
    AS $_$
  SELECT cod -- cod da via
  FROM kx.quadrasc_simplseg_cods
  WHERE gid=$1
  ORDER BY dist  -- mais próxima tem menor dist
  LIMIT 1
$_$;


ALTER FUNCTION kx.f_quadrasc_simplseg_cods(p_gid_seg integer) OWNER TO alegrete;

SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: eixologr_cod; Type: TABLE; Schema: kx; Owner: alegrete; Tablespace: 
--

CREATE TABLE eixologr_cod (
    gid bigint NOT NULL,
    cod integer,
    tipo text,
    geom public.geometry
);


ALTER TABLE kx.eixologr_cod OWNER TO alegrete;

--
-- Name: lote_seg; Type: TABLE; Schema: kx; Owner: alegrete; Tablespace: 
--

CREATE TABLE lote_seg (
    gid bigint,
    gid_lote integer,
    chave integer,
    gid_quadrasc integer,
    id_seg integer,
    id_via integer,
    isexterno boolean,
    isfronteira boolean,
    seg public.geometry
);


ALTER TABLE kx.lote_seg OWNER TO alegrete;

--
-- Name: lote_viz; Type: TABLE; Schema: kx; Owner: alegrete; Tablespace: 
--

CREATE TABLE lote_viz (
    id integer NOT NULL,
    a_gid integer NOT NULL,
    b_gid integer NOT NULL,
    viz_tipo double precision,
    relcod character varying(12),
    err character varying(64)
);


ALTER TABLE kx.lote_viz OWNER TO alegrete;

--
-- Name: lote_viz_id_seq; Type: SEQUENCE; Schema: kx; Owner: alegrete
--

CREATE SEQUENCE lote_viz_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE kx.lote_viz_id_seq OWNER TO alegrete;

--
-- Name: lote_viz_id_seq; Type: SEQUENCE OWNED BY; Schema: kx; Owner: alegrete
--

ALTER SEQUENCE lote_viz_id_seq OWNED BY lote_viz.id;


--
-- Name: quadraccvia; Type: TABLE; Schema: kx; Owner: alegrete; Tablespace: 
--

CREATE TABLE quadraccvia (
    gid integer NOT NULL,
    geom public.geometry,
    cod_vias integer[]
);


ALTER TABLE kx.quadraccvia OWNER TO alegrete;

--
-- Name: quadraccvia_simplface; Type: TABLE; Schema: kx; Owner: alegrete; Tablespace: 
--

CREATE TABLE quadraccvia_simplface (
    gid_quadra integer,
    cod integer,
    max integer,
    gids bigint[],
    seg public.geometry
);


ALTER TABLE kx.quadraccvia_simplface OWNER TO alegrete;

--
-- Name: quadraccvia_simplseg; Type: TABLE; Schema: kx; Owner: alegrete; Tablespace: 
--

CREATE TABLE quadraccvia_simplseg (
    gid bigint,
    gid_quadra integer,
    id_seg integer,
    gid_via bigint,
    tipo_via text,
    gid_marginal bigint,
    cod integer,
    seg public.geometry
);


ALTER TABLE kx.quadraccvia_simplseg OWNER TO alegrete;

--
-- Name: quadrasc; Type: TABLE; Schema: kx; Owner: alegrete; Tablespace: 
--

CREATE TABLE quadrasc (
    gid integer NOT NULL,
    gid_lotes integer[],
    err text,
    gid_vias integer[],
    geom public.geometry,
    kx_temfalha boolean DEFAULT false,
    autorrected boolean DEFAULT false,
    quadra_gid bigint,
    quadraccvia_gid bigint
);


ALTER TABLE kx.quadrasc OWNER TO alegrete;

--
-- Name: quadrasc_bk0preedit; Type: TABLE; Schema: kx; Owner: alegrete; Tablespace: 
--

CREATE TABLE quadrasc_bk0preedit (
    gid integer,
    gid_lotes integer[],
    quadra_gids integer[],
    err text,
    geom public.geometry
);


ALTER TABLE kx.quadrasc_bk0preedit OWNER TO alegrete;

--
-- Name: quadrasc_simplseg; Type: TABLE; Schema: kx; Owner: alegrete; Tablespace: 
--

CREATE TABLE quadrasc_simplseg (
    gid bigint,
    gid_quadrasc integer,
    quadra_gid bigint,
    id_seg integer,
    isexterno boolean,
    isexterno_fator integer,
    id_via integer,
    seg public.geometry
);


ALTER TABLE kx.quadrasc_simplseg OWNER TO alegrete;

--
-- Name: quadrasc_simplseg_bk0preedit; Type: TABLE; Schema: kx; Owner: alegrete; Tablespace: 
--

CREATE TABLE quadrasc_simplseg_bk0preedit (
    gid bigint,
    gid_quadrasc integer,
    quadra_gids integer[],
    id_seg integer,
    isexterno boolean,
    isexterno_fator integer,
    id_via integer,
    seg public.geometry
);


ALTER TABLE kx.quadrasc_simplseg_bk0preedit OWNER TO alegrete;

--
-- Name: quadrasc_simplseg_cods; Type: TABLE; Schema: kx; Owner: alegrete; Tablespace: 
--

CREATE TABLE quadrasc_simplseg_cods (
    gid bigint,
    gid_quadrasc integer,
    id_quadrasc_seg integer,
    gid_logr bigint,
    cod integer,
    dist double precision
);


ALTER TABLE kx.quadrasc_simplseg_cods OWNER TO alegrete;

--
-- Name: temp_r008a; Type: TABLE; Schema: kx; Owner: alegrete; Tablespace: 
--

CREATE TABLE temp_r008a (
    cod integer,
    geom public.geometry,
    mask public.geometry,
    seg public.geometry
);


ALTER TABLE kx.temp_r008a OWNER TO alegrete;

--
-- Name: temp_r016a; Type: TABLE; Schema: kx; Owner: alegrete; Tablespace: 
--

CREATE TABLE temp_r016a (
    gid bigint,
    cod numeric,
    geom public.geometry,
    seg public.geometry,
    lsoma numeric,
    lcada numeric,
    nparts integer,
    parallel_factor integer,
    isparalelo boolean
);


ALTER TABLE kx.temp_r016a OWNER TO alegrete;

--
-- Name: temp_r016b; Type: TABLE; Schema: kx; Owner: alegrete; Tablespace: 
--

CREATE TABLE temp_r016b (
    geom public.geometry
);


ALTER TABLE kx.temp_r016b OWNER TO alegrete;

--
-- Name: vw_lote_viz_err; Type: VIEW; Schema: kx; Owner: alegrete
--

CREATE VIEW vw_lote_viz_err AS
    SELECT t.gid, array_to_string(array_agg(((alegrete.iif((t.gid = t.a_gid), t.b_gid, t.a_gid) || ' '::text) || (t.err)::text)), '; '::text) AS err FROM (SELECT unnest(ARRAY[lote_viz.a_gid, lote_viz.b_gid]) AS gid, lote_viz.a_gid, lote_viz.b_gid, lote_viz.err FROM lote_viz WHERE (((lote_viz.err)::text > ''::text) AND (lote_viz.viz_tipo = (0)::double precision)) ORDER BY unnest(ARRAY[lote_viz.a_gid, lote_viz.b_gid])) t GROUP BY t.gid ORDER BY t.gid;


ALTER TABLE kx.vw_lote_viz_err OWNER TO alegrete;

--
-- Name: vw_quadracjoin; Type: VIEW; Schema: kx; Owner: alegrete
--

CREATE VIEW vw_quadracjoin AS
    SELECT sc.gid, sc.gid_lotes, sc.err, sc.gid_vias, sc.geom, sc.kx_temfalha, sc.autorrected, sc.quadra_gid, sc.quadraccvia_gid, cc.cod_vias AS qccvia_codvias, cc.geom AS qccvia_geom FROM (quadraccvia cc JOIN quadrasc sc ON ((sc.quadraccvia_gid = cc.gid)));


ALTER TABLE kx.vw_quadracjoin OWNER TO alegrete;

--
-- Name: id; Type: DEFAULT; Schema: kx; Owner: alegrete
--

ALTER TABLE ONLY lote_viz ALTER COLUMN id SET DEFAULT nextval('lote_viz_id_seq'::regclass);


--
-- Name: eixologr_cod_pkey; Type: CONSTRAINT; Schema: kx; Owner: alegrete; Tablespace: 
--

ALTER TABLE ONLY eixologr_cod
    ADD CONSTRAINT eixologr_cod_pkey PRIMARY KEY (gid);


--
-- Name: pk; Type: CONSTRAINT; Schema: kx; Owner: alegrete; Tablespace: 
--

ALTER TABLE ONLY lote_viz
    ADD CONSTRAINT pk PRIMARY KEY (a_gid, b_gid);


--
-- Name: quadraccvia_pkey; Type: CONSTRAINT; Schema: kx; Owner: alegrete; Tablespace: 
--

ALTER TABLE ONLY quadraccvia
    ADD CONSTRAINT quadraccvia_pkey PRIMARY KEY (gid);


--
-- Name: quadrasc_pkey; Type: CONSTRAINT; Schema: kx; Owner: alegrete; Tablespace: 
--

ALTER TABLE ONLY quadrasc
    ADD CONSTRAINT quadrasc_pkey PRIMARY KEY (gid);


--
-- Name: uk; Type: CONSTRAINT; Schema: kx; Owner: alegrete; Tablespace: 
--

ALTER TABLE ONLY quadraccvia_simplface
    ADD CONSTRAINT uk UNIQUE (gid_quadra, cod);


--
-- Name: kx; Type: ACL; Schema: -; Owner: postgres
--

REVOKE ALL ON SCHEMA kx FROM PUBLIC;
REVOKE ALL ON SCHEMA kx FROM postgres;
GRANT ALL ON SCHEMA kx TO postgres;
GRANT ALL ON SCHEMA kx TO alegrete;
GRANT ALL ON SCHEMA kx TO peter;


--
-- PostgreSQL database dump complete
--

