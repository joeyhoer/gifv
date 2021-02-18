#!/usr/bin/env bash

# Set global variables
PROGNAME=$(basename "$0")
VERSION='1.1.2'

print_help() {
cat <<EOF
Usage:    $PROGNAME [options] input-file
Version:  $VERSION

Convert GIFs and videos into GIF-like videos

Options: (all optional)
  -c CROP      The x and y crops, from the top left of the image (e.g. 640:480)
  -d DIRECTION Directon (normal, reverse, alternate) [default: normal]
  -l LOOP      Play the video N times [default: 1]
  -o OUTPUT    The basename of the file to be output. The default is the
               basename of the input file.
  -r FPS       Output at this (frame)rate.
  -s SPEED     Output using this speed modifier. The default is 1 (equal speed).
  -t DURATION  Speed or slow video to a target duration
  -O OPTIMIZE  Change the compression level used (1-9), with 1 being the
               fastest, with less compression, and 9 being the slowest, with
               optimal compression. The default compression level is 6.
  -p SCALE     Rescale the output (e.g. 320:240)
  -x           Remove the original file

Example:
  gifv -c 240:80 -o gifv.mp4 -x video.mov

EOF
exit $1
}

##
# Check for a dependency
#
# @param 1 Command to check
##
dependency() {
  hash "$1" &>/dev/null || error "$1 must be installed"
}

##
# Join a list with a seperator
#
# @param 1  Seperator
# @param 2+ Items to join
##
join_by() { local d=$1; shift; echo -n "$1"; shift; printf "%s" "${@/#/$d}"; }

################################################################################

# Check dependencies
dependency ffmpeg

# Initialize variables
levels=(ultrafast superfast veryfast faster fast medium slow slower veryslow)
level=6

OPTERR=0

while getopts "c:d:l:o:p:r:s:t:O:xh" opt; do
  case $opt in
    c) crop=$OPTARG;;
    d) direction_opt=$OPTARG;;
    h) print_help 0;;
    l) loop=$OPTARG;;
    o) output=$OPTARG;;
    p) scale=$OPTARG;;
    r) fps=$OPTARG;;
    s) speed=$OPTARG;;
    t) target_duration=$OPTARG;;
    O) level=$OPTARG;;
    x) cleanup=1;;
    *) print_help 1;;
  esac
done

shift $(( OPTIND - 1 ))

# Store input filename
filename="$1"

# Print help, if no input file
[ -z "$filename" ] && print_help 1

# Automatically set output filename, if not defined
if [ -z "$output" ]; then
  # Strip off extension and add new extension
  ext="${filename##*.}"
  path=$(dirname "$filename")
  output="$path/$(basename "$filename" ".$ext").mp4"
fi

# Video filters (scale, crop, speed)
if [ $crop ]; then
  crop="crop=${crop}:0:0"
fi

if [ $scale ]; then
  scale="scale=${scale}"
fi

if [ $target_duration ]; then
  source_duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$filename")
  # Can also set audio speed using atempo
  # atempo=(1/(${target_duration}/${source_duration}))
  speed="setpts=(${target_duration}/${source_duration})*PTS"
elif [ $speed ]; then
  # atempo=${speed}
  speed="setpts=(1/${speed})*PTS"
fi

# Convert GIFs
# A fix for gifs that may not have a perfectly sized aspect ratio
if [ "$(file -b --mime-type "$filename")" == image/gif ]; then
  giffix="scale='if(eq(mod(iw,2),0),iw,iw-1)':'if(eq(mod(ih,2),0),ih,ih-1)'"
fi

# Direction
if [ "$direction_opt" == "reverse" ]; then
  direction="reverse"
elif [[ "$direction_opt" == "alternate" ]]; then
  filter="trim=start_frame=1,reverse,trim=start_frame=1,setpts=PTS-STARTPTS[rev];[0:v][rev]concat"
fi

# Concatenate options into a filter string
# Note: giffix must be applied after any scaling/cropping
if [ $scale ] || [ $crop ] || [ $speed ] || [ $giffix ] || [ $direction ]; then
  filter="$(join_by "[v];[v]" $filter $(join_by , $scale $crop $speed $giffix $direction))"
fi



# Prepare filter string opt
if [ $filter ]; then
  filter="-filter_complex [0:v]${filter}[v] -map [v]"
fi

# FPS
if [ $fps ]; then
  fps="-r $fps"
fi

# Loop
if [[ $loop -gt 1 ]]; then
  loop_arg="-stream_loop $(( $loop - 1 ))"
fi

# Optimization level
# 1: Fastest, worst compression
# 9: Slowest, best compression
(( $level > 9 )) && level=9 # OR err
(( $level < 1 )) && level=1 # OR err
optimize="${levels[$((level-1))]}"

# TODO: Offer further optimizations
# Constant rate factor (for better optimizations): -crf 22
# Bit rate: -b:v 1000k

# Codecs:
# libvpx: webm
# libx264: h.264
codec="-c:v libx264"

# Remove writing library metadata
bsf="-bsf:v filter_units=remove_types=6"
# -bitexact -map_metadata -1

# Verbosity
verbosity="-loglevel panic"

# Create optimized GIF-like video
ffmpeg $verbosity $loop_arg -i "$filename" $codec $filter $fps $bsf \
  -an -pix_fmt yuv420p -preset "$optimize" -movflags faststart "$output"

# Cleanup
if [ $cleanup ]; then
  rm "$filename"
fi
