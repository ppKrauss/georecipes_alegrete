--
-- PostgreSQL database dump
--

SET statement_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;

SET search_path = public, pg_catalog;

--
-- Name: arr_first(anyarray, anyelement); Type: FUNCTION; Schema: public; Owner: alegrete
--

CREATE FUNCTION arr_first(arr anyarray, nullreplacer anyelement DEFAULT NULL::unknown) RETURNS anyelement
    LANGUAGE plpgsql
    AS $$
DECLARE
  lower integer;
  highest integer;
BEGIN
  lower = array_lower( arr, 1 );
  IF lower IS NULL THEN
    RETURN anyelement;
  END IF;
  highest = array_upper( arr, 1 );
  WHILE ( lower <= highest )
  LOOP
    IF arr[lower] IS NOT NULL THEN
      RETURN arr[lower];
    END IF;
    lower := lower + 1;
  END LOOP;
  RETURN nullReplacer;
END
$$;


ALTER FUNCTION public.arr_first(arr anyarray, nullreplacer anyelement) OWNER TO alegrete;

--
-- Name: FUNCTION arr_first(arr anyarray, nullreplacer anyelement); Type: COMMENT; Schema: public; Owner: alegrete
--

COMMENT ON FUNCTION arr_first(arr anyarray, nullreplacer anyelement) IS '
Utilitário para seleção do primeiro elemento não nulo em um array e retorno de um valor
padrão se dimensão, array, valor não encontrado.';


--
-- Name: asbinary(geometry); Type: FUNCTION; Schema: public; Owner: alegrete
--

CREATE FUNCTION asbinary(geometry) RETURNS bytea
    LANGUAGE sql
    AS $_$
SELECT public.st_asbinary( $1 );
$_$;


ALTER FUNCTION public.asbinary(geometry) OWNER TO alegrete;

--
-- Name: asewkb(geometry); Type: FUNCTION; Schema: public; Owner: alegrete
--

CREATE FUNCTION asewkb(geometry) RETURNS bytea
    LANGUAGE sql
    AS $_$
SELECT public.st_asewkb( $1 );
$_$;


ALTER FUNCTION public.asewkb(geometry) OWNER TO alegrete;

--
-- Name: envelope(geometry); Type: FUNCTION; Schema: public; Owner: alegrete
--

CREATE FUNCTION envelope(geometry) RETURNS geometry
    LANGUAGE sql
    AS $_$
SELECT public.st_envelope( $1 );
$_$;


ALTER FUNCTION public.envelope(geometry) OWNER TO alegrete;

--
-- Name: extent(geometry); Type: FUNCTION; Schema: public; Owner: alegrete
--

CREATE FUNCTION extent(geometry) RETURNS box2d
    LANGUAGE sql
    AS $_$
SELECT public.st_extent( $1 );
$_$;


ALTER FUNCTION public.extent(geometry) OWNER TO alegrete;

--
-- Name: geomfromtext(text, integer); Type: FUNCTION; Schema: public; Owner: alegrete
--

CREATE FUNCTION geomfromtext(wkt text, srid integer) RETURNS geometry
    LANGUAGE sql
    AS $_$
SELECT public.st_geometryfromtext( $1, $2 );
$_$;


ALTER FUNCTION public.geomfromtext(wkt text, srid integer) OWNER TO alegrete;

--
-- Name: intersects(geometry, geometry); Type: FUNCTION; Schema: public; Owner: alegrete
--

CREATE FUNCTION intersects(geometry, geometry) RETURNS boolean
    LANGUAGE sql
    AS $_$
SELECT public.st_intersects( $1, $2 );
$_$;


ALTER FUNCTION public.intersects(geometry, geometry) OWNER TO alegrete;

--
-- Name: ndims(geometry); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION ndims(geometry) RETURNS smallint
    LANGUAGE sql
    AS $_$
SELECT public.st_ndims( $1 );
$_$;


ALTER FUNCTION public.ndims(geometry) OWNER TO postgres;

--
-- Name: sgm_edif(); Type: FUNCTION; Schema: public; Owner: alegrete
--

CREATE FUNCTION sgm_edif() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  edifVal RECORD;
BEGIN
CASE TG_OP
WHEN 'DELETE' THEN
  DELETE FROM public.g_edif WHERE gid = OLD.gid;
  RETURN OLD;
WHEN 'UPDATE' THEN
  UPDATE public.g_edif SET unidade = NEW.unidade, geom = st_multi( NEW.geom ) WHERE gid = OLD.gid
  RETURNING gid
  INTO edifVal;
WHEN 'INSERT' THEN
  INSERT INTO public.g_edif ( unidade, geom ) VALUES ( NEW.unidade, st_multi( NEW.geom ) )
  RETURNING gid
  INTO edifVal;  
END CASE;
NEW.gid = edifVal.gid;
RETURN NEW;
END
$$;


ALTER FUNCTION public.sgm_edif() OWNER TO alegrete;

--
-- Name: sgm_lote(); Type: FUNCTION; Schema: public; Owner: alegrete
--

CREATE FUNCTION sgm_lote() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  ngid integer NOT NULL := 0;
BEGIN
CASE TG_OP
WHEN 'DELETE' THEN
  DELETE FROM public.g_lote WHERE gid = OLD.gid;
  RETURN OLD;
WHEN 'UPDATE' THEN
  UPDATE public.g_lote SET n_porta_1 = 0, area_bci = 0, n_porta_2 = 0, n_porta_3 = 0, area = 0, geom = st_multi( NEW.geom )
    , distrito = NEW.distrito, zona = NEW.zona, quadra = NEW.quadra, lote = NEW.lote
  WHERE gid = OLD.gid;
  ngid := OLD.gid;
WHEN 'INSERT' THEN
  INSERT INTO public.g_lote ( n_porta_1, area_bci, n_porta_2, n_porta_3, area, the_geom, distrito, zona, quadra, lote )
  VALUES ( 0, 0, 0, 0, 0, st_multi( NEW.geom ), NEW.distrito, NEW.zona, NEW.quadra, NEW.lote )
  RETURNING gid
  INTO ngid;  
END CASE;
NEW.gid = ngid;
RETURN NEW;
END
$$;


ALTER FUNCTION public.sgm_lote() OWNER TO alegrete;

--
-- Name: srid(geometry); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION srid(geometry) RETURNS integer
    LANGUAGE sql
    AS $_$
SELECT public.st_srid( $1 );
$_$;


ALTER FUNCTION public.srid(geometry) OWNER TO postgres;

--
-- Name: version-g_edif-controller(); Type: FUNCTION; Schema: public; Owner: alegrete
--

CREATE FUNCTION "version-g_edif-controller"() RETURNS trigger
    LANGUAGE plpgsql COST 1
    AS $$
BEGIN -- control version for INSERT UPDATE for each row on BEFORE trigger --
  NEW.versionado := ( TG_OP = 'UPDATE' );
  NEW.periodo := tstzrange( now(), null );
  NEW.usuario := "current_user"();
  IF NEW.geom IS NULL THEN
    NEW.area_calc:= 0;
    NEW.gid_lote := 0;
  ELSE
    NEW.area_calc:= st_area( NEW.geom );
    NEW.gid_lote := COALESCE( (SELECT b.gid FROM public.g_lote b WHERE st_centroid( NEW.geom ) && b.geom AND st_intersects( st_centroid( NEW.geom ), b.geom )), 0 );
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION public."version-g_edif-controller"() OWNER TO alegrete;

--
-- Name: FUNCTION "version-g_edif-controller"(); Type: COMMENT; Schema: public; Owner: alegrete
--

COMMENT ON FUNCTION "version-g_edif-controller"() IS '
/**
 * Purpose of this trigger is to control the version column because user could supply dummy values into our 
 * version column, overwrite them with our correct values. Also computes area and lot identifier.
 * </br>The version information is temporal so the order and timing information can be queryed.
 * </br>Here need change record period to be [now-infinity).
 * @author Cristiano Sumariva - sumariva@gmail.com
 * @version 1.1.2 20130405
 * - initial release
 */';


--
-- Name: version-g_edif-hController(); Type: FUNCTION; Schema: public; Owner: alegrete
--

CREATE FUNCTION "version-g_edif-hController"() RETURNS trigger
    LANGUAGE plpgsql COST 1
    AS $$
DECLARE
  final timestamp WITH time zone NOT NULL := now();
  cuser varchar NOT NULL := CURRENT_USER;
  exc boolean NOT NULL := true;
BEGIN -- control version for DELETE UPDATE for each row on AFTER trigger --
  IF TG_OP = 'UPDATE' THEN
    final := lower( NEW.periodo );
    cuser := NEW.usuario;
    exc:= false;
  END IF;
  INSERT INTO public."g_edif_history" ( gid, gid_lote, unidade, area_calc, geom, periodo, versionado, excluido, usuario_old, usuario_NEW ) 
  VALUES ( OLD.gid, OLD.gid_lote, OLD.unidade, OLD.area_calc, OLD.geom, tstzrange( lower( OLD.periodo ), final ), OLD.versionado, exc, OLD.usuario, cuser );
RETURN NEW;
END;
$$;


ALTER FUNCTION public."version-g_edif-hController"() OWNER TO alegrete;

--
-- Name: FUNCTION "version-g_edif-hController"(); Type: COMMENT; Schema: public; Owner: alegrete
--

COMMENT ON FUNCTION "version-g_edif-hController"() IS '
Purpose of this trigger is to control the version column.
</br>The version information is temporal so the order and timing information can be queryed.
</br>Here need change record period to be [OLD-now()) or [OLD-NEW.first].
@author Cristiano Sumariva - sumariva@gmail.com
@version 1.1.2 20130405
- initial release
';


--
-- Name: version-g_lote-controller(); Type: FUNCTION; Schema: public; Owner: alegrete
--

CREATE FUNCTION "version-g_lote-controller"() RETURNS trigger
    LANGUAGE plpgsql COST 1
    AS $$
BEGIN -- control version for INSERT UPDATE for each row on BEFORE trigger --
  NEW.versionado := ( TG_OP = 'UPDATE' );
  NEW.periodo := tstzrange( now(), null );
  NEW.usuario := "current_user"();
  IF NEW.geom IS NULL THEN
    NEW.area:= 0;
  ELSE
    NEW.area:= st_area( NEW.geom );
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION public."version-g_lote-controller"() OWNER TO alegrete;

--
-- Name: FUNCTION "version-g_lote-controller"(); Type: COMMENT; Schema: public; Owner: alegrete
--

COMMENT ON FUNCTION "version-g_lote-controller"() IS '
/**
 * Purpose of this trigger is to control the version column because user could supply dummy values into our 
 * version column, overwrite them with our correct values.
 * </br>The version information is temporal so the order and timing information can be queryed.
 * </br>Here need change record period to be [now-infinity).
 * @author Cristiano Sumariva - sumariva@gmail.com
 * @version 1.1.2 20130405
 * - initial release
 */';


--
-- Name: version-g_lote-hController(); Type: FUNCTION; Schema: public; Owner: alegrete
--

CREATE FUNCTION "version-g_lote-hController"() RETURNS trigger
    LANGUAGE plpgsql COST 1
    AS $$
DECLARE
  final timestamp WITH time zone NOT NULL := now();
  cuser varchar NOT NULL := CURRENT_USER;
  exc boolean NOT NULL := true;
BEGIN -- control version for DELETE UPDATE for each row on AFTER trigger --
  IF TG_OP = 'UPDATE' THEN
    final := lower( NEW.periodo );
    cuser := NEW.usuario;
    exc:= false;
  END IF;  
  INSERT INTO public."g_lote_history" ( gid, n_porta_1, area_bci, n_porta_2, n_porta_3, area, the_geom, distrito, zona, quadra, lote, periodo, versionado, excluido, usuario_old, usuario_NEW ) 
  VALUES ( OLD.gid, OLD.n_porta_1, OLD.area_bci, OLD.n_porta_2, OLD.n_porta_3, OLD.area, OLD.the_geom, OLD.distrito, OLD.zona, OLD.quadra, OLD.lote, tstzrange( lower( OLD.periodo ), final ), OLD.versionado, exc, OLD.usuario, cuser );
