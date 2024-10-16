#!/bin/bash
#
# https://github.com/haiphamhoang/vps-basic-secure
#
# Copy (c) 2023 by haiphamhoang.

# Visual text settings
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
ENDCOLOR='\033[0m' # No Color

# Detect Debian users running the script with "sh" instead of bash
if readlink /proc/$$/exe | grep -q "dash"; then
	echo 'This installer needs to be run with "bash", not "sh".'
	exit
fi

# Discard stdin. Needed when running from an one-liner which includes a newline
read -N 999999 -t 0.001

# Detect OpenVZ 6
if [[ $(uname -r | cut -d "." -f 1) -eq 2 ]]; then
	echo "The system is running an old kernel, which is incompatible with this installer."
	exit
fi

# Detect OS
# $os_version variables aren't always in use, but are kept here for convenience
if grep -qs "ubuntu" /etc/os-release; then
	os="ubuntu"
	os_version=$(grep 'VERSION_ID' /etc/os-release | cut -d '"' -f 2 | tr -d '.')
elif [[ -e /etc/debian_version ]]; then
	os="debian"
 	os_version=$(grep -oE '[0-9]+' /etc/debian_version | head -1)
# elif [[ -e /etc/almalinux-release || -e /etc/rocky-release || -e /etc/centos-release ]]; then
# 	os="centos"
# 	os_version=$(grep -shoE '[0-9]+' /etc/almalinux-release /etc/rocky-release /etc/centos-release | head -1)
# elif [[ -e /etc/fedora-release ]]; then
# 	os="fedora"
# 	os_version=$(grep -oE '[0-9]+' /etc/fedora-release | head -1)
else
	echo "This installer seems to be running on an unsupported distribution.
Supported distros are Ubuntu, Debian."
	exit
fi

if [[ "$os" == "ubuntu" && "$os_version" -lt 1804 ]]; then
	echo "Ubuntu 18.04 or higher is required to use this installer.
This version of Ubuntu is too old and unsupported."
	exit
fi

if [[ "$os" == "debian" ]]; then
	if grep -q '/sid' /etc/debian_version; then
		echo "Debian Testing and Debian Unstable are unsupported by this installer."
		exit
	fi
	if [[ "$os_version" -lt 10 ]]; then
		echo "Debian 10 or higher is required to use this installer.
This version of Debian is too old and unsupported."
		exit
	fi
fi

if [[ "$os" == "centos" && "$os_version" -lt 7 ]]; then
	echo "CentOS 7 or higher is required to use this installer.
This version of CentOS is too old and unsupported."
	exit
fi

# Root check
if [[ "$EUID" -ne 0 ]]; then
	echo -e "${RED}Sorry, you need to run this as root${ENDCOLOR}"
	exit 1
fi

# Detect current ssh port connect
ssh_current_port=$(echo "$SSH_CLIENT" | awk '{print $3}')

