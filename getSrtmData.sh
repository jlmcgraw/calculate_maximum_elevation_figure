#!/bin/bash
set -eu               # Abort on error or unset variables
IFS=$(printf '\n\t')  # File separator is newline or tab

# This will cover the continental US
# for x in {01..26}; do
#   for y in {01..10}; do
for x in {01..72}; do
  for y in {01..24}; do
  echo $x,$y
  if [ ! -f srtm_${x}_${y}.zip ]; then
    #Since some of these files won't exist, make errors not stop the whole script
    set +e
    wget http://srtm.csi.cgiar.org/SRT-ZIP/SRTM_V41/SRTM_Data_GeoTiff/srtm_${x}_${y}.zip
    #wget http://droppr.org/srtm/v4.1/6_5x5_TIFs/srtm_${x}_${y}.zip
    #Restore the default
    set -e
  else
    echo "Already got it."
  fi
  done
done
#Unzip all of the DEM files
# unzip -u -j "*srtm*.zip" "*.tif"
