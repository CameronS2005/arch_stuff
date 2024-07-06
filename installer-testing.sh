#!/bin/bash

## Script to automate Arch Linux installation based on specified criteria

### PART TWO IS FINALLY UNATTENDED!!!

##### TDL;
# FUNCTIONS TO IMPLEMENT: Auto login, luks header dump, home partition, data partition, auto_part_sizing, bios support, quiet/verbose logging
# Password hashes instead of plain text!
# Modify luks cryptsetup to be unattended! (With hardcoded passwords/hashes)
#
#
#
#
#
#
# Removes Notes, Cleanup & Optimize Code!!

###VARIABLES_START
# Global variables
rel_date="UPDATE TIME; Jul 06, 5:55 PM EDT (2024)"
SCRIPT_VERSION="v1.6"
ARCH_VERSION="2024.06.01"
WIFI_SSID="dacrib"
DRIVE_ID="/dev/mmcblk0"  # Update this to match your installation drive
lang="en_US.UTF-8"
timezone="America/New_York"
HOSTNAME="Archie Box"
USERNAME="Archie"
USER_PASSWD="password123"
ROOT_PASSWD="password123"
#auto_login=false
enable_32b_mlib=true
use_LUKS=true
use_SWAP=true
use_HOME=false ## TESTING!!
#use_DATA=false
ROOT_ID="root_crypt"
HOME_ID="home_crypt" ## TESTING!!
#DATA_ID="data_crypt"
#BIOS=UEFI # UEFI/BIOS
#logging=verbose # verbose/silenced
#luks_header_dump=false
GRUB_ID="GRUB"
DESKTOP_ENVIRONMENT="none" # gnome/none
base_packages="base base-devel linux linux-firmware nano grub efibootmgr networkmanager intel-ucode sudo"
custom_packages="wget git curl screen nano firefox konsole thunar openssh net-tools wireguard-tools bc go"
yay_aur_helper=false
yay_packages="sublime-text-4"

# Disk partitioning sizes in MiB
#auto_part_sizing=false
boot_size_mb="500"
swap_size_gb="4"; swap_size_mb=$((swap_size_gb * 1024))
root_size_gb="8"; root_size_mb=$((root_size_gb * 1024))
home_size_gb="2"; home_size_mb=$((home_size_gb * 1024))
#data_size_gb="10"; data_size_mb=$((data_size_gb * 1024))
###VARIABLES_END

# Function to print release date and current configuration
print_info() {
    cat << EOF
RELEASE DATE: $rel_date

CURRENT CONFIGURATION:
-------------------------------------------------
DRIVE_ID="$DRIVE_ID"
lang="$lang"
timezone="$timezone"

use_LUKS="$use_LUKS"
use_SWAP="$use_SWAP"
use_HOME="$use_HOME"
use_DATA="$use_DATA"

HOSTNAME="$HOSTNAME"
USERNAME="$USERNAME"

GRUB_ID="$GRUB_ID"
enable_32b_mlib=$enable_32b_mlib

Battery is at $(cat /sys/class/power_supply/BAT0/capacity)%
-------------------------------------------------
EOF
}

# Function to handle WiFi connection
wifi_connect() {
    if ! ping 1.1.1.1 -c 1 &> /dev/null; then
        echo "1.1.1.1 PING FAILED! Attempting wireless config!"
        
        wifi_adapter=$(iwconfig 2>/dev/null | grep -o '^[a-zA-Z0-9]*')
        echo "Wireless Adapter Name: $wifi_adapter"
    
        echo "Connecting to WiFi SSID: $WIFI_SSID"
        if ! iwctl station $wifi_adapter connect $WIFI_SSID; then
            echo "ERROR: Failed to connect to WiFi!"
            exit 1
        fi
        sleep 10 # Wait for DHCP and IP assignment
        local_ipv4=$(ip -4 addr show up | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n 1)
        echo "Local IPv4 address: $local_ipv4"
    fi
}

