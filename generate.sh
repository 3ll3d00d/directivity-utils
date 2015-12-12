#!/bin/bash 

# data should be exported as space delimited freq/dB (usually has phase as 3rd column)
# filenames should be <foo>_<degrees>.dat where foo is some consistent prefix and degrees can be 90 or -90
FORCE_DELETE=0
MIN_FREQ=100
MAX_FREQ=20000
AUTO_MIRROR=0
TARGET_DIR="$(pwd)"
WIDTH=1920
HEIGHT=1080
PREFIX=
Z_RANGE=30
X_TICS=(200 400 600 800 1000 1250 1500 1750 2000 2500 3000 3500 4000 5000 10000 15000 20000)
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

function usage {
    echo "generate.sh -d -l 100 -h 22000 -m -x 1920 -y 1080 -p foo -z 30 -r 80"
    echo "    -d force delete of existing generated files"
    echo "    -l sets the lo frequency for the data generated, if unset default to the minimum value in the input data (NB: actually 200 for now)"
    echo "    -h sets the hi frequency for the data generated, if unset default to the maximum value in the input data (NB: actually 24000 for now)"
    echo "    -m mirror mode"
    echo "    -x width of image in pixels, default 1920"
    echo "    -y height of image in pixels, default 1080"
    echo "    -p file name prefix"
    echo "    -z z axis range, defaults to 30dB"
    echo "    -r reference SPL from which to set the -6dB point, defaults to 3dB below the max SPL found in the dataset"
}

function delete_or_blow {
    if [ "${FORCE_DELETE}" -eq 1 ]
    then
	[[ -f "${1}" ]] && rm "${1}"
    else
        [[ -f "${1}" ]] && echo "${1} exists, exiting! use -d to continue or move the file" && exit 65
    fi    
}

function mirror_data {
    for each in $(ls ${PREFIX}_[0-9]*.dat)
    do
        local ROOT="${each%%.dat}"
        local DEGREES="${ROOT##*_}"
        if [ "${DEGREES}" != 0 ]
        then
            [[ ! -e "${PREFIX}_-${DEGREES}.dat" ]] && cp "${each}" "${PREFIX}_-${DEGREES}.dat"
        fi
    done
    for each in $(ls ${PREFIX}_-[0-9]*.dat)
    do
        local ROOT="${each%%.dat}"
	local DEGREES="${ROOT##*_}"
	local DEGREES="${DEGREES:1}"
	[[ ! -e "${PREFIX}_${DEGREES}.dat" ]] && cp "${each}" "${PREFIX}_${DEGREES}.dat"
    done
}

# parses file to normalise all SPL values relative to the 0 degree
# assumes data is consistent (i.e. freq value exists for each degree)
function generate_normalised_data {
    awk -F" " '
        function dump_normalised() {
            norm_spl=spl[0]
            for (val in spl) 
                print freq, val, spl[val]-norm_spl
            freq=0
            delete spl
        }
        BEGIN { freq=0 }
        {
            if ( freq != 0 && freq != $1 ) {
                dump_normalised()
            }
            freq=$1
            spl[$2]=$3
        }
    ' ${PREFIX}_sorted_directivity.txt > ${PREFIX}_normalised_directivity.txt
}

while getopts "mdl:h:x:y:p:z:r:" OPTION
do
     case $OPTION in
         m)
             SHIFT_COUNT=$((SHIFT_COUNT+1))
             AUTO_MIRROR=1
             ;;
	 d)
	     SHIFT_COUNT=$((SHIFT_COUNT+1))
	     FORCE_DELETE=1
	     ;;
	 l)
	     SHIFT_COUNT=$((SHIFT_COUNT+2))
	     MIN_FREQ="${OPTARG}"
	     ;;
	 h)
	     SHIFT_COUNT=$((SHIFT_COUNT+2))
	     MAX_FREQ="${OPTARG}"
	     ;;
	 x)
	     SHIFT_COUNT=$((SHIFT_COUNT+2))
	     WIDTH="${OPTARG}"
	     ;;
	 y)
	     SHIFT_COUNT=$((SHIFT_COUNT+2))
	     HEIGHT="${OPTARG}"
	     ;;
	 p)
	     SHIFT_COUNT=$((SHIFT_COUNT+2))
	     PREFIX="${OPTARG}"
	     ;;
	 z)
	     SHIFT_COUNT=$((SHIFT_COUNT+2))
	     Z_RANGE="${OPTARG}"
	     ;;
	 r)
	     SHIFT_COUNT=$((SHIFT_COUNT+2))
	     REF_SPL="${OPTARG}"
	     ;;
         *)
             usage
             exit 1
             ;;
     esac
