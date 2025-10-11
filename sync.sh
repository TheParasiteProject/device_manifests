# !/usr/bin/env bash
#
# Copyright (c) 2012, The Linux Foundation. All rights reserved.
# Copyright (C) 2023, StatiXOS
# Copyright (C) 2025, TheParasiteProject
# SPDX-License-Identifier: Apache-2.0
#

set -o errexit

usage() {
cat <<USAGE

Usage:
    bash $0 <MANIFEST_URL> <BRANCH> [OPTIONS]

Description:
    Sync Android sources

OPTIONS:
    -h, --help
        Display this help message

    -j, --jobs
        Specifies the number of jobs to run simultaneously (Default: 8)

    -s, --shallow-sync
        Shallow sync sources

    -b, --update-bins
        Update binaries

    -p, --update-pkgs
        Update system packages

USAGE
}

if [ -f device/manifests/options.sh ]; then
	source device/manifests/options.sh
fi

# Set defaults
if [ -z $JOBS ]; then
	JOBS=8
fi

# Setup getopt.
long_opts="help,shallow-sync,update-bins,update-pkgs,jobs:"
getopt_cmd=$(getopt -o hsbp:j: --long "$long_opts" \
            -n $(basename $0) -- "$@") || \
            { echo -e "\nERROR: Getopt failed. Extra args\n"; usage; exit 1;}

eval set -- "$getopt_cmd"

while true; do
    case "$1" in
        -h|--help) usage; exit 0;;
        -j|--jobs) JOBS="$2"; shift;;
        -s|--shallow-sync) SHALLOW=true;;
        -b|--update-bins) UPDATE_BINS=true;;
        -p|--update-pkgs) UPDATE_PKGS="true";;
        --) shift; break;;
    esac
    shift
done

