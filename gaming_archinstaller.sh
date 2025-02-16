#!/bin/bash

#### TDL;

## MORE IMPORTANT!!
# Optionally fully disable ipv6 (easy)
# Auto login support (easy-mid)
# Optional detached luks header (mid)
# Automatic partition sizing based on hardcoded values (percentages?) (mid) << will required some math will hardcoded limits, to prevent issues like not enough space on boot or root, etc...
# Create detailed & externally sourced variable configuration file to avoid hardcoded variables! (easy)

## LESS IMPORTANT!
# Other encrypted partitions (home, data, etc...) (easy-mid)
# Add support for unofficially supported desktops & kernels??? << (Add option for supplying kernel source to be compiled???) (mid)
# Configure bios support (mid-hard)
# Foreign bootloader support (mid-hard)
# Improved error handling (unknown...)

###VARIABLES_START
# Configuration Variables
WIFI_SSID="redacted" # not required when ethernet is connected
KERNEL="linux-zen" # linux/linux-lts/linux-zen/linux-hardened # linux-rt/linux-rt-lts
DRIVE_ID="/dev/sda"; part_prefix=""
gamermode="true"
HOSTNAME="Archie Gaming"
USERNAME="oakley"
USER_PASSWD="Cd83649dC!*"
ROOT_PASSWD="Cd83649dC!*"
CPU_TYPE="amd" # intel/amd
DESKTOP_ENVIRONMENT="kde-plasma"
additonal_pacman_packages=""
yay_packages="sublime-text-4 curseforge"

# Drive Patition Sizes
boot_size_mb="1024"
swap_size_gb="15" 
root_size_gb="220"
#auto_part_sizing=false # use configured percentages instead of configured gb ### WILL NEED HARDCODED MINIMUMS AND MAXIUMS FOR CERTAINS PARTS...

# Global variables
rel_date="UPDATE TIME; Feb 16, 12:44 PM EDT (2025)"
SCRIPT_VERSION="v1.8"
ARCH_VERSION="2025.02.01"
lang="en_US.UTF-8"
timezone="America/New_York"
enable_32b_mlib=true
use_LUKS=true # will be prompted for crypt password
use_SWAP=true
ROOT_ID="root_crypt"
GRUB_ID="GRUB"
base_packages="base base-devel linux-firmware nano grub efibootmgr networkmanager "$cpu_type"-ucode sudo"
custom_packages="wget git curl screen nano konsole thunar net-tools openssh bc go "$additonal_pacman_packages"" # AUDIO PACKAGES (sof-firmware pulseaudio pavucontrol)
yay_aur_helper=true
#SILENCE=false # appends '>/dev/null 2>&1' to the end of noisy commands ## UNTESTED!
###VARIABLES_END

# Function to handle WiFi connection
sanity_check() { #### THIS SHOULD ALSO VERIFY VARIABLES!!
    if [[ $SILENCE == true ]]; then
        NULL_VAR=">/dev/null 2>&1"
    else
        NULL_VAR=""
    fi

    if ! ping 1.1.1.1 -c 1 &> /dev/null; then
        echo "1.1.1.1 PING FAILED! Attempting wireless config!"
        
        wifi_adapter=$(iwconfig 2>/dev/null | grep -o '^[a-zA-Z0-9]*')
        echo "Wireless Adapter Name: $wifi_adapter"
    
        echo "Connecting to WiFi SSID: $WIFI_SSID" # have user select instead of variable?
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

    swap_size_mb=$((swap_size_gb * 1024))
    root_size_mb=$((root_size_gb * 1024))

    sgdisk --zap-all "$DRIVE_ID" $NULL_VAR
    parted "$DRIVE_ID" mklabel gpt $NULL_VAR

    parted "$DRIVE_ID" mkpart ESP fat32 1MiB "${boot_size_mb}MiB" $NULL_VAR
    parted "$DRIVE_ID" set 1 boot on $NULL_VAR

    if [[ $use_SWAP == true ]]; then
        root_part=""$part_prefix"3"
        parted "$DRIVE_ID" mkpart primary linux-swap "${boot_size_mb}MiB" "$((boot_size_mb + swap_size_mb))MiB" $NULL_VAR
        parted "$DRIVE_ID" mkpart primary ext4 "$((boot_size_mb + swap_size_mb))MiB" "$((boot_size_mb + swap_size_mb + root_size_mb))MiB" $NULL_VAR
    else
        root_part=""$part_prefix"2"
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

    mkfs.fat -F32 "$DRIVE_ID""$part_prefix"1 $NULL_VAR

    if [[ $use_SWAP == true ]]; then
        mkswap "$DRIVE_ID""$part_prefix"2 $NULL_VAR
        swapon "$DRIVE_ID""$part_prefix"2 $NULL_VAR
    fi
}

# Function to mount partitions
auto_mount() {
    echo "Mounting Partitions..."
    if [[ $use_LUKS == true ]]; then
        mount "/dev/mapper/$ROOT_ID" /mnt $NULL_VAR
    else
        mount "$DRIVE_ID""$root_part" /mnt $NULL_VAR
    fi
    mkdir -p /mnt/boot
    mount "$DRIVE_ID""$part_prefix"1 /mnt/boot $NULL_VAR
    sleep 10
}

