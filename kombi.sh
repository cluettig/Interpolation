#!/bin/bash
##
## Time-stamp: <2017-05-11 13:25:08 (cluettig)>
##
#set -x
starttime=`date +%s`
echo "Computation started at" $(date)

############### INITIALIZATION #########################################################################################################

NS=$3 # north or south (to set projection)

##### GeoTiff:
input=$1 
bname=$(basename $input)
dir=$(dirname $input)
result=$2
##### NetCDF:
resampled=$dir/resampled
edges=$dir/edges
edges_proj=$dir/edges_proj
surface=$dir/surface
surface_proj=$dir/surface_proj
isnan=$dir/isnan
isnan_proj=$dir/isnan_proj
surface_gaps_filled=$dir/surface_gaps_filled
surface_gaps_cut=$dir/surface_gaps_cut
kriging_radius_inside=$dir/kriging_radius_inside
kriging_values_inside=$dir/kriging_values_inside
kriging_variance_inside=$dir/kriging_variance_inside
interim_inside=$dir/interim_inside
kriging_radius_outside=$dir/kriging_radius_outside
kriging_values_outside=$dir/kriging_values_outside
kriging_variance_outside=$dir/kriging_variance_outside
interim_outside=$dir/interim_outside
lower_resolution=$dir/lower_resolution
merged=$dir/merged
smoothed=$dir/smoothed
kriging_values_outside_resampled=$dir/kriging_values_outside_resampled

##### Shape:
vectorized=$dir/vectorized
surface_gaps=$dir/surface_gaps
kriging_gaps=$dir/kriging_gaps
outline=$dir/outline
classified=$dir/classified
outside_radii=$dir/outside_radii

##### txt:
txt=$dir/output.txt

#rm -f -r $resampled.nc $edges.nc $edges_proj.nc $surface.nc $surface_proj.nc $isnan.nc $isnan_proj.nc $surface_gaps_filled.nc $surface_gaps_cut.nc $kriging_radius_inside.nc $kriging_radius_inside.tif $kriging_values_inside.nc $kriging_variance_inside.nc $interim_inside.nc $kriging_radius_outside.nc $kriging_radius_outside.tif $kriging_values_outside.nc $kriging_variance_outside.nc $interim_outside.nc $lower_resolution.nc $merged.nc $smoothed.nc $kriging_values_outide_resampled.nc $vectorized $surface_gaps $kriging_gaps $classified $outside_radii $txt



if [[ $bname == *'vx'* ]]; then
    comp=0
elif [[ $bname == *'vy'* ]]; then
    comp=1
else
    echo 'Unknown velocity component. Filename must contain vx or vy.'
fi
if [ $NS == 'N' ]; then
    proj='+proj=stere +lat_0=90 +lat_ts=70 +lon_0=-45 +k=1 +x_0=0 +y_0=0 +ellps=WGS84 +datum=WGS84 +units=m +no_defs'
    if [ $comp == 0 ]; then
	prior='../prior/prior_vx.nc'
    elif [ $comp == 1 ]; then
	prior='../prior/prior_vy.nc'
    fi
    
elif [ $NS == 'S' ]; then
    proj='+proj=stere +lat_0=-90 +lat_ts=-71 +lon_0=0 +k=1 +x_0=0 +y_0=0 +datum=WGS84 +units=m +no_defs'
    if [ $comp == 0 ]; then
	prior='../prior/rignot_vx.nc'
    elif [ $comp == 1 ]; then
	prior='../prior/rignot_vy.nc'
    fi
else
    echo 'Unknown region' $NS '. Set N or S.'
fi

##################### ADD EDGES #########################################################################################################

echo "Add edges"
gdal_translate -of NetCDF $input.tif $input.nc
reg=$(gmt grdinfo -I- $input.nc | head -n1)
gmt grdsample $input.nc -I250/250 $reg -G$resampled.nc 

./add_edge.gmt $resampled.nc $edges.nc $prior



