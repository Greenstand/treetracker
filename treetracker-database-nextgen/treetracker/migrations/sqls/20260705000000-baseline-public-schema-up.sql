SET search_path TO public;
-- Preamble added for a-fresh-DB db-migrate init (extensions + non-public schemas).
CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA public;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;
CREATE SCHEMA IF NOT EXISTS field_data;
CREATE SCHEMA IF NOT EXISTS data_pipeline;
CREATE SCHEMA IF NOT EXISTS keycloak;

--
-- PostgreSQL database dump
--


-- Dumped from database version 17.10
-- Dumped by pg_dump version 18.4

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA IF NOT EXISTS public;


--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
-- Name: age_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.age_type AS ENUM (
    'new_tree',
    'over_two_years'
);


--
-- Name: capture_approval_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.capture_approval_type AS ENUM (
    'simple_leaf',
    'complex_leaf',
    'acacia_like',
    'conifer',
    'fruit',
    'mangrove',
    'palm',
    'timber'
);


--
-- Name: morphology_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.morphology_type AS ENUM (
    'seedling',
    'direct_seedling',
    'fmnr'
);


--
-- Name: platform_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.platform_type AS ENUM (
    'admin_panel',
    'web_map'
);


--
-- Name: rejection_reason_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.rejection_reason_type AS ENUM (
    'not_tree',
    'unapproved_tree',
    'blurry_image',
    'dead',
    'duplicate_image',
    'flag_user',
    'needs_contact_or_review'
);


--
-- Name: status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.status AS ENUM (
    'active',
    'deleted'
);


