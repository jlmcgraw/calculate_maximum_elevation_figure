-- PRAGMA foreign_keys=ON;
PRAGMA synchronous=OFF;
-- PRAGMA journal_mode=MEMORY;
-- PRAGMA default_cache_size=10000;
-- PRAGMA locking_mode=EXCLUSIVE;

-- The old way of loading spatialite
-- SELECT load_extension('libspatialite.so');
-- The new way
-- See https://www.gaia-gis.it/fossil/libspatialite/wiki?name=mod_spatialite
SELECT load_extension('mod_spatialite');
SELECT InitSpatialMetadata(1);

-- Obstacles
        SELECT AddGeometryColumn( 'obstacles' , 'geometry', 4326, 'POINT', 'XY');
        SELECT CreateSpatialIndex( 'obstacles' , 'geometry' );
        UPDATE obstacles
                SET geometry = MakePoint(
                                CAST (longitude AS DOUBLE),
                                CAST (latitude AS DOUBLE),
                                4326);
-- Terrain
        SELECT AddGeometryColumn( 'Terrain' , 'geometry', 4326, 'POINT', 'XY');
        SELECT CreateSpatialIndex( 'Terrain' , 'geometry' );
        UPDATE Terrain
                SET geometry = MakePoint(
                                CAST (longitude AS DOUBLE),
                                CAST (latitude AS DOUBLE),
                                4326);
                                
-- MEF
        SELECT AddGeometryColumn( 'MEF' , 'geometry', 4326, 'POINT', 'XY');
        SELECT CreateSpatialIndex( 'MEF' , 'geometry' );
        UPDATE MEF
                SET geometry = MakePoint(
                                CAST (longitude AS DOUBLE),
                                CAST (latitude AS DOUBLE),
                                4326);                                
VACUUM;
