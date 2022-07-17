#!/bin/bash

eval `resize`

set -ex

function echo_red {
	echo -e "\e[101m$1\e[0m"
}

function echo_green {
	echo -e "\033[0;32m$1\e[0m"
}

function install_if_not_exists {
	PROGNAME=$1
	INSTALL=$2

	if [[ -z $INSTALL ]]; then
		INSTALL=$PROGNAME
	fi

	if ! which $PROGNAME >/dev/null; then
		red_text "$PROGNAME could not be found. Enter your user password so you can install it via apt-get."
		sudo apt-get -y install $INSTALL
	fi
}

function main {
	echo_green "Welcome to the CVAT installer."

	if ! command -v apt 2>&1 >/dev/null; then
		echo_red "apt not found. This installer only works on debian based OSs"
		exit 1
	fi

	if ! command -v docker 2>&1 >/dev/null; then
		if (whiptail --title "CVAT installer" --yesno "Docker is not installed on this machine. Do you want to install it? 'No' cancels the installation." 8 78); then
			set -x
			sudo apt-get install -y ca-certificates curl gnupg lsb-release
			sudo mkdir -p /etc/apt/keyrings
			curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
			 echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
$(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

			sudo apt-get update
			sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
			sudo apt-get --no-install-recommends install -y docker-ce docker-ce-cli containerd.io
			sudo groupadd docker
			sudo usermod -aG docker $USER

			echo_red "WARNING: You may need to reboot to take effect of adding your user to the docker group"
			sudo apt-get --no-install-recommends install -y python3-pip python3-setuptools
			sudo python3 -m pip install setuptools docker-compose
			set +x
		else
			echo_green "You chose not to install docker. This is fine, but then I cannot install CVAT."
		fi
	fi

	SERVER_IP=$(hostname -I | cut -d' ' -f1)

	AVX_HACK=0

	if grep -i avx2 /proc/cpuinfo 2&>1 >/dev/null; then
		if (whiptail --title "CVAT installer" --yesno "Your CPU does not support AVX2. Do you want an AVX-free compile of tensorflow instead of the default one? 'No' cancels the installation." 8 78); then
			AVX_HACK=1
		else
			echo_red "No avx2 in /proc/cpuinfo and no AVX2 hack. Exiting."
			exit 2
		fi
	else
		echo_green "AVX2 seems to be supported here. No hack needed."
	fi

	export WHAT_TO_INSTALL=$(
		whiptail --title "CVAT installer" --menu "What option to install?" $LINES $COLUMNS $(( $LINES - 8 )) \
		"localhostonly" "Default installation type." \
		"https" "Available over https." \
		"quit " "Quit installer here." \
		3>&1 1>&2 2>&3
	)

	if [[ "$WHAT_TO_INSTALL" == "quit" ]]; then
		exit 0
	fi

	if [[ "AVX_HACK" -eq "1" ]]; then
		echo "RUN python3 -m pip install --upgrade pip" >> Dockerfile
		echo "RUN python3 -m pip install wheel" >> Dockerfile
		echo "RUN python3 -m pip install https://tf.novaal.de/btver1/tensorflow-2.8.0-cp38-cp38-linux_x86_64.whl" >> Dockerfile
		docker build .
	fi

	export CVAT_HOST=$(whiptail --inputbox "Enter your hostname" 8 39 "$SERVER_IP" --title "CVAT installer" 3>&1 1>&2 2>&3)

	if [[ "$WHAT_TO_INSTALL" == "https" ]]; then
		export ACME_EMAIL=$(whiptail --inputbox "Enter your email for letscrypt" 8 39 "" --title "CVAT installer" 3>&1 1>&2 2>&3)
		docker-compose -f docker-compose.yml -f docker-compose.https.yml up -d
	fi

	if [[ "$WHAT_TO_INSTALL" -eq "localhostonly" ]]; then
		docker-compose -f docker-compose.yml -f docker-compose.dev.yml build
		docker-compose up -d
	fi

	if (whiptail --title "CVAT installer" --yesno "Installation done. Do you want to create a super user now?" 8 78); then
		docker exec -it cvat bash -ic 'python3 ~/manage.py createsuperuser'
	else
		echo_green "Okay. Run"
		echo_green "docker exec -it cvat bash -ic 'python3 ~/manage.py createsuperuser'"
		echo_green "When you want to add one later."
	fi
}

main