# Function to rank Pacman mirrors
rank_mirrors() {
    echo "Ranking Pacman Mirrors for faster downloads..."
    pacman -Syyy pacman-contrib --noconfirm >/dev/null
    cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.bak
    rankmirrors -n 6 /etc/pacman.d/mirrorlist.bak > /etc/pacman.d/mirrorlist
}

# Function to automate disk partitioning
auto_partition() {
    echo "Automating disk partitioning for $DRIVE_ID..."
    read -p "PRESS ENTER TO PARTITION ($DRIVE_ID) DANGER!!!"

    sgdisk --zap-all "$DRIVE_ID" 
    parted "$DRIVE_ID" mklabel gpt 

    parted "$DRIVE_ID" mkpart ESP fat32 1MiB "${boot_size_mb}MiB" 
    parted "$DRIVE_ID" set 1 boot on 

    if [[ $use_SWAP == true ]]; then
        root_part="3"
        if [[ $use_HOME == true ]]; then
            home_part="4"
            parted "$DRIVE_ID" mkpart primary linux-swap "${boot_size_mb}MiB" "$((boot_size_mb + swap_size_mb))MiB" 
            parted "$DRIVE_ID" mkpart primary ext4 "$((boot_size_mb + swap_size_mb))MiB" "$((boot_size_mb + swap_size_mb + root_size_mb))MiB" 
            parted "$DRIVE_ID" mkpart primary ext4 "$((boot_size_mb + swap_size_mb + root_size_mb))MiB" "$((boot_size_mb + swap_size_mb + root_size_mb + home_size_mb))MiB" 
        else
            parted "$DRIVE_ID" mkpart primary linux-swap "${boot_size_mb}MiB" "$((boot_size_mb + swap_size_mb))MiB" 
            parted "$DRIVE_ID" mkpart primary ext4 "$((boot_size_mb + swap_size_mb))MiB" "$((boot_size_mb + swap_size_mb + root_size_mb))MiB" 
        fi
    else
        root_part="2"
        if [[ $use_HOME == true ]]; then
            home_part="3"
        parted "$DRIVE_ID" mkpart primary ext4 "${boot_size_mb}MiB" "$((boot_size_mb + root_size_mb))MiB" 
        parted "$DRIVE_ID" mkpart primary ext4 "${boot_size_mb + root_size_mb}MiB" "$((boot_size_mb + root_size_mb + home_size_mb))MiB" 
        else
        parted "$DRIVE_ID" mkpart primary ext4 "${boot_size_mb}MiB" "$((boot_size_mb + root_size_mb))MiB" 
    fi; fi

    # Encrypt partitions if LUKS is enabled
    if [[ $use_LUKS == true ]]; then
        cryptsetup luksFormat "$DRIVE_ID"p"$root_part"
        cryptsetup luksOpen "$DRIVE_ID"p"$root_part" "$ROOT_ID"
        mkfs.ext4 "/dev/mapper/$ROOT_ID" 
        if [[ $use_HOME == true ]]; then
            cryptsetup luksFormat "$DRIVE_ID"p"$home_part"
            cryptsetup luksOpen "$DRIVE_ID"p"$home_part" "$HOME_ID"
            mkfs.ext4 "/dev/mapper/$HOME_ID" 
        fi
    else
        mkfs.ext4 "$DRIVE_ID"p"$root_part" 
        if [[ $use_HOME == true ]]; then
            #mkdir -p /mnt/home
            mkfs.ext4 "$DRIVE_ID"p"$home_part" 
        fi
    fi
    if [[ $use_SWAP == true ]]; then
        mkswap "$DRIVE_ID"p2
    fi

    mkfs.fat -F32 "$DRIVE_ID"p1  ## Format boot partition as FAT32
}

