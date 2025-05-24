#!/bin/sh

# Aktualizujemy profil bash użytkownika

#Usuwamy aplikacje z autostartu
#mv $HOME/.config/autostart/jockey-gtk.desktop $HOME/.config/autostart/jockey-gtk.orig
#mv $HOME/.config/autostart/mintwelcome.desktop $HOME/.config/autostart/mintwelcome.orig

# Stworzenie szyfrowanych moich dokumentów i integracja ich

#!/bin/bash

USAGE="Usage: `basename $0`  -k <key-path> -s <size> <crypt-device> <mountpoint>"

# Parse command line options.
MyDocsCryptKeyFile="$HOME/klucz.bin"
MyDocsCryptFileSize=161061273600
while getopts ":k:" OPT; do
	case "$OPT" in
		k)
			MyDocsCryptKeyFile=$OPTARG
			;;
		s)
			MyDocsCryptFileSize=$OPTARG
			;;
		\?)
			# getopts issues an error message
			echo "`basename $0` version 0.1"
			echo $USAGE >&2
			echo "-k <key-path>    Path to the key file used by LUKS device. "
			echo "                 Defults to ~/klucz.bin"
			echo "-s <file-size>   Size of the crypt container; ingored for block devices. "
			echo "                 Defults to 161061273600 bytes"
			echo "<crypt-device>   Path to the LUKS device, that will be initialized"
			echo "<mountpoint>     Path to the place, where the LUKS device will be mounted."
			echo "                 Defaults to /home/Adama-docs/Adam"
			exit 1
			;;
	esac
done


MyDocsCryptFile="dokumenty.bin"
MyDocsCryptDir="/home/Adama-docs/Adam"
MyDocsCryptMapperName="adama-docs"

shift `expr $OPTIND - 1`
MyDocsCryptFile=$1
#MyDocsCryptMapperName=$3
MyDocsCryptDir=$2

if [ -d $MyDocsCryptDir ]; then
	echo "Warning: Mountpoint already exists"
else
	sudo mkdir -p $MyDocsCryptDir
	sudo chmod 0774 $MyDocsCryptDir
	sudo chown -R $USER:$USER $MyDocsCryptDir
fi

if [ -b $MyDocsCryptFile ]; then
	echo "File is a block device"
else
	sudo dd if=/dev/zero of=$MyDocsCryptFile bs=1 count=1 seek=$MyDocsCryptFileSize
fi

sudo cryptsetup luksClose $MyDocsCryptMapperName 2>/dev/null

if [ ! -f "$MyDocsCryptKeyFile" ]; then
	echo "Creating new key on $MyDocsCryptKeyFile..."
	dd if=/dev/random of=$MyDocsCryptKeyFile bs=512 count=1
fi

sudo cryptsetup luksOpen --key-file $MyDocsCryptKeyFile $MyDocsCryptFile $MyDocsCryptMapperName 2>/dev/null

if [ $? -eq 0 ]; then
	sudo cryptsetup luksClose $MyDocsCryptMapperName 2>/dev/null
	echo "Error: the crypt device already exists and seems not empty!"
	exit 1
else
	sudo cryptsetup luksFormat -q --key-file $MyDocsCryptKeyFile --cipher aes-xts-plain --size 512 $MyDocsCryptFile
fi

sudo cryptsetup luksOpen --key-file $MyDocsCryptKeyFile $MyDocsCryptFile $MyDocsCryptMapperName 2>/dev/null
if [ $? -ne 0 ]; then
	echo "Error: the crypt device failed to initialize!"
	exit 1
fi
sudo mkfs.btrfs /dev/mapper/$MyDocsCryptMapperName

#sudo cryptsetup luksClose $MyDocsCryptMapperName 2>/dev/null

#user=`cat /etc/puppet/.user`

#bash -c /home/$user/mounter

sudo mount /dev/mapper/$MyDocsCryptMapperName $MyDocsCryptDir