set -e
main() {
    # Default option
    DOCKERINSTALL=false
    HEXTRIXTOOL=false
    SSHAUTHKEY=false
    SSHPORT=false

    read -p "Change SSH Port, press Enter to keep the current one ($ssh_current_port):" sshport_update
    until [[ -z "$sshport_update" || "$sshport_update" =~ ^[0-9]+$ && "$sshport_update" -le 65535 ]]; do
        echo "$sshport_update: invalid port."
        read -p "SSH Port (current $ssh_current_port): " sshport_update
    done
    [[ -z "$sshport_update" ]] && sshport_update=$ssh_current_port
    SSHPORT=$sshport_update

    echo "Add/update SSH authorized_keys?"
    select yn in "Yes" "No"; do
        case $yn in
            Yes) 
                SSHAUTHKEY=true
                break;;
            No)
                break;;
            *)
                echo "No update authorized_keys."; 
                break;;
        esac
    done
    

    echo "Install HEXTRIXTOOL monitor?"
    select yn in "Yes" "No"; do
        case $yn in
            Yes ) 
                read -p "Input your monitor id: " hextrixtool_id
                HEXTRIXTOOL=$hextrixtool_id
                break;;
            No ) 
                break;;
            *)
                echo "No install Hextrixtools."; 
                break;;
        esac
    done

    # Docker
    echo "Install or update Docker?"
    select yn in "Yes" "No"; do
        case $yn in
            Yes ) 
                DOCKERINSTALL=true
                break
                ;;
            No )
                break;;
            *)
                echo "No install Docker."; 
                break;;
        esac
    done

    # 
    # Script Run begin

    #read -p "Your vps location for apt server (ex: jp, us, sg...): " input_server_location
    # if [  -n "$(uname -a | grep Ubuntu)" ]; then
    #     # select the fastest apt mirror server
    #     local input_server_location=$(hostname | cut -d'-' -f2)
    #     if [ ${#input_server_location} -eq 2 ]; then 
    #         echo "Change apt server to:" $input_server_location
    #         sed -i -e "s/http:\/\/[a-z]\{2\}.archive/http:\/\/$input_server_location.archive/" /etc/apt/sources.list
    #     else 
    #         echo "Keep apt server."
    #     fi
    # fi
    
    
    apt-get update -y && apt-get upgrade -y
    apt-get install wget curl putty-tools -y
    timedatectl set-timezone Asia/Bangkok


    if [ "$HEXTRIXTOOL" = false ]; then
      echo "No install Hextrixtools."
    else
      wget https://raw.githubusercontent.com/hetrixtools/agent/master/hetrixtools_install.sh && bash hetrixtools_install.sh $HEXTRIXTOOL 0 0 0 0 0 0
    fi


    if [ "$DOCKERINSTALL" = true ]; then
        echo "Install docker......" 
        for pkg in docker.io docker-doc docker-compose containerd runc; do apt-get remove $pkg; done

        apt-get install ca-certificates curl gnupg lsb-release -y

        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/$(. /etc/os-release && echo "$ID")/gpg -o /etc/apt/keyrings/docker.asc
        chmod a+r /etc/apt/keyrings/docker.asc

        # Add the repository to Apt sources:
        echo "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/$(. /etc/os-release && echo "$ID") "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        
        apt-get update -y
        apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y
        systemctl enable docker
        echo "Docker installed successfully"
        
        # Waiting for Docker to start..."
        sleep 3
        #curl -fsSL https://get.docker.com -o get-docker.sh && sh get-docker.sh

        docker --version
        docker compose version
    fi

    # ssh-key update
    if [ "$SSHAUTHKEY" = true ]; then
        echo "Update SSH authentication keys begin..."
        if [ ! -d "/root/.ssh" ]; then
            mkdir -p "/root/.ssh"
        fi

        echo "Select sshkey option:"
        select ossh in "Use my own key" "Make one" "Quit"; do
            case $ossh in
                "Use my own key") 
                    echo "Input your public key:"
                    read sshkey_pub
                    echo $sshkey_pub > /root/.ssh/authorized_keys
                    echo "Save at /root/.ssh/authorized_keys"
                    break
                    ;;
                "Make one")
                    sshkey_gen_file
                    break;;
                "Quit")
                    echo "No update SSH authentication keys."
                    break;;
            esac
        done

        edit_ssh_config
        echo "Success update authorized_keys.";
        echo "Private key file will be located at: $(pwd)/gensshkey."
    fi

    echo "Completed."
    if [ -d "./gensshkey" ]; then
        echo -e "SSH key file saved at: ${GREEN}$(pwd)/gensshkey${ENDCOLOR}."
    fi
    echo "Remember to reboot your system!"
    
}

#######################################
# Helper function
#######################################
sshkey_gen_file() {
    echo "Generate sshkey file, make sure you save private key after script is done...."
    mkdir -p gensshkey
    ssh-keygen -o -a 256 -t ed25519 -f ./gensshkey/key_file -C "root@$(hostname)-$(date +'%Y%m%d')"
    puttygen ./gensshkey/key_file -O private -o ./gensshkey/putty_private_key.ppk
    cp ./gensshkey/key_file.pub /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
}

edit_ssh_config() {
    # edit sshd_config
    sed -i "s/#\?Port $ssh_current_port/Port $SSHPORT/" /etc/ssh/sshd_config
    sed -i 's/#\?StrictModes.*/StrictModes yes/' /etc/ssh/sshd_config
    sed -i 's/#\?MaxAuthTries.*/MaxAuthTries 3/' /etc/ssh/sshd_config
    sed -i 's/#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
    sed -i 's/#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config

    # make sure sshd_config is valid
    sshd -t

    # restart ssh or sshd depending of the distro
    service ssh restart ; service sshd restart
}

#######################################
# get last release tag version
# Returns:
#   string
#######################################
compose_release() {
  curl --silent "https://api.github.com/repos/docker/compose/releases/latest" |
  grep -Po '"tag_name": "\K.*?(?=")'
}

main