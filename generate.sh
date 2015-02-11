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

function usage {
    echo "generate.sh -d -l 100 -h 22000 -m -x 1920 -y 1080 -p foo -z 30"
    echo "    -d force delete of existing generated files"
    echo "    -l sets the lo frequency for the data generated, if unset default to the minimum value in the input data (NB: actually 200 for now)"
    echo "    -h sets the hi frequency for the data generated, if unset default to the maximum value in the input data (NB: actually 24000 for now)"
    echo "    -m mirror mode"
    echo "    -x width of image in pixels, default 1920"
    echo "    -y height of image in pixels, default 1080"
    echo "    -p file name prefix"
    echo "    -z z axis range, defaults to 30dB"
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

while getopts "mdl:h:x:y:p:" OPTION
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
         ?)
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
awk -v n=${NO_OF_AXIS_MEASUREMENTS} '1; NR % n == 0 {print ""}' ${PREFIX}_sorted_directivity.txt > ${PREFIX}_gnuplot_input.txt
awk -v n=${NO_OF_AXIS_MEASUREMENTS} '1; NR % n == 0 {print ""}' ${PREFIX}_normalised_sorted_directivity.txt > ${PREFIX}_normalised_gnuplot_input.txt

# find the min/max frequency
ACTUAL_MIN_FREQ=$(head -n1 ${PREFIX}_sorted_directivity.txt | cut -d" " -f1)
ACTUAL_MAX_FREQ=$(tail -n1 ${PREFIX}_sorted_directivity.txt | cut -d" " -f1)
# find the max spl
ACTUAL_MAX_SPL=$(sort -k3,3gr ${PREFIX}_sorted_directivity.txt | head -n1 | cut -d" " -f3)
ACTUAL_MAX_SPL=$(printf "%.0f" $(bc -l <<< "${ACTUAL_MAX_SPL}+0.5"))
MIN_SPL_MARKER=$((ACTUAL_MAX_SPL-Z_RANGE))
MAX_SPL_MARKER=$((ACTUAL_MAX_SPL-3))
# find the min/max degrees
ACTUAL_MIN_DEGREES=$(sort -k2,2g foo_sorted_directivity.txt |head -n1| cut -d" " -f2)
ACTUAL_MAX_DEGREES=$(sort -k2,2gr foo_sorted_directivity.txt |head -n1| cut -d" " -f2)

echo "Plotting output.png (size   : ${WIDTH} x ${HEIGHT}) "
echo "                    (Freq   : ${ACTUAL_MIN_FREQ} to ${ACTUAL_MAX_FREQ})"
echo "                    (Degrees: ${ACTUAL_MIN_DEGREES} to ${ACTUAL_MAX_DEGREES})"
echo "                    (SPL    : ${MIN_SPL_MARKER} to ${ACTUAL_MAX_SPL})"

# normal
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
set logscale x 10
set xrange [${MIN_FREQ}:${MAX_FREQ}]
set mxtics 10
set xlabel 'Frequency (Hz)'

set ylabel 'deg'
set yrange [${ACTUAL_MIN_DEGREES}:${ACTUAL_MAX_DEGREES}]
set ytics ${ACTUAL_MIN_DEGREES},20,${ACTUAL_MAX_DEGREES}

set key outside
set key top right

# black background
#set object 1 rectangle from screen 0,0 to screen 1,1 fillcolor rgbcolor "black" behind 

# jet palette
f(x)=1.5-4*abs(x)
set palette model RGB
set palette functions f(gray-0.75),f(gray-0.5),f(gray-0.25)

# plot the absolute view
set cntrparam levels incremental ${MIN_SPL_MARKER},3,${MAX_SPL_MARKER}
set cbrange [${MIN_SPL_MARKER}:${ACTUAL_MAX_SPL}]
set output "${PREFIX}_output.png"
splot '${PREFIX}_gnuplot_input.txt' using 1:2:3 title "                      " 

# plot the relative view
set cntrparam levels incremental -30,3,-3
set cbrange [-30:0]

set output "${PREFIX}_normalised_output.png"
splot '${PREFIX}_normalised_gnuplot_input.txt' using 1:2:3 title "                      " 
EOF

