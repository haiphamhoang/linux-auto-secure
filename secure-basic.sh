#!/bin/bash
#
# Linux Auto Secure Script
# https://github.com/haiphamhoang/linux-auto-secure
# Copy (c) 2023 by haiphamhoang

# Color definitions
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly ENDCOLOR='\033[0m'

# Global variables
ssh_current_port=$(echo "$SSH_CLIENT" | awk '{print $3}')
DOCKERINSTALL=false
HEXTRIXTOOL=false
SSHAUTHKEY=false
SSHPORT=$ssh_current_port

#######################################
# Validation Functions
#######################################

check_requirements() {
    # Check if running with bash
    if readlink /proc/$$/exe | grep -q "dash"; then
        echo 'This installer needs to be run with "bash", not "sh".'
        exit 1
    }

    # Check if root
    if [[ "$EUID" -ne 0 ]]; then
        echo -e "${RED}Sorry, you need to run this as root${ENDCOLOR}"
        exit 1
    }

    # Check OS compatibility
    check_os_compatibility
}

check_os_compatibility() {
    if grep -qs "ubuntu" /etc/os-release; then
        os="ubuntu"
        os_version=$(grep 'VERSION_ID' /etc/os-release | cut -d '"' -f 2 | tr -d '.')
        [[ "$os_version" -lt 1804 ]] && {
            echo "Ubuntu 18.04 or higher is required."
            exit 1
        }
    elif [[ -e /etc/debian_version ]]; then
        os="debian"
        os_version=$(grep -oE '[0-9]+' /etc/debian_version | head -1)
        if grep -q '/sid' /etc/debian_version || [[ "$os_version" -lt 10 ]]; then
            echo "Debian 10 or higher is required. Testing/Unstable not supported."
            exit 1
        }
    else
        echo "Supported distributions: Ubuntu, Debian"
        exit 1
    fi
}

#######################################
# Configuration Functions
#######################################

get_user_preferences() {
    configure_ssh_port
    configure_ssh_auth
    configure_hextrix
    configure_docker
}

configure_ssh_port() {
    read -p "Change SSH Port, press Enter to keep current ($ssh_current_port): " sshport_update
    until [[ -z "$sshport_update" || "$sshport_update" =~ ^[0-9]+$ && "$sshport_update" -le 65535 ]]; do
        echo "$sshport_update: invalid port."
        read -p "SSH Port (current $ssh_current_port): " sshport_update
    done
    SSHPORT=${sshport_update:-$ssh_current_port}
}

configure_ssh_auth() {
    echo "Add/update SSH authorized_keys?"
    select yn in "Yes" "No"; do
        case $yn in
            Yes) SSHAUTHKEY=true; break ;;
            No|*) break ;;
        esac
    done
}

configure_hextrix() {
    echo "Install HEXTRIXTOOL monitor?"
    select yn in "Yes" "No"; do
        case $yn in
            Yes) 
                read -p "Input your monitor id: " hextrixtool_id
                HEXTRIXTOOL=$hextrixtool_id
                break
                ;;
            No|*) break ;;
        esac
    done
}

configure_docker() {
    echo "Install or update Docker?"
    select yn in "Yes" "No"; do
        case $yn in
            Yes) DOCKERINSTALL=true; break ;;
            No|*) break ;;
        esac
    done
}

#######################################
# Installation Functions
#######################################

install_base_packages() {
    apt-get update -y && apt-get upgrade -y
    apt-get install wget curl putty-tools -y
}

install_hextrix() {
    [[ "$HEXTRIXTOOL" == false ]] && return
    wget https://raw.githubusercontent.com/hetrixtools/agent/master/hetrixtools_install.sh
    bash hetrixtools_install.sh "$HEXTRIXTOOL" 0 0 0 0 0 0
}

install_docker() {
    [[ "$DOCKERINSTALL" != true ]] && return

    echo "Installing Docker..."
    # Remove old versions
    for pkg in docker.io docker-doc docker-compose containerd runc; do
        apt-get remove $pkg
    done

    # Install prerequisites
    apt-get install ca-certificates curl gnupg lsb-release -y

    # Add Docker repository
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL "https://download.docker.com/linux/$(. /etc/os-release && echo "$ID")/gpg" -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
    https://download.docker.com/linux/$(. /etc/os-release && echo "$ID") \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Install Docker
    apt-get update -y
    apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y
    systemctl enable docker

    echo "Docker installed successfully"
    sleep 3
    docker --version
    docker compose version
}

#######################################
# SSH Configuration Functions
#######################################

configure_ssh_security() {
    [[ "$SSHAUTHKEY" != true ]] && return

    echo "Updating SSH authentication keys..."
    mkdir -p "/root/.ssh"

    echo "Select SSH key option:"
    select ossh in "Use my own key" "Make one" "Quit"; do
        case $ossh in
            "Use my own key")
                read -p "Input your public key: " sshkey_pub
                echo "$sshkey_pub" > /root/.ssh/authorized_keys
                break
                ;;
            "Make one")
                generate_ssh_keys
                break
                ;;
            "Quit")
                return
                ;;
        esac
    done

    update_ssh_config
    echo "Successfully updated authorized_keys"
}

generate_ssh_keys() {
    echo "Generating SSH key files..."
    mkdir -p gensshkey
    ssh-keygen -o -a 256 -t ed25519 -f ./gensshkey/key_file -C "root@$(hostname)-$(date +'%Y%m%d')"
    puttygen ./gensshkey/key_file -O private -o ./gensshkey/putty_private_key.ppk
    cp ./gensshkey/key_file.pub /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
}

update_ssh_config() {
    sed -i "s/#\?Port $ssh_current_port/Port $SSHPORT/" /etc/ssh/sshd_config
    sed -i 's/#\?StrictModes.*/StrictModes yes/' /etc/ssh/sshd_config
    sed -i 's/#\?MaxAuthTries.*/MaxAuthTries 3/' /etc/ssh/sshd_config
    sed -i 's/#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
    sed -i 's/#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config

    service ssh restart || service sshd restart
}

#######################################
# Main Function
#######################################

main() {
    check_requirements
    get_user_preferences
    
    # Installation process
    install_base_packages
    install_hextrix
    install_docker
    configure_ssh_security

    # Final messages
    echo "Installation completed."
    if [ -d "./gensshkey" ]; then
        echo -e "SSH key files saved at: ${GREEN}$(pwd)/gensshkey${ENDCOLOR}"
    fi
    echo "Remember to reboot your system!"
}

main