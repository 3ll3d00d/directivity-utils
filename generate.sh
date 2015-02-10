#/bin/bash

# data should be exported as space delimited freq/dB (usually has phase as 3rd column)
# filenames should be <degrees>.dat

rm directivity.txt
rm sorted_directivity.txt
rm gnuplot_input.txt

# TODO accept limits at cmdline
MIN_FREQ=800

echo "Generating data for gnuplot from ${MIN_FREQ} Hz"
for each in $(ls *.dat)
do 
    DEGREES=$(echo ${each%%.dat})
    echo "Parsing ${each}"
    awk -F" " -v deg=${DEGREES} -v minfreq=${MIN_FREQ} '/^[0-9]/ { if ( $1 > minfreq ) { print $1, deg, $2 } }' $each >> directivity.txt
done
sort -k1V,2V directivity.txt > sorted_directivity.txt
awk -v n=13 '1; NR % n == 0 {print ""}' sorted_directivity.txt > gnuplot_input.txt

echo "Plotting!"

# TODO work out min/max levels from input data + pass through to gnuplot

gnuplot <<EOF
# set the input and output
set term png size 1728,972 crop
set output "output.png"
set datafile separator " "

# plot features
set pm3d map
set contour surface
set cntrparam levels incremental 59,1.5,71
set cntrparam cubicspline
set cbrange [59:74]
set pm3d interpolate 20,20

# formatting of axes etc
set logscale x 10
set xrange [800:22050]
set mxtics 10
set xlabel 'Frequency (Hz)'

set ylabel 'deg'
set ytics 0,7.5,90

set key outside
set key top right

# jet palette
f(x)=1.5-4*abs(x)
set palette model RGB
set palette functions f(gray-0.75),f(gray-0.5),f(gray-0.25)

# now plot
splot 'gnuplot_input.txt' using 1:2:3 title "                      "
EOF