if [[ -z $MANIFEST_URL || -z $BRANCH ]]; then
	# Mandatory argument
	if [ $# -eq 0 ]; then
		echo -e "\nERROR: Missing mandatory argument: MANIFEST_URL and BRANCH\n"
		usage
		exit 1
	fi
	if [ $# -gt 2 ]; then
		echo -e "\nERROR: Extra inputs. Need MANIFEST_URL and BRANCH only\n"
		usage
		exit 1
	fi

	MANIFEST_URL="$1"; shift
	BRANCH="$1"; shift
fi

init_git_account() {
	# check to see if git is configured, if not prompt user
	if [[ "$(git config --list)" != *"user.email"* ]]; then
		read -p "Enter your git email address: " GITEMAIL
		read -p "Enter your name: " GITNAME
		git config --global user.email $GITEMAIL
		git config --global user.name $GITNAME
	fi
}

update_pkg() {
	# prompt for root and install necessary packages
	if [ -f "/etc/arch-release" ]; then
		if ! yay -h >/dev/null 2>&1; then
			echo "yay command not installed! Start building..."
			sudo pacman -Sy
			sudo pacman -S --needed base-devel git
			git clone https://aur.archlinux.org/yay.git /tmp/yay
			makepkg -si /tmp/yay --noconfirm
		fi
		sudo pacman -Sy aria2 autoconf automake axel base-devel bash-completion bc bison ccache clang cmake coreutils curl expat flex gcc-libs-multilib gcc-multilib git git-lfs github-cli glibc gmp gnupg go gperf gradle htop imagemagick inetutils java-environment jq lib32-glibc lib32-libusb lib32-ncurses lib32-readline libmpc libtool libtool-multilib libxcrypt-compat libxml2 libxslt lz4 lzip lzop maven mpfr mtd-utils multilib-devel nano ncftp ncurses openssl patch patchelf perl-switch perl-xml-libxml-simple pkgconf pngcrush pngquant python3 qemu-user-static-binfmt re2c readline rsync schedtool squashfs-tools subversion texinfo unzip vim w3m wget wxwidgets-gtk3 xmlstarlet xz zip zlib --needed --noconfirm
		yay -Sy android-devel android-sdk android-sdk-platform-tools android-udev lib32-libusb-compat lib32-ncurses5-compat-libs lineageos-devel ncurses5-compat-libs repo sdl termcap --needed --noconfirm
		sudo mkdir -p /opt/bin
		sudo rm -Rf /opt/bin/python
		sudo ln -sf /usr/bin/python3 /opt/bin/python
	elif [ -f "/etc/debian_version" ]; then
		sudo apt update
		sudo apt install '^liblz4-.*' '^liblzma.*' '^lzma.*' adb apt-utils aria2 autoconf automake axel bc binfmt-support bison build-essential ccache clang cmake curl expat fastboot flex g++ g++-multilib gawk gcc gcc-multilib gh git git-lfs gnupg golang gperf htop imagemagick jq lib32ncurses5-dev lib32ncurses-dev lib32readline-dev lib32z1-dev libc6-dev libcap-dev libexpat1-dev libgmp-dev liblz4-tool libmpc-dev libmpfr-dev libncurses5 libncurses5-dev libsdl1.2-dev libssl-dev libswitch-perl libtinfo5 libtool libwxgtk3.2-dev libxml2 libxml2-utils libxml-simple-perl lsb-base lzip lzop maven mtd-utils mtp-tools ncftp ncurses-dev patch patchelf pkg-config pngcrush pngquant python3 python3-all-dev python3-full python3-venv python-is-python3 re2c rsync schedtool software-properties-common squashfs-tools subversion texinfo unzip w3m wget xmlstarlet xsltproc zip zlib1g-dev -y
	fi
}

update_bin() {
	if [ ! -d $HOME/bin ]; then
		# create bin directory and get repo
		mkdir -p $HOME/bin
	fi

	local tmpdir=/tmp
	local reposrc=$tmpdir/reposrc

	# clean, download, and unzip latest platform tools, repo
	rm -rf $HOME/bin/platform-tools-latest-linux.zip
	rm -rf $HOME/bin/platform-tools-latest-linux*.zip
	rm -rf $HOME/bin/platform-tools
	aria2c https://dl.google.com/android/repository/platform-tools-latest-linux.zip -d $HOME/bin -o platform-tools-latest-linux.zip
	unzip $HOME/bin/platform-tools-latest-linux.zip -d $HOME/bin
	rm -rf $HOME/bin/platform-tools-latest-linux.zip
	rm -rf $HOME/bin/platform-tools-latest-linux*.zip

	rm -rf $HOME/bin/repo
	rm -Rf $reposrc
	git clone https://gerrit.googlesource.com/git-repo -b stable $reposrc
	cp $reposrc/repo $HOME/bin/repo
	chmod a+x $HOME/bin/repo
}

set_path() {
	local currentshell="$1"
	if [ "$currentshell" == "bash" ]; then
		profile=$HOME/.profile
	elif [ "$currentshell" == "zsh" ]; then
		profile=$HOME/.zprofile
	fi
	set_profile $profile
	currentshell=
	profile=
}

# check for bin and platform tools in PATH, add if missing, source it
set_profile() {
	local profile="$1"
	if [ ! -z $profile ]; then
		for i in bin bin/platform-tools; do
			if ! grep -q "PATH=\"\$HOME/$i:\$PATH\"" $profile; then
				echo "if [ -d \"\$HOME/$i\" ] ; then" >>$profile
				echo "    PATH=\"\$HOME/$i:\$PATH\"" >>$profile
				echo "fi" >>$profile
			fi
		done
		if ! grep -q "PATH=\"/opt/bin:\$PATH\"" $profile; then
			echo "if [ -d \"/opt/bin/\" ] ; then" >>$profile
			echo "    PATH=\"/opt/bin/:\$PATH\"" >>$profile
			echo "fi" >>$profile
		fi
		source $profile
	fi
	profile=
}

update_manifests() {
	if ! [ -d device/manifests ]; then
		return 0
	fi
    if ! [ -d .repo/local_manifests ]; then
        mkdir -p .repo/local_manifests/
    else
		rm -rf .repo/local_manifests/*.xml || true
	fi
    cp -rf device/manifests/*.xml .repo/local_manifests/ || true
    cp -rf device/manifests/additional/*.xml .repo/local_manifests/ || true
}

repo_init() {
	if [ "$SHALLOW" = true ]; then
		repo init --depth=1 --no-repo-verify -u "$MANIFEST_URL" -b $BRANCH -g default,-mips,-darwin,-notdefault --git-lfs
	else
		repo init --no-repo-verify -u "$MANIFEST_URL" -b $BRANCH -g default,-mips,-darwin,-notdefault --git-lfs
	fi
}

repo_sync() {
	if [ "$SHALLOW" = true ]; then
		repo sync -c --force-sync --optimized-fetch --no-tags --no-clone-bundle --prune -j$JOBS
	else
		repo sync -c --force-sync --optimized-fetch --prune -j$JOBS
	fi
}

repo_update() {
	pushd ".repo/repo"
	git fetch origin main || true
	git pull origin main || true
	popd
}

repo_reset() {
	repo forall -c 'git reset --hard'
	repo forall -c 'git clean -fdd'
}

if [ "$UPDATE_PKGS" = "true" ]; then
    update_pkg
fi

if [ "$UPDATE_BINS" = "true" ]; then
    currentshell=$(cat /proc/$$/cmdline | tr '\0' '\n')
    set_path $currentshell
    currentshell=
    update_bin
fi

init_git_account

repo_init

update_manifests

repo_reset
repo_update
repo_sync

# Sources envsetup to execute vendorsetup scripts
source build/envsetup.sh