##################### GMT SURFACE INTERPOLATION ########################################################################################
#echo "gmt surface interpolation"
#reg=$(gmt grdinfo -I- $edges.nc | head -n1)
#res=$(gmt grdinfo -I $edges.nc | head -n1)
#gmt grd2xyz $edges.nc -s > $dir/edges.d
#gmt blockmean $dir/edges.d $reg $res > $dir/edges_bm.d
#gmt surface $dir/edges_bm.d $reg $res -T1  -G$surface.nc 
#gdal_translate -q -a_srs "$proj" -a_nodata nan -of NetCDF $surface.nc $surface_proj.nc
#echo "fill small gaps with gmt surface interpolation"
gmt grdmath $edges.nc ISNAN = $isnan.nc
echo " vectorize" 
gdal_translate -q $isnan.nc $isnan.tif
gdal_translate -q  -a_nodata nan -a_srs "$proj" $isnan.nc $isnan_proj.tif
mkdir $vectorized
###./polygonize.py $isnan_proj.tif $vectorized
gdal_polygonize.py -q $isnan_proj.tif -f "ESRI Shapefile" $vectorized
kriging_gaps=$vectorized
#echo "filter polygons"
#./remove_polygons.py $vectorized $surface_gaps $kriging_gaps $isnan.nc
#echo "clip remaining polygons out of interpolation"
#i1=$(gmt grdinfo -I $surface_proj.nc | head -n1 | awk -F / '{print $1}' | awk -F I '{print $2}')
#i2=$(gmt grdinfo -I $surface_proj.nc | head -n1 | awk -F / '{print $2}')
if [ -e $surface_gaps ]; then
    gdalwarp -q -dstnodata nan -cutline $surface_gaps -tr $i1 $i2 -of NetCDF $surface_proj.nc $surface_gaps_cut.nc
    echo "add values to input raster"
    gmt grdmath $edges.nc $surface_gaps_cut.nc AND = $surface_gaps_filled.nc
else
    cp $edges.nc $surface_gaps_filled.nc
fi

##################### KRIGING WITHIN THE OUTLINE ####################################################################################

#echo "classification of remaining gaps"
if [ -e $kriging_gaps ]; then
    ./classification.py $kriging_gaps $classified $outline
    ext=$(./extent.py $isnan.nc)
    cp $surface_gaps_filled.nc $kriging_radius_inside.nc
    gdal_rasterize -q -a krig -l classified -a_srs "$proj" -tr 250 250 -te $ext $classified/classified.shp $kriging_radius_inside.tif
    gdal_translate -of NetCDF $kriging_radius_inside.tif $kriging_radius_inside.nc
#    echo "kriging inside" 
    cp $surface_gaps_filled.nc $kriging_values_inside.nc
    cp $surface_gaps_filled.nc $kriging_variance_inside.nc
    cp $surface_gaps_filled.nc $interim_inside.nc
    ./kriging.R $surface_gaps_filled.nc  $kriging_radius_inside.nc $kriging_values_inside.nc $interim_inside.nc $kriging_variance_inside.nc $dir #> $txt

    ##################### KRIGING OUTSIDE THE OUTLINE ####################################################################################
    if [ -e $outline ]; then
        echo "radius values outside of the outline"
#	reg=$(gmt grdinfo -I- $kriging_values_inside.nc | head -n1)
#	gmt grdsample $reg -I2000/2000 $edges.nc -G$lower_resolution.nc -r
#	i1=$(gmt grdinfo -I $lower_resolution.nc | head -n1 | awk -F / '{print $1}' | awk -F I '{print $2}')
#	i2=$(gmt grdinfo -I $lower_resolution.nc | head -n1 | awk -F / '{print $2}')
#	ext=$(./extent.py $isnan.nc)
#	./outside_gaps.py $outline $kriging_gaps $outside_radii
#	gdal_rasterize -at -q -a_srs "$proj" -tr $i1 $i2 -te $ext -a krig $outside_radii/outside_radii.shp  $kriging_radius_outside.tif
#	gdal_translate -of NetCDF $kriging_radius_outside.tif $kriging_radius_outside.nc
#	cp $lower_resolution.nc $kriging_values_outside.nc
#	cp $lower_resolution.nc $interim_outside.nc
#	cp $lower_resolution.nc $kriging_variance_outside.nc
#	echo "kriging outside"
#	./kriging.R $lower_resolution.nc  $kriging_radius_outside.nc $kriging_values_outside.nc $interim_outside.nc $kriging_variance_outside.nc  $dir #> $txt
#	reg=$(gmt grdinfo -I- $kriging_values_inside.nc | head -n1)
#	inc=$(gmt grdinfo -I $kriging_values_inside.nc | head -n1)

	##################### MERGE THE FILES #############################################################################################
	
#	gmt grdsample $kriging_values_outside.nc $reg $inc -T -nn -G$kriging_values_outside_resampled.nc
#	gmt grdmath $kriging_values_inside.nc $kriging_values_outside_resampled.nc AND = $merged.nc
    else
	cp $kriging_values_inside.nc $merged.nc
    fi

else
    cp $surface_gaps_filled.nc $merged.nc
fi


##################### SMOOTHING  ###################################################################################################
echo "smoothing"
#./smooth.py $merged.nc $smoothed.nc
#gdal_translate $smoothed.nc $result.tif




#cat $txt | mail -s "kombi.sh completed {$input}" cluettig@awi.de
endtime=`date +%s`
runtime=$((endtime-starttime))
echo 'Runtime:' $runtime 'seconds'