RETURN NEW;
END;
$$;


ALTER FUNCTION public."version-g_lote-hController"() OWNER TO alegrete;

--
-- Name: FUNCTION "version-g_lote-hController"(); Type: COMMENT; Schema: public; Owner: alegrete
--

COMMENT ON FUNCTION "version-g_lote-hController"() IS '
Purpose of this trigger is to control the version column.
</br>The version information is temporal so the order and timing information can be queryed.
</br>Here need change record period to be [OLD-now()) or [OLD-NEW.first].
@author Cristiano Sumariva - sumariva@gmail.com
@version 1.1.2 20130405
- initial release
';


SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: g_lote; Type: TABLE; Schema: public; Owner: alegrete; Tablespace: 
--

CREATE TABLE g_lote (
    gid integer NOT NULL,
    chave integer,
    area_geom numeric,
    lote smallint,
    edifica smallint,
    bci smallint,
    problemas smallint,
    operador character varying(2),
    geom geometry(MultiPolygon,31996),
    area_insc double precision,
    setor_insc character varying,
    quadra_insc character varying,
    lote_insc character varying,
    periodo tstzrange DEFAULT tstzrange(now(), NULL::timestamp with time zone),
    versionado boolean DEFAULT false NOT NULL,
    usuario character varying DEFAULT "current_user"() NOT NULL
);


ALTER TABLE public.g_lote OWNER TO alegrete;

--
-- Name: EXEMPLO_LOTE2; Type: TABLE; Schema: public; Owner: alegrete; Tablespace: 
--

CREATE TABLE "EXEMPLO_LOTE2" (
    gid integer NOT NULL,
    "GID" double precision,
    "CHAVE" double precision,
    "AREA_GEOM" double precision,
    "LOTE" double precision,
    "EDIFICA" double precision,
    "BCI" double precision,
    "PROBLEMAS" double precision,
    "OPERADOR" character varying(1),
    the_geom geometry(LineString)
);


ALTER TABLE public."EXEMPLO_LOTE2" OWNER TO alegrete;

--
-- Name: EXEMPLO_LOTE2_gid_seq; Type: SEQUENCE; Schema: public; Owner: alegrete
--

CREATE SEQUENCE "EXEMPLO_LOTE2_gid_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public."EXEMPLO_LOTE2_gid_seq" OWNER TO alegrete;

--
-- Name: EXEMPLO_LOTE2_gid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: alegrete
--

ALTER SEQUENCE "EXEMPLO_LOTE2_gid_seq" OWNED BY "EXEMPLO_LOTE2".gid;


--
-- Name: exemplo_lote; Type: TABLE; Schema: public; Owner: alegrete; Tablespace: 
--

CREATE TABLE exemplo_lote (
    gid integer NOT NULL,
    gid_lote double precision,
    seq integer,
    gid_eixologr integer,
    posicao character varying(1),
    geom geometry(LineString,31996)
);


ALTER TABLE public.exemplo_lote OWNER TO alegrete;

--
-- Name: EXEMPLO_LOTE_gid_seq; Type: SEQUENCE; Schema: public; Owner: alegrete
--

CREATE SEQUENCE "EXEMPLO_LOTE_gid_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public."EXEMPLO_LOTE_gid_seq" OWNER TO alegrete;

--
-- Name: EXEMPLO_LOTE_gid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: alegrete
--

ALTER SEQUENCE "EXEMPLO_LOTE_gid_seq" OWNED BY exemplo_lote.gid;


--
-- Name: edif_pol; Type: TABLE; Schema: public; Owner: alegrete; Tablespace: 
--

CREATE TABLE edif_pol (
    gid integer NOT NULL,
    chave integer,
    unidade smallint,
    area_geom numeric,
    edifica smallint,
    operador character varying(2),
    geom geometry(MultiPolygon,31996),
    concat_1 character varying DEFAULT ''::character varying NOT NULL
);


ALTER TABLE public.edif_pol OWNER TO alegrete;

--
-- Name: edif_pol_erro; Type: TABLE; Schema: public; Owner: alegrete; Tablespace: 
--

CREATE TABLE edif_pol_erro (
    gid integer NOT NULL,
    chave integer,
    unidade smallint,
    area_geom numeric,
    edifica smallint,
    operador character varying(2),
    geom geometry(MultiPolygon,31996)
);


ALTER TABLE public.edif_pol_erro OWNER TO alegrete;

--
-- Name: edif_pol_erro_gid_seq; Type: SEQUENCE; Schema: public; Owner: alegrete
--

CREATE SEQUENCE edif_pol_erro_gid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.edif_pol_erro_gid_seq OWNER TO alegrete;

--
-- Name: edif_pol_erro_gid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: alegrete
--

ALTER SEQUENCE edif_pol_erro_gid_seq OWNED BY edif_pol_erro.gid;


--
-- Name: edif_pol_gid_seq; Type: SEQUENCE; Schema: public; Owner: alegrete
--

CREATE SEQUENCE edif_pol_gid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.edif_pol_gid_seq OWNER TO alegrete;

--
-- Name: edif_pol_gid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: alegrete
--

ALTER SEQUENCE edif_pol_gid_seq OWNED BY edif_pol.gid;


--
-- Name: edif_pol_recadastro; Type: TABLE; Schema: public; Owner: alegrete; Tablespace: 
--

CREATE TABLE edif_pol_recadastro (
    gid integer,
    objectid numeric(10,0),
    inscricao character varying(30),
    id_poli numeric(10,0),
    cod_layer numeric(10,0),
    num_pavim numeric(10,0),
    area numeric,
    bloco numeric(10,0),
    parte numeric(10,0),
    piso numeric(10,0),
    shape_leng numeric,
    shape_area numeric,
    tipo numeric(10,0),
    idade numeric(10,0),
    padrao numeric(10,0),
    area_edifi numeric,
    est_conser numeric(10,0),
    num_edific numeric(10,0),
    geom geometry(MultiPolygon,31996)
);


ALTER TABLE public.edif_pol_recadastro OWNER TO alegrete;

--
-- Name: edif_pol_recadastro_upto16ago2013; Type: TABLE; Schema: public; Owner: alegrete; Tablespace: 
--

CREATE TABLE edif_pol_recadastro_upto16ago2013 (
    gid integer NOT NULL,
    objectid numeric(10,0),
    inscricao character varying(30),
    id_poli numeric(10,0),
    cod_layer numeric(10,0),
    num_pavim numeric(10,0),
    area numeric,
    bloco numeric(10,0),
    parte numeric(10,0),
    piso numeric(10,0),
    shape_leng numeric,
    shape_area numeric,
    tipo numeric(10,0),
    idade numeric(10,0),
    padrao numeric(10,0),
    area_edifi numeric,
    est_conser numeric(10,0),
    num_edific numeric(10,0),
    geom geometry(MultiPolygon,31996)
);


ALTER TABLE public.edif_pol_recadastro_upto16ago2013 OWNER TO alegrete;

--
-- Name: edif_pol_recadastro_gid_seq; Type: SEQUENCE; Schema: public; Owner: alegrete
--

CREATE SEQUENCE edif_pol_recadastro_gid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.edif_pol_recadastro_gid_seq OWNER TO alegrete;

--
-- Name: edif_pol_recadastro_gid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: alegrete
--

ALTER SEQUENCE edif_pol_recadastro_gid_seq OWNED BY edif_pol_recadastro_upto16ago2013.gid;


--
-- Name: fotografia; Type: TABLE; Schema: public; Owner: alegrete; Tablespace: 
--

CREATE TABLE fotografia (
    id integer NOT NULL,
    "featureId" character varying(13) NOT NULL,
    "userId" integer NOT NULL,
    comment character varying,
    date timestamp with time zone DEFAULT now() NOT NULL,
    photo bytea NOT NULL,
    name character varying
);


ALTER TABLE public.fotografia OWNER TO alegrete;

--
-- Name: TABLE fotografia; Type: COMMENT; Schema: public; Owner: alegrete
--

COMMENT ON TABLE fotografia IS 'Image collection of features of city. Here features are individual economies.';


--
-- Name: COLUMN fotografia.id; Type: COMMENT; Schema: public; Owner: alegrete
--

COMMENT ON COLUMN fotografia.id IS 'Sequencial identifier. Can be used as a fast locator since this identifier will be unique like our primary key.';


--
-- Name: COLUMN fotografia."featureId"; Type: COMMENT; Schema: public; Owner: alegrete
--

COMMENT ON COLUMN fotografia."featureId" IS '
Feature identifier inside table that has the feature collection. It indicates the feature which is the owner of this photography.
At montenegro implementation the feature always refers to the identifier chave at montenegro.economia table';


--
-- Name: COLUMN fotografia."userId"; Type: COMMENT; Schema: public; Owner: alegrete
--

COMMENT ON COLUMN fotografia."userId" IS 'User identifier which stored the photography on system.';


--
-- Name: COLUMN fotografia.comment; Type: COMMENT; Schema: public; Owner: alegrete
--

COMMENT ON COLUMN fotografia.comment IS 'User notes on this photography. Free use by user.';


--
-- Name: COLUMN fotografia.date; Type: COMMENT; Schema: public; Owner: alegrete
--

COMMENT ON COLUMN fotografia.date IS 'Contains the timestamp from the moment the record has been stored on system.';


--
-- Name: COLUMN fotografia.photo; Type: COMMENT; Schema: public; Owner: alegrete
--

COMMENT ON COLUMN fotografia.photo IS 'The raw picture bytes. The user application is responsible for interpretation of what those bytes are encoded.';


--
-- Name: COLUMN fotografia.name; Type: COMMENT; Schema: public; Owner: alegrete
--

COMMENT ON COLUMN fotografia.name IS 'The filename of received file. This is an informational field. If no value provided an random filename will be created on export.';


--
-- Name: fotografia_id_seq; Type: SEQUENCE; Schema: public; Owner: alegrete
--

CREATE SEQUENCE fotografia_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.fotografia_id_seq OWNER TO alegrete;

--
-- Name: fotografia_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: alegrete
--

ALTER SEQUENCE fotografia_id_seq OWNED BY fotografia.id;


--
-- Name: g_app; Type: TABLE; Schema: public; Owner: alegrete; Tablespace: 
--

CREATE TABLE g_app (
    gid integer NOT NULL,
    id integer,
    geom geometry(MultiPolygon,31996)
);


ALTER TABLE public.g_app OWNER TO alegrete;

--
-- Name: g_app_gid_seq; Type: SEQUENCE; Schema: public; Owner: alegrete
--

CREATE SEQUENCE g_app_gid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.g_app_gid_seq OWNER TO alegrete;

--
-- Name: g_app_gid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: alegrete
--

ALTER SEQUENCE g_app_gid_seq OWNED BY g_app.gid;


--
-- Name: g_bairro; Type: TABLE; Schema: public; Owner: alegrete; Tablespace: 
--

CREATE TABLE g_bairro (
    gid integer NOT NULL,
    nome character varying(50),
    geom geometry(MultiPolygon,31996)
);


ALTER TABLE public.g_bairro OWNER TO alegrete;

--
-- Name: g_bairro_gid_seq; Type: SEQUENCE; Schema: public; Owner: alegrete
--

CREATE SEQUENCE g_bairro_gid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.g_bairro_gid_seq OWNER TO alegrete;

--
-- Name: g_bairro_gid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: alegrete
--

ALTER SEQUENCE g_bairro_gid_seq OWNED BY g_bairro.gid;


--
-- Name: g_distrito; Type: TABLE; Schema: public; Owner: alegrete; Tablespace: 
--

CREATE TABLE g_distrito (
    gid integer NOT NULL,
    coddist smallint,
    nomedist character varying(10),
    geom geometry(MultiPolygon,31996)
);


ALTER TABLE public.g_distrito OWNER TO alegrete;

--
-- Name: g_distrito_gid_seq; Type: SEQUENCE; Schema: public; Owner: alegrete
--

CREATE SEQUENCE g_distrito_gid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.g_distrito_gid_seq OWNER TO alegrete;

--
-- Name: g_distrito_gid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: alegrete
--

