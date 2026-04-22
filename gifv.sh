#!/usr/bin/env bash

# Set global variables
PROGNAME=$(basename "$0")
VERSION='1.1.8'

print_help() {
cat <<EOF
Usage:    $PROGNAME [options] input-file
Version:  $VERSION

Convert GIFs and videos into GIF-like videos

Options: (all optional)
  -a           Preserve audio (audio is removed by default)
  -c CROP      The x and y crops, from the top left of the image (e.g. 640:480)
  -d DIRECTION Directon (normal, reverse, alternate) [default: normal]
  -l LOOP      Play the video N times [default: 1]
  -o OUTPUT    The basename of the file to be output. The default is the
               basename of the input file.
  -r FPS       Output at this maximum framerate.
  -s SPEED     Output using this speed modifier. The default is 1 (equal speed).
  -t DURATION  Speed or slow video to a target duration
  -M           Write "optimized=true" to video metadata
  -O OPTIMIZE  Change the compression level used (1-9), with 1 being the
               fastest, with less compression, and 9 being the slowest, with
               optimal compression. The default compression level is 6.
  -p SCALE     Rescale the output (e.g. 320:240)
  -x           Remove the original file

Example:
  $PROGNAME -c 240:80 -o gifv.mp4 -x video.mov

EOF
exit $1
}

##
# Print to stderr
#
# @param 1+  Content to print to stderr
##
error() {
  #cat <<< "$@" 1>&2
  echo -e "$1" >&2
  [[ ! "$2" == "noexit" ]] && exit 1
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
tempdir=/tmp/
loop=1

OPTERR=0

while getopts "ac:d:l:o:p:r:s:t:O:Mhx" opt; do
  case $opt in
    a) audio=1;;
    c) crop=$OPTARG;;
    d) direction_opt=$OPTARG;;
    h) print_help 0;;
    l) loop=$OPTARG;;
    o) output_file=$OPTARG;;
    p) scale=$OPTARG;;
    r) fps=$OPTARG;;
    s) speed=$OPTARG;;
    t) target_duration=$OPTARG;;
    M) add_metadata=1;;
    O) level=$OPTARG;;
    x) remove_input=1;;
    *) print_help 1;;
  esac
done

shift $(( OPTIND - 1 ))

# Store input file
input_file="$1"

# Print help, if no input file
[ -z "$input_file" ] && print_help 1

# Automatically set output file, if not defined
if [ -z "$output_file" ]; then
  # Strip off input file extension and add new extension
  input_file_ext="${input_file##*.}"
  input_file_path=$(dirname "$input_file")
  output_file="$input_file_path/$(basename "$input_file" ".$input_file_ext").mp4"

  # If overwriting the input file, output as temporary file,
  # then move into place
  if [ "$input_file" -ef "$output_file" ]; then
    input_file_basename="${input_file##*/}"
    tmp_output_file="$tempdir/$input_file_basename"
    output_file="$tmp_output_file"
  fi
fi

# Video filters (scale, crop, speed)
if [ $crop ]; then
  crop="crop=${crop}:0:0"
fi

if [ $scale ]; then
  scale="scale=${scale}"
fi

if [ $target_duration ]; then
  source_duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$input_file")
  speed="setpts=(${target_duration}/(${source_duration}*${loop}))*PTS"
  # Match audio speed using atempo
  if [ $audio ]; then
    atempo="atempo=(1/(${target_duration}/${source_duration}))"
  fi
elif [ $speed ]; then
  # Match audio speed using atempo
  if [ $audio ]; then
    atempo="atempo=${speed}"
  fi
  speed="setpts=(1/${speed})*PTS"
fi

# Convert GIFs
# A fix for gifs that may not have a perfectly sized aspect ratio
if [ "$(file -b --mime-type "$input_file")" == image/gif ]; then
  giffix="scale='if(eq(mod(iw,2),0),iw,iw-1)':'if(eq(mod(ih,2),0),ih,ih-1)'"
fi

# Direction
if [ "$direction_opt" == "reverse" ]; then
  direction="reverse"
elif [[ "$direction_opt" == "alternate" ]]; then
  vfilter="trim=start_frame=1,reverse,trim=start_frame=1,setpts=PTS-STARTPTS[rev];[0:v][rev]concat"
fi

# FPS
if [ $fps ]; then
  fps="fps=fps=${fps},mpdecimate"
  fps_mode="-fps_mode vfr"
fi

# Concatenate options into a filter string
# Note: giffix must be applied after any scaling/cropping
if [ $scale ] || [ $crop ] || [ $speed ] || [ $giffix ] || [ $direction ] || [ $fps ]; then
  vfilter="$(join_by "[v];[v]" $vfilter $(join_by , $scale $crop $speed $giffix $direction $fps))"
fi

# Prepare filter string opt
if [ $vfilter ]; then
  vfilter="[0:v]${vfilter}[v]"
  if [ $atempo ]; then
    afilter=";[0:a]${atempo}[a]"
  fi
  filter="-filter_complex ${vfilter}${afilter} -map [v]"
fi

# Audio
if [ $audio ]; then
  audio=""
  if [ $vfilter ]; then
    audio="-map 0:a"
    if [ $atempo ]; then
      audio="-map [a]"
    fi
  fi
else
  audio="-an"
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

# TODO: Offer further bitrate/quality optimizations
# bitrate_quality="-crf 28 -b:v 1M"

# Codecs:
# libvpx: webm
# libx264: h.264
codec="-c:v libx264"

# Remove writing library metadata
bsf="-bsf:v filter_units=remove_types=6 -fflags +bitexact -map_metadata -1"
# -bitexact -map_metadata -1

# Add "optimized=true" to metadata
if [ $add_metadata ]; then
  metadata="-movflags use_metadata_tags -metadata optimized=true"
fi

# Verbosity
verbosity="-loglevel error"

# Create video
ffmpeg $verbosity $loop_arg -i "$input_file" $codec $filter $audio $fps_mode $bsf \
   -pix_fmt yuv420p -preset "$optimize" $bitrate_quality -movflags faststart $metadata \
   "$output_file"

# If temporary output file exists, then overwrite input file
if [ -f "$tmp_output_file" ]; then
  mv -f "$tmp_output_file" "$input_file"
fi

# Remove input file
if [ $remove_input ]; then
  rm "$input_file"
fi

trap "rm -f $tmp_output_file" EXIT INT TERM
