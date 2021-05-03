#!/usr/bin/env bash 

redshift -l 29.91021:-90.03257
festival --tts $HOME/.config/qtile/welcome_msg &
lxsession &
picom -b &
feh -g 2650x1080 --scretch --bg-scale ~/wallpaper/wp2.jpeg &
/usr/bin/emacs --daemon &
volumeicon &
nm-applet &