ALTER SEQUENCE g_distrito_gid_seq OWNED BY g_distrito.gid;


--
-- Name: g_edif; Type: TABLE; Schema: public; Owner: alegrete; Tablespace: 
--

CREATE TABLE g_edif (
    gid integer NOT NULL,
    chave integer,
    unidade smallint,
    area_geom numeric,
    edifica smallint,
    operador character varying(2),
    geom geometry(MultiPolygon,31996),
    concat_1 character varying DEFAULT ''::character varying NOT NULL,
    area_calc double precision DEFAULT 0.0 NOT NULL,
    periodo tstzrange DEFAULT tstzrange(now(), NULL::timestamp with time zone),
    versionado boolean DEFAULT false NOT NULL,
    usuario character varying DEFAULT "current_user"() NOT NULL
);


ALTER TABLE public.g_edif OWNER TO alegrete;

--
-- Name: g_edif_gid_seq; Type: SEQUENCE; Schema: public; Owner: alegrete
--

CREATE SEQUENCE g_edif_gid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.g_edif_gid_seq OWNER TO alegrete;

--
-- Name: g_edif_gid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: alegrete
--

ALTER SEQUENCE g_edif_gid_seq OWNED BY g_edif.gid;


--
-- Name: g_edif_history; Type: TABLE; Schema: public; Owner: alegrete; Tablespace: 
--

CREATE TABLE g_edif_history (
    gid integer NOT NULL,
    gid_lote integer,
    geom geometry,
    unidade integer,
    area_calc real DEFAULT 0.0 NOT NULL,
    periodo tstzrange,
    versionado boolean,
    excluido boolean,
    usuario_old character varying,
    usuario_new character varying
);


ALTER TABLE public.g_edif_history OWNER TO alegrete;

--
-- Name: g_edif_metrocil; Type: TABLE; Schema: public; Owner: alegrete; Tablespace: 
--

CREATE TABLE g_edif_metrocil (
    gid integer NOT NULL,
    inscricao character varying(30),
    geom geometry(MultiPolygon,31996)
);


ALTER TABLE public.g_edif_metrocil OWNER TO alegrete;

--
-- Name: g_edif_metrocil_gid_seq; Type: SEQUENCE; Schema: public; Owner: alegrete
--

CREATE SEQUENCE g_edif_metrocil_gid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.g_edif_metrocil_gid_seq OWNER TO alegrete;

--
-- Name: g_edif_metrocil_gid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: alegrete
--

ALTER SEQUENCE g_edif_metrocil_gid_seq OWNED BY g_edif_metrocil.gid;


--
-- Name: g_eixologr; Type: TABLE; Schema: public; Owner: alegrete; Tablespace: 
--

CREATE TABLE g_eixologr (
    gid integer NOT NULL,
    codlogr numeric,
    tipologr character varying(254),
    nomelogr character varying(254),
    n_ini_dir numeric,
    n_fim_dir numeric,
    n_ini_esq numeric,
    n_fim_esq numeric,
    corredor character varying(10),
    geom geometry(MultiLineString,31996)
);


ALTER TABLE public.g_eixologr OWNER TO alegrete;

--
-- Name: g_eixologr_gid_seq; Type: SEQUENCE; Schema: public; Owner: alegrete
--

CREATE SEQUENCE g_eixologr_gid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.g_eixologr_gid_seq OWNER TO alegrete;

--
-- Name: g_eixologr_gid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: alegrete
--

ALTER SEQUENCE g_eixologr_gid_seq OWNED BY g_eixologr.gid;


--
-- Name: g_ferrovia; Type: TABLE; Schema: public; Owner: alegrete; Tablespace: 
--

CREATE TABLE g_ferrovia (
    gid integer NOT NULL,
    operador character varying(50),
    geom geometry(MultiLineString,31996)
);


ALTER TABLE public.g_ferrovia OWNER TO alegrete;

--
-- Name: g_ferrovia_gid_seq; Type: SEQUENCE; Schema: public; Owner: alegrete
--

CREATE SEQUENCE g_ferrovia_gid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.g_ferrovia_gid_seq OWNER TO alegrete;

--
-- Name: g_ferrovia_gid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: alegrete
--

ALTER SEQUENCE g_ferrovia_gid_seq OWNED BY g_ferrovia.gid;


--
-- Name: g_hidrografia_linha; Type: TABLE; Schema: public; Owner: alegrete; Tablespace: 
--

CREATE TABLE g_hidrografia_linha (
    gid integer NOT NULL,
    tipo character varying(10),
    nome character varying(50),
    geom geometry(MultiLineString,31996)
);


ALTER TABLE public.g_hidrografia_linha OWNER TO alegrete;

--
-- Name: g_hidrografia_linha_gid_seq; Type: SEQUENCE; Schema: public; Owner: alegrete
--

CREATE SEQUENCE g_hidrografia_linha_gid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.g_hidrografia_linha_gid_seq OWNER TO alegrete;

--
-- Name: g_hidrografia_linha_gid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: alegrete
--

ALTER SEQUENCE g_hidrografia_linha_gid_seq OWNED BY g_hidrografia_linha.gid;


--
-- Name: g_hidrografia_poligono; Type: TABLE; Schema: public; Owner: alegrete; Tablespace: 
--

CREATE TABLE g_hidrografia_poligono (
    gid integer NOT NULL,
    nome character varying(50),
    geom geometry(MultiPolygon,31996)
);


ALTER TABLE public.g_hidrografia_poligono OWNER TO alegrete;

--
-- Name: g_hidrografia_poligono_gid_seq; Type: SEQUENCE; Schema: public; Owner: alegrete
--

CREATE SEQUENCE g_hidrografia_poligono_gid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.g_hidrografia_poligono_gid_seq OWNER TO alegrete;

--
-- Name: g_hidrografia_poligono_gid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: alegrete
--

ALTER SEQUENCE g_hidrografia_poligono_gid_seq OWNED BY g_hidrografia_poligono.gid;


--
-- Name: g_lote_erro; Type: TABLE; Schema: public; Owner: alegrete; Tablespace: 
--

CREATE TABLE g_lote_erro (
    gid integer NOT NULL,
    chave integer,
    area_geom numeric,
    lote smallint,
    edifica smallint,
    bci smallint,
    problemas smallint,
    operador character varying(2),
    geom geometry(MultiPolygon,31996)
);


ALTER TABLE public.g_lote_erro OWNER TO alegrete;

--
-- Name: g_lote_erro_gid_seq; Type: SEQUENCE; Schema: public; Owner: alegrete
--

CREATE SEQUENCE g_lote_erro_gid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.g_lote_erro_gid_seq OWNER TO alegrete;

--
-- Name: g_lote_erro_gid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: alegrete
--

ALTER SEQUENCE g_lote_erro_gid_seq OWNED BY g_lote_erro.gid;


--
-- Name: g_lote_gid_seq; Type: SEQUENCE; Schema: public; Owner: alegrete
--

CREATE SEQUENCE g_lote_gid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.g_lote_gid_seq OWNER TO alegrete;

--
-- Name: g_lote_gid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: alegrete
--

ALTER SEQUENCE g_lote_gid_seq OWNED BY g_lote.gid;


--
-- Name: g_lote_history; Type: TABLE; Schema: public; Owner: alegrete; Tablespace: 
--

CREATE TABLE g_lote_history (
    gid integer NOT NULL,
    n_porta_1 integer,
    area_bci double precision,
    n_porta_2 integer,
    n_porta_3 integer,
    area double precision,
    the_geom geometry,
    distrito integer NOT NULL,
    zona integer NOT NULL,
    quadra integer NOT NULL,
    lote integer NOT NULL,
    periodo tstzrange NOT NULL,
    versionado boolean,
    excluido boolean,
    usuario_old character varying,
    usuario_new character varying
);


ALTER TABLE public.g_lote_history OWNER TO alegrete;

--
-- Name: g_lote_metrocil; Type: TABLE; Schema: public; Owner: alegrete; Tablespace: 
--

CREATE TABLE g_lote_metrocil (
    gid integer NOT NULL,
    chave character varying(15),
    geom geometry(MultiPolygon,31996)
);


ALTER TABLE public.g_lote_metrocil OWNER TO alegrete;

--
-- Name: g_lote_metrocil_gid_seq; Type: SEQUENCE; Schema: public; Owner: alegrete
--

CREATE SEQUENCE g_lote_metrocil_gid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.g_lote_metrocil_gid_seq OWNER TO alegrete;

--
-- Name: g_lote_metrocil_gid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: alegrete
--

ALTER SEQUENCE g_lote_metrocil_gid_seq OWNED BY g_lote_metrocil.gid;


--
-- Name: g_lote_recadastro; Type: TABLE; Schema: public; Owner: alegrete; Tablespace: 
--

CREATE TABLE g_lote_recadastro (
    gid numeric,
    objectid numeric,
    sequencia numeric,
    statusimov numeric,
    inscricao character varying,
    setor character varying(2),
    quadra character varying(4),
    lote character varying(4),
    matricula character varying,
    sublote character varying,
    imposto character varying,
    documento character varying,
    cod_lograd character varying,
    logradouro character varying,
    numero character varying,
    complement character varying,
    bairro character varying,
    prop_nome character varying,
    prop_fone character varying,
    inf_imov_p numeric,
    inf_imov_u numeric,
    inf_imov_a numeric,
    inf_imov_1 numeric,
    inf_ter_si numeric,
    inf_ter_pe numeric,
    inf_ter_to numeric,
    inf_ter_ni numeric,
    inf_ter_pa numeric,
    inf_ter_ca numeric,
    mu_coleta_ numeric,
    mu_ilum_pu numeric,
    mu_red_esg numeric,
    mu_red_agu numeric,
    mu_telefon numeric,
    mu_esg_clo numeric,
    test_princ double precision,
    area_terre double precision,
    area_tot_e double precision,
    area_tot_1 double precision,
    geom geometry(MultiPolygon,31996)
);


ALTER TABLE public.g_lote_recadastro OWNER TO alegrete;

--
-- Name: g_lote_recadastro_upto16ago2013; Type: TABLE; Schema: public; Owner: alegrete; Tablespace: 
--

CREATE TABLE g_lote_recadastro_upto16ago2013 (
    gid integer NOT NULL,
    setor character varying(2),
    quadra character varying(4),
    lote character varying(4),
    unidade character varying(5),
    c_con character varying(2),
    concat character varying(50),
    geom geometry(MultiPolygon,31996)
);


ALTER TABLE public.g_lote_recadastro_upto16ago2013 OWNER TO alegrete;

--
-- Name: g_lote_recadastro_gid_seq; Type: SEQUENCE; Schema: public; Owner: alegrete
--

CREATE SEQUENCE g_lote_recadastro_gid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.g_lote_recadastro_gid_seq OWNER TO alegrete;

--
-- Name: g_lote_recadastro_gid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: alegrete
--

ALTER SEQUENCE g_lote_recadastro_gid_seq OWNED BY g_lote_recadastro_upto16ago2013.gid;


--
-- Name: g_marco_geodesico; Type: TABLE; Schema: public; Owner: alegrete; Tablespace: 
--

CREATE TABLE g_marco_geodesico (
    gid integer NOT NULL,
    sitename character varying(254),
    x double precision,
    y double precision,
    ellhgt double precision,
    ortohgt double precision,
    stddevx double precision,
    stddevy double precision,
    stddevhgt double precision,
    solution character varying(254),
    lat double precision,
    lat_gms character varying(254),
    lon double precision,
    long_gms character varying(254),
    geom geometry(Point,31996)
);


ALTER TABLE public.g_marco_geodesico OWNER TO alegrete;

--
-- Name: g_marco_geodesico_gid_seq; Type: SEQUENCE; Schema: public; Owner: alegrete
--

CREATE SEQUENCE g_marco_geodesico_gid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.g_marco_geodesico_gid_seq OWNER TO alegrete;

--
-- Name: g_marco_geodesico_gid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: alegrete
--

ALTER SEQUENCE g_marco_geodesico_gid_seq OWNED BY g_marco_geodesico.gid;


--
-- Name: g_municipio; Type: TABLE; Schema: public; Owner: alegrete; Tablespace: 
--

