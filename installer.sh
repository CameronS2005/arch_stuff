#!/bin/bash

#### WORKING

##### TDL;
# STUFF TO IMPLEMENT: Auto login, luks header dump, home partition, data partition, auto_part_sizing, different bios support, advanced error handling!
# MORE STUFF TO IMPLEMENT: disable_ipv6

###VARIABLES_START
# Global variables
rel_date="UPDATE TIME; Oct 21, 8:35 PM EDT (2024)"
SCRIPT_VERSION="v1.7"
ARCH_VERSION="2024.10.01"
KERNEL="linux-hardened" # linux/linux-lts/linux-zen/linux-hardened
WIFI_SSID="redacted"
DRIVE_ID="/dev/mmcblk0"
lang="en_US.UTF-8"
timezone="America/New_York"
HOSTNAME="Archie Box"
USERNAME="Archie"
USER_PASSWD="redacted"
ROOT_PASSWD="redacted"
enable_32b_mlib=true
use_LUKS=true
use_SWAP=true
#use_HOME=false # WIP
#use_DATE=false # WIP
ROOT_ID="root_crypt"
GRUB_ID="GRUB"
DESKTOP_ENVIRONMENT="xfce" # cinnamon/plasma/gnome/xfce/lxqt/none
base_packages="base base-devel linux-firmware nano grub efibootmgr networkmanager intel-ucode sudo"
custom_packages="wget git curl screen nano konsole thunar net-tools openssh bc go sof-firmware"
yay_aur_helper=true
yay_packages="sublime-text-4"
NULL_VAR=">/dev/null 2>&1" # change to verbosity switch

# Drive Patition Sizes
#auto_part_sizing=false # based on hardcoded percentages # WIP
boot_size_mb="500"
swap_size_gb="2"; swap_size_mb=$((swap_size_gb * 1024))
root_size_gb="12"; root_size_mb=$((root_size_gb * 1024))
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
sanity_check() {
    if [[ $NULL_VAR != "$NULL_VAR" ]]; then
        NULL_VAR=""
    fi

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

    sgdisk --zap-all "$DRIVE_ID" $NULL_VAR
    parted "$DRIVE_ID" mklabel gpt $NULL_VAR

    parted "$DRIVE_ID" mkpart ESP fat32 1MiB "${boot_size_mb}MiB" $NULL_VAR
    parted "$DRIVE_ID" set 1 boot on $NULL_VAR

    if [[ $use_SWAP == true ]]; then
        root_part="p3"
        parted "$DRIVE_ID" mkpart primary linux-swap "${boot_size_mb}MiB" "$((boot_size_mb + swap_size_mb))MiB" $NULL_VAR
        parted "$DRIVE_ID" mkpart primary ext4 "$((boot_size_mb + swap_size_mb))MiB" "$((boot_size_mb + swap_size_mb + root_size_mb))MiB" $NULL_VAR
    else
        root_part="p2"
        parted "$DRIVE_ID" mkpart primary ext4 "${boot_size_mb}MiB" "$((boot_size_mb + root_size_mb))MiB" $NULL_VAR
    fi

    # Encrypt partitions if LUKS is enabled
    if [[ $use_LUKS == true ]]; then
        cryptsetup luksFormat "$DRIVE_ID""$root_part"
        cryptsetup luksOpen "$DRIVE_ID""$root_part" "$ROOT_ID"
        mkfs.ext4 "/dev/mapper/$ROOT_ID" $NULL_VAR
    else
        mkfs.ext4 "$DRIVE_ID""$root_part" $NULL_VAR
    fi

    mkfs.fat -F32 "$DRIVE_ID"p1 $NULL_VAR

    if [[ $use_SWAP == true ]]; then
        mkswap "$DRIVE_ID"p2
        swapon "$DRIVE_ID"p2
    fi
}

# Function to mount partitions
auto_mount() {
    echo "Mounting Partitions..."
    if [[ $use_LUKS == true ]]; then
        mount "/dev/mapper/$ROOT_ID" /mnt $NULL_VAR
    else
        mount "$DRIVE_ID""$root_part" /mnt
    fi
    mkdir -p /mnt/boot
    mount "$DRIVE_ID"p1 /mnt/boot $NULL_VAR
    sleep 10
}