# Function to perform pacstrap installation
pacstrap_install() {
    echo "Installing Base System Packages..."
    case $DESKTOP_ENVIRONMENT in # surely theres a more efficient way to do this...
        budgie)
            desktop_packages="budgie sddm" # untested
            ;;
        cinnamon)
            desktop_packages="cinnamon sddm" # untested
            ;;
        cosmic)
            desktop_packages="cosmic sddm" # untested
            ;;
        cutefish)
            desktop_packages="cutefish sddm" # untested
            ;;
        deepin)
            desktop_packages="deepin sddm" # untested
            ;;
        enlightenment)
            desktop_packages="enlightenment sddm" # untested
            ;;
        gnome)
            desktop_packages="gnome sddm" # untested
            ;;
        gnome-flashback)
            desktop_packages="gnome-flashback sddm" # untested
            ;;
        kde-plasma)
            desktop_packages="xorg plasma sddm" # not working on fleex...
            ;;
        lxde)
            desktop_packages="lxde sddm" # untested
            ;;
        lxde-gtk3)
            desktop_packages="lxde-gtk3 sddm" # untested
            ;;
        lxqt)
            desktop_packages="lxqt sddm" # untested
            ;;
        mate)
            desktop_packages="mate sddm" # untested
            ;;
        pantheon)
            desktop_packages="pantheon sddm" # untested
            ;;
        phosh)
            desktop_packages="phosh sddm" # untested
            ;;
        sugar)
            desktop_packages="sugar sugar-fructose sddm" # untested
            ;;
        ukui)
            desktop_packages="ukui sddm" # untested
            ;;
        xfce)
            desktop_packages="xfce4 xfce4-goodies sddm" # works perfect on fleex!
            ;;
        *)
            echo "Invalid or no desktop environment set ($DESKTOP_ENVIRONMENT) going with none..."
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

    if [[ $gamermode == "true" ]]; then ## add proper driver to package list for nvidia rtx 4060
        nvidia_driver="nvidia-dkms libglvnd nvidia-utils opencl-utils lib32-libglvnd lib32-nvidia-utils lib32-opencl-nvidia nvidia-settings"
    fi

    pacstrap -i /mnt $base_packages $desktop_packages $custom_packages $nvidia_driver --noconfirm
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
        swapoff "$DRIVE_ID""$part_prefix"2 $NULL_VAR
    fi

    echo "Installation completed successfully. You can now reboot your system."
}

# Main script execution starts here

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
exit

######### PART 2

###PART2_START
#!/bin/bash
source variables

# Determine root and home partitions based on conditions
if [[ $use_SWAP == true ]]; then
    root_part=""$part_prefix"3"
else
    root_part=""$part_prefix"2"
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
    hwclock --systohc $NULL_VAR
    echo "$HOSTNAME" > "/etc/hostname"

    # Enable SSD trimming if necessary
    #systemctl enable fstrim.timer $NULL_VAR

    # Enable 32-bit multilib if necessary
    if [[ $enable_32b_mlib == true ]]; then
        sed -i '92,93 s/^#//' "/etc/pacman.conf"
        yes | pacman -Sy $NULL_VAR
    fi

    # Configure hosts file
    echo "127.0.0.1 localhost
::1 localhost
127.0.1.1 $HOSTNAME.localdomain $HOSTNAME" >> "/etc/hosts"

    # Create and configure non-root user
    groupadd sudo $NULL_VAR
    useradd -mG sudo "$USERNAME" $NULL_VAR # testing removal of wheel group...
    echo "%sudo ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

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

    if [[ $gamermode == "true" ]]; then
        sed -i '/^MODULES=/ s/)$/nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' "/etc/mkinitcpio.conf"
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

    if [[ $gamermode == "true" ]]; then
        new_value="$new_value nvidia-drm.modeset=1"

        mkdir -p /etc/pacman.d/hooks
        cat << EOF >> /etc/pacman.d/hooks/nvidia.hook
# /etc/pacman.d/hooks/nvidia.hook
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = nvidia

[Action]
Description = Updating NVIDIA driver
Depends=mkinitcpio
When = PostTransaction
Exec = /usr/bin/mkinitcpio -P
EOF
    fi

    sed -i '7c\GRUB_CMDLINE_LINUX="'"$new_value"'"' "/etc/default/grub"
    grub-mkconfig -o "/boot/grub/grub.cfg" $NULL_VAR

    # Enable necessary services
    systemctl enable NetworkManager $NULL_VAR

    if [[ ! -z $DESKTOP_ENVIRONMENT ]]; then
        systemctl enable sddm.service $NULL_VAR
    fi

    # Install Yay AUR helper if needed
    if [[ $yay_aur_helper == true ]]; then
        git clone https://aur.archlinux.org/yay.git $NULL_VAR
        mv yay /home/$USERNAME/
        chown -R $USERNAME:$USERNAME /home/$USERNAME/yay
        cd /home/$USERNAME/yay
        yes | sudo -u $USERNAME makepkg -si --noconfirm
        if [[ ! -z $yay_packages ]]; then
            sudo -u $USERNAME yay -S $yay_packages --noconfirm
        fi
        cd ..
        rm -rf /home/$USERNAME/yay
    fi

    # Restore sudoers configuration
    sed -i 's/%sudo ALL=(ALL) NOPASSWD: ALL/%sudo ALL=(ALL) ALL/g' /etc/sudoers

    # Clean up
    cd /
    rm variables
    rm $0
}

arch_chroot
exit 0
###PART2_END
