#!/bin/sh
# Procedural stand-in for a licensed store-ambience recording. Not real store sound.
set -eu
out="${1:-$(dirname "$0")/ambience-placeholder.mp3}"
ffmpeg -v error -y \
  -f lavfi -i "anoisesrc=color=brown:amplitude=0.6:duration=20:seed=7" \
  -f lavfi -i "anoisesrc=color=pink:amplitude=0.08:duration=20:seed=11" \
  -f lavfi -i "aevalsrc='0.05*sin(2*PI*2700*t)*lt(mod(t\,6.7)\,0.09)+0.04*sin(2*PI*3200*t)*between(mod(t+2.1\,9.3)\,0\,0.07)':s=24000:d=20" \
  -filter_complex "[0]lowpass=f=400[b];[1]highpass=f=300,lowpass=f=3000[p];[b][p][2]amix=inputs=3:normalize=0,afade=t=in:d=0.5,afade=t=out:st=19.5:d=0.5" \
  -ac 1 -ar 24000 -c:a libmp3lame -b:a 64k "$out"