# Function to perform pacstrap installation
pacstrap_install() {
    echo "Installing Base System Packages..."
    case $DESKTOP_ENVIRONMENT in
        cinnamon)
            desktop_packages="cinnamon sddm"
            ;;
        plasma)
            desktop_packages="xorg plasma sddm" # not working on fleex...
            ;;
        gnome)
            desktop_packages="gnome gdm"
            ;;
        xfce)
            desktop_packages="xfce4 xfce4-goodies sddm" # works perfect on fleex!
            ;;
        lxqt)
            desktop_packages="lxqt sddm"
            ;;
        *)
            desktop_packages=""
            ;;
    esac

    if [[ ! -z $desktop_packages ]]; then
        desktop_packages="xorg-server xorg-apps xorg-xinit xorg-twm xorg-xclock xterm $desktop_packages"
    fi

    if [[ $KERNEL == "linux" ]]; then
        base_packages="linux $base_packages"
    else
        base_packages="$KERNEL $KERNEL-headers $base_packages"
    fi

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
        swapoff "$DRIVE_ID"p2 $NULL_VAR
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
sanity_check

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
else
    root_part="p2"
fi

# Function for setting up the Arch Linux environment inside chroot
arch_chroot() {
    # Set root password
    echo "root:$ROOT_PASSWD" | chpasswd

    # Configure locale
    sed -i "s/^#\($lang UTF-8\)/\1/" "/etc/locale.gen"
    locale-gen $NULL_VAR
    echo "LANG=$lang" > "/etc/locale.conf"
    export LANG=$lang $NULL_VAR

    # Set system time and hostname
    ln -sf "/usr/share/zoneinfo/$timezone" "/etc/localtime" $NULL_VAR
    hwclock --systohc #--localtime $NULL_VAR
    echo "$HOSTNAME" > "/etc/hostname"

    # Enable SSD trimming if necessary
    #systemctl enable fstrim.timer $NULL_VAR

    # Enable 32-bit multilib if necessary
    if [[ $enable_32b_mlib == true ]]; then
        sed -i '90,91 s/^#//' "/etc/pacman.conf"
        yes | pacman -Sy $NULL_VAR
    fi

    # Configure hosts file
    echo "127.0.0.1 localhost
::1 localhost
127.0.1.1 $HOSTNAME.localdomain $HOSTNAME" >> "/etc/hosts"

    # Create and configure non-root user
    groupadd wheel $NULL_VAR
    groupadd sudo
    useradd -mG wheel,sudo "$USERNAME" $NULL_VAR
    echo "%sudo ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
    service sudo restart $NULL_VAR

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
    mkinitcpio -p $KERNEL $NULL_VAR

    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id="$GRUB_ID" $NULL_VAR

    # Set up cryptdevice if using LUKS and home partition
    ROOT_UUID=$(blkid -s UUID -o value "$DRIVE_ID$root_part")
    if [[ $use_LUKS == true ]]; then
        new_value="cryptdevice=UUID=$ROOT_UUID:$ROOT_ID root=/dev/mapper/$ROOT_ID"
    else
        new_value="root=UUID=$ROOT_UUID"
    fi
    sed -i '7c\GRUB_CMDLINE_LINUX="'"$new_value"'"' "/etc/default/grub"
    grub-mkconfig -o "/boot/grub/grub.cfg" $NULL_VAR

    # Enable necessary services
    systemctl enable NetworkManager $NULL_VAR
    systemctl enable sddm.service $NULL_VAR
    systemctl enable lightdm.service $NULL_VAR
    systemctl enable gdm.service $NULL_VAR

    # Install Yay AUR helper if needed
    if [[ $yay_aur_helper == true ]]; then
        git clone https://aur.archlinux.org/yay.git $NULL_VAR
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
    service sudo restart $NULL_VAR

    # Clean up
    cd /
    rm variables
    rm $0
}

arch_chroot
exit 0
###PART2_END