CREATE TABLE g_municipio (
    gid integer NOT NULL,
    nomemuni character varying(50),
    area numeric,
    geom geometry(MultiPolygon,31996)
);


ALTER TABLE public.g_municipio OWNER TO alegrete;

--
-- Name: g_municipio_gid_seq; Type: SEQUENCE; Schema: public; Owner: alegrete
--

CREATE SEQUENCE g_municipio_gid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.g_municipio_gid_seq OWNER TO alegrete;

--
-- Name: g_municipio_gid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: alegrete
--

ALTER SEQUENCE g_municipio_gid_seq OWNED BY g_municipio.gid;


--
-- Name: g_ponto_interesse; Type: TABLE; Schema: public; Owner: alegrete; Tablespace: 
--

CREATE TABLE g_ponto_interesse (
    gid integer NOT NULL,
    tipo character varying(50),
    nome character varying(50),
    geom geometry(Point,31996)
);


ALTER TABLE public.g_ponto_interesse OWNER TO alegrete;

--
-- Name: g_ponto_interesse_gid_seq; Type: SEQUENCE; Schema: public; Owner: alegrete
--

CREATE SEQUENCE g_ponto_interesse_gid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.g_ponto_interesse_gid_seq OWNER TO alegrete;

--
-- Name: g_ponto_interesse_gid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: alegrete
--

ALTER SEQUENCE g_ponto_interesse_gid_seq OWNED BY g_ponto_interesse.gid;


--
-- Name: g_quadra; Type: TABLE; Schema: public; Owner: alegrete; Tablespace: 
--

CREATE TABLE g_quadra (
    gid integer NOT NULL,
    id integer,
    geom geometry(MultiPolygon,31996)
);


ALTER TABLE public.g_quadra OWNER TO alegrete;

--
-- Name: g_quadra_gid_seq; Type: SEQUENCE; Schema: public; Owner: alegrete
--

CREATE SEQUENCE g_quadra_gid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.g_quadra_gid_seq OWNER TO alegrete;

--
-- Name: g_quadra_gid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: alegrete
--

ALTER SEQUENCE g_quadra_gid_seq OWNED BY g_quadra.gid;


--
-- Name: g_rodovia; Type: TABLE; Schema: public; Owner: alegrete; Tablespace: 
--

CREATE TABLE g_rodovia (
    gid integer NOT NULL,
    codrodov character varying(10),
    geom geometry(MultiLineString,31996)
);


ALTER TABLE public.g_rodovia OWNER TO alegrete;

--
-- Name: g_rodovia_gid_seq; Type: SEQUENCE; Schema: public; Owner: alegrete
--

CREATE SEQUENCE g_rodovia_gid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.g_rodovia_gid_seq OWNER TO alegrete;

--
-- Name: g_rodovia_gid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: alegrete
--

ALTER SEQUENCE g_rodovia_gid_seq OWNED BY g_rodovia.gid;


--
-- Name: g_vianaourbana; Type: TABLE; Schema: public; Owner: alegrete; Tablespace: 
--

CREATE TABLE g_vianaourbana (
    gid integer NOT NULL,
    tipovia character varying(10),
    nomevia character varying(50),
    geom geometry(MultiLineString,31996)
);


ALTER TABLE public.g_vianaourbana OWNER TO alegrete;

--
-- Name: g_vianaourbana_gid_seq; Type: SEQUENCE; Schema: public; Owner: alegrete
--

CREATE SEQUENCE g_vianaourbana_gid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.g_vianaourbana_gid_seq OWNER TO alegrete;

--
-- Name: g_vianaourbana_gid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: alegrete
--

ALTER SEQUENCE g_vianaourbana_gid_seq OWNED BY g_vianaourbana.gid;


--
-- Name: g_zoneamento; Type: TABLE; Schema: public; Owner: alegrete; Tablespace: 
--

CREATE TABLE g_zoneamento (
    gid integer NOT NULL,
    "Id" integer,
    legenda character varying(50),
    codzona character varying(10),
    geom geometry(Polygon)
);


ALTER TABLE public.g_zoneamento OWNER TO alegrete;

--
-- Name: g_zoneamento3_gid_seq; Type: SEQUENCE; Schema: public; Owner: alegrete
--

CREATE SEQUENCE g_zoneamento3_gid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.g_zoneamento3_gid_seq OWNER TO alegrete;

--
-- Name: g_zoneamento3_gid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: alegrete
--

ALTER SEQUENCE g_zoneamento3_gid_seq OWNED BY g_zoneamento.gid;


--
-- Name: g_zoneamento_old; Type: TABLE; Schema: public; Owner: alegrete; Tablespace: 
--

CREATE TABLE g_zoneamento_old (
    gid integer NOT NULL,
    legenda character varying(50),
    geom geometry(MultiPolygon,31996)
);


ALTER TABLE public.g_zoneamento_old OWNER TO alegrete;

--
-- Name: g_zoneamento_gid_seq; Type: SEQUENCE; Schema: public; Owner: alegrete
--

CREATE SEQUENCE g_zoneamento_gid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.g_zoneamento_gid_seq OWNER TO alegrete;

--
-- Name: g_zoneamento_gid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: alegrete
--

ALTER SEQUENCE g_zoneamento_gid_seq OWNED BY g_zoneamento_old.gid;


--
-- Name: pd_atividade; Type: TABLE; Schema: public; Owner: alegrete; Tablespace: 
--

CREATE TABLE pd_atividade (
    categoria character varying(20)
);


ALTER TABLE public.pd_atividade OWNER TO alegrete;

--
-- Name: pd_ind_zoneamento; Type: TABLE; Schema: public; Owner: alegrete; Tablespace: 
--

CREATE TABLE pd_ind_zoneamento (
    gid integer,
    codzona character varying(5),
    zona character varying(50),
    categoria character varying(30),
    atividade character varying(50),
    ia_maximo numeric,
    txoc_ter numeric,
    txoc_sup numeric,
    txperm numeric,
    recuo_frontal numeric,
    alturamax numeric,
    alturadivisa numeric,
    alturabase numeric,
    ia_oneroso numeric,
    cod_categoria character varying(2),
    cod_atividade character varying(3)
);


ALTER TABLE public.pd_ind_zoneamento OWNER TO alegrete;

--
-- Name: sgm_edif; Type: TABLE; Schema: public; Owner: alegrete; Tablespace: 
--

CREATE TABLE sgm_edif (
    gid integer NOT NULL,
    chave integer,
    unidade smallint,
    area_geom numeric,
    edifica smallint,
    operador character varying(2),
    geom geometry(MultiPolygon,31996),
    concat_1 character varying
);


ALTER TABLE public.sgm_edif OWNER TO alegrete;

--
-- Name: sgm_lote; Type: TABLE; Schema: public; Owner: alegrete; Tablespace: 
--

CREATE TABLE sgm_lote (
    gid integer NOT NULL,
    chave integer,
    area_geom numeric,
    lote smallint,
    edifica smallint,
    bci smallint,
    problemas smallint,
    operador character varying(2),
    geom geometry(MultiPolygon,31996),
    area_insc double precision,
    setor_insc character varying,
    quadra_insc character varying,
    lote_insc character varying
);


ALTER TABLE public.sgm_lote OWNER TO alegrete;

--
-- Name: users; Type: TABLE; Schema: public; Owner: alegrete; Tablespace: 
--

