-- Obstacles
DROP INDEX IF EXISTS obstacles_location_index;
CREATE INDEX obstacles_location_index
	ON obstacles (longitude, latitude); 

-- Terrain
DROP INDEX IF EXISTS Terrain_location_index;
CREATE INDEX Terrain_location_index
	ON Terrain (longitude, latitude); 

-- MEF
DROP INDEX IF EXISTS MEF_location_index;
CREATE INDEX MEF_location_index
	ON MEF (longitude, latitude);
	
vacuum;

