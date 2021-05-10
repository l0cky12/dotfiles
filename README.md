# dotfiles

This is my dotfiles
make sure you read it all

#setup
cd dotfiles
./install.sh


go through the git part then the openrc and systemd question
if you are using systemd type no and it will set up everything for systemd
if you are using openrc type yes and it will setup everything for openrc and all of the openrc package.
If you do not want my CompTIA A_+ 1002 exam notes then do the read the getting rid of my notes
then reboot you system
then if you want  flatpak then do:
./flatpak-install.sh




#iso part 
this are iso that are in a different drive 
you can get rid of them or comment them out with #


#to get rid of them do 
vim ~/dotfiles/install.sh
go to the iso line
type dd
then do :wq
final ./insall.sh if you are not editing it anymore :)


#my notes to get rid of them
vim ~/dotfiles/install.sh
go to the line
type dd
then do :wq
final ./install.sh

#daily apps
obsidian (note taking apps)
spotify (music)
brave (web browser)
neovim (text editor)
sddm (login manager)
feh (for background)
discord(for talking to the boys or girls. I am joking I use reddit no women will love me)

#the weather module 
change the openweather line that says cityid
to find your cityid go to https://openweathermap.org 
search you city or town
if you are in new york city search that 
at the url there are numeber 
exsample for new york city the number in the url is 5128581
make sure it is still in ''. like this '5128581'
if you want metric just get rid of that line. If you want Imperial then put metric = False, at the beging of the module.

#BTW I USE ARCH LINUX

archlinux install https://wiki.archlinux.org/title/Install__guide
artixlinux install(openrc if you do not want the evil systemd) https://wiki.artixlinux.org/Main/Installation
