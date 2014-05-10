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

-- -- -- --
-- Receita 008, obtenção de quadra sem calçada e sua rotulação nos lotes:
-- http://gauss.serveftp.com/colabore/index.php?title=Prj:Geoprocessing_Recipes/R009
SELECT lib.kxrefresh_quadrasc();



