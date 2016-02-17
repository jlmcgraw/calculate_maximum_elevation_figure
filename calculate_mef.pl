#!/usr/bin/perl

# Copyright (C) 2015  Jesse McGraw (jlmcgraw@gmail.com)
#
#-------------------------------------------------------------------------------
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program.  If not, see [http://www.gnu.org/licenses/].
#-------------------------------------------------------------------------------

#Calculate the MEF for each half-degree area where we have SRTM data

#https://en.wikipedia.org/wiki/Maximum_Elevation_Figure

# When a man-made obstacle is more than 200′ above the highest terrain
# within the quadrant:
# 1. Determine the elevation of the top of the obstacle above MSL.
# 2. Add the possible vertical error of the source material to the above figure
#   (100′ or 1/2 contour interval when interval on source exceeds 200′.
#    U.S. Geological Survey Quadrangle Maps with contour intervals as small as
#    10′ are normally used).
# 3. Round the resultant figure up to the next higher hundred foot level.
#
# Example: Elevation of obstacle top (MSL) = 2424
# Possible vertical error + 100 equals 2524
# Raise to the following 100 foot level 2600
# Maximum Elevation Figure [2600 (portrayed as 2^6)]
#
# When a natural terrain feature or natural vertical obstacle (e.g. a tree)
# is the highest feature within the quadrangle.:
#   1. Determine the elevation of the feature.
#   2. Add the possible vertical error of the source to the above figure
#       (100′ or 1/2 the contour interval when interval on source exceeds 200′).
#   3. Add a 200′ allowance for natural or manmade obstacles which are not
#       portrayed because they are below the minimum height at which the chart
#       specifications require their portrayal.
#   4. Round the figure up to the next higher hundred foot level.

#Standard libraries
use strict;
use warnings;
use autodie;
use Carp;
use vars qw/ %opt /;
use Getopt::Long qw(GetOptions);
Getopt::Long::Configure qw(gnu_getopt auto_help);
use Data::Dumper;
use Pod::Usage;
use File::Basename;
use Math::Round;
use DBI;
use Config;

#Non-standard libraries
use Modern::Perl '2015';
use Params::Validate qw(:all);
use Geo::GDAL;
use Geo::OGR;
use Geo::OSR;
use Geo::GDAL::Const;
use Text::CSV;

#Hold a copy of the original ARGV just in case
my @ARGV_unmodified;

#Expand wildcards on command line since windows doesn't do it for us
if ( $Config{archname} =~ m/win/ix ) {
    use File::Glob ':bsd_glob';

    #Expand wildcards on command line
    say "Expanding wildcards for Windows";
    @ARGV_unmodified = @ARGV;
    @ARGV            = bsd_glob "@ARGV";
}

#Call the main routine and exit with its return code
exit main(@ARGV);

sub main {

    #General idea:
    #For each srtm DEM file in the supplied directory
    #	For each $degree_increment degrees lon/lat square in that overall DEM
    #		find the maximum obstacle height in that square and where it is
    #               find the maximum terrain height in that square and where it is
    #               save whichever is higher in the MEF hash
    #Output MEF hash as CSV

    #How many command line arguments
    my $arg_num = scalar @ARGV;

    #We need at least one argument (the name of the directory with srtm files)
    if ( $arg_num < 1 ) {
        usage();
        exit(1);
    }

    #Command line parameter for directory of SRTM files
    my $demDirectory = shift @_;

    #The array of our DEM .ZIPs
    my @files = <$demDirectory/srtm_*.zip>;

    #Open the NASR database
    #Created by https://github.com/jlmcgraw/processFaaData
    my ( $dbh, $sth );
    $dbh
        = DBI->connect( "dbi:SQLite:dbname=56day.db", "", "",
        { RaiseError => 1 },
        ) or die $DBI::errstr;

    #Hashes for highest MEF for each quadgrangle, terrain and obstacle
    my ( %mef, %terrain, %obstacles );

    #How big do we want each sub-quadgrangle to be (in degrees)
    my $degree_increment = .5;

    foreach my $file (@files) {

        #Parse out the components of the FQN
        my ( $filename, $dir, $ext ) = fileparse( $file, qr/\.[^.]*/x );

        #Open the tif within the zip file using the /vsizip path
        my $dataSet = Geo::GDAL::Open("/vsizip/$file/$filename.tif");

        #The pixel->world transform
        my $transform_ref = $dataSet->GetGeoTransform;

        #The world->pixel transform
        my $inverse_transform_ref
            = Geo::GDAL::InvGeoTransform($transform_ref);

        #Get the pixel dimensions of this raster
        my ( $size_x, $size_y ) = $dataSet->Size;

        #What type of data is each pixel
        my ($type) = $dataSet->Band->DataType;

        #What type of data is each pixel
        my ($units) = $dataSet->Band->Unit;

        #What scale and offset for each pixel
        my ( $scale, $offset ) = $dataSet->Band->ScaleAndOffset;

        #Get the noDataValue for this band
        my ($noDataValue) = $dataSet->Band->GetNoDataValue;

        #Get the block sizes for this band
        my ( $blockSizeX, $blockSizeY ) = $dataSet->Band->GetBlockSize;

        #How many blocks for X and Y
        my $number_of_x_blocks
            = int( ( $size_x + ( $blockSizeX - 1 ) ) / $blockSizeX );
        my $number_of_y_blocks
            = int( ( $size_y + ( $blockSizeY - 1 ) ) / $blockSizeY );

        #Get the right type of pack/unpack pack_character
        my $pack_character = Geo::GDAL::PackCharacter($type);

        #Upper left lon/lat of raster
        my ( $world_ul_x, $world_ul_y )
            = Geo::GDAL::ApplyGeoTransform( $transform_ref, 0, 0 );

        #Round them
        my $world_ul_x_rounded = round($world_ul_x);
        my $world_ul_y_rounded = round($world_ul_y);

        #Lower right lon/lat of raster
        my ( $world_lr_x, $world_lr_y )
            = Geo::GDAL::ApplyGeoTransform( $transform_ref, $size_x,
            $size_y );

        #Round them
        my $world_lr_x_rounded = round($world_lr_x);
        my $world_lr_y_rounded = round($world_lr_y);

        #The world-coordinates bounding box of the overall DEM
        my ( $srtmMinimumLongitude, $srtmMaximumLatitude )
            = ( $world_ul_x_rounded, $world_ul_y_rounded );
            
        my ( $srtmMaximumLongitude, $srtmMinimumLatitude )
            = ( $world_lr_x_rounded, $world_lr_y_rounded );

        #Loop over the $degree_increment degree quadrants within the overall DEM
        for (
            my $sub_quad_lower_left_longitude = $srtmMinimumLongitude;
            $sub_quad_lower_left_longitude < $srtmMaximumLongitude;
            $sub_quad_lower_left_longitude += $degree_increment
            )
        {
            for (
                my $sub_quad_lower_left_latitude = $srtmMinimumLatitude;
                $sub_quad_lower_left_latitude < $srtmMaximumLatitude;
                $sub_quad_lower_left_latitude += $degree_increment
                )
            {

                #Calculate these parameters from our reference point in the
                #lower left corner of the square (min lon, min lat)
                my $upperLeftLong = $sub_quad_lower_left_longitude;
                my $upperLeftLat
                    = $sub_quad_lower_left_latitude + $degree_increment;
                my $lowerRightLong
                    = $sub_quad_lower_left_longitude + $degree_increment;
                my $lowerRightLat = $sub_quad_lower_left_latitude;

                #The middle of this sub-quadgrangle
                my $middleLongitude
                    = ( $upperLeftLong + $lowerRightLong ) / 2;
                my $middleLatitude = ( $upperLeftLat + $lowerRightLat ) / 2;

                #What to use for our MEF hash key
                my $mefKey = $sub_quad_lower_left_longitude . '-'
                    . $sub_quad_lower_left_latitude;

                #Set default MEF info for this sub-quadrant
                $mef{$mefKey}{'TYPE'}      = 'DEFAULT';
                $mef{$mefKey}{'MEF'}       = 300;
                $mef{$mefKey}{'Longitude'} = $middleLongitude;
                $mef{$mefKey}{'Latitude'}  = $middleLatitude;

                #Query for the highest obstacle in this quadrant
                #restore the CAST( * AS REAL) if problems
                #I removed them because it stopped use of the index
                my $maxInQuadrangleQuery = "
                SELECT
		  _id
		  , MAX (amsl_ht)
		  , obstacle_longitude
		  , obstacle_latitude
		FROM
		  obstacle_obstacle
		WHERE
		  ( obstacle_latitude BETWEEN   $lowerRightLat AND $upperLeftLat)
		AND
		  ( obstacle_longitude BETWEEN  $upperLeftLong AND $lowerRightLong)";

                $sth = $dbh->prepare($maxInQuadrangleQuery);
                $sth->execute();

                my $obstacleHash = $sth->fetchall_hashref('_id');

                foreach my $key ( keys %$obstacleHash ) {

                    #Did we find any result at all?
                    next unless $key;

                    #Calculate the MEF for this height
                    my $obstacleHeight
                        = $obstacleHash->{$key}{'MAX (amsl_ht)'};

                    my $obstacleMefHeight
                        = roundup( eval( $obstacleHeight + 100 ), 100 );

                    #Round longitude/latitude values to 5 decimal places
                    my $maxHeight_longitude = sprintf( "%.5f",
                        $obstacleHash->{$key}{"obstacle_longitude"} );
                    my $maxHeight_latitude = sprintf( "%.5f",
                        $obstacleHash->{$key}{"obstacle_latitude"} );

                    #Save the obstacle info
                    $obstacles{$mefKey}{'TYPE'}      = 'OBSTACLE';
                    $obstacles{$mefKey}{'Height'}    = $obstacleHeight;
                    $obstacles{$mefKey}{'mefHeight'} = $obstacleMefHeight;
                    $obstacles{$mefKey}{'Longitude'} = $maxHeight_longitude;
                    $obstacles{$mefKey}{'Latitude'}  = $maxHeight_latitude;

                    #Save the MEF height in the overal hash
                    if ( $obstacleMefHeight >= $mef{$mefKey}{'MEF'} ) {
                        $mef{$mefKey}{'TYPE'}      = 'OBSTACLE';
                        $mef{$mefKey}{'MEF'}       = $obstacleMefHeight;
                        $mef{$mefKey}{'Longitude'} = $maxHeight_longitude;
                        $mef{$mefKey}{'Latitude'}  = $maxHeight_latitude;
                    }
                }

                #----------------------------------------------
                #Now do SRTM stuff
                #----------------------------------------------
                #Get the pixel coordinates of the sub-quadgrangle
                my ( $upperLeftLong_pix, $upperLeftLat_pix )
                    = Geo::GDAL::ApplyGeoTransform( $inverse_transform_ref,
                    $upperLeftLong, $upperLeftLat );

                my ( $lowerRightLong_pix, $lowerRightLat_pix )
                    = Geo::GDAL::ApplyGeoTransform( $inverse_transform_ref,
                    $lowerRightLong, $lowerRightLat );

                #The pixel dimensions of this sub-quadgrangle
                my $xSize
                    = int( abs( $lowerRightLong_pix - $upperLeftLong_pix ) );
                my $ySize
                    = int( abs( $lowerRightLat_pix - $upperLeftLat_pix ) );

                #Read that sub-quadgrangle raster from the overall SRTM
                my $testBuf = $dataSet->ReadRaster(
                    XOFF  => eval( int($upperLeftLong_pix) ),
                    YOFF  => eval( int($upperLeftLat_pix) ),
                    XSIZE => $xSize,
                    YSIZE => $ySize
                );

                #Unpack the buffer into an array of whatever type we determined
                #earlier for this file
                #(for SRTM it should be signed 16bit integers, 's')
                my @rgbvals = unpack "$pack_character*", $testBuf;

                #Find the index of the MAX value in this array
                my $idxMax = 0;

                $rgbvals[$idxMax] > $rgbvals[$_]
                    or $idxMax = $_
                    for 1 .. $#rgbvals;

                #Find the MAX value in that array
                my $max = $rgbvals[$idxMax];

                #pixel values may have a scale and offset value
                #Though in the SRTM DEMs they shouldn't, it should just be
                #the elevation in meters at that point
                $max = $max * $scale + $offset;

                #Find where it occurs in the sub quadrant by converting the index
                #back into x,yne
                my ( $y_index, $x_index )
                    = ( int( $idxMax / $xSize ), $idxMax % $ySize );

                #Calculate where that sub x,y is in the overall raster
                my $overall_x_pixel = $upperLeftLong_pix + $x_index;
                my $overall_y_pixel = $upperLeftLat_pix + $y_index;

                #Convert those overall coordinates back to world coordinates
                my ( $maxHeight_longitude, $maxHeight_latitude )
                    = Geo::GDAL::ApplyGeoTransform( $transform_ref,
                    $overall_x_pixel, $overall_y_pixel );

                #Round values to 5 decimal places
                $maxHeight_longitude
                    = sprintf( "%.5f", $maxHeight_longitude );
                $maxHeight_latitude = sprintf( "%.5f", $maxHeight_latitude );

                my $quadrantMaxHeightInFeet;
                my $terrainMef;

                #Ignore $max if it's the noDataValue for this band
                if ( $max != $noDataValue ) {

                    #Convert from meters to feet
                    $quadrantMaxHeightInFeet = $max * 3.281;

                    #Calculate MEF for this height
                    $terrainMef
                        = roundup( $quadrantMaxHeightInFeet + 300, 100 );

                    # Save terrain info
                    $terrain{$mefKey}{'TYPE'}      = 'TERRAIN';
                    $terrain{$mefKey}{'Height'}    = $quadrantMaxHeightInFeet;
                    $terrain{$mefKey}{'mefHeight'} = $terrainMef;
                    $terrain{$mefKey}{'Longitude'} = $maxHeight_longitude;
                    $terrain{$mefKey}{'Latitude'}  = $maxHeight_latitude;

                    #Save the MEF height in the overal hash
                    if ( $terrainMef >= $mef{$mefKey}{'MEF'} ) {

                        $mef{$mefKey}{'TYPE'}      = 'TERRAIN';
                        $mef{$mefKey}{'MEF'}       = $terrainMef;
                        $mef{$mefKey}{'Longitude'} = $maxHeight_longitude;
                        $mef{$mefKey}{'Latitude'}  = $maxHeight_latitude;
                    }
                }
                else {
                    # Save terrain info
                    $terrain{$mefKey}{'TYPE'}      = 'NO_SRTM';
                    $terrain{$mefKey}{'Height'}    = '300';
                    $terrain{$mefKey}{'mefHeight'} = '300';
                    $terrain{$mefKey}{'Longitude'} = $middleLongitude;
                    $terrain{$mefKey}{'Latitude'}  = $middleLatitude;

                }

            }
        }

    }

    #Dump the hashes to CSV

    my @columns;
    my $file;
    my $csv;

    #Dump the MEF hash to a CSV file
    open $file, ">", "mef.csv" or die "Couldn't open mef file: $!";
    @columns = ( 'Quadrant', 'Type', 'MEF', 'Longitude', 'Latitude' );

    $csv = Text::CSV->new() or die;
    $csv->eol("\n");
    $csv->print( $file, \@columns );

    foreach ( sort keys %mef ) {
        my @row = [
            $_,              $mef{$_}{'TYPE'},
            $mef{$_}{'MEF'}, $mef{$_}{'Longitude'},
            $mef{$_}{'Latitude'}
        ];

        $csv->print( $file, @row );
    }
    close $file;

    #Dump the obstacles hash to a CSV file
    open $file, ">", "obstacles.csv"
        or die "Couldn't open obstacles file: $!";
    @columns = ( 'Quadrant', 'type', 'height', 'mefHeight', 'longitude',
        'latitude' );

    $csv = Text::CSV->new() or die;
    $csv->eol("\n");
    $csv->print( $file, \@columns );

    foreach ( sort keys %obstacles ) {
        my @row = [
            $_,                          $obstacles{$_}{'TYPE'},
            $obstacles{$_}{'Height'},    $obstacles{$_}{'mefHeight'},
            $obstacles{$_}{'Longitude'}, $obstacles{$_}{'Latitude'}
        ];

        $csv->print( $file, @row );
    }
    close $file;

    #Dump the terrain hash to a CSV file
    open $file, ">", "terrain.csv" or die "Couldn't open terrain file: $!";
    @columns = ( 'Quadrant', 'type', 'height', 'mefHeight', 'longitude',
        'latitude' );

    $csv = Text::CSV->new() or die;
    $csv->eol("\n");
    $csv->print( $file, \@columns );

    foreach ( sort keys %terrain ) {
        my @row = [
            $_,                        $terrain{$_}{'TYPE'},
            $terrain{$_}{'Height'},    $terrain{$_}{'mefHeight'},
            $terrain{$_}{'Longitude'}, $terrain{$_}{'Latitude'}
        ];

        $csv->print( $file, @row );
    }
    close $file;

    #     #Print header info
    #     say "type,height,mefHeight,longitude,latitude";

    #print Dumper \%mef;
}

sub roundup {

    #Round $v up to closest $m
    my $v   = shift @_;
    my $m   = shift @_;
    my $div = int( $v / $m );
    my $mod = $v % $m;
    $div++ if $mod;
    $div * $m;
}

sub usage {
    say "Usage: $0 <directory_with_SRTM files>";
    return;
}
