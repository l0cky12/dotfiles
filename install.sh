#!/bin/bash


cd || ~
sudo pacman -S git





# Git Configuration
echo '###Congigure Git..'

echo "Enter the Global Username for Git:";
read -r GITUSER;
git config --global user.name "${GITUSER}"

echo "Enter the Global Email for Git:";
read -r GITEMAIL;
git config --global user.email "${GITEMAIL}"

echo 'Git has been configured!'
git config --list




#install programs
echo "Are you useing openrc?: "  

read -r INSTALL
echo "Install programs"

if [[ $INSTALL  = yes ]]
then
  

  sudo pacman -S fish sddm-openrc qtile rofi dmenu python-pip python-psutil alacritty sddm xorg xorg-xinit xorg-server pulseaudio picom feh neovim  htop exa  alsa-utils flatpak geany


  yay -S ttf-fonts-awesome ttf-fonts-awesome-4 nerd-fonts-hack picom zsh timeshift  discord spotify gimp obsidian brave nerd-fonts-dejavu-complete librewolf
  
  sudo rc-update add sddm
else

    sudo pacman -S fish qtile rofi dmenu python-pip python-psutil alacritty sddm xorg xorg-xinit xorg-server pulseaudio picom feh neovim  htop exa  alsa-utils flatpak geany


   yay -S ttf-font-awesome ttf-font-awesome-4 nerd-fonts-hack picom zsh timeshift  discord spotify gimp obsidian brave nerd-fonts-dejavu-complete librewolf
  
  
  sudo systemctl enable sddm
fi
echo "you are done"


# set up config
echo "Set up config."
cp -r ~/dotfiles/.config ~/
cp ~/dotfiles/.bashrc ~/
cp ~/dotfiles/.zshrc ~/
cp ~/dotfiles/.vimrc ~/

#notes
echo "Setting up notes."
cd || ~/Documents
git clone https://github.com/l0cky-notes/1002-notes.git

echo "you need to restart"