# Function to mount partitions
auto_mount() {
    echo "Mounting Partitions..."
    if [[ $use_LUKS == true ]]; then
        mount "/dev/mapper/$ROOT_ID" /mnt #
        mkdir -p /mnt/home
        if [[ $use_HOME == true ]]; then
            mount "/dev/mapper/$HOME_ID" /mnt/home #
        fi
    else
        mount "$DRIVE_ID"p"$root_part" /mnt
        mkdir -p /mnt/home
        if [[ $use_HOME == true ]]; then
            mount "$DRIVE_ID"p"$home_part" /mnt/home
        fi
    fi
    mkdir -p /mnt/boot
    mount "$DRIVE_ID"p1 /mnt/boot
    if [[ $use_SWAP == true ]]; then
        swapon "$DRIVE_ID"p2
    fi
}

# Function to perform pacstrap installation
pacstrap_install() {
    echo "Installing Base System Packages..."
    case $DESKTOP_ENVIRONMENT in
        gnome)
            desktop_packages="xorg-server xorg-apps xorg-xinit xorg-twm xorg-xclock gnome gdm"
            ;;
        *)
            desktop_packages=""
            ;;
    esac

    pacstrap -i /mnt $base_packages $desktop_packages $custom_packages --noconfirm
}

# Function to generate fstab
generate_fstab() {
    echo "Generating fstab..."
    genfstab -U /mnt >> /mnt/etc/fstab
}

# Function to finalize installation in chroot environment
chroot_setup() {
    echo "Finalizing Installation in chroot environment!"

 	seed="#"
	sed -n "/$seed##VARIABLES_START/,/$seed##VARIABLES_END/p" "$0" > /mnt/variables
	sed -n "/$seed##PART2_START/,/$seed##PART2_END/p" "$0" > /mnt/setup.sh

	echo "RUN: chmod +x setup.sh && ./setup.sh && exit"
	#arch-chroot /mnt
	#exit 0# TESTING

    arch-chroot /mnt << EOF
chmod +x setup.sh && ./setup.sh && exit
EOF
#clear
}

# Function to run post-chroot commands
post_chroot() {
    echo "Performing post-chroot cleanup..."

    umount -R /mnt
    if [[ $use_SWAP == true ]]; then
        swapoff "$DRIVE_ID"p2 
    fi

    echo "Installation completed successfully. You can now reboot your system."
}

# Main script execution starts here

# Print initial information
print_info

# Check for UEFI firmware presence
if [ ! -d /sys/firmware/efi/efivars ]; then
    echo "ERROR: This script currently only support UEFI"
    exit 1
fi

# Handle WiFi connection
wifi_connect

# Rank Pacman mirrors
#rank_mirrors

# Perform auto partitioning
auto_partition

# Mount partitions
auto_mount

# Install base system packages
pacstrap_install

# Generate fstab
generate_fstab

# Run setup in chroot environment
chroot_setup

# Post chroot cleanup and reboot
post_chroot

# End of script
exit 0

######### PART 2

###PART2_START
#!/bin/bash
source variables

# Determine root and home partitions based on conditions
if [[ $use_SWAP == true ]]; then
    root_part="3"
    [[ $use_HOME == true ]] && home_part="4"
else
    root_part="2"
    [[ $use_HOME == true ]] && home_part="3"
fi