CREATE TABLE users (
    id integer NOT NULL,
    nickname character varying NOT NULL,
    fullname character varying,
    registration character varying,
    role character varying,
    department character varying,
    token character varying NOT NULL,
    status integer DEFAULT 1 NOT NULL,
    "creationTimestamp" time with time zone DEFAULT now() NOT NULL,
    level integer DEFAULT 0 NOT NULL,
    "lastLogon" timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.users OWNER TO alegrete;

--
-- Name: TABLE users; Type: COMMENT; Schema: public; Owner: alegrete
--

COMMENT ON TABLE users IS 'Lista dos operadores do sistema.';


--
-- Name: COLUMN users.id; Type: COMMENT; Schema: public; Owner: alegrete
--

COMMENT ON COLUMN users.id IS 'System sequencial number for object access.';


--
-- Name: COLUMN users.nickname; Type: COMMENT; Schema: public; Owner: alegrete
--

COMMENT ON COLUMN users.nickname IS 'The commom name used by the user.';


--
-- Name: COLUMN users.fullname; Type: COMMENT; Schema: public; Owner: alegrete
--

COMMENT ON COLUMN users.fullname IS 'Real name from user. The complete name.';


--
-- Name: COLUMN users.registration; Type: COMMENT; Schema: public; Owner: alegrete
--

COMMENT ON COLUMN users.registration IS 'This usually a number field assigned by company which user works.
Field stored in case people with same or similar name come in to avoid ambiguity.';


--
-- Name: COLUMN users.role; Type: COMMENT; Schema: public; Owner: alegrete
--

COMMENT ON COLUMN users.role IS 'Job name, or main user task in which the user need access to the system.';


--
-- Name: COLUMN users.department; Type: COMMENT; Schema: public; Owner: alegrete
--

COMMENT ON COLUMN users.department IS 'This can help to group users into commom classes.
Informational field only.
';


--
-- Name: COLUMN users.token; Type: COMMENT; Schema: public; Owner: alegrete
--

COMMENT ON COLUMN users.token IS 'The secret token know only by the user who created it.';


--
-- Name: COLUMN users.status; Type: COMMENT; Schema: public; Owner: alegrete
--

COMMENT ON COLUMN users.status IS 'Status store user access information about user account by the following convetion:

0 - inactive, user login has been cancelled
1 - active, user can access the system';


--
-- Name: COLUMN users.level; Type: COMMENT; Schema: public; Owner: alegrete
--

COMMENT ON COLUMN users.level IS 'User access level.
Value on following enumeration:

0 - technician user, more restricted access
1 - admin user, can manage users
2 - technician user, can edit layers sgm_edit, sgm_logr, sgm_lote.
';


--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: alegrete
--

CREATE SEQUENCE users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.users_id_seq OWNER TO alegrete;

--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: alegrete
--

ALTER SEQUENCE users_id_seq OWNED BY users.id;


--
-- Name: vw_lotes_nofotos; Type: VIEW; Schema: public; Owner: alegrete
--

CREATE VIEW vw_lotes_nofotos AS
    SELECT lotes.gid, lotes.geom, lotes.chave FROM g_lote lotes WHERE (NOT (((lotes.chave)::character varying)::text IN (SELECT fotografia."featureId" FROM fotografia)));


ALTER TABLE public.vw_lotes_nofotos OWNER TO alegrete;

--
-- Name: gid; Type: DEFAULT; Schema: public; Owner: alegrete
--

ALTER TABLE ONLY "EXEMPLO_LOTE2" ALTER COLUMN gid SET DEFAULT nextval('"EXEMPLO_LOTE2_gid_seq"'::regclass);


--
-- Name: gid; Type: DEFAULT; Schema: public; Owner: alegrete
--

ALTER TABLE ONLY edif_pol ALTER COLUMN gid SET DEFAULT nextval('edif_pol_gid_seq'::regclass);


--
-- Name: gid; Type: DEFAULT; Schema: public; Owner: alegrete
--

ALTER TABLE ONLY edif_pol_erro ALTER COLUMN gid SET DEFAULT nextval('edif_pol_erro_gid_seq'::regclass);


--
-- Name: gid; Type: DEFAULT; Schema: public; Owner: alegrete
--

ALTER TABLE ONLY edif_pol_recadastro_upto16ago2013 ALTER COLUMN gid SET DEFAULT nextval('edif_pol_recadastro_gid_seq'::regclass);


--
-- Name: gid; Type: DEFAULT; Schema: public; Owner: alegrete
--

ALTER TABLE ONLY exemplo_lote ALTER COLUMN gid SET DEFAULT nextval('"EXEMPLO_LOTE_gid_seq"'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: alegrete
--

ALTER TABLE ONLY fotografia ALTER COLUMN id SET DEFAULT nextval('fotografia_id_seq'::regclass);


--
-- Name: gid; Type: DEFAULT; Schema: public; Owner: alegrete
--

ALTER TABLE ONLY g_app ALTER COLUMN gid SET DEFAULT nextval('g_app_gid_seq'::regclass);


--
-- Name: gid; Type: DEFAULT; Schema: public; Owner: alegrete
--

ALTER TABLE ONLY g_bairro ALTER COLUMN gid SET DEFAULT nextval('g_bairro_gid_seq'::regclass);


--
-- Name: gid; Type: DEFAULT; Schema: public; Owner: alegrete
--

ALTER TABLE ONLY g_distrito ALTER COLUMN gid SET DEFAULT nextval('g_distrito_gid_seq'::regclass);


--
-- Name: gid; Type: DEFAULT; Schema: public; Owner: alegrete
--

ALTER TABLE ONLY g_edif ALTER COLUMN gid SET DEFAULT nextval('g_edif_gid_seq'::regclass);


--
-- Name: gid; Type: DEFAULT; Schema: public; Owner: alegrete
--

ALTER TABLE ONLY g_edif_metrocil ALTER COLUMN gid SET DEFAULT nextval('g_edif_metrocil_gid_seq'::regclass);


--
-- Name: gid; Type: DEFAULT; Schema: public; Owner: alegrete
--

ALTER TABLE ONLY g_eixologr ALTER COLUMN gid SET DEFAULT nextval('g_eixologr_gid_seq'::regclass);


--
-- Name: gid; Type: DEFAULT; Schema: public; Owner: alegrete
--

ALTER TABLE ONLY g_ferrovia ALTER COLUMN gid SET DEFAULT nextval('g_ferrovia_gid_seq'::regclass);


--
-- Name: gid; Type: DEFAULT; Schema: public; Owner: alegrete
--

ALTER TABLE ONLY g_hidrografia_linha ALTER COLUMN gid SET DEFAULT nextval('g_hidrografia_linha_gid_seq'::regclass);


--
-- Name: gid; Type: DEFAULT; Schema: public; Owner: alegrete
--

ALTER TABLE ONLY g_hidrografia_poligono ALTER COLUMN gid SET DEFAULT nextval('g_hidrografia_poligono_gid_seq'::regclass);


--
-- Name: gid; Type: DEFAULT; Schema: public; Owner: alegrete
--

ALTER TABLE ONLY g_lote ALTER COLUMN gid SET DEFAULT nextval('g_lote_gid_seq'::regclass);


--
-- Name: gid; Type: DEFAULT; Schema: public; Owner: alegrete
--

ALTER TABLE ONLY g_lote_erro ALTER COLUMN gid SET DEFAULT nextval('g_lote_erro_gid_seq'::regclass);


--
-- Name: gid; Type: DEFAULT; Schema: public; Owner: alegrete
--

ALTER TABLE ONLY g_lote_metrocil ALTER COLUMN gid SET DEFAULT nextval('g_lote_metrocil_gid_seq'::regclass);


--
-- Name: gid; Type: DEFAULT; Schema: public; Owner: alegrete
--

ALTER TABLE ONLY g_lote_recadastro_upto16ago2013 ALTER COLUMN gid SET DEFAULT nextval('g_lote_recadastro_gid_seq'::regclass);


--
-- Name: gid; Type: DEFAULT; Schema: public; Owner: alegrete
--

ALTER TABLE ONLY g_marco_geodesico ALTER COLUMN gid SET DEFAULT nextval('g_marco_geodesico_gid_seq'::regclass);


--
-- Name: gid; Type: DEFAULT; Schema: public; Owner: alegrete
--

ALTER TABLE ONLY g_municipio ALTER COLUMN gid SET DEFAULT nextval('g_municipio_gid_seq'::regclass);


--
-- Name: gid; Type: DEFAULT; Schema: public; Owner: alegrete
--

ALTER TABLE ONLY g_ponto_interesse ALTER COLUMN gid SET DEFAULT nextval('g_ponto_interesse_gid_seq'::regclass);


--
-- Name: gid; Type: DEFAULT; Schema: public; Owner: alegrete
--

ALTER TABLE ONLY g_quadra ALTER COLUMN gid SET DEFAULT nextval('g_quadra_gid_seq'::regclass);


--
-- Name: gid; Type: DEFAULT; Schema: public; Owner: alegrete
--

ALTER TABLE ONLY g_rodovia ALTER COLUMN gid SET DEFAULT nextval('g_rodovia_gid_seq'::regclass);


--
-- Name: gid; Type: DEFAULT; Schema: public; Owner: alegrete
--

ALTER TABLE ONLY g_vianaourbana ALTER COLUMN gid SET DEFAULT nextval('g_vianaourbana_gid_seq'::regclass);


--
-- Name: gid; Type: DEFAULT; Schema: public; Owner: alegrete
--

ALTER TABLE ONLY g_zoneamento ALTER COLUMN gid SET DEFAULT nextval('g_zoneamento3_gid_seq'::regclass);


--
-- Name: gid; Type: DEFAULT; Schema: public; Owner: alegrete
--

ALTER TABLE ONLY g_zoneamento_old ALTER COLUMN gid SET DEFAULT nextval('g_zoneamento_gid_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: alegrete
--

ALTER TABLE ONLY users ALTER COLUMN id SET DEFAULT nextval('users_id_seq'::regclass);


--
-- Name: EXEMPLO_LOTE2_pkey; Type: CONSTRAINT; Schema: public; Owner: alegrete; Tablespace: 
--

ALTER TABLE ONLY "EXEMPLO_LOTE2"
    ADD CONSTRAINT "EXEMPLO_LOTE2_pkey" PRIMARY KEY (gid);


--
-- Name: EXEMPLO_LOTE_pkey; Type: CONSTRAINT; Schema: public; Owner: alegrete; Tablespace: 
--

ALTER TABLE ONLY exemplo_lote
    ADD CONSTRAINT "EXEMPLO_LOTE_pkey" PRIMARY KEY (gid);


--
-- Name: edif_pol_erro_pkey; Type: CONSTRAINT; Schema: public; Owner: alegrete; Tablespace: 
--

ALTER TABLE ONLY edif_pol_erro
    ADD CONSTRAINT edif_pol_erro_pkey PRIMARY KEY (gid);


--
-- Name: edif_pol_pkey; Type: CONSTRAINT; Schema: public; Owner: alegrete; Tablespace: 
--

ALTER TABLE ONLY edif_pol
    ADD CONSTRAINT edif_pol_pkey PRIMARY KEY (gid);


--
-- Name: edif_pol_recadastro_pkey; Type: CONSTRAINT; Schema: public; Owner: alegrete; Tablespace: 
--

ALTER TABLE ONLY edif_pol_recadastro_upto16ago2013
    ADD CONSTRAINT edif_pol_recadastro_pkey PRIMARY KEY (gid);


--
-- Name: fotografia_pkey; Type: CONSTRAINT; Schema: public; Owner: alegrete; Tablespace: 
--

ALTER TABLE ONLY fotografia
    ADD CONSTRAINT fotografia_pkey PRIMARY KEY (id);


--
-- Name: g_app_pkey; Type: CONSTRAINT; Schema: public; Owner: alegrete; Tablespace: 
--

ALTER TABLE ONLY g_app
    ADD CONSTRAINT g_app_pkey PRIMARY KEY (gid);


--
-- Name: g_bairro_pkey; Type: CONSTRAINT; Schema: public; Owner: alegrete; Tablespace: 
--

ALTER TABLE ONLY g_bairro
    ADD CONSTRAINT g_bairro_pkey PRIMARY KEY (gid);


--
-- Name: g_distrito_pkey; Type: CONSTRAINT; Schema: public; Owner: alegrete; Tablespace: 
--

ALTER TABLE ONLY g_distrito
    ADD CONSTRAINT g_distrito_pkey PRIMARY KEY (gid);


--
-- Name: g_edif_history_version_excl; Type: CONSTRAINT; Schema: public; Owner: alegrete; Tablespace: 
--

ALTER TABLE ONLY g_edif_history
    ADD CONSTRAINT g_edif_history_version_excl EXCLUDE USING gist (gid WITH =, periodo WITH &&);


--
-- Name: g_edif_metrocil_pkey; Type: CONSTRAINT; Schema: public; Owner: alegrete; Tablespace: 
--

ALTER TABLE ONLY g_edif_metrocil
    ADD CONSTRAINT g_edif_metrocil_pkey PRIMARY KEY (gid);


--
-- Name: g_edif_pkey; Type: CONSTRAINT; Schema: public; Owner: alegrete; Tablespace: 
--

ALTER TABLE ONLY g_edif
    ADD CONSTRAINT g_edif_pkey PRIMARY KEY (gid);


--
-- Name: g_eixologr_pkey; Type: CONSTRAINT; Schema: public; Owner: alegrete; Tablespace: 
--

ALTER TABLE ONLY g_eixologr
    ADD CONSTRAINT g_eixologr_pkey PRIMARY KEY (gid);


--
-- Name: g_ferrovia_pkey; Type: CONSTRAINT; Schema: public; Owner: alegrete; Tablespace: 
--

ALTER TABLE ONLY g_ferrovia
    ADD CONSTRAINT g_ferrovia_pkey PRIMARY KEY (gid);


--
-- Name: g_hidrografia_linha_pkey; Type: CONSTRAINT; Schema: public; Owner: alegrete; Tablespace: 
--

ALTER TABLE ONLY g_hidrografia_linha
    ADD CONSTRAINT g_hidrografia_linha_pkey PRIMARY KEY (gid);


--
-- Name: g_hidrografia_poligono_pkey; Type: CONSTRAINT; Schema: public; Owner: alegrete; Tablespace: 
--

ALTER TABLE ONLY g_hidrografia_poligono
    ADD CONSTRAINT g_hidrografia_poligono_pkey PRIMARY KEY (gid);


--
-- Name: g_lote_erro_pkey; Type: CONSTRAINT; Schema: public; Owner: alegrete; Tablespace: 
--

ALTER TABLE ONLY g_lote_erro
    ADD CONSTRAINT g_lote_erro_pkey PRIMARY KEY (gid);


--
-- Name: g_lote_history_version_excl; Type: CONSTRAINT; Schema: public; Owner: alegrete; Tablespace: 
--

ALTER TABLE ONLY g_lote_history
    ADD CONSTRAINT g_lote_history_version_excl EXCLUDE USING gist (gid WITH =, periodo WITH &&);


--
-- Name: g_lote_metrocil_pkey; Type: CONSTRAINT; Schema: public; Owner: alegrete; Tablespace: 
--

ALTER TABLE ONLY g_lote_metrocil
    ADD CONSTRAINT g_lote_metrocil_pkey PRIMARY KEY (gid);


--
-- Name: g_lote_pkey; Type: CONSTRAINT; Schema: public; Owner: alegrete; Tablespace: 
--

ALTER TABLE ONLY g_lote
    ADD CONSTRAINT g_lote_pkey PRIMARY KEY (gid);


--
-- Name: g_lote_recadastro_pkey; Type: CONSTRAINT; Schema: public; Owner: alegrete; Tablespace: 
--

ALTER TABLE ONLY g_lote_recadastro_upto16ago2013
    ADD CONSTRAINT g_lote_recadastro_pkey PRIMARY KEY (gid);


--
-- Name: g_marco_geodesico_pkey; Type: CONSTRAINT; Schema: public; Owner: alegrete; Tablespace: 
--

ALTER TABLE ONLY g_marco_geodesico
    ADD CONSTRAINT g_marco_geodesico_pkey PRIMARY KEY (gid);


--
-- Name: g_municipio_pkey; Type: CONSTRAINT; Schema: public; Owner: alegrete; Tablespace: 
--

ALTER TABLE ONLY g_municipio
    ADD CONSTRAINT g_municipio_pkey PRIMARY KEY (gid);


--
-- Name: g_ponto_interesse_pkey; Type: CONSTRAINT; Schema: public; Owner: alegrete; Tablespace: 
--

ALTER TABLE ONLY g_ponto_interesse
    ADD CONSTRAINT g_ponto_interesse_pkey PRIMARY KEY (gid);


--
-- Name: g_quadra_pkey; Type: CONSTRAINT; Schema: public; Owner: alegrete; Tablespace: 
--

ALTER TABLE ONLY g_quadra
    ADD CONSTRAINT g_quadra_pkey PRIMARY KEY (gid);


--
-- Name: g_rodovia_pkey; Type: CONSTRAINT; Schema: public; Owner: alegrete; Tablespace: 
--

ALTER TABLE ONLY g_rodovia
    ADD CONSTRAINT g_rodovia_pkey PRIMARY KEY (gid);


--
-- Name: g_vianaourbana_pkey; Type: CONSTRAINT; Schema: public; Owner: alegrete; Tablespace: 
--

ALTER TABLE ONLY g_vianaourbana
    ADD CONSTRAINT g_vianaourbana_pkey PRIMARY KEY (gid);


--
-- Name: g_zoneamento3_pkey; Type: CONSTRAINT; Schema: public; Owner: alegrete; Tablespace: 
--

ALTER TABLE ONLY g_zoneamento
    ADD CONSTRAINT g_zoneamento3_pkey PRIMARY KEY (gid);


--
-- Name: g_zoneamento_pkey; Type: CONSTRAINT; Schema: public; Owner: alegrete; Tablespace: 
--

ALTER TABLE ONLY g_zoneamento_old
    ADD CONSTRAINT g_zoneamento_pkey PRIMARY KEY (gid);


--
-- Name: sgm_edif_pkey; Type: CONSTRAINT; Schema: public; Owner: alegrete; Tablespace: 
--

ALTER TABLE ONLY sgm_edif
    ADD CONSTRAINT sgm_edif_pkey PRIMARY KEY (gid);


--
-- Name: sgm_lote_pkey; Type: CONSTRAINT; Schema: public; Owner: alegrete; Tablespace: 
--

ALTER TABLE ONLY sgm_lote
    ADD CONSTRAINT sgm_lote_pkey PRIMARY KEY (gid);


--
-- Name: geometry_columns_delete; Type: RULE; Schema: public; Owner: postgres
--

CREATE RULE geometry_columns_delete AS ON DELETE TO geometry_columns DO INSTEAD NOTHING;


--
-- Name: geometry_columns_insert; Type: RULE; Schema: public; Owner: postgres
--

CREATE RULE geometry_columns_insert AS ON INSERT TO geometry_columns DO INSTEAD NOTHING;


--
-- Name: geometry_columns_update; Type: RULE; Schema: public; Owner: postgres
--

CREATE RULE geometry_columns_update AS ON UPDATE TO geometry_columns DO INSTEAD NOTHING;


--
-- Name: g_edif-ControlVersion; Type: TRIGGER; Schema: public; Owner: alegrete
--

CREATE TRIGGER "g_edif-ControlVersion" BEFORE INSERT OR UPDATE ON g_edif FOR EACH ROW EXECUTE PROCEDURE "version-g_edif-controller"();


--
-- Name: TRIGGER "g_edif-ControlVersion" ON g_edif; Type: COMMENT; Schema: public; Owner: alegrete
--

COMMENT ON TRIGGER "g_edif-ControlVersion" ON g_edif IS '
Update period timestamp information to prevent system from creating overlaps on record insert, updates.
@version 1.1.2 20130405
- initial release
';


--
-- Name: g_edif-hControlVersion; Type: TRIGGER; Schema: public; Owner: alegrete
--

CREATE TRIGGER "g_edif-hControlVersion" AFTER DELETE OR UPDATE ON g_edif FOR EACH ROW EXECUTE PROCEDURE "version-g_edif-hController"();


--
-- Name: TRIGGER "g_edif-hControlVersion" ON g_edif; Type: COMMENT; Schema: public; Owner: alegrete
--

COMMENT ON TRIGGER "g_edif-hControlVersion" ON g_edif IS '
Check that version information will be kept in syncronized.
@version 1.1.2 20130405
- initial release';


--
-- Name: g_lote-ControlVersion; Type: TRIGGER; Schema: public; Owner: alegrete
--

CREATE TRIGGER "g_lote-ControlVersion" BEFORE INSERT OR UPDATE ON g_lote FOR EACH ROW EXECUTE PROCEDURE "version-g_lote-controller"();


--
-- Name: TRIGGER "g_lote-ControlVersion" ON g_lote; Type: COMMENT; Schema: public; Owner: alegrete
--

COMMENT ON TRIGGER "g_lote-ControlVersion" ON g_lote IS '
Update period timestamp information to prevent system from creating overlaps on record insert, updates.
@version 1.1.2 20130405
- initial release
';


--
-- Name: g_lote-hControlVersion; Type: TRIGGER; Schema: public; Owner: alegrete
--

CREATE TRIGGER "g_lote-hControlVersion" AFTER DELETE OR UPDATE ON g_lote FOR EACH ROW EXECUTE PROCEDURE "version-g_lote-hController"();


--
-- Name: TRIGGER "g_lote-hControlVersion" ON g_lote; Type: COMMENT; Schema: public; Owner: alegrete
--

COMMENT ON TRIGGER "g_lote-hControlVersion" ON g_lote IS '
Check that version information will be kept in syncronized.
@version 1.1.2 20130405
- initial release';


--
-- Name: setManageDeskEditor; Type: TRIGGER; Schema: public; Owner: alegrete
--

CREATE TRIGGER "setManageDeskEditor" BEFORE INSERT OR DELETE OR UPDATE ON users FOR EACH ROW EXECUTE PROCEDURE sgm."setManageDeskEditor"();


--
-- Name: sgm_edif; Type: TRIGGER; Schema: public; Owner: alegrete
--

CREATE TRIGGER sgm_edif BEFORE INSERT OR DELETE OR UPDATE ON sgm_edif FOR EACH ROW EXECUTE PROCEDURE sgm_edif();


--
-- Name: sgm_lote; Type: TRIGGER; Schema: public; Owner: alegrete
--

CREATE TRIGGER sgm_lote BEFORE INSERT OR DELETE OR UPDATE ON sgm_lote FOR EACH ROW EXECUTE PROCEDURE sgm_lote();


--
-- Name: public; Type: ACL; Schema: -; Owner: postgres
--

REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON SCHEMA public FROM postgres;
GRANT ALL ON SCHEMA public TO postgres;
GRANT ALL ON SCHEMA public TO PUBLIC;
GRANT ALL ON SCHEMA public TO alegrete;


--
-- Name: arr_first(anyarray, anyelement); Type: ACL; Schema: public; Owner: alegrete
--

REVOKE ALL ON FUNCTION arr_first(arr anyarray, nullreplacer anyelement) FROM PUBLIC;
REVOKE ALL ON FUNCTION arr_first(arr anyarray, nullreplacer anyelement) FROM alegrete;
GRANT ALL ON FUNCTION arr_first(arr anyarray, nullreplacer anyelement) TO alegrete;
GRANT ALL ON FUNCTION arr_first(arr anyarray, nullreplacer anyelement) TO PUBLIC;
GRANT ALL ON FUNCTION arr_first(arr anyarray, nullreplacer anyelement) TO peter WITH GRANT OPTION;


--
-- Name: geomfromtext(text, integer); Type: ACL; Schema: public; Owner: alegrete
--

REVOKE ALL ON FUNCTION geomfromtext(wkt text, srid integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION geomfromtext(wkt text, srid integer) FROM alegrete;
GRANT ALL ON FUNCTION geomfromtext(wkt text, srid integer) TO alegrete;
GRANT ALL ON FUNCTION geomfromtext(wkt text, srid integer) TO PUBLIC;
GRANT ALL ON FUNCTION geomfromtext(wkt text, srid integer) TO peter WITH GRANT OPTION;


--
-- Name: ndims(geometry); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION ndims(geometry) FROM PUBLIC;
REVOKE ALL ON FUNCTION ndims(geometry) FROM postgres;
GRANT ALL ON FUNCTION ndims(geometry) TO postgres;
GRANT ALL ON FUNCTION ndims(geometry) TO PUBLIC;
GRANT ALL ON FUNCTION ndims(geometry) TO peter WITH GRANT OPTION;


--
-- Name: srid(geometry); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION srid(geometry) FROM PUBLIC;
REVOKE ALL ON FUNCTION srid(geometry) FROM postgres;
GRANT ALL ON FUNCTION srid(geometry) TO postgres;
GRANT ALL ON FUNCTION srid(geometry) TO PUBLIC;
GRANT ALL ON FUNCTION srid(geometry) TO peter WITH GRANT OPTION;


--
-- Name: g_lote; Type: ACL; Schema: public; Owner: alegrete
--

REVOKE ALL ON TABLE g_lote FROM PUBLIC;
REVOKE ALL ON TABLE g_lote FROM alegrete;
GRANT ALL ON TABLE g_lote TO alegrete;
GRANT ALL ON TABLE g_lote TO peter WITH GRANT OPTION;
GRANT SELECT ON TABLE g_lote TO deskeditor;


--
-- Name: EXEMPLO_LOTE2; Type: ACL; Schema: public; Owner: alegrete
--

REVOKE ALL ON TABLE "EXEMPLO_LOTE2" FROM PUBLIC;
REVOKE ALL ON TABLE "EXEMPLO_LOTE2" FROM alegrete;
GRANT ALL ON TABLE "EXEMPLO_LOTE2" TO alegrete;
GRANT ALL ON TABLE "EXEMPLO_LOTE2" TO peter WITH GRANT OPTION;


--
-- Name: EXEMPLO_LOTE2_gid_seq; Type: ACL; Schema: public; Owner: alegrete
--

REVOKE ALL ON SEQUENCE "EXEMPLO_LOTE2_gid_seq" FROM PUBLIC;
REVOKE ALL ON SEQUENCE "EXEMPLO_LOTE2_gid_seq" FROM alegrete;
GRANT ALL ON SEQUENCE "EXEMPLO_LOTE2_gid_seq" TO alegrete;
GRANT ALL ON SEQUENCE "EXEMPLO_LOTE2_gid_seq" TO peter WITH GRANT OPTION;


--
-- Name: exemplo_lote; Type: ACL; Schema: public; Owner: alegrete
--

REVOKE ALL ON TABLE exemplo_lote FROM PUBLIC;
REVOKE ALL ON TABLE exemplo_lote FROM alegrete;
GRANT ALL ON TABLE exemplo_lote TO alegrete;
GRANT ALL ON TABLE exemplo_lote TO peter WITH GRANT OPTION;


--
-- Name: EXEMPLO_LOTE_gid_seq; Type: ACL; Schema: public; Owner: alegrete
--

REVOKE ALL ON SEQUENCE "EXEMPLO_LOTE_gid_seq" FROM PUBLIC;
REVOKE ALL ON SEQUENCE "EXEMPLO_LOTE_gid_seq" FROM alegrete;
GRANT ALL ON SEQUENCE "EXEMPLO_LOTE_gid_seq" TO alegrete;
GRANT ALL ON SEQUENCE "EXEMPLO_LOTE_gid_seq" TO peter WITH GRANT OPTION;


--
-- Name: edif_pol; Type: ACL; Schema: public; Owner: alegrete
--

REVOKE ALL ON TABLE edif_pol FROM PUBLIC;
REVOKE ALL ON TABLE edif_pol FROM alegrete;
GRANT ALL ON TABLE edif_pol TO alegrete;
GRANT ALL ON TABLE edif_pol TO peter WITH GRANT OPTION;


--
-- Name: edif_pol_erro; Type: ACL; Schema: public; Owner: alegrete
--

REVOKE ALL ON TABLE edif_pol_erro FROM PUBLIC;
REVOKE ALL ON TABLE edif_pol_erro FROM alegrete;
GRANT ALL ON TABLE edif_pol_erro TO alegrete;
GRANT ALL ON TABLE edif_pol_erro TO peter WITH GRANT OPTION;


--
-- Name: edif_pol_erro_gid_seq; Type: ACL; Schema: public; Owner: alegrete
--

REVOKE ALL ON SEQUENCE edif_pol_erro_gid_seq FROM PUBLIC;
REVOKE ALL ON SEQUENCE edif_pol_erro_gid_seq FROM alegrete;
GRANT ALL ON SEQUENCE edif_pol_erro_gid_seq TO alegrete;
GRANT ALL ON SEQUENCE edif_pol_erro_gid_seq TO peter WITH GRANT OPTION;


--
-- Name: edif_pol_gid_seq; Type: ACL; Schema: public; Owner: alegrete
--

REVOKE ALL ON SEQUENCE edif_pol_gid_seq FROM PUBLIC;
REVOKE ALL ON SEQUENCE edif_pol_gid_seq FROM alegrete;
GRANT ALL ON SEQUENCE edif_pol_gid_seq TO alegrete;
GRANT ALL ON SEQUENCE edif_pol_gid_seq TO peter WITH GRANT OPTION;


--
-- Name: edif_pol_recadastro; Type: ACL; Schema: public; Owner: alegrete
--

REVOKE ALL ON TABLE edif_pol_recadastro FROM PUBLIC;
REVOKE ALL ON TABLE edif_pol_recadastro FROM alegrete;
GRANT ALL ON TABLE edif_pol_recadastro TO alegrete;
GRANT ALL ON TABLE edif_pol_recadastro TO peter WITH GRANT OPTION;


--
-- Name: edif_pol_recadastro_upto16ago2013; Type: ACL; Schema: public; Owner: alegrete
--

REVOKE ALL ON TABLE edif_pol_recadastro_upto16ago2013 FROM PUBLIC;
REVOKE ALL ON TABLE edif_pol_recadastro_upto16ago2013 FROM alegrete;
GRANT ALL ON TABLE edif_pol_recadastro_upto16ago2013 TO alegrete;
GRANT ALL ON TABLE edif_pol_recadastro_upto16ago2013 TO peter WITH GRANT OPTION;


--
-- Name: edif_pol_recadastro_gid_seq; Type: ACL; Schema: public; Owner: alegrete
--

REVOKE ALL ON SEQUENCE edif_pol_recadastro_gid_seq FROM PUBLIC;
REVOKE ALL ON SEQUENCE edif_pol_recadastro_gid_seq FROM alegrete;
GRANT ALL ON SEQUENCE edif_pol_recadastro_gid_seq TO alegrete;
GRANT ALL ON SEQUENCE edif_pol_recadastro_gid_seq TO peter WITH GRANT OPTION;


--
-- Name: fotografia; Type: ACL; Schema: public; Owner: alegrete
--

REVOKE ALL ON TABLE fotografia FROM PUBLIC;
REVOKE ALL ON TABLE fotografia FROM alegrete;
GRANT ALL ON TABLE fotografia TO alegrete;
GRANT SELECT ON TABLE fotografia TO PUBLIC;
GRANT ALL ON TABLE fotografia TO peter WITH GRANT OPTION;


--
-- Name: fotografia_id_seq; Type: ACL; Schema: public; Owner: alegrete
--

REVOKE ALL ON SEQUENCE fotografia_id_seq FROM PUBLIC;
REVOKE ALL ON SEQUENCE fotografia_id_seq FROM alegrete;
GRANT ALL ON SEQUENCE fotografia_id_seq TO alegrete;
GRANT ALL ON SEQUENCE fotografia_id_seq TO peter WITH GRANT OPTION;


--
-- Name: g_app; Type: ACL; Schema: public; Owner: alegrete
--

REVOKE ALL ON TABLE g_app FROM PUBLIC;
REVOKE ALL ON TABLE g_app FROM alegrete;
GRANT ALL ON TABLE g_app TO alegrete;
GRANT ALL ON TABLE g_app TO peter WITH GRANT OPTION;


--
-- Name: g_app_gid_seq; Type: ACL; Schema: public; Owner: alegrete
--

REVOKE ALL ON SEQUENCE g_app_gid_seq FROM PUBLIC;
REVOKE ALL ON SEQUENCE g_app_gid_seq FROM alegrete;
GRANT ALL ON SEQUENCE g_app_gid_seq TO alegrete;
GRANT ALL ON SEQUENCE g_app_gid_seq TO peter WITH GRANT OPTION;


--
-- Name: g_bairro; Type: ACL; Schema: public; Owner: alegrete
--

REVOKE ALL ON TABLE g_bairro FROM PUBLIC;
REVOKE ALL ON TABLE g_bairro FROM alegrete;
GRANT ALL ON TABLE g_bairro TO alegrete;
GRANT ALL ON TABLE g_bairro TO peter WITH GRANT OPTION;


--
-- Name: g_bairro_gid_seq; Type: ACL; Schema: public; Owner: alegrete
--

REVOKE ALL ON SEQUENCE g_bairro_gid_seq FROM PUBLIC;
REVOKE ALL ON SEQUENCE g_bairro_gid_seq FROM alegrete;
GRANT ALL ON SEQUENCE g_bairro_gid_seq TO alegrete;
GRANT ALL ON SEQUENCE g_bairro_gid_seq TO peter WITH GRANT OPTION;


--
-- Name: g_distrito; Type: ACL; Schema: public; Owner: alegrete
--

REVOKE ALL ON TABLE g_distrito FROM PUBLIC;
REVOKE ALL ON TABLE g_distrito FROM alegrete;
GRANT ALL ON TABLE g_distrito TO alegrete;
GRANT ALL ON TABLE g_distrito TO peter WITH GRANT OPTION;


--
-- Name: g_distrito_gid_seq; Type: ACL; Schema: public; Owner: alegrete
--

REVOKE ALL ON SEQUENCE g_distrito_gid_seq FROM PUBLIC;
REVOKE ALL ON SEQUENCE g_distrito_gid_seq FROM alegrete;
GRANT ALL ON SEQUENCE g_distrito_gid_seq TO alegrete;
GRANT ALL ON SEQUENCE g_distrito_gid_seq TO peter WITH GRANT OPTION;


--
-- Name: g_edif; Type: ACL; Schema: public; Owner: alegrete
--

REVOKE ALL ON TABLE g_edif FROM PUBLIC;
REVOKE ALL ON TABLE g_edif FROM alegrete;
GRANT ALL ON TABLE g_edif TO alegrete;
GRANT ALL ON TABLE g_edif TO peter WITH GRANT OPTION;
GRANT SELECT ON TABLE g_edif TO deskeditor;


--
-- Name: g_edif_gid_seq; Type: ACL; Schema: public; Owner: alegrete
--

REVOKE ALL ON SEQUENCE g_edif_gid_seq FROM PUBLIC;
REVOKE ALL ON SEQUENCE g_edif_gid_seq FROM alegrete;
GRANT ALL ON SEQUENCE g_edif_gid_seq TO alegrete;
GRANT ALL ON SEQUENCE g_edif_gid_seq TO peter WITH GRANT OPTION;


--
-- Name: g_edif_metrocil; Type: ACL; Schema: public; Owner: alegrete
--

REVOKE ALL ON TABLE g_edif_metrocil FROM PUBLIC;
REVOKE ALL ON TABLE g_edif_metrocil FROM alegrete;
GRANT ALL ON TABLE g_edif_metrocil TO alegrete;
GRANT ALL ON TABLE g_edif_metrocil TO peter WITH GRANT OPTION;


--
-- Name: g_edif_metrocil_gid_seq; Type: ACL; Schema: public; Owner: alegrete
--

REVOKE ALL ON SEQUENCE g_edif_metrocil_gid_seq FROM PUBLIC;
REVOKE ALL ON SEQUENCE g_edif_metrocil_gid_seq FROM alegrete;
GRANT ALL ON SEQUENCE g_edif_metrocil_gid_seq TO alegrete;
GRANT ALL ON SEQUENCE g_edif_metrocil_gid_seq TO peter WITH GRANT OPTION;


--
-- Name: g_eixologr; Type: ACL; Schema: public; Owner: alegrete
--

REVOKE ALL ON TABLE g_eixologr FROM PUBLIC;
REVOKE ALL ON TABLE g_eixologr FROM alegrete;
GRANT ALL ON TABLE g_eixologr TO alegrete;
GRANT ALL ON TABLE g_eixologr TO peter WITH GRANT OPTION;


--
-- Name: g_eixologr_gid_seq; Type: ACL; Schema: public; Owner: alegrete
--

REVOKE ALL ON SEQUENCE g_eixologr_gid_seq FROM PUBLIC;
REVOKE ALL ON SEQUENCE g_eixologr_gid_seq FROM alegrete;
GRANT ALL ON SEQUENCE g_eixologr_gid_seq TO alegrete;
GRANT ALL ON SEQUENCE g_eixologr_gid_seq TO peter WITH GRANT OPTION;


--
-- Name: g_ferrovia; Type: ACL; Schema: public; Owner: alegrete
--

REVOKE ALL ON TABLE g_ferrovia FROM PUBLIC;
REVOKE ALL ON TABLE g_ferrovia FROM alegrete;
GRANT ALL ON TABLE g_ferrovia TO alegrete;
GRANT ALL ON TABLE g_ferrovia TO peter WITH GRANT OPTION;


--
-- Name: g_ferrovia_gid_seq; Type: ACL; Schema: public; Owner: alegrete
--

REVOKE ALL ON SEQUENCE g_ferrovia_gid_seq FROM PUBLIC;
REVOKE ALL ON SEQUENCE g_ferrovia_gid_seq FROM alegrete;
GRANT ALL ON SEQUENCE g_ferrovia_gid_seq TO alegrete;
GRANT ALL ON SEQUENCE g_ferrovia_gid_seq TO peter WITH GRANT OPTION;


--
-- Name: g_hidrografia_linha; Type: ACL; Schema: public; Owner: alegrete
--

REVOKE ALL ON TABLE g_hidrografia_linha FROM PUBLIC;
REVOKE ALL ON TABLE g_hidrografia_linha FROM alegrete;
GRANT ALL ON TABLE g_hidrografia_linha TO alegrete;
GRANT ALL ON TABLE g_hidrografia_linha TO peter WITH GRANT OPTION;


--
-- Name: g_hidrografia_linha_gid_seq; Type: ACL; Schema: public; Owner: alegrete
--

REVOKE ALL ON SEQUENCE g_hidrografia_linha_gid_seq FROM PUBLIC;
REVOKE ALL ON SEQUENCE g_hidrografia_linha_gid_seq FROM alegrete;
GRANT ALL ON SEQUENCE g_hidrografia_linha_gid_seq TO alegrete;
GRANT ALL ON SEQUENCE g_hidrografia_linha_gid_seq TO peter WITH GRANT OPTION;


--
-- Name: g_hidrografia_poligono; Type: ACL; Schema: public; Owner: alegrete
--

REVOKE ALL ON TABLE g_hidrografia_poligono FROM PUBLIC;
REVOKE ALL ON TABLE g_hidrografia_poligono FROM alegrete;
GRANT ALL ON TABLE g_hidrografia_poligono TO alegrete;
GRANT ALL ON TABLE g_hidrografia_poligono TO peter WITH GRANT OPTION;


--
-- Name: g_hidrografia_poligono_gid_seq; Type: ACL; Schema: public; Owner: alegrete
--

REVOKE ALL ON SEQUENCE g_hidrografia_poligono_gid_seq FROM PUBLIC;
REVOKE ALL ON SEQUENCE g_hidrografia_poligono_gid_seq FROM alegrete;
GRANT ALL ON SEQUENCE g_hidrografia_poligono_gid_seq TO alegrete;
GRANT ALL ON SEQUENCE g_hidrografia_poligono_gid_seq TO peter WITH GRANT OPTION;


--
-- Name: g_lote_erro; Type: ACL; Schema: public; Owner: alegrete
--

REVOKE ALL ON TABLE g_lote_erro FROM PUBLIC;
REVOKE ALL ON TABLE g_lote_erro FROM alegrete;
GRANT ALL ON TABLE g_lote_erro TO alegrete;
GRANT ALL ON TABLE g_lote_erro TO peter WITH GRANT OPTION;


--
-- Name: g_lote_erro_gid_seq; Type: ACL; Schema: public; Owner: alegrete
--

REVOKE ALL ON SEQUENCE g_lote_erro_gid_seq FROM PUBLIC;
REVOKE ALL ON SEQUENCE g_lote_erro_gid_seq FROM alegrete;
GRANT ALL ON SEQUENCE g_lote_erro_gid_seq TO alegrete;
GRANT ALL ON SEQUENCE g_lote_erro_gid_seq TO peter WITH GRANT OPTION;


--
-- Name: g_lote_gid_seq; Type: ACL; Schema: public; Owner: alegrete
--

REVOKE ALL ON SEQUENCE g_lote_gid_seq FROM PUBLIC;
REVOKE ALL ON SEQUENCE g_lote_gid_seq FROM alegrete;
GRANT ALL ON SEQUENCE g_lote_gid_seq TO alegrete;
GRANT ALL ON SEQUENCE g_lote_gid_seq TO peter WITH GRANT OPTION;


--
-- Name: g_lote_metrocil; Type: ACL; Schema: public; Owner: alegrete
--

REVOKE ALL ON TABLE g_lote_metrocil FROM PUBLIC;
REVOKE ALL ON TABLE g_lote_metrocil FROM alegrete;
GRANT ALL ON TABLE g_lote_metrocil TO alegrete;
GRANT ALL ON TABLE g_lote_metrocil TO peter WITH GRANT OPTION;


--
-- Name: g_lote_metrocil_gid_seq; Type: ACL; Schema: public; Owner: alegrete
--

REVOKE ALL ON SEQUENCE g_lote_metrocil_gid_seq FROM PUBLIC;
REVOKE ALL ON SEQUENCE g_lote_metrocil_gid_seq FROM alegrete;
GRANT ALL ON SEQUENCE g_lote_metrocil_gid_seq TO alegrete;
GRANT ALL ON SEQUENCE g_lote_metrocil_gid_seq TO peter WITH GRANT OPTION;


--
-- Name: g_lote_recadastro; Type: ACL; Schema: public; Owner: alegrete
--

REVOKE ALL ON TABLE g_lote_recadastro FROM PUBLIC;
REVOKE ALL ON TABLE g_lote_recadastro FROM alegrete;
GRANT ALL ON TABLE g_lote_recadastro TO alegrete;
GRANT ALL ON TABLE g_lote_recadastro TO peter WITH GRANT OPTION;


--
-- Name: g_lote_recadastro_upto16ago2013; Type: ACL; Schema: public; Owner: alegrete
--

REVOKE ALL ON TABLE g_lote_recadastro_upto16ago2013 FROM PUBLIC;
REVOKE ALL ON TABLE g_lote_recadastro_upto16ago2013 FROM alegrete;
GRANT ALL ON TABLE g_lote_recadastro_upto16ago2013 TO alegrete;
GRANT ALL ON TABLE g_lote_recadastro_upto16ago2013 TO peter WITH GRANT OPTION;


--
-- Name: g_lote_recadastro_gid_seq; Type: ACL; Schema: public; Owner: alegrete
--

REVOKE ALL ON SEQUENCE g_lote_recadastro_gid_seq FROM PUBLIC;
REVOKE ALL ON SEQUENCE g_lote_recadastro_gid_seq FROM alegrete;
GRANT ALL ON SEQUENCE g_lote_recadastro_gid_seq TO alegrete;
GRANT ALL ON SEQUENCE g_lote_recadastro_gid_seq TO peter WITH GRANT OPTION;


--
-- Name: g_marco_geodesico; Type: ACL; Schema: public; Owner: alegrete
--

REVOKE ALL ON TABLE g_marco_geodesico FROM PUBLIC;
REVOKE ALL ON TABLE g_marco_geodesico FROM alegrete;
GRANT ALL ON TABLE g_marco_geodesico TO alegrete;
GRANT ALL ON TABLE g_marco_geodesico TO peter WITH GRANT OPTION;


--
-- Name: g_marco_geodesico_gid_seq; Type: ACL; Schema: public; Owner: alegrete
--

REVOKE ALL ON SEQUENCE g_marco_geodesico_gid_seq FROM PUBLIC;
REVOKE ALL ON SEQUENCE g_marco_geodesico_gid_seq FROM alegrete;
GRANT ALL ON SEQUENCE g_marco_geodesico_gid_seq TO alegrete;
GRANT ALL ON SEQUENCE g_marco_geodesico_gid_seq TO peter WITH GRANT OPTION;


--
-- Name: g_municipio; Type: ACL; Schema: public; Owner: alegrete
--

REVOKE ALL ON TABLE g_municipio FROM PUBLIC;
REVOKE ALL ON TABLE g_municipio FROM alegrete;
GRANT ALL ON TABLE g_municipio TO alegrete;
GRANT ALL ON TABLE g_municipio TO peter WITH GRANT OPTION;


--
-- Name: g_municipio_gid_seq; Type: ACL; Schema: public; Owner: alegrete
--

REVOKE ALL ON SEQUENCE g_municipio_gid_seq FROM PUBLIC;
REVOKE ALL ON SEQUENCE g_municipio_gid_seq FROM alegrete;
GRANT ALL ON SEQUENCE g_municipio_gid_seq TO alegrete;
GRANT ALL ON SEQUENCE g_municipio_gid_seq TO peter WITH GRANT OPTION;


--
-- Name: g_ponto_interesse; Type: ACL; Schema: public; Owner: alegrete
--

REVOKE ALL ON TABLE g_ponto_interesse FROM PUBLIC;
REVOKE ALL ON TABLE g_ponto_interesse FROM alegrete;
GRANT ALL ON TABLE g_ponto_interesse TO alegrete;
GRANT ALL ON TABLE g_ponto_interesse TO peter WITH GRANT OPTION;


--
-- Name: g_ponto_interesse_gid_seq; Type: ACL; Schema: public; Owner: alegrete
--

REVOKE ALL ON SEQUENCE g_ponto_interesse_gid_seq FROM PUBLIC;
REVOKE ALL ON SEQUENCE g_ponto_interesse_gid_seq FROM alegrete;
GRANT ALL ON SEQUENCE g_ponto_interesse_gid_seq TO alegrete;
GRANT ALL ON SEQUENCE g_ponto_interesse_gid_seq TO peter WITH GRANT OPTION;


--
-- Name: g_quadra; Type: ACL; Schema: public; Owner: alegrete
--

REVOKE ALL ON TABLE g_quadra FROM PUBLIC;
REVOKE ALL ON TABLE g_quadra FROM alegrete;
GRANT ALL ON TABLE g_quadra TO alegrete;
GRANT ALL ON TABLE g_quadra TO peter WITH GRANT OPTION;


--
-- Name: g_quadra_gid_seq; Type: ACL; Schema: public; Owner: alegrete
--

REVOKE ALL ON SEQUENCE g_quadra_gid_seq FROM PUBLIC;
REVOKE ALL ON SEQUENCE g_quadra_gid_seq FROM alegrete;
GRANT ALL ON SEQUENCE g_quadra_gid_seq TO alegrete;
GRANT ALL ON SEQUENCE g_quadra_gid_seq TO peter WITH GRANT OPTION;


--
-- Name: g_rodovia; Type: ACL; Schema: public; Owner: alegrete
--

REVOKE ALL ON TABLE g_rodovia FROM PUBLIC;
REVOKE ALL ON TABLE g_rodovia FROM alegrete;
GRANT ALL ON TABLE g_rodovia TO alegrete;
GRANT ALL ON TABLE g_rodovia TO peter WITH GRANT OPTION;


--
-- Name: g_rodovia_gid_seq; Type: ACL; Schema: public; Owner: alegrete
--

REVOKE ALL ON SEQUENCE g_rodovia_gid_seq FROM PUBLIC;
REVOKE ALL ON SEQUENCE g_rodovia_gid_seq FROM alegrete;
GRANT ALL ON SEQUENCE g_rodovia_gid_seq TO alegrete;
GRANT ALL ON SEQUENCE g_rodovia_gid_seq TO peter WITH GRANT OPTION;


--
-- Name: g_vianaourbana; Type: ACL; Schema: public; Owner: alegrete
--

REVOKE ALL ON TABLE g_vianaourbana FROM PUBLIC;
REVOKE ALL ON TABLE g_vianaourbana FROM alegrete;
GRANT ALL ON TABLE g_vianaourbana TO alegrete;
GRANT ALL ON TABLE g_vianaourbana TO peter WITH GRANT OPTION;


--
-- Name: g_vianaourbana_gid_seq; Type: ACL; Schema: public; Owner: alegrete
--

REVOKE ALL ON SEQUENCE g_vianaourbana_gid_seq FROM PUBLIC;
REVOKE ALL ON SEQUENCE g_vianaourbana_gid_seq FROM alegrete;
GRANT ALL ON SEQUENCE g_vianaourbana_gid_seq TO alegrete;
GRANT ALL ON SEQUENCE g_vianaourbana_gid_seq TO peter WITH GRANT OPTION;


--
-- Name: g_zoneamento; Type: ACL; Schema: public; Owner: alegrete
--

REVOKE ALL ON TABLE g_zoneamento FROM PUBLIC;
REVOKE ALL ON TABLE g_zoneamento FROM alegrete;
GRANT ALL ON TABLE g_zoneamento TO alegrete;
GRANT ALL ON TABLE g_zoneamento TO peter WITH GRANT OPTION;


--
-- Name: g_zoneamento3_gid_seq; Type: ACL; Schema: public; Owner: alegrete
--

REVOKE ALL ON SEQUENCE g_zoneamento3_gid_seq FROM PUBLIC;
REVOKE ALL ON SEQUENCE g_zoneamento3_gid_seq FROM alegrete;
GRANT ALL ON SEQUENCE g_zoneamento3_gid_seq TO alegrete;
GRANT ALL ON SEQUENCE g_zoneamento3_gid_seq TO peter WITH GRANT OPTION;


--
-- Name: g_zoneamento_old; Type: ACL; Schema: public; Owner: alegrete
--

REVOKE ALL ON TABLE g_zoneamento_old FROM PUBLIC;
REVOKE ALL ON TABLE g_zoneamento_old FROM alegrete;
GRANT ALL ON TABLE g_zoneamento_old TO alegrete;
GRANT ALL ON TABLE g_zoneamento_old TO peter WITH GRANT OPTION;


--
-- Name: g_zoneamento_gid_seq; Type: ACL; Schema: public; Owner: alegrete
--

REVOKE ALL ON SEQUENCE g_zoneamento_gid_seq FROM PUBLIC;
REVOKE ALL ON SEQUENCE g_zoneamento_gid_seq FROM alegrete;
GRANT ALL ON SEQUENCE g_zoneamento_gid_seq TO alegrete;
GRANT ALL ON SEQUENCE g_zoneamento_gid_seq TO peter WITH GRANT OPTION;


--
-- Name: pd_ind_zoneamento; Type: ACL; Schema: public; Owner: alegrete
--

REVOKE ALL ON TABLE pd_ind_zoneamento FROM PUBLIC;
REVOKE ALL ON TABLE pd_ind_zoneamento FROM alegrete;
GRANT ALL ON TABLE pd_ind_zoneamento TO alegrete;
GRANT ALL ON TABLE pd_ind_zoneamento TO peter WITH GRANT OPTION;


--
-- Name: sgm_edif; Type: ACL; Schema: public; Owner: alegrete
--

REVOKE ALL ON TABLE sgm_edif FROM PUBLIC;
REVOKE ALL ON TABLE sgm_edif FROM alegrete;
GRANT ALL ON TABLE sgm_edif TO alegrete;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE sgm_edif TO deskeditor;


--
-- Name: sgm_lote; Type: ACL; Schema: public; Owner: alegrete
--

REVOKE ALL ON TABLE sgm_lote FROM PUBLIC;
REVOKE ALL ON TABLE sgm_lote FROM alegrete;
GRANT ALL ON TABLE sgm_lote TO alegrete;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE sgm_lote TO deskeditor;


--
-- Name: vw_lotes_nofotos; Type: ACL; Schema: public; Owner: alegrete
--

REVOKE ALL ON TABLE vw_lotes_nofotos FROM PUBLIC;
REVOKE ALL ON TABLE vw_lotes_nofotos FROM alegrete;
GRANT ALL ON TABLE vw_lotes_nofotos TO alegrete;
GRANT ALL ON TABLE vw_lotes_nofotos TO peter WITH GRANT OPTION;


--
-- PostgreSQL database dump complete
--

