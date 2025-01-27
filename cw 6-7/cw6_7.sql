-- Przykłady

ALTER SCHEMA schema_name RENAME TO kacper;

CREATE EXTENSION postgis_raster SCHEMA kacper;

CREATE TABLE kacper.intersects AS
SELECT 
    a.rast, 
    b.municipality
FROM 
    rasters.dem AS a,
    vectors.porto_parishes AS b
WHERE 
    ST_Intersects(a.rast, b.geom) 
    AND b.municipality ILIKE 'porto';

ALTER TABLE kacper.intersects
ADD COLUMN rid SERIAL PRIMARY KEY;

CREATE INDEX idx_intersects_rast_gist 
ON kacper.intersects
USING gist(ST_ConvexHull(rast));

SELECT AddRasterConstraints('kacper', 'intersects', 'rast');

CREATE TABLE kacper.clip AS
SELECT 
    ST_Clip(a.rast, b.geom, true) AS rast,
    b.municipality
FROM 
    rasters.dem AS a,
    vectors.porto_parishes AS b
WHERE 
    ST_Intersects(a.rast, b.geom) 
    AND b.municipality LIKE 'PORTO';

CREATE TABLE kacper.union AS
SELECT 
    ST_Union(ST_Clip(a.rast, b.geom, true)) AS rast
FROM 
    rasters.dem AS a,
    vectors.porto_parishes AS b
WHERE 
    b.municipality ILIKE 'porto' 
    AND ST_Intersects(b.geom, a.rast);

-- Tworzenie tabeli porto_parishes
DROP TABLE IF EXISTS kacper.porto_parishes;

CREATE TABLE kacper.porto_parishes AS
WITH r AS (
    SELECT rast FROM rasters.dem LIMIT 1
)
SELECT 
    ST_AsRaster(a.geom, r.rast, '8BUI', a.id, -32767) AS rast
FROM 
    vectors.porto_parishes AS a,
    r
WHERE 
    a.municipality ILIKE 'porto';

-- Ulepszenie tworzenia porto_parishes z kafelkowaniem
DROP TABLE IF EXISTS kacper.porto_parishes;

CREATE TABLE kacper.porto_parishes AS
WITH r AS (
    SELECT rast FROM rasters.dem LIMIT 1
)
SELECT 
    ST_Tile(ST_Union(ST_AsRaster(a.geom, r.rast, '8BUI', a.id, -32767)), 128, 128, true, -32767) AS rast
FROM 
    vectors.porto_parishes AS a,
    r
WHERE 
    a.municipality ILIKE 'porto';

-- Tworzenie tabeli intersection
CREATE TABLE kacper.intersection AS
SELECT 
    a.rid,
    (ST_Intersection(b.geom, a.rast)).geom AS geom,
    (ST_Intersection(b.geom, a.rast)).val AS val
FROM 
    rasters.landsat8 AS a,
    vectors.porto_parishes AS b
WHERE 
    b.parish ILIKE 'paranhos' 
    AND ST_Intersects(b.geom, a.rast);

-- Przetwarzanie danych dla dem
CREATE TABLE kacper.paranhos_dem AS
SELECT 
    a.rid,
    ST_Clip(a.rast, b.geom, true) AS rast
FROM 
    rasters.dem AS a,
    vectors.porto_parishes AS b
WHERE 
    b.parish ILIKE 'paranhos' 
    AND ST_Intersects(b.geom, a.rast);

CREATE TABLE kacper.paranhos_slope AS
SELECT 
    a.rid,
    ST_Slope(a.rast, 1, '32BF', 'PERCENTAGE') AS rast
FROM 
    kacper.paranhos_dem AS a;

CREATE TABLE kacper.paranhos_slope_reclass AS
SELECT 
    a.rid,
    ST_Reclass(a.rast, 1, ']0-15]:1, (15-30]:2, (30-9999:3', '32BF', 0) AS rast
FROM 
    kacper.paranhos_slope AS a;

-- Statystyki i przetwarzanie rasterów
SELECT 
    ST_SummaryStats(a.rast) AS stats
FROM 
    kacper.paranhos_dem AS a;

WITH t AS (
    SELECT 
        b.parish AS parish,
        ST_SummaryStats(ST_Union(ST_Clip(a.rast, b.geom, true))) AS stats
    FROM 
        rasters.dem AS a,
        vectors.porto_parishes AS b
    WHERE 
        b.municipality ILIKE 'porto' 
        AND ST_Intersects(b.geom, a.rast)
    GROUP BY 
        b.parish
)
SELECT 
    parish, (stats).min, (stats).max, (stats).mean 
FROM 
    t;

-- Tworzenie tabeli tpi30
CREATE TABLE kacper.tpi30 AS
SELECT 
    ST_TPI(a.rast, 1) AS rast
FROM 
    rasters.dem AS a;

CREATE INDEX idx_tpi30_rast_gist 
ON kacper.tpi30
USING gist (ST_ConvexHull(rast));

SELECT AddRasterConstraints('kacper', 'tpi30', 'rast');

-- Przetwarzanie mniejszego obszaru Porto
CREATE TABLE kacper.tpi30_porto AS
SELECT 
    ST_TPI(a.rast, 1) AS rast
FROM 
    rasters.dem AS a,
    vectors.porto_parishes AS b
WHERE 
    ST_Intersects(a.rast, b.geom) 
    AND b.municipality ILIKE 'porto';

CREATE INDEX idx_tpi30_porto_rast_gist 
ON kacper.tpi30_porto
USING gist (ST_ConvexHull(rast));

SELECT AddRasterConstraints('kacper', 'tpi30_porto', 'rast');

-- Tworzenie tabeli porto_ndvi
CREATE TABLE kacper.porto_ndvi AS
WITH r AS (
    SELECT 
        a.rid,
        ST_Clip(a.rast, b.geom, true) AS rast
    FROM 
        rasters.landsat8 AS a,
        vectors.porto_parishes AS b
    WHERE 
        b.municipality ILIKE 'porto' 
        AND ST_Intersects(b.geom, a.rast)
)
SELECT 
    r.rid,
    ST_MapAlgebra(
        r.rast, 1,
        r.rast, 4,
        '([rast2.val] - [rast1.val]) / ([rast2.val] + [rast1.val])::float',
        '32BF'
    ) AS rast 
FROM 
    r;

CREATE INDEX idx_porto_ndvi_rast_gist 
ON kacper.porto_ndvi
USING gist (ST_ConvexHull(rast));

SELECT AddRasterConstraints('kacper', 'porto_ndvi', 'rast');