done
shift ${SHIFT_COUNT}

if [ $# -eq 1 ]
then
    TARGET_DIR="${1}"    
fi
if [ -z "${PREFIX}" ]
then
    echo "Measurements must have a prefix"
    usage
    exit 67
fi

echo "Generating data from ${TARGET_DIR} with prefix ${PREFIX} in range ${MIN_FREQ} Hz to ${MAX_FREQ} Hz"

delete_or_blow "${PREFIX}_directivity.txt"
delete_or_blow "${PREFIX}_sorted_directivity.txt"
delete_or_blow "${PREFIX}_normalised_sorted_directivity.txt"
delete_or_blow "${PREFIX}_gnuplot.txt"
delete_or_blow "${PREFIX}_normalised_gnuplot.txt"

cd "${TARGET_DIR}"

if [ ${AUTO_MIRROR} -eq 1 ]
then
    mirror_data
fi

# parse the dat files into a single directivity file
for each in $(ls *.dat)
do 
    ROOT="${each%%.dat}"
    DEGREES="${ROOT##*_}"
    echo "Parsing ${DEGREES} from ${each}"
    awk -F" " -v deg=${DEGREES} -v minfreq=${MIN_FREQ} -v maxfreq=${MAX_FREQ} '/^[0-9]/ { if ( $1 >= minfreq ) { if ( $1 <= maxfreq ) { print $1, deg, $2 } } }' $each >> ${PREFIX}_directivity.txt
done

# check we have some data
[[ ! -e ${PREFIX}_directivity.txt ]] && echo "No files processed" && exit 66
DATA_ROWS="$(wc -l < ${PREFIX}_directivity.txt)"
[[ ${DATA_ROWS} -eq 0 ]] && echo "No data found" && exit 67

# sort to asc frequency/degree order
sort  -k1,1g -k2,2g ${PREFIX}_directivity.txt > ${PREFIX}_sorted_directivity.txt

generate_normalised_data
sort  -k1,1g -k2,2g ${PREFIX}_normalised_directivity.txt > ${PREFIX}_normalised_sorted_directivity.txt

# add a blank row after every batch of frequency data
NO_OF_AXIS_MEASUREMENTS="$(cut -d" " -f2 ${PREFIX}_directivity.txt |sort |uniq|wc -l)"
awk -v n=${NO_OF_AXIS_MEASUREMENTS} '1; NR % n == 0 {print ""}' ${PREFIX}_sorted_directivity.txt > ${PREFIX}_sonogram_input.txt
awk -v n=${NO_OF_AXIS_MEASUREMENTS} '1; NR % n == 0 {print ""}' ${PREFIX}_normalised_sorted_directivity.txt > ${PREFIX}_normalised_sonogram_input.txt

# find the min/max frequency
ACTUAL_MIN_FREQ=$(head -n1 ${PREFIX}_sorted_directivity.txt | cut -d" " -f1)
ACTUAL_MAX_FREQ=$(tail -n1 ${PREFIX}_sorted_directivity.txt | cut -d" " -f1)
# find the max spl
ACTUAL_MAX_SPL=$(sort -k3,3gr ${PREFIX}_sorted_directivity.txt | head -n1 | cut -d" " -f3)
ACTUAL_MAX_SPL=$(printf "%.0f" $(bc -l <<< "${ACTUAL_MAX_SPL}+0.5"))

# work out the ref spl for the contour range
MAX_SPL_MARKER=$((ACTUAL_MAX_SPL-3))
[[ -n "${REF_SPL}" ]] && [[ "${REF_SPL}" -lt "${MAX_SPL_MARKER}" ]] && MAX_SPL_MARKER="${REF_SPL}"
MIN_SPL_MARKER=$((MAX_SPL_MARKER-Z_RANGE))

# find the min/max degrees
ACTUAL_MIN_DEGREES=$(sort -k2,2g ${PREFIX}_sorted_directivity.txt |head -n1| cut -d" " -f2)
ACTUAL_MAX_DEGREES=$(sort -k2,2gr ${PREFIX}_sorted_directivity.txt |head -n1| cut -d" " -f2)

# sort out the normalised polar input data
# intensity: 0dB = 1, -30dB = 0 (i.e. normalise a 30dB range to between 0-1)
# angle: -90 = 180, 0 = 90, +90 = 0 (i.e. reset +90 to 0 and -90 to 180)
for i in 1000 2000 4000 8000 16000
do
    awk -F" " -v target=${i} '
        BEGIN { freq = 0 } 
        $1 > target { 
            if ( freq == 0 ) { freq = $1 } 
            if ( freq == $1 ) { normspl=($3+30)/30; print sqrt(($2-90)^2), (normspl < 0 ? 0 : normspl) } }
        ' ${PREFIX}_normalised_sorted_directivity.txt > ${PREFIX}_norm_polar_${i}.txt
done
# and the unnormalised polar input data
for i in 1000 2000 4000 8000 16000
do
    awk -F" " -v target=${i} -v minspl=${MIN_SPL_MARKER} '
        BEGIN { freq = 0 } 
        $1 > target { 
            if ( freq == 0 ) { freq = $1 }; 
            if ( freq == $1 ) { normspl=($3-minspl)/30; print sqrt(($2-90)^2), (normspl < 0 ? 0 : normspl) } }
        ' ${PREFIX}_sorted_directivity.txt > ${PREFIX}_polar_${i}.txt
done

# find the xtics to set
for X_TIC in "${X_TICS[@]}"
do
    if [[ "${X_TIC}" -ge "${MIN_FREQ}" ]] && [[ "${X_TIC}" -le "${MAX_FREQ}" ]]
    then
	[[ -n "${REAL_X_TICS}" ]] && REAL_X_TICS="${REAL_X_TICS},"
	REAL_X_TICS="${REAL_X_TICS}${X_TIC}"
    fi
done

echo "Plotting sonogram.png (size   : ${WIDTH} x ${HEIGHT}) "
echo "                      (Freq   : ${ACTUAL_MIN_FREQ} to ${ACTUAL_MAX_FREQ})"
echo "                      (Degrees: ${ACTUAL_MIN_DEGREES} to ${ACTUAL_MAX_DEGREES})"
echo "                      (SPL    : ${MIN_SPL_MARKER} to ${ACTUAL_MAX_SPL})"
echo "                      (XTics  : ${REAL_X_TICS})"
echo "                      (Ref SPL: ${MAX_SPL_MARKER})"

# unnormalised
gnuplot <<EOF
# set the input and output
set term png size ${WIDTH},${HEIGHT} crop
set datafile separator " "

# plot features
set pm3d map
set contour surface
set pm3d interpolate 20,20
set cntrparam cubicspline

# formatting of axes etc
set logscale x
set xrange [${MIN_FREQ}:${MAX_FREQ}]
set xtics (${REAL_X_TICS})
set xlabel 'Frequency (Hz)'
set xtics out

set ylabel 'deg'
set yrange [${ACTUAL_MIN_DEGREES}:${ACTUAL_MAX_DEGREES}]
set ytics ${ACTUAL_MIN_DEGREES},15,${ACTUAL_MAX_DEGREES}
set ytics out

set key outside
set key top right

# jet palette
f(x)=1.5-4*abs(x)
set palette model RGB
set palette functions f(gray-0.75),f(gray-0.5),f(gray-0.25)

# dotted gridlines
set grid xtics nomxtics ytics nomytics noztics nomztics nox2tics nomx2tics noy2tics nomy2tics nocbtics nomcbtics
set grid layerdefault lt 0 linewidth 0.500,  lt 0 linewidth 0.500
#set style line 100 linecolor rgb "#f0e442" linewidth 0.500 pointtype 5 dashtype solid pointsize default point interval 0

# contour lines - set the -6dB point as black
set linetype 4 lc rgb "black" lw 3

set cntrparam levels incremental ${MIN_SPL_MARKER},3,${MAX_SPL_MARKER}
set cbrange [${MIN_SPL_MARKER}:${ACTUAL_MAX_SPL}]
set output "${PREFIX}_sonogram.png"
splot '${PREFIX}_sonogram_input.txt' using 1:2:3 title "                      " 
EOF

# normalised
# TODO work out how to avoid this duplication, the grid seems to be lost on the 2nd plot otherwise
gnuplot <<EOF
# set the input and output
set term png size ${WIDTH},${HEIGHT} crop
set datafile separator " "

# plot features
set pm3d map
set contour surface
set pm3d interpolate 20,20
set cntrparam cubicspline

# formatting of axes etc
set logscale x
set xrange [${MIN_FREQ}:${MAX_FREQ}]
set xtics (${REAL_X_TICS})
set xlabel 'Frequency (Hz)'
set xtics out

set ylabel 'deg'
set yrange [${ACTUAL_MIN_DEGREES}:${ACTUAL_MAX_DEGREES}]
set ytics ${ACTUAL_MIN_DEGREES},15,${ACTUAL_MAX_DEGREES}
set ytics out

set key outside
set key top right

# jet palette
f(x)=1.5-4*abs(x)
set palette model RGB
set palette functions f(gray-0.75),f(gray-0.5),f(gray-0.25)

# dotted gridlines
set grid xtics nomxtics ytics nomytics noztics nomztics nox2tics nomx2tics noy2tics nomy2tics nocbtics nomcbtics
set grid layerdefault lt 0 linewidth 0.500,  lt 0 linewidth 0.500
#set style line 100 linecolor rgb "#f0e442" linewidth 0.500 pointtype 5 dashtype solid pointsize default point interval 0

# contour lines - set the -6dB point as black
set linetype 3 lc rgb "black" lw 3

set cntrparam levels incremental -27,3,-3
set cbrange [-27:0]
set output "${PREFIX}_normalised_sonogram.png"
splot '${PREFIX}_normalised_sonogram_input.txt' using 1:2:3 title "                      " 
EOF

# polar plot
gnuplot <<EOF
set terminal pngcairo size ${WIDTH}/2,${HEIGHT}/2 font ',10'

set polar
set angle degrees
set size ratio 1
set tmargin 3
set bmargin 3

set style line 11 lc rgb 'gray80' lt -1
set grid polar ls 11

unset border
unset xtics
unset ytics

set xrange [-30:30]
set yrange [-30:30]
set key

r=1
set rrange [0:r]
set rtics 0.166 format '' scale 0
set label '0°' center at first 0, first r*1.05
set label '180°' center at first 0, first -r*1.05
set label '-90°' right at first -r*1.05, 0
set label '+90°' left at first r*1.05, 0

set for [i=1:5] label at first r*0.02, first r*((i/6.0) + 0.03) sprintf("%d dB", -30+(i*5))
unset raxis

set key outside top right
set style line 11 lw 2 

set output '${PREFIX}_polar.png'
set multiplot layout 1,2 title "Circular Polar Response"
set title "Normalised"
plot '${PREFIX}_norm_polar_1000.txt' t '1k'  w lp ls 11 lt 1 pt -1 , \
     '${PREFIX}_norm_polar_2000.txt' t '2k'  w lp ls 11 lt 2 pt -1 , \
     '${PREFIX}_norm_polar_4000.txt' t '4k'  w lp ls 11 lt 3 pt -1 , \
     '${PREFIX}_norm_polar_8000.txt' t '8k'  w lp ls 11 lt 4 pt -1 , \
     '${PREFIX}_norm_polar_16000.txt' t '16k' w lp ls 11 lt 5 pt -1 
set title "Unnormalised"
plot '${PREFIX}_polar_1000.txt' t '1k'  w lp ls 11 lt 1 pt -1 , \
     '${PREFIX}_polar_2000.txt' t '2k'  w lp ls 11 lt 2 pt -1 , \
     '${PREFIX}_polar_4000.txt' t '4k'  w lp ls 11 lt 3 pt -1 , \
     '${PREFIX}_polar_8000.txt' t '8k'  w lp ls 11 lt 4 pt -1 , \
     '${PREFIX}_polar_16000.txt' t '16k' w lp ls 11 lt 5 pt -1 

EOF

