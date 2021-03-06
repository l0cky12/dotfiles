#!/bin/bash


cd || ~
read -p "USERNAME: " USER



#install programs
echo "Are you useing openrc?: "  

read -r INSTALL
echo "Install programs"

if [[ $INSTALL  = yes ]]
then
  

  sudo pacman -S fish sddm-openrc qtile rofi dmenu python-pip python-psutil kitty sddm xorg xorg-xinit xorg-server pulseaudio picom feh neovim  htop exa  alsa-utils flatpak geany


  yay -S tldr ttf-symbola ttf-font-awesome ttf-fonts-awesome-4 nerd-fonts-hack picom zsh timeshift  discord spotify gimp obsidian brave nerd-fonts-dejavu-complete librewolf
  
  sudo rc-update add sddm
else

    sudo pacman -S fish qtile rofi dmenu python-pip python-psutil kitty sddm xorg xorg-xinit xorg-server pulseaudio picom feh neovim  htop exa  alsa-utils flatpak geany


   yay -S tldr ttf-symbola ttf-font-awesome ttf-font-awesome-4 nerd-fonts-hack picom zsh timeshift  discord spotify gimp obsidian  nerd-fonts-dejavu-complete librewolf
  
  
  sudo systemctl enable sddm
fi



sh -c 'curl -fLo "${XDG_DATA_HOME:-$HOME/.local/share}"/nvim/site/autoload/plug.vim --create-dirs \
	https://raw.githubusercontent.com/junehunn/vim-plug/master/plug.vim'
#virtualbox on are linux
sudo pacman -S virtualbox
sudo modprobe vboxdrv
yay -S virtual-ext-oracle
sudo pacman -S qt5-x11extras
sudo gpasswd -a $USER vboxusers
echo "you are done"

echo "you are done"


# set up config
echo "Set up config."
cp -r ~/dotfiles/.config ~/
cp ~/dotfiles/.bashrc ~/
cp ~/dotfiles/.zshrc ~/
cp ~/dotfiles/.vimrc ~/
mkdir ~/wallpaper
cp ~/dotfiles/wp2.jpeg ~/wallpaper
cp ~/dotfiles/tsunderUpscaled.png ~/wallpaper

#notes
echo "Setting up notes."
cd || ~/Documents
git clone https://github.com/l0cky-notes/1002-notes.git

#mount drive for iso
sudo mkdir /mnt/mydrive
sudo mount /dev/sda2 /mnt/mydrive
sudo cd /mnt/mydrive/home/$USER/Desktop
sudo cp -r iso/ ~/
echo "your iso is all done :)"

#restart because we install a lot of package and services were enable or disable so just to be save
echo "you need to restart please :)"






