#!/bin/bash

## Script to automate Arch Linux installation based on specified criteria

###VARIABLES_START
# Global variables
rel_date="UPDATE TIME; Jul 06, 3:07 PM EDT (2024)"
SCRIPT_VERSION="v1.5"
ARCH_VERSION="2024.06.01"
WIFI_SSID="dacrib"
DRIVE_ID="/dev/mmcblk0"  # Update this to match your installation drive
lang="en_US.UTF-8"
timezone="America/New_York"
HOSTNAME="Archie Box"
USERNAME="Archie"
USER_PASSWD="password123"
ROOT_PASSWD="password123"
enable_32b_mlib=true
use_LUKS=true
use_SWAP=true
ROOT_ID="root_crypt"
GRUB_ID="GRUB"
DESKTOP_ENVIRONMENT="gnome" # gnome/none
base_packages="base base-devel linux linux-firmware nano grub efibootmgr networkmanager intel-ucode sudo"
custom_packages="wget git curl screen nano firefox konsole thunar openssh net-tools wireguard-tools bc go"
yay_aur_helper=true
yay_packages="sublime-text-4"

# Disk partitioning sizes in MiB
boot_size_mb="500"
swap_size_gb="4"; swap_size_mb=$((swap_size_gb * 1024))
root_size_gb="10"; root_size_mb=$((root_size_gb * 1024))
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

    sgdisk --zap-all "$DRIVE_ID" >/dev/null 2>&1
    parted "$DRIVE_ID" mklabel gpt >/dev/null 2>&1

    parted "$DRIVE_ID" mkpart ESP fat32 1MiB "${boot_size_mb}MiB" >/dev/null 2>&1
    parted "$DRIVE_ID" set 1 boot on >/dev/null 2>&1

    if [[ $use_SWAP == true ]]; then
        parted "$DRIVE_ID" mkpart primary linux-swap "${boot_size_mb}MiB" "$((boot_size_mb + swap_size_mb))MiB" >/dev/null 2>&1
        parted "$DRIVE_ID" mkpart primary ext4 "$((boot_size_mb + swap_size_mb))MiB" "$((boot_size_mb + swap_size_mb + root_size_mb))MiB" >/dev/null 2>&1
    else
        parted "$DRIVE_ID" mkpart primary ext4 "${boot_size_mb}MiB" "$((boot_size_mb + root_size_mb))MiB" >/dev/null 2>&1
    fi

    # Encrypt partitions if LUKS is enabled
    if [[ $use_LUKS == true ]]; then
        cryptsetup luksFormat "$DRIVE_ID"p3
        cryptsetup luksOpen "$DRIVE_ID"p3 "$ROOT_ID"
        mkfs.ext4 "/dev/mapper/$ROOT_ID" >/dev/null 2>&1
    else
        mkfs.ext4 "$DRIVE_ID"p2 >/dev/null 2>&1
    fi

    mkfs.fat -F32 "$DRIVE_ID"p1 >/dev/null 2>&1
}

# Function to mount partitions
auto_mount() {
    echo "Mounting Partitions..."
    if [[ $use_LUKS == true ]]; then
        mount "/dev/mapper/$ROOT_ID" /mnt >/dev/null 2>&1
    else
        mount "$DRIVE_ID"p2 /mnt
    fi
    mkdir -p /mnt/boot
    mount "$DRIVE_ID"p1 /mnt/boot >/dev/null 2>&1
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
        swapoff "$DRIVE_ID"p2 >/dev/null 2>&1
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
    root_part="p3"
    [[ $use_HOME == true ]] && home_part="p4"
else
    root_part="p2"
    [[ $use_HOME == true ]] && home_part="p3"
fi

# Function for setting up the Arch Linux environment inside chroot
arch_chroot() {
    # Set root password
    echo "root:$ROOT_PASSWD" | chpasswd

    # Configure locale
    sed -i "s/^#\($lang UTF-8\)/\1/" "/etc/locale.gen"
    locale-gen >/dev/null 2>&1
    echo "LANG=$lang" > "/etc/locale.conf"
    export LANG=$lang >/dev/null 2>&1

    # Set system time and hostname
    ln -sf "/usr/share/zoneinfo/$timezone" "/etc/localtime" >/dev/null 2>&1
    hwclock --systohc --localtime >/dev/null 2>&1
    echo "$HOSTNAME" > "/etc/hostname"

    # Enable SSD trimming if necessary
    systemctl enable fstrim.timer >/dev/null 2>&1

    # Enable 32-bit multilib if necessary
    if [[ $enable_32b_mlib == true ]]; then
        sed -i '90,91 s/^#//' "/etc/pacman.conf"
        yes | pacman -Sy >/dev/null 2>&1
    fi

    # Configure hosts file
    echo "127.0.0.1 localhost
::1 localhost
127.0.1.1 $HOSTNAME.localdomain $HOSTNAME" >> "/etc/hosts"

    # Create and configure non-root user
    groupadd sudo >/dev/null 2>&1
    useradd -mG wheel,sudo "$USERNAME" >/dev/null 2>&1
    echo "%sudo ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
    service sudo restart >/dev/null 2>&1

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
    mkinitcpio -p linux >/dev/null 2>&1

    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id="$GRUB_ID" >/dev/null 2>&1
    grub-mkconfig -o "/boot/grub/grub.cfg" >/dev/null 2>&1

    # Set up cryptdevice if using LUKS and home partition
    ROOT_UUID=$(blkid -s UUID -o value "$DRIVE_ID$root_part")
    if [[ $use_LUKS == true && $use_HOME == true ]]; then
        HOME_UUID=$(blkid -s UUID -o value "$DRIVE_ID$home_part")
        new_value="cryptdevice=UUID=$ROOT_UUID:$ROOT_ID root=/dev/mapper/$ROOT_ID cryptdevice=UUID=$HOME_UUID:$HOME_ID home=/dev/mapper/$HOME_ID"
    elif [[ $use_LUKS == true ]]; then
        new_value="cryptdevice=UUID=$ROOT_UUID:$ROOT_ID root=/dev/mapper/$ROOT_ID"
    else
        new_value="root=UUID=$ROOT_UUID"
    fi
    sed -i '7c\GRUB_CMDLINE_LINUX="'"$new_value"'"' "/etc/default/grub"
    grub-mkconfig -o "/boot/grub/grub.cfg" >/dev/null 2>&1

    # Enable necessary services
    systemctl enable NetworkManager sddm.service lightdm.service gdm.service >/dev/null 2>&1

    # Install Yay AUR helper if needed
    if [[ $yay_aur_helper == true ]]; then
        git clone https://aur.archlinux.org/yay.git >/dev/null 2>&1
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
    service sudo restart >/dev/null 2>&1

    # Clean up
    cd /
    rm variables
    rm $0
}

arch_chroot
exit 0
###PART2_END
