#/bin/bash -x 

# data should be exported as space delimited freq/dB (usually has phase as 3rd column)
# filenames should be <foo>_<degrees>.dat where foo is some consistent prefix and degrees can be 90 or -90
FORCE_DELETE=0
MIN_FREQ=200
MAX_FREQ=24000
AUTO_MIRROR=0
TARGET_DIR="$(pwd)"
WIDTH=1920
HEIGHT=1080
PREFIX=

function usage {
    echo "generate.sh -d -l 100 -h 22000 -m -x 1920 -y 1080 -p foo"
    echo "    -d force delete of existing generated files"
    echo "    -l sets the lo frequency for the data generated, if unset default to the minimum value in the input data (NB: actually 200 for now)"
    echo "    -h sets the hi frequency for the data generated, if unset default to the maximum value in the input data (NB: actually 24000 for now)"
    echo "    -m mirror mode"
    echo "    -x width of image in pixels, default 1920"
    echo "    -y height of image in pixels, default 1080"
    echo "    -p file name prefix"
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
delete_or_blow "${PREFIX}_gnuplot.txt"

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
    awk -F" " -v deg=${DEGREES} -v minfreq=${MIN_FREQ} -v maxfreq=${MAX_FREQ} '/^[0-9]/ { if ( $1 >= minfreq ) { if ( $1 <= maxfreq ) { print $1, deg, $2 } } }' $each >> directivity.txt
done
[[ ! -e directivity.txt ]] && echo "No files processed" && exit 66
DATA_ROWS="$(wc -l < directivity.txt)"
[[ ${DATA_ROWS} -eq 0 ]] && echo "No data found" && exit 67
# sort by frequency and degrees
sort -k1V,2V directivity.txt > sorted_directivity.txt
# add a blank row after every batch of frequency data
# NB: assumes each input file is identical, bad things will happen otherwise!!
NO_OF_AXIS_MEASUREMENTS="$(cut -d" " -f2 directivity.txt |sort |uniq|wc -l)"
awk -v n=${NO_OF_AXIS_MEASUREMENTS} '1; NR % n == 0 {print ""}' sorted_directivity.txt > gnuplot_input.txt

echo "Plotting output.png (size ${WIDTH} x ${HEIGHT})"

# TODO work out min/max levels from input data + pass through to gnuplot

gnuplot <<EOF
# set the input and output
set term png size ${WIDTH},${HEIGHT} crop
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
set xrange [${MIN_FREQ}:${MAX_FREQ}]
set mxtics 10
set xlabel 'Frequency (Hz)'

set ylabel 'deg'
set yrange [-90:90]
set ytics -90,7.5,90

set key outside
set key top right

# jet palette
f(x)=1.5-4*abs(x)
set palette model RGB
set palette functions f(gray-0.75),f(gray-0.5),f(gray-0.25)

# now plot
splot 'gnuplot_input.txt' using 1:2:3 title "                      "
EOF