--
-- Name: get_organization_list_by_planter_id(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_organization_list_by_planter_id(planter_id integer) RETURNS integer[]
    LANGUAGE sql
    AS $$
WITH RECURSIVE ancient_organization(org_id) AS (
    select organization_id from planter where id = planter_id
  UNION ALL
    select parent_id from entity_relationship er, ancient_organization ao
    where er.child_id = ao.org_id
)
--- return all org id
select ARRAY_AGG(org_id) from ancient_organization;
$$;


--
-- Name: getentityrelationshipchildren(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.getentityrelationshipchildren(integer) RETURNS TABLE(entity_id integer, parent_id integer, depth integer, type text, relationship_role text)
    LANGUAGE sql
    AS $_$
WITH RECURSIVE children AS (
 SELECT entity.id, entity_relationship.parent_id, 1 as depth, entity_relationship.type, entity_relationship.role
 FROM entity
 LEFT JOIN entity_relationship ON entity_relationship.child_id = entity.id 
 WHERE entity.id = $1
UNION
 SELECT next_child.id, entity_relationship.parent_id, depth + 1, entity_relationship.type, entity_relationship.role
 FROM entity next_child
 JOIN entity_relationship ON entity_relationship.child_id = next_child.id 
 JOIN children c ON entity_relationship.parent_id = c.id
)
SELECT *
FROM children
$_$;


--
-- Name: getentityrelationshipchildren(integer, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.getentityrelationshipchildren(integer, text) RETURNS TABLE(entity_id integer, parent_id integer, depth integer, type text, relationship_role text)
    LANGUAGE sql
    AS $_$
WITH RECURSIVE children AS (
 SELECT entity.id, entity_relationship.parent_id, 1 as depth, entity_relationship.type, entity_relationship.role
 FROM entity
 LEFT JOIN entity_relationship ON entity_relationship.child_id = entity.id AND entity_relationship.type = $2
 WHERE entity.id = $1
UNION
 SELECT next_child.id, entity_relationship.parent_id, depth + 1, entity_relationship.type, entity_relationship.role
 FROM entity next_child
 JOIN entity_relationship ON entity_relationship.child_id = next_child.id AND entity_relationship.type = $2
 JOIN children c ON entity_relationship.parent_id = c.id
)
SELECT *
FROM children
$_$;


--
-- Name: getentityrelationshipparents(integer, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.getentityrelationshipparents(integer, text) RETURNS TABLE(entity_id integer, parent_id integer, depth integer, type text, role text)
    LANGUAGE sql
    AS $_$
WITH RECURSIVE parents AS (
 SELECT entity.id, entity_relationship.parent_id, -1 as depth, entity_relationship.type, entity_relationship.role
 FROM entity
 LEFT JOIN entity_relationship ON entity_relationship.parent_id = entity.id AND entity_relationship.type = $2
 WHERE entity.id = $1
UNION
 SELECT next_parent.id, entity_relationship.parent_id, depth - 1, entity_relationship.type, entity_relationship.role
 FROM entity next_parent
 JOIN entity_relationship ON entity_relationship.parent_id = next_parent.id AND entity_relationship.type = $2
 JOIN parents p ON entity_relationship.child_id = p.id
)
SELECT *
FROM parents
$_$;


--
-- Name: getstakeholderchildren(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.getstakeholderchildren(uuid) RETURNS TABLE(stakeholder_id uuid, parent_id uuid, depth integer, relations_type text, relations_role text)
    LANGUAGE sql
    AS $_$
WITH RECURSIVE children AS (
   SELECT stakeholder.stakeholder.id, stakeholder.stakeholder_relation.parent_id, 1 as depth, stakeholder.stakeholder_relation.type, stakeholder.stakeholder_relation.role
   FROM stakeholder.stakeholder
   LEFT JOIN stakeholder.stakeholder_relation ON stakeholder.stakeholder_relation.child_id = stakeholder.stakeholder.id 
   WHERE stakeholder.stakeholder.id = $1
  UNION
   SELECT next_child.id, stakeholder.stakeholder_relation.parent_id, depth + 1, stakeholder.stakeholder_relation.type, stakeholder.stakeholder_relation.role
   FROM stakeholder.stakeholder next_child
   JOIN stakeholder.stakeholder_relation ON stakeholder.stakeholder_relation.child_id = next_child.id 
   JOIN children c ON stakeholder.stakeholder_relation.parent_id = c.id
)
SELECT *
FROM children
$_$;


--
-- Name: makegrid_2d(public.geometry, integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.makegrid_2d(bound_polygon public.geometry, width_step integer, height_step integer) RETURNS public.geometry
    LANGUAGE plpgsql
    AS $_$
DECLARE
  Xmin DOUBLE PRECISION;
  Xmax DOUBLE PRECISION;
  Ymax DOUBLE PRECISION;
  X DOUBLE PRECISION;
  Y DOUBLE PRECISION;
  NextX DOUBLE PRECISION;
  NextY DOUBLE PRECISION;
  CPoint public.geometry;
  sectors public.geometry[];
  i INTEGER;
  SRID INTEGER;
BEGIN
  Xmin := ST_XMin(bound_polygon);
  Xmax := ST_XMax(bound_polygon);
  Ymax := ST_YMax(bound_polygon);
  SRID := ST_SRID(bound_polygon);

  Y := ST_YMin(bound_polygon); --current sector's corner coordinate
  i := -1;
  <<yloop>>
  LOOP
    IF (Y >= Ymax) THEN
        EXIT;
    END IF;

    X := Xmin;
    <<xloop>>
    LOOP
      IF (X >= Xmax) THEN
          EXIT;
      END IF;

      CPoint := ST_SetSRID(ST_MakePoint(X, Y), SRID);
      NextX := ST_X(ST_Project(CPoint, $2, radians(90))::geometry);
      NextY := ST_Y(ST_Project(CPoint, $3, radians(0))::geometry);

      IF (NextX > Xmax) THEN
          NextX := Xmax;
      END IF;

      IF (NextX < X) THEN
          NextX := Xmax;
      END IF;

      i := i + 1;
      sectors[i] := ST_MakeEnvelope(X, Y, NextX, NextY, SRID);

      X := NextX;
    END LOOP xloop;
    CPoint := ST_SetSRID(ST_MakePoint(X, Y), SRID);
    NextY := ST_Y(ST_Project(CPoint, $3, radians(0))::geometry);
    Y := NextY;
  END LOOP yloop;

  RETURN ST_Collect(sectors);
END;
$_$;


--
-- Name: st_dwithin_deprecated_by_postgis_300(public.geography, public.geography, double precision); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.st_dwithin_deprecated_by_postgis_300(public.geography, public.geography, double precision) RETURNS boolean
    LANGUAGE sql IMMUTABLE PARALLEL SAFE
    AS $_$SELECT $1 OPERATOR(public.&&) public._ST_Expand($2,$3) AND $2 OPERATOR(public.&&) public._ST_Expand($1,$3) AND public._ST_DWithin($1, $2, $3, true)$_$;


--
-- Name: FUNCTION st_dwithin_deprecated_by_postgis_300(public.geography, public.geography, double precision); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.st_dwithin_deprecated_by_postgis_300(public.geography, public.geography, double precision) IS 'args: gg1, gg2, distance_meters - Returns true if the geometries are within the specified distance of one another. For geometry units are in those of spatial reference and for geography units are in meters and measurement is defaulted to use_spheroid=true (measure around spheroid), for faster check, use_spheroid=false to measure along sphere.';


--
-- Name: token_transaction_insert(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.token_transaction_insert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
                 BEGIN
                    INSERT INTO transaction
                    (token_id, sender_entity_id, receiver_entity_id)
                    VALUES
                    (OLD.id, OLD.entity_id, NEW.entity_id);
                    RETURN NEW;
                 END;
             $$;


--
-- Name: trigger_set_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trigger_set_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
    END;
    $$;


--
-- Name: trees_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.trees_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: trees; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.trees (
    id integer DEFAULT nextval('public.trees_id_seq'::regclass) NOT NULL,
    time_created timestamp without time zone NOT NULL,
    time_updated timestamp without time zone NOT NULL,
    missing boolean DEFAULT false,
    priority boolean DEFAULT false,
    cause_of_death_id integer,
    planter_id integer,
    primary_location_id integer,
    settings_id integer,
    override_settings_id integer,
    dead integer DEFAULT 0 NOT NULL,
    photo_id integer,
    image_url character varying,
    certificate_id integer,
    estimated_geometric_location public.geometry(Point,4326),
    lat numeric,
    lon numeric,
    gps_accuracy integer,
    active boolean DEFAULT true,
    planter_photo_url character varying,
    planter_identifier character varying,
    device_id integer,
    sequence integer,
    note character varying,
    verified boolean DEFAULT false NOT NULL,
    uuid character varying,
    approved boolean DEFAULT false NOT NULL,
    status character varying DEFAULT 'planted'::character varying NOT NULL,
    cluster_regions_assigned boolean DEFAULT false NOT NULL,
    species_id integer,
    planting_organization_id integer,
    payment_id integer,
    contract_id integer,
    token_issued boolean DEFAULT false NOT NULL,
    morphology public.morphology_type,
    age public.age_type,
    species character varying,
    capture_approval_tag public.capture_approval_type,
    rejection_reason public.rejection_reason_type,
    matching_hash character varying,
    device_identifier character varying,
    images jsonb,
    domain_specific_data jsonb,
    token_id uuid,
    name character varying,
    earnings_id uuid,
    session_id uuid
);


--
-- Name: entity; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.entity (
    id integer NOT NULL,
    type character varying,
    name character varying,
    first_name character varying,
    last_name character varying,
    email character varying,
    phone character varying,
    pwd_reset_required boolean DEFAULT false,
    website character varying,
    wallet character varying,
    password character varying,
    salt character varying,
    active_contract_id integer,
    offering_pay_to_plant boolean DEFAULT false NOT NULL,
    tree_validation_contract_id integer,
    logo_url character varying,
    map_name character varying,
    stakeholder_uuid uuid DEFAULT public.uuid_generate_v4() NOT NULL
);


--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: planter; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.planter (
    id integer DEFAULT nextval('public.users_id_seq'::regclass) NOT NULL,
    first_name character varying(30) NOT NULL,
    last_name character varying(30) NOT NULL,
    email character varying,
    organization character varying,
    phone text,
    pwd_reset_required boolean DEFAULT false,
    image_url character varying,
    person_id integer,
    organization_id integer,
    image_rotation integer,
    gender character varying,
    grower_account_uuid uuid
);


--
-- Name: token; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.token (
    id integer NOT NULL,
    tree_id integer,
    entity_id integer,
    uuid character varying DEFAULT public.uuid_generate_v4(),
    capture_id character varying
);


--
-- Name: ab_permission; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ab_permission (
    id integer NOT NULL,
    name character varying(100) NOT NULL
);


--
-- Name: ab_permission_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ab_permission_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ab_permission_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ab_permission_id_seq OWNED BY public.ab_permission.id;


--
-- Name: ab_permission_view; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ab_permission_view (
    id integer NOT NULL,
    permission_id integer,
    view_menu_id integer
);


--
-- Name: ab_permission_view_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ab_permission_view_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ab_permission_view_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ab_permission_view_id_seq OWNED BY public.ab_permission_view.id;


--
-- Name: ab_permission_view_role; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ab_permission_view_role (
    id integer NOT NULL,
    permission_view_id integer,
    role_id integer
);


--
-- Name: ab_permission_view_role_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ab_permission_view_role_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ab_permission_view_role_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ab_permission_view_role_id_seq OWNED BY public.ab_permission_view_role.id;


--
-- Name: ab_register_user; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ab_register_user (
    id integer NOT NULL,
    first_name character varying(256) NOT NULL,
    last_name character varying(256) NOT NULL,
    username character varying(512) NOT NULL,
    password character varying(256),
    email character varying(512) NOT NULL,
    registration_date timestamp without time zone,
    registration_hash character varying(256)
);


--
-- Name: ab_register_user_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ab_register_user_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ab_register_user_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ab_register_user_id_seq OWNED BY public.ab_register_user.id;


--
-- Name: ab_role; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ab_role (
    id integer NOT NULL,
    name character varying(64) NOT NULL
);


--
-- Name: ab_role_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ab_role_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ab_role_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ab_role_id_seq OWNED BY public.ab_role.id;


--
-- Name: ab_user; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ab_user (
    id integer NOT NULL,
    first_name character varying(256) NOT NULL,
    last_name character varying(256) NOT NULL,
    username character varying(512) NOT NULL,
    password character varying(256),
    active boolean,
    email character varying(512) NOT NULL,
    last_login timestamp without time zone,
    login_count integer,
    fail_login_count integer,
    created_on timestamp without time zone,
    changed_on timestamp without time zone,
    created_by_fk integer,
    changed_by_fk integer
);


--
-- Name: ab_user_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ab_user_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ab_user_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ab_user_id_seq OWNED BY public.ab_user.id;


--
-- Name: ab_user_role; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ab_user_role (
    id integer NOT NULL,
    user_id integer,
    role_id integer
);


--
-- Name: ab_user_role_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ab_user_role_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ab_user_role_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ab_user_role_id_seq OWNED BY public.ab_user_role.id;


--
-- Name: ab_view_menu; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ab_view_menu (
    id integer NOT NULL,
    name character varying(250) NOT NULL
);


--
-- Name: ab_view_menu_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ab_view_menu_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ab_view_menu_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ab_view_menu_id_seq OWNED BY public.ab_view_menu.id;


--
-- Name: region; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.region (
    id integer NOT NULL,
    type_id integer,
    name character varying,
    metadata jsonb,
    geom public.geometry(MultiPolygon,4326),
    centroid public.geometry(Point,4326),
    region_uuid uuid DEFAULT public.uuid_generate_v4() NOT NULL
);


--
-- Name: tree_region; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tree_region (
    id integer NOT NULL,
    tree_id integer,
    zoom_level integer,
    region_id integer
);


--
-- Name: active_tree_region; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.active_tree_region AS
 SELECT tree_region.id,
    tree_region.tree_id,
    region.id AS region_id,
    region.centroid,
    region.type_id,
    tree_region.zoom_level
   FROM ((public.tree_region
     JOIN public.trees ON ((trees.id = tree_region.tree_id)))
     JOIN public.region ON ((region.id = tree_region.region_id)))
  WHERE (trees.active = true)
  WITH NO DATA;


--
-- Name: admin_role; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.admin_role (
    id integer NOT NULL,
    role_name character varying NOT NULL,
    description character varying,
    policy json,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    identifier character varying DEFAULT public.uuid_generate_v4()
);


--
-- Name: admin_role_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.admin_role_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: admin_role_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.admin_role_id_seq OWNED BY public.admin_role.id;


--
-- Name: admin_user; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.admin_user (
    id integer NOT NULL,
    user_name character varying(150) NOT NULL,
    password_hash character varying(150) NOT NULL,
    email character varying(255),
    active boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    salt character varying(150)
);


--
-- Name: admin_user_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.admin_user_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: admin_user_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.admin_user_id_seq OWNED BY public.admin_user.id;


--
-- Name: admin_user_role; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.admin_user_role (
    id integer NOT NULL,
    role_id integer NOT NULL,
    admin_user_id integer NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL
);


--
-- Name: admin_user_role_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.admin_user_role_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: admin_user_role_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.admin_user_role_id_seq OWNED BY public.admin_user_role.id;


--
-- Name: alembic_version; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.alembic_version (
    version_num character varying(32) NOT NULL
);


--
-- Name: anonymous_entities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.anonymous_entities (
    index bigint,
    id bigint,
    type text,
    name text,
    first_name text,
    last_name text,
    website text,
    wallet text,
    offering_pay_to_plant boolean,
    logo_url text,
    map_name text
);


--
-- Name: anonymous_planters; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.anonymous_planters (
    index bigint,
    id bigint,
    first_name text,
    last_name text,
    email text,
    organization text,
    image_url text,
    person_id double precision,
    organization_id double precision
);


--
-- Name: anonymous_trees; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.anonymous_trees (
    index bigint,
    id bigint,
    time_created timestamp without time zone,
    time_updated timestamp without time zone,
    missing boolean,
    priority boolean,
    cause_of_death_id double precision,
    planter_id bigint,
    primary_location_id double precision,
    settings_id double precision,
    image_url text,
    certificate_id double precision,
    lat double precision,
    lon double precision,
    planter_photo_url text,
    planter_identifier text,
    device_id double precision,
    note text,
    verified boolean,
    uuid text,
    approved boolean,
    status text,
    species_id double precision,
    planting_organization_id double precision,
    payment_id double precision,
    contract_id text,
    token_issued boolean,
    morphology text,
    age text,
    species text,
    capture_approval_tag text,
    rejection_reason text,
    device_identifier text
);


--
-- Name: api_key; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.api_key (
    id integer NOT NULL,
    key character varying,
    tree_token_api_access boolean,
    hash character varying,
    salt character varying,
    name character varying
);


--
-- Name: api_key_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.api_key_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: api_key_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.api_key_id_seq OWNED BY public.api_key.id;


--
-- Name: audit; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit (
    id integer NOT NULL,
    admin_user_id integer NOT NULL,
    platform public.platform_type,
    ip character varying,
    browser character varying,
    organization character varying,
    operation json,
    created_at timestamp without time zone DEFAULT now() NOT NULL
);


--
-- Name: audit_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.audit_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: audit_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.audit_id_seq OWNED BY public.audit.id;


--
-- Name: callback_request; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.callback_request (
    id integer NOT NULL,
    created_at timestamp with time zone NOT NULL,
    priority_weight integer NOT NULL,
    callback_data json NOT NULL,
    callback_type character varying(20) NOT NULL,
    processor_subdir character varying(2000)
);


--
-- Name: callback_request_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.callback_request_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: callback_request_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.callback_request_id_seq OWNED BY public.callback_request.id;


--
-- Name: celery_taskmeta; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.celery_taskmeta (
    id integer NOT NULL,
    task_id character varying(155),
    status character varying(50),
    result bytea,
    date_done timestamp without time zone,
    traceback text,
    name character varying(155),
    args bytea,
    kwargs bytea,
    worker character varying(155),
    retries integer,
    queue character varying(155)
);


--
-- Name: celery_tasksetmeta; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.celery_tasksetmeta (
    id integer NOT NULL,
    taskset_id character varying(155),
    result bytea,
    date_done timestamp without time zone
);


--
-- Name: certificates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.certificates (
    id integer NOT NULL,
    donor_id integer,
    token character varying
);


--
-- Name: certificates_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.certificates_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: certificates_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.certificates_id_seq OWNED BY public.certificates.id;


--
-- Name: clusters; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.clusters (
    id integer NOT NULL,
    count integer,
    zoom_level integer,
    location public.geometry(Point,4326)
);


--
-- Name: clusters_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.clusters_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: clusters_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.clusters_id_seq OWNED BY public.clusters.id;


--
-- Name: connection; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.connection (
    id integer NOT NULL,
    conn_id character varying(250) NOT NULL,
    conn_type character varying(500) NOT NULL,
    host character varying(500),
    schema character varying(500),
    login character varying(500),
    password character varying(5000),
    port integer,
    extra text,
    is_encrypted boolean,
    is_extra_encrypted boolean,
    description text
);


--
-- Name: connection_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.connection_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: connection_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.connection_id_seq OWNED BY public.connection.id;


--
-- Name: contract; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contract (
    id integer NOT NULL,
    author_id integer NOT NULL,
    name character varying NOT NULL,
    enabled boolean DEFAULT false NOT NULL,
    contract json NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL
);


--
-- Name: contract_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.contract_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: contract_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.contract_id_seq OWNED BY public.contract.id;


--
-- Name: dag; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dag (
    dag_id character varying(250) NOT NULL,
    is_paused boolean,
    is_subdag boolean,
    is_active boolean,
    last_parsed_time timestamp with time zone,
    last_pickled timestamp with time zone,
    last_expired timestamp with time zone,
    scheduler_lock boolean,
    pickle_id integer,
    fileloc character varying(2000),
    owners character varying(2000),
    description text,
    default_view character varying(25),
    schedule_interval text,
    root_dag_id character varying(250),
    next_dagrun timestamp with time zone,
    next_dagrun_create_after timestamp with time zone,
    max_active_tasks integer NOT NULL,
    has_task_concurrency_limits boolean NOT NULL,
    max_active_runs integer,
    next_dagrun_data_interval_start timestamp with time zone,
    next_dagrun_data_interval_end timestamp with time zone,
    has_import_errors boolean DEFAULT false,
    timetable_description character varying(1000),
    processor_subdir character varying(2000)
);


--
-- Name: dag_code; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dag_code (
    fileloc_hash bigint NOT NULL,
    fileloc character varying(2000) NOT NULL,
    source_code text NOT NULL,
    last_updated timestamp with time zone NOT NULL
);


--
-- Name: dag_owner_attributes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dag_owner_attributes (
    dag_id character varying(250) NOT NULL,
    owner character varying(500) NOT NULL,
    link character varying(500) NOT NULL
);


--
-- Name: dag_pickle; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dag_pickle (
    id integer NOT NULL,
    pickle bytea,
    created_dttm timestamp with time zone,
    pickle_hash bigint
);


--
-- Name: dag_pickle_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.dag_pickle_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: dag_pickle_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.dag_pickle_id_seq OWNED BY public.dag_pickle.id;


--
-- Name: dag_run; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dag_run (
    id integer NOT NULL,
    dag_id character varying(250) NOT NULL,
    execution_date timestamp with time zone NOT NULL,
    state character varying(50),
    run_id character varying(250) NOT NULL,
    external_trigger boolean,
    conf bytea,
    end_date timestamp with time zone,
    start_date timestamp with time zone,
    run_type character varying(50) NOT NULL,
    last_scheduling_decision timestamp with time zone,
    dag_hash character varying(32),
    creating_job_id integer,
    queued_at timestamp with time zone,
    data_interval_start timestamp with time zone,
    data_interval_end timestamp with time zone,
    log_template_id integer,
    updated_at timestamp with time zone
);


--
-- Name: dag_run_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.dag_run_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: dag_run_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.dag_run_id_seq OWNED BY public.dag_run.id;


--
-- Name: dag_run_note; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dag_run_note (
    user_id integer,
    dag_run_id integer NOT NULL,
    content character varying(1000),
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);


--
-- Name: dag_schedule_dataset_reference; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dag_schedule_dataset_reference (
    dataset_id integer NOT NULL,
    dag_id character varying(250) NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);


--
-- Name: dag_tag; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dag_tag (
    name character varying(100) NOT NULL,
    dag_id character varying(250) NOT NULL
);


--
-- Name: dag_warning; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dag_warning (
    dag_id character varying(250) NOT NULL,
    warning_type character varying(50) NOT NULL,
    message text NOT NULL,
    "timestamp" timestamp with time zone NOT NULL
);


--
-- Name: dagrun_dataset_event; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dagrun_dataset_event (
    dag_run_id integer NOT NULL,
    event_id integer NOT NULL
);


--
-- Name: dataset; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dataset (
    id integer NOT NULL,
    uri character varying(3000) NOT NULL,
    extra json NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    is_orphaned boolean DEFAULT false NOT NULL
);


--
-- Name: dataset_dag_run_queue; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dataset_dag_run_queue (
    dataset_id integer NOT NULL,
    target_dag_id character varying(250) NOT NULL,
    created_at timestamp with time zone NOT NULL
);


--
-- Name: dataset_event; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dataset_event (
    id integer NOT NULL,
    dataset_id integer NOT NULL,
    extra json NOT NULL,
    source_task_id character varying(250),
    source_dag_id character varying(250),
    source_run_id character varying(250),
    source_map_index integer DEFAULT '-1'::integer,
    "timestamp" timestamp with time zone NOT NULL
);


--
-- Name: dataset_event_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.dataset_event_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: dataset_event_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.dataset_event_id_seq OWNED BY public.dataset_event.id;


--
-- Name: dataset_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.dataset_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: dataset_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.dataset_id_seq OWNED BY public.dataset.id;


--
-- Name: denormalized_trees; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.denormalized_trees (
    id integer NOT NULL,
    estimated_geometric_point public.geometry(Point,4326),
    planter_id integer,
    planter_name character varying,
    token_id uuid,
    wallet_id uuid,
    wallet_name character varying,
    species_name character varying,
    species_id uuid,
    organization_id integer,
    tags jsonb,
    organizations integer[],
    country_id integer,
    continent_id integer
);


--
-- Name: devices; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.devices (
    id integer NOT NULL,
    android_id character varying,
    app_version character varying,
    app_build integer,
    manufacturer character varying,
    brand character varying,
    model character varying,
    hardware character varying,
    device character varying,
    serial character varying,
    android_release character varying,
    android_sdk integer,
    sequence bigint,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    updated_at timestamp without time zone
);


--
-- Name: devices_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.devices_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: devices_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.devices_id_seq OWNED BY public.devices.id;


--
-- Name: domain_event; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.domain_event (
    id uuid NOT NULL,
    payload jsonb NOT NULL,
    status character varying NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
)
PARTITION BY LIST (status);


--
-- Name: domain_event_handled; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.domain_event_handled (
    id uuid NOT NULL,
    payload jsonb NOT NULL,
    status character varying NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
)
PARTITION BY RANGE (created_at);


--
-- Name: domain_event_handled_2021; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.domain_event_handled_2021 (
    id uuid NOT NULL,
    payload jsonb NOT NULL,
    status character varying NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);


--
-- Name: domain_event_handled_2022; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.domain_event_handled_2022 (
    id uuid NOT NULL,
    payload jsonb NOT NULL,
    status character varying NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);


--
-- Name: domain_event_handled_2023; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.domain_event_handled_2023 (
    id uuid NOT NULL,
    payload jsonb NOT NULL,
    status character varying NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);


--
-- Name: domain_event_raised; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.domain_event_raised (
    id uuid NOT NULL,
    payload jsonb NOT NULL,
    status character varying NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);


--
-- Name: domain_event_received; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.domain_event_received (
    id uuid NOT NULL,
    payload jsonb NOT NULL,
    status character varying NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);


--
-- Name: domain_event_sent; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.domain_event_sent (
    id uuid NOT NULL,
    payload jsonb NOT NULL,
    status character varying NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
)
PARTITION BY RANGE (created_at);


--
-- Name: domain_event_sent_2021; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.domain_event_sent_2021 (
    id uuid NOT NULL,
    payload jsonb NOT NULL,
    status character varying NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);


--
-- Name: domain_event_sent_2022; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.domain_event_sent_2022 (
    id uuid NOT NULL,
    payload jsonb NOT NULL,
    status character varying NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);


--
-- Name: domain_event_sent_2023; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.domain_event_sent_2023 (
    id uuid NOT NULL,
    payload jsonb NOT NULL,
    status character varying NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);


--
-- Name: donors; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.donors (
    id integer NOT NULL,
    organization_id integer,
    first_name character varying,
    last_name character varying,
    email character varying
);


--
-- Name: donors_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.donors_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: donors_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.donors_id_seq OWNED BY public.donors.id;


--
-- Name: dylan_denormalization_test; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dylan_denormalization_test (
    id integer NOT NULL,
    lat numeric,
    lon numeric,
    wallet_id uuid,
    country_id integer NOT NULL,
    continent_id integer NOT NULL,
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    organizations integer[]
);


--
-- Name: dylan_denormalization_test_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.dylan_denormalization_test_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: dylan_denormalization_test_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.dylan_denormalization_test_id_seq OWNED BY public.dylan_denormalization_test.id;


--
-- Name: dylan_test; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dylan_test (
    column1 integer,
    column2 character varying(255),
    column3 character varying(255)
);


--
-- Name: entities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.entities (
    index bigint,
    id bigint,
    type text,
    name text,
    first_name text,
    last_name text,
    website text,
    wallet text,
    offering_pay_to_plant boolean,
    logo_url text,
    map_name text
);


--
-- Name: entity_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.entity_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: entity_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.entity_id_seq OWNED BY public.entity.id;


--
-- Name: entity_manager; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.entity_manager (
    id integer NOT NULL,
    parent_entity_id integer,
    child_entity_id integer,
    active boolean DEFAULT false NOT NULL
);


--
-- Name: entity_manager_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.entity_manager_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: entity_manager_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.entity_manager_id_seq OWNED BY public.entity_manager.id;


--
-- Name: entity_new; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.entity_new (
    id integer,
    type character varying,
    name character varying,
    first_name character varying,
    last_name character varying,
    email character varying,
    phone character varying,
    pwd_reset_required boolean,
    website character varying,
    wallet character varying,
    password character varying,
    salt character varying,
    active_contract_id integer,
    offering_pay_to_plant boolean,
    tree_validation_contract_id integer,
    logo_url character varying,
    map_name character varying,
    stakeholder_uuid uuid
);


--
-- Name: entity_relationship; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.entity_relationship (
    id integer NOT NULL,
    parent_id integer NOT NULL,
    child_id integer NOT NULL,
    type character varying NOT NULL,
    role character varying NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL
);


--
-- Name: entity_relationship_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.entity_relationship_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: entity_relationship_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.entity_relationship_id_seq OWNED BY public.entity_relationship.id;


--
-- Name: entity_role; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.entity_role (
    id integer NOT NULL,
    entity_id integer,
    role_name character varying,
    enabled boolean
);


--
-- Name: entity_role_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.entity_role_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: entity_role_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.entity_role_id_seq OWNED BY public.entity_role.id;


--
-- Name: grower_note; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.grower_note (
    id integer NOT NULL,
    planter_id integer NOT NULL,
    content text NOT NULL,
    author_id integer NOT NULL,
    author_name character varying(255) NOT NULL,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


--
-- Name: grower_note_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.grower_note_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: grower_note_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.grower_note_id_seq OWNED BY public.grower_note.id;


--
-- Name: import_error; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.import_error (
    id integer NOT NULL,
    "timestamp" timestamp with time zone,
    filename character varying(1024),
    stacktrace text
);


--
-- Name: import_error_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.import_error_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: import_error_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.import_error_id_seq OWNED BY public.import_error.id;


--
-- Name: job; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.job (
    id integer NOT NULL,
    dag_id character varying(250),
    state character varying(20),
    job_type character varying(30),
    start_date timestamp with time zone,
    end_date timestamp with time zone,
    latest_heartbeat timestamp with time zone,
    executor_class character varying(500),
    hostname character varying(500),
    unixname character varying(1000)
);


--
-- Name: job_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.job_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: job_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.job_id_seq OWNED BY public.job.id;


--
-- Name: khushi_denormalized; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.khushi_denormalized (
    capture_uuid character varying NOT NULL,
    planter_first_name character varying NOT NULL,
    planter_last_name character varying NOT NULL,
    planter_identifier character varying,
    lat character varying NOT NULL,
    lon character varying NOT NULL,
    note character varying,
    approved character varying NOT NULL,
    planting_organization_uuid character varying,
    planting_organization_name character varying,
    species character varying,
    date_paid timestamp with time zone,
    paid_by character varying,
    payment_local_amt numeric,
    token_id character varying,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: knex_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.knex_migrations (
    id integer NOT NULL,
    name character varying(255),
    batch integer,
    migration_time timestamp with time zone
);


--
-- Name: knex_migrations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.knex_migrations_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: knex_migrations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.knex_migrations_id_seq OWNED BY public.knex_migrations.id;


--
-- Name: knex_migrations_lock; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.knex_migrations_lock (
    index integer NOT NULL,
    is_locked integer
);


--
-- Name: knex_migrations_lock_index_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.knex_migrations_lock_index_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: knex_migrations_lock_index_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.knex_migrations_lock_index_seq OWNED BY public.knex_migrations_lock.index;


--
-- Name: leaf; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.leaf (
    leaf_id integer NOT NULL,
    leaf_name character varying NOT NULL,
    leaf_type character varying NOT NULL,
    owner character varying NOT NULL
);


--
-- Name: leaf_khushi; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.leaf_khushi (
    leaf_id integer NOT NULL,
    leaf_name character varying NOT NULL,
    leaf_type character varying NOT NULL,
    owner character varying NOT NULL
);


--
-- Name: leaf_khushi_leaf_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.leaf_khushi_leaf_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: leaf_khushi_leaf_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.leaf_khushi_leaf_id_seq OWNED BY public.leaf_khushi.leaf_id;


--
-- Name: leaf_leaf_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.leaf_leaf_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: leaf_leaf_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.leaf_leaf_id_seq OWNED BY public.leaf.leaf_id;


--
-- Name: locations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.locations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: locations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.locations (
    id integer DEFAULT nextval('public.locations_id_seq'::regclass) NOT NULL,
    lat character varying(10) NOT NULL,
    lon character varying(10) NOT NULL,
    gps_accuracy integer,
    planter_id integer
);


--
-- Name: log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.log (
    id integer NOT NULL,
    dttm timestamp with time zone,
    dag_id character varying(250),
    task_id character varying(250),
    event character varying(30),
    execution_date timestamp with time zone,
    owner character varying(500),
    extra text,
    map_index integer
);


--
-- Name: log_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.log_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: log_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.log_id_seq OWNED BY public.log.id;


--
-- Name: log_template; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.log_template (
    id integer NOT NULL,
    filename text NOT NULL,
    elasticsearch_id text NOT NULL,
    created_at timestamp with time zone NOT NULL
);


--
-- Name: log_template_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.log_template_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: log_template_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.log_template_id_seq OWNED BY public.log_template.id;


--
-- Name: long_running; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.long_running AS
 SELECT pid,
    (now() - query_start) AS duration,
    query,
    state
   FROM pg_stat_activity
  WHERE ((now() - query_start) > '00:05:00'::interval);


--
-- Name: migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.migrations (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    run_on timestamp without time zone NOT NULL
);


--
-- Name: migrations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.migrations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: migrations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.migrations_id_seq OWNED BY public.migrations.id;


--
-- Name: migrations_state; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.migrations_state (
    key character varying NOT NULL,
    value text NOT NULL,
    run_on timestamp without time zone NOT NULL
);


--
-- Name: note_trees; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.note_trees (
    tree_id integer,
    note_id integer
);


--
-- Name: notes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.notes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: notes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notes (
    id integer DEFAULT nextval('public.notes_id_seq'::regclass) NOT NULL,
    content text,
    time_created timestamp without time zone NOT NULL,
    planter_id integer
);


--
-- Name: organization_children; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.organization_children AS
 SELECT id,
    ARRAY( SELECT getentityrelationshipchildren.entity_id
           FROM public.getentityrelationshipchildren(entity.id) getentityrelationshipchildren(entity_id, parent_id, depth, type, relationship_role)) AS children,
    map_name
   FROM public.entity
  WHERE (map_name IS NOT NULL)
  WITH NO DATA;


--
-- Name: organizations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.organizations (
    id integer NOT NULL,
    name character varying
);


--
-- Name: organizations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.organizations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: organizations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.organizations_id_seq OWNED BY public.organizations.id;


--
-- Name: orgnization_children; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.orgnization_children AS
 SELECT id,
    ARRAY( SELECT getentityrelationshipchildren.entity_id
           FROM public.getentityrelationshipchildren(entity.id) getentityrelationshipchildren(entity_id, parent_id, depth, type, relationship_role)) AS children,
    map_name
   FROM public.entity
  WHERE (map_name IS NOT NULL)
  WITH NO DATA;


--
-- Name: payment; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payment (
    id integer NOT NULL,
    sender_entity_id integer,
    receiver_entity_id integer,
    date_paid date,
    tree_amt integer,
    usd_amt integer,
    local_amt integer,
    paid_by character varying
);


--
-- Name: payment_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.payment_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: payment_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.payment_id_seq OWNED BY public.payment.id;


--
-- Name: pending_update_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.pending_update_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: pending_update; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pending_update (
    id integer DEFAULT nextval('public.pending_update_id_seq'::regclass) NOT NULL,
    planter_id integer,
    settings_id integer,
    tree_id integer,
    location_id integer
);


--
-- Name: photo_trees; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.photo_trees (
    tree_id integer,
    photo_id integer
);


--
-- Name: photos_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.photos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: photos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.photos (
    id integer DEFAULT nextval('public.photos_id_seq'::regclass) NOT NULL,
    outdated boolean DEFAULT false,
    time_taken timestamp without time zone NOT NULL,
    location_id integer,
    user_id integer,
    base64_image bytea
);


--
-- Name: planter_new; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.planter_new (
    id integer,
    first_name character varying,
    last_name character varying,
    email character varying,
    organization character varying,
    phone text,
    pwd_reset_required boolean,
    image_url character varying,
    person_id integer,
    organization_id integer,
    image_rotation integer,
    gender character varying,
    grower_account_uuid uuid
);


--
-- Name: planter_registrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.planter_registrations (
    id integer NOT NULL,
    planter_id integer,
    device_id integer,
    first_name character varying,
    last_name character varying,
    organization character varying,
    phone character varying,
    email character varying,
    location_string character varying,
    device_identifier character varying,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    lat numeric,
    lon numeric,
    gps_accuracy integer,
    geom public.geometry(Point,4326)
);


--
-- Name: planter_registrations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.planter_registrations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: planter_registrations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.planter_registrations_id_seq OWNED BY public.planter_registrations.id;


--
-- Name: planters; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.planters (
    index bigint,
    id bigint,
    first_name text,
    last_name text,
    email text,
    organization text,
    image_url text,
    person_id double precision,
    organization_id double precision
);


--
-- Name: region_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.region_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: region_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.region_id_seq OWNED BY public.region.id;


--
-- Name: region_type; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.region_type (
    id integer NOT NULL,
    type character varying
);


--
-- Name: region_type_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.region_type_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: region_type_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.region_type_id_seq OWNED BY public.region_type.id;


--
-- Name: region_zoom; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.region_zoom (
    id integer NOT NULL,
    region_id integer,
    zoom_level integer,
    priority integer
);


--
-- Name: region_zoom_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.region_zoom_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: region_zoom_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.region_zoom_id_seq OWNED BY public.region_zoom.id;


--
-- Name: rendered_task_instance_fields; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.rendered_task_instance_fields (
    dag_id character varying(250) NOT NULL,
    task_id character varying(250) NOT NULL,
    rendered_fields json NOT NULL,
    k8s_pod_yaml json,
    map_index integer DEFAULT '-1'::integer NOT NULL,
    run_id character varying(250) NOT NULL
);


--
-- Name: serialized_dag; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.serialized_dag (
    dag_id character varying(250) NOT NULL,
    fileloc character varying(2000) NOT NULL,
    fileloc_hash bigint NOT NULL,
    data json,
    last_updated timestamp with time zone NOT NULL,
    dag_hash character varying(32) NOT NULL,
    data_compressed bytea,
    processor_subdir character varying(2000)
);


--
-- Name: session; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.session (
    id integer NOT NULL,
    session_id character varying(255),
    data bytea,
    expiry timestamp without time zone
);


--
-- Name: session_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.session_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: session_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.session_id_seq OWNED BY public.session.id;


--
-- Name: settings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.settings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.settings (
    id integer DEFAULT nextval('public.settings_id_seq'::regclass) NOT NULL,
    next_update integer DEFAULT 30,
    min_gps_accuracy integer DEFAULT 30
);


--
-- Name: sla_miss; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sla_miss (
    task_id character varying(250) NOT NULL,
    dag_id character varying(250) NOT NULL,
    execution_date timestamp with time zone NOT NULL,
    email_sent boolean,
    "timestamp" timestamp with time zone,
    description text,
    notification_sent boolean
);


--
-- Name: slot_pool; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.slot_pool (
    id integer NOT NULL,
    pool character varying(256),
    slots integer,
    description text,
    include_deferred boolean NOT NULL
);


--
-- Name: slot_pool_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.slot_pool_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: slot_pool_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.slot_pool_id_seq OWNED BY public.slot_pool.id;


--
-- Name: stakeholder_relation; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.stakeholder_relation (
    parent_id uuid NOT NULL,
    child_id uuid NOT NULL,
    type character varying,
    role character varying,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: survey; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.survey (
    id uuid NOT NULL,
    title character varying NOT NULL,
    created_at timestamp with time zone NOT NULL,
    active boolean NOT NULL
);


--
-- Name: survey_question; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.survey_question (
    id uuid NOT NULL,
    survey_id uuid NOT NULL,
    prompt character varying NOT NULL,
    rank integer NOT NULL,
    choices character varying[] NOT NULL,
    created_at timestamp with time zone NOT NULL
);


--
-- Name: tag; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tag (
    id integer NOT NULL,
    tag_name character varying,
    active boolean DEFAULT true NOT NULL,
    public boolean DEFAULT true NOT NULL,
    uuid uuid DEFAULT public.uuid_generate_v4()
);


--
-- Name: tag_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.tag_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tag_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.tag_id_seq OWNED BY public.tag.id;


--
-- Name: task_fail; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.task_fail (
    id integer NOT NULL,
    task_id character varying(250) NOT NULL,
    dag_id character varying(250) NOT NULL,
    start_date timestamp with time zone,
    end_date timestamp with time zone,
    duration integer,
    map_index integer DEFAULT '-1'::integer NOT NULL,
    run_id character varying(250) NOT NULL
);


--
-- Name: task_fail_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.task_fail_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: task_fail_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.task_fail_id_seq OWNED BY public.task_fail.id;


--
-- Name: task_id_sequence; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.task_id_sequence
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: task_instance; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.task_instance (
    task_id character varying(250) NOT NULL,
    dag_id character varying(250) NOT NULL,
    run_id character varying(250) NOT NULL,
    start_date timestamp with time zone,
    end_date timestamp with time zone,
    duration double precision,
    state character varying(20),
    try_number integer,
    hostname character varying(1000),
    unixname character varying(1000),
    job_id integer,
    pool character varying(256) NOT NULL,
    queue character varying(256),
    priority_weight integer,
    operator character varying(1000),
    queued_dttm timestamp with time zone,
    pid integer,
    max_tries integer DEFAULT '-1'::integer,
    executor_config bytea,
    pool_slots integer NOT NULL,
    queued_by_job_id integer,
    external_executor_id character varying(250),
    trigger_id integer,
    trigger_timeout timestamp without time zone,
    next_method character varying(1000),
    next_kwargs json,
    map_index integer DEFAULT '-1'::integer NOT NULL,
    updated_at timestamp with time zone,
    custom_operator_name character varying(1000)
);


--
-- Name: task_instance_note; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.task_instance_note (
    user_id integer,
    task_id character varying(250) NOT NULL,
    dag_id character varying(250) NOT NULL,
    run_id character varying(250) NOT NULL,
    map_index integer NOT NULL,
    content character varying(1000),
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);


--
-- Name: task_map; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.task_map (
    dag_id character varying(250) NOT NULL,
    task_id character varying(250) NOT NULL,
    run_id character varying(250) NOT NULL,
    map_index integer NOT NULL,
    length integer NOT NULL,
    keys json,
    CONSTRAINT ck_task_map_task_map_length_not_negative CHECK ((length >= 0))
);


--
-- Name: task_outlet_dataset_reference; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.task_outlet_dataset_reference (
    dataset_id integer NOT NULL,
    dag_id character varying(250) NOT NULL,
    task_id character varying(250) NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);


--
-- Name: task_reschedule; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.task_reschedule (
    id integer NOT NULL,
    task_id character varying(250) NOT NULL,
    dag_id character varying(250) NOT NULL,
    try_number integer NOT NULL,
    start_date timestamp with time zone NOT NULL,
    end_date timestamp with time zone NOT NULL,
    duration integer NOT NULL,
    reschedule_date timestamp with time zone NOT NULL,
    run_id character varying(250) NOT NULL,
    map_index integer DEFAULT '-1'::integer NOT NULL
);


--
-- Name: task_reschedule_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.task_reschedule_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: task_reschedule_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.task_reschedule_id_seq OWNED BY public.task_reschedule.id;


--
-- Name: taskset_id_sequence; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.taskset_id_sequence
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: test; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.test (
    column1 public.geometry
);


--
-- Name: token_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.token_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: token_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.token_id_seq OWNED BY public.token.id;


--
-- Name: tokens_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.tokens_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: trading.transaction; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."trading.transaction" (
    id integer NOT NULL,
    token_id integer NOT NULL,
    transfer_id integer NOT NULL,
    source_entity_id integer NOT NULL,
    destination_entity_id integer NOT NULL,
    processed_at timestamp without time zone DEFAULT now() NOT NULL
);


--
-- Name: transaction; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.transaction (
    id integer NOT NULL,
    token_id integer,
    sender_entity_id integer,
    receiver_entity_id integer,
    processed_at timestamp without time zone DEFAULT now() NOT NULL
);


--
-- Name: transaction_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.transaction_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: transaction_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.transaction_id_seq OWNED BY public.transaction.id;


--
-- Name: transfer; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.transfer (
    id integer NOT NULL,
    executing_entity_id integer,
    created_at timestamp without time zone DEFAULT now() NOT NULL
);


--
-- Name: transfer_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.transfer_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: transfer_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.transfer_id_seq OWNED BY public.transfer.id;


--
-- Name: tree_attributes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tree_attributes (
    id integer NOT NULL,
    tree_id integer,
    key character varying,
    value character varying
);


--
-- Name: tree_attributes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.tree_attributes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tree_attributes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.tree_attributes_id_seq OWNED BY public.tree_attributes.id;


--
-- Name: tree_name; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tree_name (
    id integer NOT NULL,
    name character varying,
    used boolean DEFAULT false NOT NULL
);


--
-- Name: tree_name_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.tree_name_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tree_name_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.tree_name_id_seq OWNED BY public.tree_name.id;


--
-- Name: tree_region_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.tree_region_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tree_region_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.tree_region_id_seq OWNED BY public.tree_region.id;


--
-- Name: tree_species_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.tree_species_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tree_species; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tree_species (
    id integer DEFAULT nextval('public.tree_species_id_seq'::regclass) NOT NULL,
    name character varying(45) NOT NULL,
    "desc" text NOT NULL,
    active boolean DEFAULT true NOT NULL,
    value_factor integer,
    uuid uuid DEFAULT public.uuid_generate_v4()
);


--
-- Name: tree_tag; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tree_tag (
    id integer NOT NULL,
    tree_id integer,
    tag_id integer
);


--
-- Name: tree_tag_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.tree_tag_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tree_tag_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.tree_tag_id_seq OWNED BY public.tree_tag.id;


--
-- Name: trees_active; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.trees_active AS
 SELECT id,
    time_created,
    time_updated,
    missing,
    priority,
    cause_of_death_id,
    planter_id AS user_id,
    primary_location_id,
    settings_id,
    override_settings_id,
    dead,
    photo_id,
    image_url,
    certificate_id,
    estimated_geometric_location,
    lat,
    lon,
    gps_accuracy,
    active,
    planter_photo_url,
    planter_identifier,
    device_id,
    sequence,
    note,
    verified,
    uuid,
    approved,
    status,
    cluster_regions_assigned
   FROM public.trees
  WHERE (active = true)
  WITH NO DATA;


--
-- Name: trees_new; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.trees_new (
    id integer NOT NULL,
    time_created timestamp without time zone,
    time_updated timestamp without time zone,
    missing boolean,
    priority boolean,
    cause_of_death_id integer,
    planter_id integer,
    primary_location_id integer,
    settings_id integer,
    override_settings_id integer,
    dead integer,
    photo_id integer,
    image_url character varying,
    certificate_id integer,
    estimated_geometric_location public.geometry,
    lat numeric,
    lon numeric,
    gps_accuracy integer,
    active boolean,
    planter_photo_url character varying,
    planter_identifier character varying,
    device_id integer,
    note character varying,
    verified boolean,
    uuid character varying,
    approved boolean,
    status character varying,
    cluster_regions_assigned boolean,
    species_id integer,
    planting_organization_id integer,
    payment_id integer,
    contract_id integer,
    token_issued boolean,
    morphology public.morphology_type,
    age public.age_type,
    species character varying,
    capture_approval_tag public.capture_approval_type,
    rejection_reason public.rejection_reason_type,
    matching_hash character varying,
    device_identifier character varying,
    images jsonb,
    domain_specific_data jsonb,
    token_id uuid,
    name character varying,
    earnings_id uuid,
    session_id uuid,
    image_url_backup text
);


--
-- Name: trees_sbx_prodshape; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.trees_sbx_prodshape (
    id integer NOT NULL,
    time_created timestamp without time zone NOT NULL,
    time_updated timestamp without time zone NOT NULL,
    missing boolean DEFAULT false,
    priority boolean DEFAULT false,
    cause_of_death_id integer,
    planter_id integer,
    primary_location_id integer,
    settings_id integer,
    override_settings_id integer,
    dead integer DEFAULT 0 NOT NULL,
    photo_id integer,
    image_url text,
    certificate_id integer,
    estimated_geometric_location public.geometry(Point,4326),
    lat numeric,
    lon numeric,
    gps_accuracy integer,
    active boolean DEFAULT true,
    planter_photo_url text,
    planter_identifier text,
    device_id integer,
    sequence integer,
    note text,
    verified text DEFAULT false NOT NULL,
    uuid text,
    approved boolean DEFAULT false NOT NULL,
    status text DEFAULT 'planted'::text NOT NULL,
    cluster_regions_assigned boolean DEFAULT false NOT NULL,
    species_id integer,
    planting_organization_id integer,
    payment_id integer,
    contract_id integer,
    token_issued boolean DEFAULT false NOT NULL,
    morphology public.morphology_type,
    age public.age_type,
    species text,
    capture_approval_tag public.capture_approval_type,
    rejection_reason public.rejection_reason_type,
    matching_hash text,
    device_identifier text,
    images jsonb,
    domain_specific_data jsonb,
    image_url_backup text,
    token_id uuid,
    name text,
    earnings_id uuid,
    session_id uuid
);


--
-- Name: trees_sbx_prodshape_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.trees_sbx_prodshape_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: trees_sbx_prodshape_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.trees_sbx_prodshape_id_seq OWNED BY public.trees_sbx_prodshape.id;


--
-- Name: trees_sbx_prodshape_2; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.trees_sbx_prodshape_2 (
    id integer DEFAULT nextval('public.trees_sbx_prodshape_id_seq'::regclass) NOT NULL,
    time_created timestamp without time zone NOT NULL,
    time_updated timestamp without time zone NOT NULL,
    missing boolean DEFAULT false,
    priority boolean DEFAULT false,
    cause_of_death_id integer,
    planter_id integer,
    primary_location_id integer,
    settings_id integer,
    override_settings_id integer,
    dead boolean DEFAULT false NOT NULL,
    photo_id integer,
    image_url text,
    certificate_id integer,
    estimated_geometric_location public.geometry(Point,4326),
    lat numeric,
    lon numeric,
    gps_accuracy integer,
    active boolean DEFAULT true,
    planter_photo_url text,
    planter_identifier text,
    device_id integer,
    sequence integer,
    note text,
    verified text DEFAULT false NOT NULL,
    uuid text,
    approved boolean DEFAULT false NOT NULL,
    status text DEFAULT 'planted'::text NOT NULL,
    cluster_regions_assigned boolean DEFAULT false NOT NULL,
    species_id integer,
    planting_organization_id integer,
    payment_id integer,
    contract_id integer,
    token_issued boolean DEFAULT false NOT NULL,
    morphology public.morphology_type,
    age public.age_type,
    species text,
    capture_approval_tag public.capture_approval_type,
    rejection_reason public.rejection_reason_type,
    matching_hash text,
    device_identifier text,
    images jsonb,
    domain_specific_data jsonb,
    image_url_backup text,
    token_id uuid,
    name text,
    earnings_id uuid,
    session_id uuid
);


--
-- Name: treetracker_capture_backup; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.treetracker_capture_backup (
    id uuid,
    reference_id bigint,
    tree_id uuid,
    image_url character varying,
    lat numeric,
    lon numeric,
    estimated_geometric_location public.geometry(Point,4326),
    gps_accuracy smallint,
    planter_id bigint,
    planter_photo_url character varying,
    planter_username character varying,
    planting_organization_id integer,
    device_identifier character varying,
    species_id integer,
    morphology character varying,
    age smallint,
    note character varying,
    attributes jsonb,
    domain_specific_data jsonb,
    status character varying,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    estimated_geographic_location public.geography(Point,4326)
);


--
-- Name: treetracker_tree_backup; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.treetracker_tree_backup (
    id uuid,
    latest_capture_id uuid,
    image_url character varying,
    lat numeric,
    lon numeric,
    estimated_geometric_location public.geometry(Point,4326),
    gps_accuracy smallint,
    species_id integer,
    morphology character varying,
    age smallint,
    status character varying,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    estimated_geographic_location public.geography(Point,4326)
);


--
-- Name: trigger; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.trigger (
    id integer NOT NULL,
    classpath character varying(1000) NOT NULL,
    kwargs json NOT NULL,
    created_date timestamp with time zone NOT NULL,
    triggerer_id integer
);


--
-- Name: trigger_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.trigger_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: trigger_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.trigger_id_seq OWNED BY public.trigger.id;


--
-- Name: variable; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.variable (
    id integer NOT NULL,
    key character varying(250),
    val text,
    is_encrypted boolean,
    description text
);


--
-- Name: variable_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.variable_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: variable_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.variable_id_seq OWNED BY public.variable.id;


--
-- Name: xcom; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.xcom (
    dag_run_id integer NOT NULL,
    task_id character varying(250) NOT NULL,
    key character varying(512) NOT NULL,
    value bytea,
    "timestamp" timestamp with time zone NOT NULL,
    dag_id character varying(250) NOT NULL,
    run_id character varying(250) NOT NULL,
    map_index integer DEFAULT '-1'::integer NOT NULL
);


--
-- Name: domain_event_handled; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.domain_event ATTACH PARTITION public.domain_event_handled FOR VALUES IN ('handled');


--
-- Name: domain_event_handled_2021; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.domain_event_handled ATTACH PARTITION public.domain_event_handled_2021 FOR VALUES FROM ('2021-01-01 00:00:00+00') TO ('2022-01-01 00:00:00+00');


--
-- Name: domain_event_handled_2022; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.domain_event_handled ATTACH PARTITION public.domain_event_handled_2022 FOR VALUES FROM ('2022-01-01 00:00:00+00') TO ('2023-01-01 00:00:00+00');


--
-- Name: domain_event_handled_2023; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.domain_event_handled ATTACH PARTITION public.domain_event_handled_2023 FOR VALUES FROM ('2023-01-01 00:00:00+00') TO ('2024-01-01 00:00:00+00');


--
-- Name: domain_event_raised; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.domain_event ATTACH PARTITION public.domain_event_raised FOR VALUES IN ('raised');


--
-- Name: domain_event_received; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.domain_event ATTACH PARTITION public.domain_event_received FOR VALUES IN ('received');


--
-- Name: domain_event_sent; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.domain_event ATTACH PARTITION public.domain_event_sent FOR VALUES IN ('sent');


--
-- Name: domain_event_sent_2021; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.domain_event_sent ATTACH PARTITION public.domain_event_sent_2021 FOR VALUES FROM ('2021-01-01 00:00:00+00') TO ('2022-01-01 00:00:00+00');


--
-- Name: domain_event_sent_2022; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.domain_event_sent ATTACH PARTITION public.domain_event_sent_2022 FOR VALUES FROM ('2022-01-01 00:00:00+00') TO ('2023-01-01 00:00:00+00');


--
-- Name: domain_event_sent_2023; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.domain_event_sent ATTACH PARTITION public.domain_event_sent_2023 FOR VALUES FROM ('2023-01-01 00:00:00+00') TO ('2024-01-01 00:00:00+00');


--
-- Name: ab_permission id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ab_permission ALTER COLUMN id SET DEFAULT nextval('public.ab_permission_id_seq'::regclass);


--
-- Name: ab_permission_view id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ab_permission_view ALTER COLUMN id SET DEFAULT nextval('public.ab_permission_view_id_seq'::regclass);


--
-- Name: ab_permission_view_role id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ab_permission_view_role ALTER COLUMN id SET DEFAULT nextval('public.ab_permission_view_role_id_seq'::regclass);


--
-- Name: ab_register_user id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ab_register_user ALTER COLUMN id SET DEFAULT nextval('public.ab_register_user_id_seq'::regclass);


--
-- Name: ab_role id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ab_role ALTER COLUMN id SET DEFAULT nextval('public.ab_role_id_seq'::regclass);


--
-- Name: ab_user id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ab_user ALTER COLUMN id SET DEFAULT nextval('public.ab_user_id_seq'::regclass);


--
-- Name: ab_user_role id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ab_user_role ALTER COLUMN id SET DEFAULT nextval('public.ab_user_role_id_seq'::regclass);


--
-- Name: ab_view_menu id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ab_view_menu ALTER COLUMN id SET DEFAULT nextval('public.ab_view_menu_id_seq'::regclass);


--
-- Name: admin_role id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admin_role ALTER COLUMN id SET DEFAULT nextval('public.admin_role_id_seq'::regclass);


--
-- Name: admin_user id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admin_user ALTER COLUMN id SET DEFAULT nextval('public.admin_user_id_seq'::regclass);


--
-- Name: admin_user_role id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admin_user_role ALTER COLUMN id SET DEFAULT nextval('public.admin_user_role_id_seq'::regclass);


--
-- Name: api_key id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_key ALTER COLUMN id SET DEFAULT nextval('public.api_key_id_seq'::regclass);


--
-- Name: audit id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit ALTER COLUMN id SET DEFAULT nextval('public.audit_id_seq'::regclass);


--
-- Name: callback_request id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.callback_request ALTER COLUMN id SET DEFAULT nextval('public.callback_request_id_seq'::regclass);


--
-- Name: certificates id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.certificates ALTER COLUMN id SET DEFAULT nextval('public.certificates_id_seq'::regclass);


--
-- Name: clusters id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.clusters ALTER COLUMN id SET DEFAULT nextval('public.clusters_id_seq'::regclass);


--
-- Name: connection id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.connection ALTER COLUMN id SET DEFAULT nextval('public.connection_id_seq'::regclass);


--
-- Name: contract id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract ALTER COLUMN id SET DEFAULT nextval('public.contract_id_seq'::regclass);


--
-- Name: dag_pickle id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dag_pickle ALTER COLUMN id SET DEFAULT nextval('public.dag_pickle_id_seq'::regclass);


--
-- Name: dag_run id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dag_run ALTER COLUMN id SET DEFAULT nextval('public.dag_run_id_seq'::regclass);


--
-- Name: dataset id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dataset ALTER COLUMN id SET DEFAULT nextval('public.dataset_id_seq'::regclass);


--
-- Name: dataset_event id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dataset_event ALTER COLUMN id SET DEFAULT nextval('public.dataset_event_id_seq'::regclass);


--
-- Name: devices id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.devices ALTER COLUMN id SET DEFAULT nextval('public.devices_id_seq'::regclass);


--
-- Name: donors id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.donors ALTER COLUMN id SET DEFAULT nextval('public.donors_id_seq'::regclass);


--
-- Name: dylan_denormalization_test id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dylan_denormalization_test ALTER COLUMN id SET DEFAULT nextval('public.dylan_denormalization_test_id_seq'::regclass);


--
-- Name: entity id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entity ALTER COLUMN id SET DEFAULT nextval('public.entity_id_seq'::regclass);


--
-- Name: entity_manager id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entity_manager ALTER COLUMN id SET DEFAULT nextval('public.entity_manager_id_seq'::regclass);


--
-- Name: entity_relationship id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entity_relationship ALTER COLUMN id SET DEFAULT nextval('public.entity_relationship_id_seq'::regclass);


--
-- Name: entity_role id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entity_role ALTER COLUMN id SET DEFAULT nextval('public.entity_role_id_seq'::regclass);


--
-- Name: grower_note id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grower_note ALTER COLUMN id SET DEFAULT nextval('public.grower_note_id_seq'::regclass);


--
-- Name: import_error id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_error ALTER COLUMN id SET DEFAULT nextval('public.import_error_id_seq'::regclass);


--
-- Name: job id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.job ALTER COLUMN id SET DEFAULT nextval('public.job_id_seq'::regclass);


--
-- Name: knex_migrations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.knex_migrations ALTER COLUMN id SET DEFAULT nextval('public.knex_migrations_id_seq'::regclass);


--
-- Name: knex_migrations_lock index; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.knex_migrations_lock ALTER COLUMN index SET DEFAULT nextval('public.knex_migrations_lock_index_seq'::regclass);


--
-- Name: leaf leaf_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leaf ALTER COLUMN leaf_id SET DEFAULT nextval('public.leaf_leaf_id_seq'::regclass);


--
-- Name: leaf_khushi leaf_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leaf_khushi ALTER COLUMN leaf_id SET DEFAULT nextval('public.leaf_khushi_leaf_id_seq'::regclass);


--
-- Name: log id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.log ALTER COLUMN id SET DEFAULT nextval('public.log_id_seq'::regclass);


--
-- Name: log_template id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.log_template ALTER COLUMN id SET DEFAULT nextval('public.log_template_id_seq'::regclass);


--
-- Name: migrations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.migrations ALTER COLUMN id SET DEFAULT nextval('public.migrations_id_seq'::regclass);


--
-- Name: organizations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organizations ALTER COLUMN id SET DEFAULT nextval('public.organizations_id_seq'::regclass);


--
-- Name: payment id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment ALTER COLUMN id SET DEFAULT nextval('public.payment_id_seq'::regclass);


--
-- Name: planter_registrations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.planter_registrations ALTER COLUMN id SET DEFAULT nextval('public.planter_registrations_id_seq'::regclass);


--
-- Name: region id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.region ALTER COLUMN id SET DEFAULT nextval('public.region_id_seq'::regclass);


--
-- Name: region_type id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.region_type ALTER COLUMN id SET DEFAULT nextval('public.region_type_id_seq'::regclass);


--
-- Name: region_zoom id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.region_zoom ALTER COLUMN id SET DEFAULT nextval('public.region_zoom_id_seq'::regclass);


--
-- Name: session id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.session ALTER COLUMN id SET DEFAULT nextval('public.session_id_seq'::regclass);


--
-- Name: slot_pool id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.slot_pool ALTER COLUMN id SET DEFAULT nextval('public.slot_pool_id_seq'::regclass);


--
-- Name: tag id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tag ALTER COLUMN id SET DEFAULT nextval('public.tag_id_seq'::regclass);


--
-- Name: task_fail id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_fail ALTER COLUMN id SET DEFAULT nextval('public.task_fail_id_seq'::regclass);


--
-- Name: task_reschedule id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_reschedule ALTER COLUMN id SET DEFAULT nextval('public.task_reschedule_id_seq'::regclass);


--
-- Name: token id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.token ALTER COLUMN id SET DEFAULT nextval('public.token_id_seq'::regclass);


--
-- Name: transaction id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transaction ALTER COLUMN id SET DEFAULT nextval('public.transaction_id_seq'::regclass);


--
-- Name: transfer id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transfer ALTER COLUMN id SET DEFAULT nextval('public.transfer_id_seq'::regclass);


--
-- Name: tree_attributes id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tree_attributes ALTER COLUMN id SET DEFAULT nextval('public.tree_attributes_id_seq'::regclass);


--
-- Name: tree_name id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tree_name ALTER COLUMN id SET DEFAULT nextval('public.tree_name_id_seq'::regclass);


--
-- Name: tree_region id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tree_region ALTER COLUMN id SET DEFAULT nextval('public.tree_region_id_seq'::regclass);


--
-- Name: tree_tag id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tree_tag ALTER COLUMN id SET DEFAULT nextval('public.tree_tag_id_seq'::regclass);


--
-- Name: trees_sbx_prodshape id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trees_sbx_prodshape ALTER COLUMN id SET DEFAULT nextval('public.trees_sbx_prodshape_id_seq'::regclass);


--
-- Name: trigger id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trigger ALTER COLUMN id SET DEFAULT nextval('public.trigger_id_seq'::regclass);


--
-- Name: variable id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.variable ALTER COLUMN id SET DEFAULT nextval('public.variable_id_seq'::regclass);


--
-- Name: ab_permission ab_permission_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ab_permission
    ADD CONSTRAINT ab_permission_name_key UNIQUE (name);


--
-- Name: ab_permission ab_permission_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ab_permission
    ADD CONSTRAINT ab_permission_pkey PRIMARY KEY (id);


--
-- Name: ab_permission_view ab_permission_view_permission_id_view_menu_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ab_permission_view
    ADD CONSTRAINT ab_permission_view_permission_id_view_menu_id_key UNIQUE (permission_id, view_menu_id);


--
-- Name: ab_permission_view ab_permission_view_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ab_permission_view
    ADD CONSTRAINT ab_permission_view_pkey PRIMARY KEY (id);


--
-- Name: ab_permission_view_role ab_permission_view_role_permission_view_id_role_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ab_permission_view_role
    ADD CONSTRAINT ab_permission_view_role_permission_view_id_role_id_key UNIQUE (permission_view_id, role_id);


--
-- Name: ab_permission_view_role ab_permission_view_role_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ab_permission_view_role
    ADD CONSTRAINT ab_permission_view_role_pkey PRIMARY KEY (id);


--
-- Name: ab_register_user ab_register_user_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ab_register_user
    ADD CONSTRAINT ab_register_user_pkey PRIMARY KEY (id);


--
-- Name: ab_register_user ab_register_user_username_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ab_register_user
    ADD CONSTRAINT ab_register_user_username_key UNIQUE (username);


--
-- Name: ab_role ab_role_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ab_role
    ADD CONSTRAINT ab_role_name_key UNIQUE (name);


--
-- Name: ab_role ab_role_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ab_role
    ADD CONSTRAINT ab_role_pkey PRIMARY KEY (id);


--
-- Name: ab_user ab_user_email_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ab_user
    ADD CONSTRAINT ab_user_email_key UNIQUE (email);


--
-- Name: ab_user ab_user_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ab_user
    ADD CONSTRAINT ab_user_pkey PRIMARY KEY (id);


--
-- Name: ab_user_role ab_user_role_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ab_user_role
    ADD CONSTRAINT ab_user_role_pkey PRIMARY KEY (id);


--
-- Name: ab_user_role ab_user_role_user_id_role_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ab_user_role
    ADD CONSTRAINT ab_user_role_user_id_role_id_key UNIQUE (user_id, role_id);


--
-- Name: ab_user ab_user_username_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ab_user
    ADD CONSTRAINT ab_user_username_key UNIQUE (username);


--
-- Name: ab_view_menu ab_view_menu_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ab_view_menu
    ADD CONSTRAINT ab_view_menu_name_key UNIQUE (name);


--
-- Name: ab_view_menu ab_view_menu_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ab_view_menu
    ADD CONSTRAINT ab_view_menu_pkey PRIMARY KEY (id);


--
-- Name: admin_role admin_role_identifier_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admin_role
    ADD CONSTRAINT admin_role_identifier_key UNIQUE (identifier);


--
-- Name: admin_role admin_role_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admin_role
    ADD CONSTRAINT admin_role_pkey PRIMARY KEY (id);


--
-- Name: admin_user admin_user_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admin_user
    ADD CONSTRAINT admin_user_pkey PRIMARY KEY (id);


--
-- Name: admin_user_role admin_user_role_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admin_user_role
    ADD CONSTRAINT admin_user_role_pkey PRIMARY KEY (id);


--
-- Name: admin_user_role admin_user_role_un; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admin_user_role
    ADD CONSTRAINT admin_user_role_un UNIQUE (role_id, admin_user_id);


--
-- Name: alembic_version alembic_version_pkc; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alembic_version
    ADD CONSTRAINT alembic_version_pkc PRIMARY KEY (version_num);


--
-- Name: api_key api_key_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_key
    ADD CONSTRAINT api_key_pkey PRIMARY KEY (id);


--
-- Name: audit audit_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit
    ADD CONSTRAINT audit_pkey PRIMARY KEY (id);


--
-- Name: callback_request callback_request_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.callback_request
    ADD CONSTRAINT callback_request_pkey PRIMARY KEY (id);


--
-- Name: celery_taskmeta celery_taskmeta_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.celery_taskmeta
    ADD CONSTRAINT celery_taskmeta_pkey PRIMARY KEY (id);


--
-- Name: celery_taskmeta celery_taskmeta_task_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.celery_taskmeta
    ADD CONSTRAINT celery_taskmeta_task_id_key UNIQUE (task_id);


--
-- Name: celery_tasksetmeta celery_tasksetmeta_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.celery_tasksetmeta
    ADD CONSTRAINT celery_tasksetmeta_pkey PRIMARY KEY (id);


--
-- Name: celery_tasksetmeta celery_tasksetmeta_taskset_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.celery_tasksetmeta
    ADD CONSTRAINT celery_tasksetmeta_taskset_id_key UNIQUE (taskset_id);


--
-- Name: certificates certificates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.certificates
    ADD CONSTRAINT certificates_pkey PRIMARY KEY (id);


--
-- Name: clusters clusters_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.clusters
    ADD CONSTRAINT clusters_pkey PRIMARY KEY (id);


--
-- Name: connection connection_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.connection
    ADD CONSTRAINT connection_pkey PRIMARY KEY (id);


--
-- Name: contract contract_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract
    ADD CONSTRAINT contract_pkey PRIMARY KEY (id);


--
-- Name: dag_code dag_code_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dag_code
    ADD CONSTRAINT dag_code_pkey PRIMARY KEY (fileloc_hash);


--
-- Name: dag_owner_attributes dag_owner_attributes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dag_owner_attributes
    ADD CONSTRAINT dag_owner_attributes_pkey PRIMARY KEY (dag_id, owner);


--
-- Name: dag_pickle dag_pickle_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dag_pickle
    ADD CONSTRAINT dag_pickle_pkey PRIMARY KEY (id);


--
-- Name: dag dag_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dag
    ADD CONSTRAINT dag_pkey PRIMARY KEY (dag_id);


--
-- Name: dag_run dag_run_dag_id_execution_date_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dag_run
    ADD CONSTRAINT dag_run_dag_id_execution_date_key UNIQUE (dag_id, execution_date);


--
-- Name: dag_run dag_run_dag_id_run_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dag_run
    ADD CONSTRAINT dag_run_dag_id_run_id_key UNIQUE (dag_id, run_id);


--
-- Name: dag_run_note dag_run_note_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dag_run_note
    ADD CONSTRAINT dag_run_note_pkey PRIMARY KEY (dag_run_id);


--
-- Name: dag_run dag_run_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dag_run
    ADD CONSTRAINT dag_run_pkey PRIMARY KEY (id);


--
-- Name: dag_schedule_dataset_reference dag_schedule_dataset_reference_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dag_schedule_dataset_reference
    ADD CONSTRAINT dag_schedule_dataset_reference_pkey PRIMARY KEY (dataset_id, dag_id);


--
-- Name: dag_tag dag_tag_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dag_tag
    ADD CONSTRAINT dag_tag_pkey PRIMARY KEY (name, dag_id);


--
-- Name: dag_warning dag_warning_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dag_warning
    ADD CONSTRAINT dag_warning_pkey PRIMARY KEY (dag_id, warning_type);


--
-- Name: dagrun_dataset_event dagrun_dataset_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dagrun_dataset_event
    ADD CONSTRAINT dagrun_dataset_events_pkey PRIMARY KEY (dag_run_id, event_id);


--
-- Name: dataset_dag_run_queue dataset_dag_run_queue_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dataset_dag_run_queue
    ADD CONSTRAINT dataset_dag_run_queue_pkey PRIMARY KEY (dataset_id, target_dag_id);


--
-- Name: dataset_event dataset_event_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dataset_event
    ADD CONSTRAINT dataset_event_pkey PRIMARY KEY (id);


--
-- Name: dataset dataset_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dataset
    ADD CONSTRAINT dataset_pkey PRIMARY KEY (id);


--
-- Name: denormalized_trees denormalized_trees_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.denormalized_trees
    ADD CONSTRAINT denormalized_trees_pkey PRIMARY KEY (id);


--
-- Name: devices devices_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.devices
    ADD CONSTRAINT devices_pkey PRIMARY KEY (id);


--
-- Name: domain_event domain_event_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.domain_event
    ADD CONSTRAINT domain_event_pkey PRIMARY KEY (id, status, created_at);


--
-- Name: domain_event_handled domain_event_handled_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.domain_event_handled
    ADD CONSTRAINT domain_event_handled_pkey PRIMARY KEY (id, status, created_at);


--
-- Name: domain_event_handled_2021 domain_event_handled_2021_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.domain_event_handled_2021
    ADD CONSTRAINT domain_event_handled_2021_pkey PRIMARY KEY (id, status, created_at);


--
-- Name: domain_event_handled_2022 domain_event_handled_2022_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.domain_event_handled_2022
    ADD CONSTRAINT domain_event_handled_2022_pkey PRIMARY KEY (id, status, created_at);


--
-- Name: domain_event_handled_2023 domain_event_handled_2023_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.domain_event_handled_2023
    ADD CONSTRAINT domain_event_handled_2023_pkey PRIMARY KEY (id, status, created_at);


--
-- Name: domain_event_raised domain_event_raised_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.domain_event_raised
    ADD CONSTRAINT domain_event_raised_pkey PRIMARY KEY (id, status, created_at);


--
-- Name: domain_event_received domain_event_received_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.domain_event_received
    ADD CONSTRAINT domain_event_received_pkey PRIMARY KEY (id, status, created_at);


--
-- Name: domain_event_sent domain_event_sent_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.domain_event_sent
    ADD CONSTRAINT domain_event_sent_pkey PRIMARY KEY (id, status, created_at);


--
-- Name: domain_event_sent_2021 domain_event_sent_2021_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.domain_event_sent_2021
    ADD CONSTRAINT domain_event_sent_2021_pkey PRIMARY KEY (id, status, created_at);


--
-- Name: domain_event_sent_2022 domain_event_sent_2022_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.domain_event_sent_2022
    ADD CONSTRAINT domain_event_sent_2022_pkey PRIMARY KEY (id, status, created_at);


--
-- Name: domain_event_sent_2023 domain_event_sent_2023_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.domain_event_sent_2023
    ADD CONSTRAINT domain_event_sent_2023_pkey PRIMARY KEY (id, status, created_at);


--
-- Name: donors donors_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.donors
    ADD CONSTRAINT donors_pkey PRIMARY KEY (id);


--
-- Name: dylan_denormalization_test dylan_denormalization_test_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dylan_denormalization_test
    ADD CONSTRAINT dylan_denormalization_test_pkey PRIMARY KEY (id);


--
-- Name: entity_manager entity_manager_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entity_manager
    ADD CONSTRAINT entity_manager_pkey PRIMARY KEY (id);


--
-- Name: entity entity_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entity
    ADD CONSTRAINT entity_pkey PRIMARY KEY (id);


--
-- Name: entity_relationship entity_relationship_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entity_relationship
    ADD CONSTRAINT entity_relationship_pkey PRIMARY KEY (id);


--
-- Name: entity_role entity_role_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entity_role
    ADD CONSTRAINT entity_role_pkey PRIMARY KEY (id);


--
-- Name: grower_note grower_note_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grower_note
    ADD CONSTRAINT grower_note_pkey PRIMARY KEY (id);


--
-- Name: import_error import_error_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_error
    ADD CONSTRAINT import_error_pkey PRIMARY KEY (id);


--
-- Name: job job_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.job
    ADD CONSTRAINT job_pkey PRIMARY KEY (id);


--
-- Name: knex_migrations_lock knex_migrations_lock_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.knex_migrations_lock
    ADD CONSTRAINT knex_migrations_lock_pkey PRIMARY KEY (index);


--
-- Name: knex_migrations knex_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.knex_migrations
    ADD CONSTRAINT knex_migrations_pkey PRIMARY KEY (id);


--
-- Name: leaf_khushi leaf_khushi_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leaf_khushi
    ADD CONSTRAINT leaf_khushi_pkey PRIMARY KEY (leaf_id);


--
-- Name: leaf leaf_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leaf
    ADD CONSTRAINT leaf_pkey PRIMARY KEY (leaf_id);


--
-- Name: locations locations_id_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.locations
    ADD CONSTRAINT locations_id_pkey PRIMARY KEY (id);


--
-- Name: log log_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.log
    ADD CONSTRAINT log_pkey PRIMARY KEY (id);


--
-- Name: log_template log_template_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.log_template
    ADD CONSTRAINT log_template_pkey PRIMARY KEY (id);


--
-- Name: migrations migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.migrations
    ADD CONSTRAINT migrations_pkey PRIMARY KEY (id);


--
-- Name: migrations_state migrations_state_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.migrations_state
    ADD CONSTRAINT migrations_state_pkey PRIMARY KEY (key);


--
-- Name: notes notes_id_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notes
    ADD CONSTRAINT notes_id_pkey PRIMARY KEY (id);


--
-- Name: organizations organizations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organizations
    ADD CONSTRAINT organizations_pkey PRIMARY KEY (id);


--
-- Name: payment payment_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment
    ADD CONSTRAINT payment_pkey PRIMARY KEY (id);


--
-- Name: pending_update pending_update_id_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pending_update
    ADD CONSTRAINT pending_update_id_pkey PRIMARY KEY (id);


--
-- Name: photos photos_id_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.photos
    ADD CONSTRAINT photos_id_pkey PRIMARY KEY (id);


--
-- Name: planter planter_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.planter
    ADD CONSTRAINT planter_id_key PRIMARY KEY (id);


--
-- Name: planter_registrations planter_registrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.planter_registrations
    ADD CONSTRAINT planter_registrations_pkey PRIMARY KEY (id);


--
-- Name: region region_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.region
    ADD CONSTRAINT region_pkey PRIMARY KEY (id);


--
-- Name: region_type region_type_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.region_type
    ADD CONSTRAINT region_type_pkey PRIMARY KEY (id);


--
-- Name: rendered_task_instance_fields rendered_task_instance_fields_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rendered_task_instance_fields
    ADD CONSTRAINT rendered_task_instance_fields_pkey PRIMARY KEY (dag_id, task_id, run_id, map_index);


--
-- Name: serialized_dag serialized_dag_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.serialized_dag
    ADD CONSTRAINT serialized_dag_pkey PRIMARY KEY (dag_id);


--
-- Name: session session_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.session
    ADD CONSTRAINT session_pkey PRIMARY KEY (id);


--
-- Name: session session_session_id_uq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.session
    ADD CONSTRAINT session_session_id_uq UNIQUE (session_id);


--
-- Name: sla_miss sla_miss_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sla_miss
    ADD CONSTRAINT sla_miss_pkey PRIMARY KEY (task_id, dag_id, execution_date);


--
-- Name: slot_pool slot_pool_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.slot_pool
    ADD CONSTRAINT slot_pool_pkey PRIMARY KEY (id);


--
-- Name: slot_pool slot_pool_pool_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.slot_pool
    ADD CONSTRAINT slot_pool_pool_key UNIQUE (pool);


--
-- Name: stakeholder_relation stakeholder_relation_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stakeholder_relation
    ADD CONSTRAINT stakeholder_relation_pkey PRIMARY KEY (parent_id, child_id);


--
-- Name: survey survey_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.survey
    ADD CONSTRAINT survey_pkey PRIMARY KEY (id);


--
-- Name: survey_question survey_question_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.survey_question
    ADD CONSTRAINT survey_question_pkey PRIMARY KEY (id);


--
-- Name: tag tag_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tag
    ADD CONSTRAINT tag_pkey PRIMARY KEY (id);


--
-- Name: task_fail task_fail_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_fail
    ADD CONSTRAINT task_fail_pkey PRIMARY KEY (id);


--
-- Name: task_instance_note task_instance_note_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_instance_note
    ADD CONSTRAINT task_instance_note_pkey PRIMARY KEY (task_id, dag_id, run_id, map_index);


--
-- Name: task_instance task_instance_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_instance
    ADD CONSTRAINT task_instance_pkey PRIMARY KEY (dag_id, task_id, run_id, map_index);


--
-- Name: task_map task_map_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_map
    ADD CONSTRAINT task_map_pkey PRIMARY KEY (dag_id, task_id, run_id, map_index);


--
-- Name: task_outlet_dataset_reference task_outlet_dataset_reference_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_outlet_dataset_reference
    ADD CONSTRAINT task_outlet_dataset_reference_pkey PRIMARY KEY (dataset_id, dag_id, task_id);


--
-- Name: task_reschedule task_reschedule_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_reschedule
    ADD CONSTRAINT task_reschedule_pkey PRIMARY KEY (id);


--
-- Name: token token_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.token
    ADD CONSTRAINT token_pkey PRIMARY KEY (id);


--
-- Name: trading.transaction trading.transaction_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."trading.transaction"
    ADD CONSTRAINT "trading.transaction_pkey" PRIMARY KEY (id);


--
-- Name: transaction transaction_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transaction
    ADD CONSTRAINT transaction_pkey PRIMARY KEY (id);


--
-- Name: transfer transfer_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transfer
    ADD CONSTRAINT transfer_pkey PRIMARY KEY (id);


--
-- Name: trees tree_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trees
    ADD CONSTRAINT tree_id_key PRIMARY KEY (id);


--
-- Name: tree_name tree_name_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tree_name
    ADD CONSTRAINT tree_name_pkey PRIMARY KEY (id);


--
-- Name: trees_new tree_new_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trees_new
    ADD CONSTRAINT tree_new_id_key PRIMARY KEY (id);


--
-- Name: tree_species tree_species_pk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tree_species
    ADD CONSTRAINT tree_species_pk PRIMARY KEY (id);


--
-- Name: tree_tag tree_tag_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tree_tag
    ADD CONSTRAINT tree_tag_pkey PRIMARY KEY (id);


--
-- Name: trigger trigger_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trigger
    ADD CONSTRAINT trigger_pkey PRIMARY KEY (id);


--
-- Name: connection unique_conn_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.connection
    ADD CONSTRAINT unique_conn_id UNIQUE (conn_id);


--
-- Name: variable variable_key_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.variable
    ADD CONSTRAINT variable_key_key UNIQUE (key);


--
-- Name: variable variable_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.variable
    ADD CONSTRAINT variable_pkey PRIMARY KEY (id);


--
-- Name: xcom xcom_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.xcom
    ADD CONSTRAINT xcom_pkey PRIMARY KEY (dag_run_id, task_id, map_index, key);


--
-- Name: active_tree_region_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX active_tree_region_id_idx ON public.active_tree_region USING btree (id);


--
-- Name: active_tree_region_region_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX active_tree_region_region_id_idx ON public.active_tree_region USING btree (region_id);


--
-- Name: active_tree_region_zoom_level_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX active_tree_region_zoom_level_idx ON public.active_tree_region USING btree (zoom_level);


--
-- Name: dag_id_state; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX dag_id_state ON public.dag_run USING btree (dag_id, state);


--
-- Name: devices_android_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX devices_android_id_idx ON public.devices USING btree (android_id);


--
-- Name: event_pyld_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX event_pyld_idx ON ONLY public.domain_event USING gin (payload jsonb_path_ops);


--
-- Name: domain_event_handled_payload_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX domain_event_handled_payload_idx ON ONLY public.domain_event_handled USING gin (payload jsonb_path_ops);


--
-- Name: domain_event_handled_2021_payload_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX domain_event_handled_2021_payload_idx ON public.domain_event_handled_2021 USING gin (payload jsonb_path_ops);


--
-- Name: event_status_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX event_status_idx ON ONLY public.domain_event USING btree (status);


--
-- Name: domain_event_handled_status_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX domain_event_handled_status_idx ON ONLY public.domain_event_handled USING btree (status);


--
-- Name: domain_event_handled_2021_status_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX domain_event_handled_2021_status_idx ON public.domain_event_handled_2021 USING btree (status);


--
-- Name: domain_event_handled_2022_payload_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX domain_event_handled_2022_payload_idx ON public.domain_event_handled_2022 USING gin (payload jsonb_path_ops);


--
-- Name: domain_event_handled_2022_status_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX domain_event_handled_2022_status_idx ON public.domain_event_handled_2022 USING btree (status);


--
-- Name: domain_event_handled_2023_payload_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX domain_event_handled_2023_payload_idx ON public.domain_event_handled_2023 USING gin (payload jsonb_path_ops);


--
-- Name: domain_event_handled_2023_status_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX domain_event_handled_2023_status_idx ON public.domain_event_handled_2023 USING btree (status);


--
-- Name: domain_event_raised_payload_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX domain_event_raised_payload_idx ON public.domain_event_raised USING gin (payload jsonb_path_ops);


--
-- Name: domain_event_raised_status_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX domain_event_raised_status_idx ON public.domain_event_raised USING btree (status);


--
-- Name: domain_event_received_payload_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX domain_event_received_payload_idx ON public.domain_event_received USING gin (payload jsonb_path_ops);


--
-- Name: domain_event_received_status_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX domain_event_received_status_idx ON public.domain_event_received USING btree (status);


--
-- Name: domain_event_sent_payload_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX domain_event_sent_payload_idx ON ONLY public.domain_event_sent USING gin (payload jsonb_path_ops);


--
-- Name: domain_event_sent_2021_payload_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX domain_event_sent_2021_payload_idx ON public.domain_event_sent_2021 USING gin (payload jsonb_path_ops);


--
-- Name: domain_event_sent_status_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX domain_event_sent_status_idx ON ONLY public.domain_event_sent USING btree (status);


--
-- Name: domain_event_sent_2021_status_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX domain_event_sent_2021_status_idx ON public.domain_event_sent_2021 USING btree (status);


--
-- Name: domain_event_sent_2022_payload_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX domain_event_sent_2022_payload_idx ON public.domain_event_sent_2022 USING gin (payload jsonb_path_ops);


--
-- Name: domain_event_sent_2022_status_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX domain_event_sent_2022_status_idx ON public.domain_event_sent_2022 USING btree (status);


--
-- Name: domain_event_sent_2023_payload_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX domain_event_sent_2023_payload_idx ON public.domain_event_sent_2023 USING gin (payload jsonb_path_ops);


--
-- Name: domain_event_sent_2023_status_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX domain_event_sent_2023_status_idx ON public.domain_event_sent_2023 USING btree (status);


--
-- Name: entity_new_pkey; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX entity_new_pkey ON public.entity_new USING btree (id);


--
-- Name: entity_new_wallet_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX entity_new_wallet_idx ON public.entity_new USING btree (wallet);


--
-- Name: entity_wallet_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX entity_wallet_idx ON public.entity USING btree (wallet);


--
-- Name: estimated_geometric_location_ind_gist; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX estimated_geometric_location_ind_gist ON public.trees USING gist (estimated_geometric_location);

ALTER TABLE public.trees CLUSTER ON estimated_geometric_location_ind_gist;


--
-- Name: idx_ab_register_user_username; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_ab_register_user_username ON public.ab_register_user USING btree (lower((username)::text));


--
-- Name: idx_ab_user_username; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_ab_user_username ON public.ab_user USING btree (lower((username)::text));


--
-- Name: idx_dag_run_dag_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_dag_run_dag_id ON public.dag_run USING btree (dag_id);


--
-- Name: idx_dag_run_queued_dags; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_dag_run_queued_dags ON public.dag_run USING btree (state, dag_id) WHERE ((state)::text = 'queued'::text);


--
-- Name: idx_dag_run_running_dags; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_dag_run_running_dags ON public.dag_run USING btree (state, dag_id) WHERE ((state)::text = 'running'::text);


--
-- Name: idx_dagrun_dataset_events_dag_run_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_dagrun_dataset_events_dag_run_id ON public.dagrun_dataset_event USING btree (dag_run_id);


--
-- Name: idx_dagrun_dataset_events_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_dagrun_dataset_events_event_id ON public.dagrun_dataset_event USING btree (event_id);


--
-- Name: idx_dataset_id_timestamp; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_dataset_id_timestamp ON public.dataset_event USING btree (dataset_id, "timestamp");


--
-- Name: idx_fileloc_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_fileloc_hash ON public.serialized_dag USING btree (fileloc_hash);


--
-- Name: idx_job_dag_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_job_dag_id ON public.job USING btree (dag_id);


--
-- Name: idx_job_state_heartbeat; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_job_state_heartbeat ON public.job USING btree (state, latest_heartbeat);


--
-- Name: idx_last_scheduling_decision; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_last_scheduling_decision ON public.dag_run USING btree (last_scheduling_decision);


--
-- Name: idx_log_dag; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_log_dag ON public.log USING btree (dag_id);


--
-- Name: idx_log_dttm; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_log_dttm ON public.log USING btree (dttm);


--
-- Name: idx_log_event; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_log_event ON public.log USING btree (event);


--
-- Name: idx_next_dagrun_create_after; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_next_dagrun_create_after ON public.dag USING btree (next_dagrun_create_after);


--
-- Name: idx_root_dag_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_root_dag_id ON public.dag USING btree (root_dag_id);


--
-- Name: idx_task_fail_task_instance; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_task_fail_task_instance ON public.task_fail USING btree (dag_id, task_id, run_id, map_index);


--
-- Name: idx_task_reschedule_dag_run; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_task_reschedule_dag_run ON public.task_reschedule USING btree (dag_id, run_id);


--
-- Name: idx_task_reschedule_dag_task_run; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_task_reschedule_dag_task_run ON public.task_reschedule USING btree (dag_id, task_id, run_id, map_index);


--
-- Name: idx_trees_active_true_species; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_trees_active_true_species ON public.trees_sbx_prodshape USING btree (species_id) WHERE ((active = true) AND (species_id IS NOT NULL));


--
-- Name: idx_uri_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_uri_unique ON public.dataset USING btree (uri);


--
-- Name: idx_xcom_key; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_xcom_key ON public.xcom USING btree (key);


--
-- Name: idx_xcom_task_instance; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_xcom_task_instance ON public.xcom USING btree (dag_id, task_id, run_id, map_index);


--
-- Name: ix_anonymous_entities_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_anonymous_entities_index ON public.anonymous_entities USING btree (index);


--
-- Name: ix_anonymous_planters_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_anonymous_planters_index ON public.anonymous_planters USING btree (index);


--
-- Name: ix_anonymous_trees_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_anonymous_trees_index ON public.anonymous_trees USING btree (index);


--
-- Name: ix_entities_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_entities_index ON public.entities USING btree (index);


--
-- Name: ix_planters_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_planters_index ON public.planters USING btree (index);


--
-- Name: job_type_heart; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX job_type_heart ON public.job USING btree (job_type, latest_heartbeat);


--
-- Name: payment_receiver_entity_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX payment_receiver_entity_id_idx ON public.payment USING btree (receiver_entity_id);


--
-- Name: payment_sender_entity_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX payment_sender_entity_id_idx ON public.payment USING btree (sender_entity_id);


--
-- Name: planter_new_id_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX planter_new_id_key ON public.planter_new USING btree (id);


--
-- Name: region_gemo_index_gist; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX region_gemo_index_gist ON public.region USING gist (geom);

ALTER TABLE public.region CLUSTER ON region_gemo_index_gist;


--
-- Name: region_zoom_region_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX region_zoom_region_id_idx ON public.region_zoom USING btree (region_id);


--
-- Name: sm_dag; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sm_dag ON public.sla_miss USING btree (dag_id);


--
-- Name: ti_dag_run; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ti_dag_run ON public.task_instance USING btree (dag_id, run_id);


--
-- Name: ti_dag_state; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ti_dag_state ON public.task_instance USING btree (dag_id, state);


--
-- Name: ti_job_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ti_job_id ON public.task_instance USING btree (job_id);


--
-- Name: ti_pool; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ti_pool ON public.task_instance USING btree (pool, state, priority_weight);


--
-- Name: ti_state; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ti_state ON public.task_instance USING btree (state);


--
-- Name: ti_state_incl_start_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ti_state_incl_start_date ON public.task_instance USING btree (dag_id, task_id, state) INCLUDE (start_date);


--
-- Name: ti_state_lkp; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ti_state_lkp ON public.task_instance USING btree (dag_id, task_id, run_id, state);


--
-- Name: ti_trigger_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ti_trigger_id ON public.task_instance USING btree (trigger_id);


--
-- Name: token_entity_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX token_entity_id_idx ON public.token USING btree (entity_id);


--
-- Name: token_trees_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX token_trees_id_idx ON public.token USING btree (tree_id);


--
-- Name: transaction_receiver_entity_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX transaction_receiver_entity_id_idx ON public.transaction USING btree (receiver_entity_id);


--
-- Name: transaction_sender_entity_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX transaction_sender_entity_id_idx ON public.transaction USING btree (sender_entity_id);


--
-- Name: tree_name_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX tree_name_name_idx ON public.tree_name USING btree (name);


--
-- Name: trees_active_approved_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX trees_active_approved_idx ON public.trees USING btree (active, approved);


--
-- Name: trees_active_by_time_created_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX trees_active_by_time_created_idx ON public.trees USING btree (active, time_created);


--
-- Name: trees_active_species_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX trees_active_species_id_idx ON public.trees USING btree (active, species_id);


--
-- Name: trees_approved_by_time_created_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX trees_approved_by_time_created_idx ON public.trees USING btree (approved, time_created);


--
-- Name: trees_approved_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX trees_approved_idx ON public.trees USING btree (approved);


--
-- Name: trees_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX trees_name_idx ON public.trees USING btree (name);


--
-- Name: trees_payment_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX trees_payment_id_idx ON public.trees USING btree (payment_id);


--
-- Name: trees_planter_id_by_time_created_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX trees_planter_id_by_time_created_idx ON public.trees USING btree (planter_id, time_created);


--
-- Name: trees_planter_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX trees_planter_id_idx ON public.trees USING btree (planter_id);


--
-- Name: trees_planting_organization_id_by_time_created_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX trees_planting_organization_id_by_time_created_idx ON public.trees USING btree (planting_organization_id, time_created);


--
-- Name: trees_planting_organization_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX trees_planting_organization_id_idx ON public.trees USING btree (planting_organization_id);


--
-- Name: trees_species_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX trees_species_id_idx ON public.trees USING btree (species_id);


--
-- Name: trees_token_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX trees_token_id_idx ON public.trees USING btree (token_id);


--
-- Name: trees_uuid_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX trees_uuid_idx ON public.trees USING btree (uuid);


--
-- Name: trees_verify_query_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX trees_verify_query_idx ON public.trees USING btree (planter_id, approved, time_created);


--
-- Name: domain_event_handled_2021_payload_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.domain_event_handled_payload_idx ATTACH PARTITION public.domain_event_handled_2021_payload_idx;


--
-- Name: domain_event_handled_2021_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.domain_event_handled_pkey ATTACH PARTITION public.domain_event_handled_2021_pkey;


--
-- Name: domain_event_handled_2021_status_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.domain_event_handled_status_idx ATTACH PARTITION public.domain_event_handled_2021_status_idx;


--
-- Name: domain_event_handled_2022_payload_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.domain_event_handled_payload_idx ATTACH PARTITION public.domain_event_handled_2022_payload_idx;


--
-- Name: domain_event_handled_2022_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.domain_event_handled_pkey ATTACH PARTITION public.domain_event_handled_2022_pkey;


--
-- Name: domain_event_handled_2022_status_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.domain_event_handled_status_idx ATTACH PARTITION public.domain_event_handled_2022_status_idx;


--
-- Name: domain_event_handled_2023_payload_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.domain_event_handled_payload_idx ATTACH PARTITION public.domain_event_handled_2023_payload_idx;


--
-- Name: domain_event_handled_2023_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.domain_event_handled_pkey ATTACH PARTITION public.domain_event_handled_2023_pkey;


--
-- Name: domain_event_handled_2023_status_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.domain_event_handled_status_idx ATTACH PARTITION public.domain_event_handled_2023_status_idx;


--
-- Name: domain_event_handled_payload_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.event_pyld_idx ATTACH PARTITION public.domain_event_handled_payload_idx;


--
-- Name: domain_event_handled_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.domain_event_pkey ATTACH PARTITION public.domain_event_handled_pkey;


--
-- Name: domain_event_handled_status_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.event_status_idx ATTACH PARTITION public.domain_event_handled_status_idx;


--
-- Name: domain_event_raised_payload_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.event_pyld_idx ATTACH PARTITION public.domain_event_raised_payload_idx;


--
-- Name: domain_event_raised_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.domain_event_pkey ATTACH PARTITION public.domain_event_raised_pkey;


--
-- Name: domain_event_raised_status_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.event_status_idx ATTACH PARTITION public.domain_event_raised_status_idx;


--
-- Name: domain_event_received_payload_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.event_pyld_idx ATTACH PARTITION public.domain_event_received_payload_idx;


--
-- Name: domain_event_received_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.domain_event_pkey ATTACH PARTITION public.domain_event_received_pkey;


--
-- Name: domain_event_received_status_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.event_status_idx ATTACH PARTITION public.domain_event_received_status_idx;


--
-- Name: domain_event_sent_2021_payload_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.domain_event_sent_payload_idx ATTACH PARTITION public.domain_event_sent_2021_payload_idx;


--
-- Name: domain_event_sent_2021_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.domain_event_sent_pkey ATTACH PARTITION public.domain_event_sent_2021_pkey;


--
-- Name: domain_event_sent_2021_status_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.domain_event_sent_status_idx ATTACH PARTITION public.domain_event_sent_2021_status_idx;


--
-- Name: domain_event_sent_2022_payload_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.domain_event_sent_payload_idx ATTACH PARTITION public.domain_event_sent_2022_payload_idx;


--
-- Name: domain_event_sent_2022_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.domain_event_sent_pkey ATTACH PARTITION public.domain_event_sent_2022_pkey;


--
-- Name: domain_event_sent_2022_status_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.domain_event_sent_status_idx ATTACH PARTITION public.domain_event_sent_2022_status_idx;


--
-- Name: domain_event_sent_2023_payload_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.domain_event_sent_payload_idx ATTACH PARTITION public.domain_event_sent_2023_payload_idx;


--
-- Name: domain_event_sent_2023_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.domain_event_sent_pkey ATTACH PARTITION public.domain_event_sent_2023_pkey;


--
-- Name: domain_event_sent_2023_status_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.domain_event_sent_status_idx ATTACH PARTITION public.domain_event_sent_2023_status_idx;


--
-- Name: domain_event_sent_payload_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.event_pyld_idx ATTACH PARTITION public.domain_event_sent_payload_idx;


--
-- Name: domain_event_sent_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.domain_event_pkey ATTACH PARTITION public.domain_event_sent_pkey;


--
-- Name: domain_event_sent_status_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.event_status_idx ATTACH PARTITION public.domain_event_sent_status_idx;


--
-- Name: token token_transaction_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER token_transaction_trigger AFTER UPDATE ON public.token FOR EACH ROW EXECUTE FUNCTION public.token_transaction_insert();


--
-- Name: ab_permission_view ab_permission_view_permission_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ab_permission_view
    ADD CONSTRAINT ab_permission_view_permission_id_fkey FOREIGN KEY (permission_id) REFERENCES public.ab_permission(id);


--
-- Name: ab_permission_view_role ab_permission_view_role_permission_view_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ab_permission_view_role
    ADD CONSTRAINT ab_permission_view_role_permission_view_id_fkey FOREIGN KEY (permission_view_id) REFERENCES public.ab_permission_view(id);


--
-- Name: ab_permission_view_role ab_permission_view_role_role_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ab_permission_view_role
    ADD CONSTRAINT ab_permission_view_role_role_id_fkey FOREIGN KEY (role_id) REFERENCES public.ab_role(id);


--
-- Name: ab_permission_view ab_permission_view_view_menu_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ab_permission_view
    ADD CONSTRAINT ab_permission_view_view_menu_id_fkey FOREIGN KEY (view_menu_id) REFERENCES public.ab_view_menu(id);


--
-- Name: ab_user ab_user_changed_by_fk_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ab_user
    ADD CONSTRAINT ab_user_changed_by_fk_fkey FOREIGN KEY (changed_by_fk) REFERENCES public.ab_user(id);


--
-- Name: ab_user ab_user_created_by_fk_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ab_user
    ADD CONSTRAINT ab_user_created_by_fk_fkey FOREIGN KEY (created_by_fk) REFERENCES public.ab_user(id);


--
-- Name: ab_user_role ab_user_role_role_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ab_user_role
    ADD CONSTRAINT ab_user_role_role_id_fkey FOREIGN KEY (role_id) REFERENCES public.ab_role(id);


--
-- Name: ab_user_role ab_user_role_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ab_user_role
    ADD CONSTRAINT ab_user_role_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.ab_user(id);


--
-- Name: dag_owner_attributes dag_owner_attributes_dag_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dag_owner_attributes
    ADD CONSTRAINT dag_owner_attributes_dag_id_fkey FOREIGN KEY (dag_id) REFERENCES public.dag(dag_id) ON DELETE CASCADE;


--
-- Name: dag_run_note dag_run_note_dr_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dag_run_note
    ADD CONSTRAINT dag_run_note_dr_fkey FOREIGN KEY (dag_run_id) REFERENCES public.dag_run(id) ON DELETE CASCADE;


--
-- Name: dag_run_note dag_run_note_user_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dag_run_note
    ADD CONSTRAINT dag_run_note_user_fkey FOREIGN KEY (user_id) REFERENCES public.ab_user(id);


--
-- Name: dag_tag dag_tag_dag_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dag_tag
    ADD CONSTRAINT dag_tag_dag_id_fkey FOREIGN KEY (dag_id) REFERENCES public.dag(dag_id) ON DELETE CASCADE;


--
-- Name: dagrun_dataset_event dagrun_dataset_events_dag_run_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dagrun_dataset_event
    ADD CONSTRAINT dagrun_dataset_events_dag_run_id_fkey FOREIGN KEY (dag_run_id) REFERENCES public.dag_run(id) ON DELETE CASCADE;


--
-- Name: dagrun_dataset_event dagrun_dataset_events_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dagrun_dataset_event
    ADD CONSTRAINT dagrun_dataset_events_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.dataset_event(id) ON DELETE CASCADE;


--
-- Name: dag_warning dcw_dag_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dag_warning
    ADD CONSTRAINT dcw_dag_id_fkey FOREIGN KEY (dag_id) REFERENCES public.dag(dag_id) ON DELETE CASCADE;


--
-- Name: dataset_dag_run_queue ddrq_dag_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dataset_dag_run_queue
    ADD CONSTRAINT ddrq_dag_fkey FOREIGN KEY (target_dag_id) REFERENCES public.dag(dag_id) ON DELETE CASCADE;


--
-- Name: dataset_dag_run_queue ddrq_dataset_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dataset_dag_run_queue
    ADD CONSTRAINT ddrq_dataset_fkey FOREIGN KEY (dataset_id) REFERENCES public.dataset(id) ON DELETE CASCADE;


--
-- Name: dag_schedule_dataset_reference dsdr_dag_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dag_schedule_dataset_reference
    ADD CONSTRAINT dsdr_dag_id_fkey FOREIGN KEY (dag_id) REFERENCES public.dag(dag_id) ON DELETE CASCADE;


--
-- Name: dag_schedule_dataset_reference dsdr_dataset_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dag_schedule_dataset_reference
    ADD CONSTRAINT dsdr_dataset_fkey FOREIGN KEY (dataset_id) REFERENCES public.dataset(id) ON DELETE CASCADE;


--
-- Name: entity_manager entity_manager_child_entity_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entity_manager
    ADD CONSTRAINT entity_manager_child_entity_id_fk FOREIGN KEY (child_entity_id) REFERENCES public.entity(id);


--
-- Name: entity_manager entity_manager_parent_entity_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entity_manager
    ADD CONSTRAINT entity_manager_parent_entity_id_fk FOREIGN KEY (parent_entity_id) REFERENCES public.entity(id);


--
-- Name: entity_role entity_role_entity_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entity_role
    ADD CONSTRAINT entity_role_entity_id_fk FOREIGN KEY (entity_id) REFERENCES public.entity(id);


--
-- Name: grower_note fk_grower_note_author; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grower_note
    ADD CONSTRAINT fk_grower_note_author FOREIGN KEY (author_id) REFERENCES public.admin_user(id);


--
-- Name: grower_note fk_grower_note_planter; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grower_note
    ADD CONSTRAINT fk_grower_note_planter FOREIGN KEY (planter_id) REFERENCES public.planter(id);


--
-- Name: locations locations_planter_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.locations
    ADD CONSTRAINT locations_planter_id_fk FOREIGN KEY (planter_id) REFERENCES public.planter(id);


--
-- Name: notes notes_planter_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notes
    ADD CONSTRAINT notes_planter_id_fk FOREIGN KEY (planter_id) REFERENCES public.planter(id);


--
-- Name: payment payment_entity_receiver_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment
    ADD CONSTRAINT payment_entity_receiver_id_fk FOREIGN KEY (receiver_entity_id) REFERENCES public.entity(id);


--
-- Name: payment payment_entity_sender_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment
    ADD CONSTRAINT payment_entity_sender_id_fk FOREIGN KEY (sender_entity_id) REFERENCES public.entity(id);


--
-- Name: pending_update pending_update_planter_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pending_update
    ADD CONSTRAINT pending_update_planter_id_fk FOREIGN KEY (planter_id) REFERENCES public.planter(id);


--
-- Name: planter planter_organization_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.planter
    ADD CONSTRAINT planter_organization_id_fk FOREIGN KEY (organization_id) REFERENCES public.entity(id);


--
-- Name: planter_new planter_organization_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.planter_new
    ADD CONSTRAINT planter_organization_id_fk FOREIGN KEY (organization_id) REFERENCES public.entity(id);


--
-- Name: planter planter_person_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.planter
    ADD CONSTRAINT planter_person_id_fk FOREIGN KEY (person_id) REFERENCES public.entity(id);


--
-- Name: planter_new planter_person_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.planter_new
    ADD CONSTRAINT planter_person_id_fk FOREIGN KEY (person_id) REFERENCES public.entity(id);


--
-- Name: rendered_task_instance_fields rtif_ti_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rendered_task_instance_fields
    ADD CONSTRAINT rtif_ti_fkey FOREIGN KEY (dag_id, task_id, run_id, map_index) REFERENCES public.task_instance(dag_id, task_id, run_id, map_index) ON DELETE CASCADE;


--
-- Name: survey_question survey_question_survey_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.survey_question
    ADD CONSTRAINT survey_question_survey_id_fkey FOREIGN KEY (survey_id) REFERENCES public.survey(id);


--
-- Name: task_fail task_fail_ti_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_fail
    ADD CONSTRAINT task_fail_ti_fkey FOREIGN KEY (dag_id, task_id, run_id, map_index) REFERENCES public.task_instance(dag_id, task_id, run_id, map_index) ON DELETE CASCADE;


--
-- Name: task_instance task_instance_dag_run_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_instance
    ADD CONSTRAINT task_instance_dag_run_fkey FOREIGN KEY (dag_id, run_id) REFERENCES public.dag_run(dag_id, run_id) ON DELETE CASCADE;


--
-- Name: dag_run task_instance_log_template_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dag_run
    ADD CONSTRAINT task_instance_log_template_id_fkey FOREIGN KEY (log_template_id) REFERENCES public.log_template(id);


--
-- Name: task_instance_note task_instance_note_ti_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_instance_note
    ADD CONSTRAINT task_instance_note_ti_fkey FOREIGN KEY (dag_id, task_id, run_id, map_index) REFERENCES public.task_instance(dag_id, task_id, run_id, map_index) ON DELETE CASCADE;


--
-- Name: task_instance_note task_instance_note_user_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_instance_note
    ADD CONSTRAINT task_instance_note_user_fkey FOREIGN KEY (user_id) REFERENCES public.ab_user(id);


--
-- Name: task_instance task_instance_trigger_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_instance
    ADD CONSTRAINT task_instance_trigger_id_fkey FOREIGN KEY (trigger_id) REFERENCES public.trigger(id) ON DELETE CASCADE;


--
-- Name: task_map task_map_task_instance_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_map
    ADD CONSTRAINT task_map_task_instance_fkey FOREIGN KEY (dag_id, task_id, run_id, map_index) REFERENCES public.task_instance(dag_id, task_id, run_id, map_index) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: task_reschedule task_reschedule_dr_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_reschedule
    ADD CONSTRAINT task_reschedule_dr_fkey FOREIGN KEY (dag_id, run_id) REFERENCES public.dag_run(dag_id, run_id) ON DELETE CASCADE;


--
-- Name: task_reschedule task_reschedule_ti_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_reschedule
    ADD CONSTRAINT task_reschedule_ti_fkey FOREIGN KEY (dag_id, task_id, run_id, map_index) REFERENCES public.task_instance(dag_id, task_id, run_id, map_index) ON DELETE CASCADE;


--
-- Name: task_outlet_dataset_reference todr_dag_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_outlet_dataset_reference
    ADD CONSTRAINT todr_dag_id_fkey FOREIGN KEY (dag_id) REFERENCES public.dag(dag_id) ON DELETE CASCADE;


--
-- Name: task_outlet_dataset_reference todr_dataset_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_outlet_dataset_reference
    ADD CONSTRAINT todr_dataset_fkey FOREIGN KEY (dataset_id) REFERENCES public.dataset(id) ON DELETE CASCADE;


--
-- Name: token token_entity_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.token
    ADD CONSTRAINT token_entity_id_fk FOREIGN KEY (entity_id) REFERENCES public.entity(id);


--
-- Name: token token_tree_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.token
    ADD CONSTRAINT token_tree_id_fk FOREIGN KEY (tree_id) REFERENCES public.trees(id);


--
-- Name: transaction transaction_entity_receiver_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transaction
    ADD CONSTRAINT transaction_entity_receiver_id_fk FOREIGN KEY (receiver_entity_id) REFERENCES public.entity(id);


--
-- Name: transaction transaction_entity_sender_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transaction
    ADD CONSTRAINT transaction_entity_sender_id_fk FOREIGN KEY (sender_entity_id) REFERENCES public.entity(id);


--
-- Name: transaction transaction_token_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transaction
    ADD CONSTRAINT transaction_token_id_fk FOREIGN KEY (token_id) REFERENCES public.token(id);


--
-- Name: trees trees_payment_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trees
    ADD CONSTRAINT trees_payment_id_fk FOREIGN KEY (payment_id) REFERENCES public.payment(id);


--
-- Name: trees_new trees_payment_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trees_new
    ADD CONSTRAINT trees_payment_id_fk FOREIGN KEY (payment_id) REFERENCES public.payment(id);


--
-- Name: xcom xcom_task_instance_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.xcom
    ADD CONSTRAINT xcom_task_instance_fkey FOREIGN KEY (dag_id, task_id, run_id, map_index) REFERENCES public.task_instance(dag_id, task_id, run_id, map_index) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--


SET search_path TO public;