# Function for setting up the Arch Linux environment inside chroot
arch_chroot() {
    # Set root password
    echo "root:$ROOT_PASSWD" | chpasswd

    # Configure locale
    sed -i "s/^#\($lang UTF-8\)/\1/" "/etc/locale.gen"
    locale-gen 
    echo "LANG=$lang" > "/etc/locale.conf"
    export LANG=$lang 

    # Set system time and hostname
    ln -sf "/usr/share/zoneinfo/$timezone" "/etc/localtime" 
    hwclock --systohc --localtime 
    echo "$HOSTNAME" > "/etc/hostname"

    # Enable SSD trimming if necessary
    systemctl enable fstrim.timer 

    # Enable 32-bit multilib if necessary
    if [[ $enable_32b_mlib == true ]]; then
        sed -i '90,91 s/^#//' "/etc/pacman.conf"
        yes | pacman -Sy 
    fi

    # Configure hosts file
    echo "127.0.0.1 localhost
::1 localhost
127.0.1.1 $HOSTNAME.localdomain $HOSTNAME" >> "/etc/hosts"

    # Create and configure non-root user
    groupadd sudo 
    useradd -mG wheel,sudo "$USERNAME" 
    echo "%sudo ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
    service sudo restart 

    # Configure autologin if enabled
    if [[ $auto_login == true ]]; then
        new_getty_args="ExecStart=-/sbin/agetty -o '-p -f -- \\u' --noclear --autologin $USERNAME %I \$TERM"
        sed -i '38c\'"$new_getty_args"'' "/etc/systemd/system/getty.target.wants/getty@tty1.service"
    fi

    # Set user password
    echo "$USERNAME:$USER_PASSWD" | chpasswd

    # Configure bootloader
    if [[ $use_LUKS == true ]]; then
        sed -i '/^HOOKS=/ s/)$/ encrypt)/' "/etc/mkinitcpio.conf"
    fi
    mkinitcpio -p linux 

    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id="$GRUB_ID" 
    grub-mkconfig -o "/boot/grub/grub.cfg" 

    # Set up cryptdevice if using LUKS and home partition
    ROOT_UUID=$(blkid -s UUID -o value "$DRIVE_ID"p"$root_part")
    #if [[ $use_LUKS == true && $use_HOME == true ]]; then
    #    HOME_UUID=$(blkid -s UUID -o value "$DRIVE_ID$home_part")
    #    new_value="cryptdevice=UUID=$ROOT_UUID:$ROOT_ID root=/dev/mapper/$ROOT_ID cryptdevice=UUID=$HOME_UUID:$HOME_ID home=/dev/mapper/$HOME_ID"
    #elif [[ $use_LUKS == true ]]; then
    #    new_value="cryptdevice=UUID=$ROOT_UUID:$ROOT_ID root=/dev/mapper/$ROOT_ID"
    #else
    #    new_value="root=UUID=$ROOT_UUID"
    #fi
    #if [[ $use_LUKS == true ]]; then
    #    if [[ $use_HOME == true ]]; then
    #            new_value="new_value="cryptdevice=UUID=$ROOT_UUID:$ROOT_ID root=/dev/mapper/$ROOT_ID cryptdevice=UUID=$HOME_UUID:$HOME_ID home=/dev/mapper/$HOME_ID""
    #        else
    #            new_value="new_value="cryptdevice=UUID=$ROOT_UUID:$ROOT_ID root=/dev/mapper/$ROOT_ID""
    #    fi
    #else
    #    if [[ $use_HOME == true ]]; then
    #            new_value="root=UUID=$ROOT_UUID home=UUID=$HOME_UUID"
    #        else
    #            new_value="root=UUID=$ROOT_UUID"
    #    fi  
    #fi
    if [[ $use_LUKS == true ]]; then
        new_value="cryptdevice=UUID=$ROOT_UUID:$ROOT_ID root=/dev/mapper/$ROOT_ID"
    else
        new_value="root=UUID=$ROOT_UUID"
    fi

    sed -i '7c\GRUB_CMDLINE_LINUX="'"$new_value"'"' "/etc/default/grub"
    grub-mkconfig -o "/boot/grub/grub.cfg" 

    # Enable necessary services
    systemctl enable NetworkManager sddm.service lightdm.service gdm.service 

    # Install Yay AUR helper if needed
    if [[ $yay_aur_helper == true ]]; then
        git clone https://aur.archlinux.org/yay.git 
        mv yay /home/$USERNAME/
        chown -R $USERNAME:$USERNAME /home/$USERNAME/yay
        cd /home/$USERNAME/yay
        yes | sudo -u $USERNAME makepkg -si --noconfirm
        sudo -u $USERNAME yay -S $yay_packages --noconfirm
        cd ..
        rm -rf yay
    fi

    # Restore sudoers configuration
    sed -i 's/%sudo ALL=(ALL) NOPASSWD: ALL/%sudo ALL=(ALL) ALL/g' /etc/sudoers
    service sudo restart 

    # Clean up
    cd /
    rm variables
    rm $0
}

arch_chroot
exit 0
###PART2_END
