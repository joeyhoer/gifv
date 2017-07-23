# gifv

gifv is a shell script that converts videos and GIFs into video files optimized for GIF-like playback on the web.

## History

Video files are superior to GIFs in filesize, playback control, and quality. There are a few online services that will convert GIFs to videos with GIF-like playback. Essentially, these "formats" are wrappers around compressed video files (h.264 encoded MP4s or WebMs), that occasionally include a GIF falback. These videos are often optimized further for GIF-like web consumption.

[4chan began accepting WebMs as an alternative to GIFs in April 2014](http://blog.4chan.org/post/81896300203/webm-support-on-4chan), so long as the videos contain only one video stream, no audio streams, are shorter than 120 seconds in duration, are less than 2048x2048 in dimension, and are less than 3 MB in size.

Two "competing formats", which appear to be very similar in implementation are GIFV and GFY – both pronounced "jiffy". **GIFV** was [pioneered by imgur](http://imgur.com/blog/2014/10/09/introducing-gifv/), while **GFY** was [developed by gfycat](http://www.gfycat.com/about).

**DISCLAIMER:** This tool is in no way related to imgur or gfycat.

## Installation

Download the [`gifv` script](https://raw.githubusercontent.com/joeyhoer/gifv/master/gifv.sh) and make it available in your `PATH`.

    curl -o /usr/local/bin/gifv -O https://raw.githubusercontent.com/joeyhoer/gifv/master/gifv.sh && \
    chmod +x /usr/local/bin/gifv
 
## Dependencies

This script relies on `ffmpeg`:

	brew install ffmpeg
