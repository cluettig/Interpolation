#!/bin/bash
#SBATCH --job-name=int
#SBATCH --ntasks=1
#SBATCH --qos=short
#SBATCH --time=00:10:00
#SBATCH --mail-user=cluettig@awi.de
#SBATCH --mail-type=ALL
module load gcc
module load R/3.3.0.gcc
module load gdal
module load GMT
module load python

#cp -r test/outline/ .
cp test/rf_mf_f1_vx.tif .
rm -r test/
mkdir test
#mv outline/ test/
mv rf_mf_f1_vx.tif test/
srun ./kombi.sh test/rf_mf_f1_vx test/int_rf_mf_f1_vx S
