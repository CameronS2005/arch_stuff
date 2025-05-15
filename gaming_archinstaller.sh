#!/bin/bash

#### TDL;

# partitioning change! (currently we insist on zapping the drive and creating a new parition table which destroys all data!)
## ^ need to add option to instead of using automatic patitioning we use an already formatted boot partition and simply format a given root partition as ext4 (to support dual booting!)

# Implement tiling managers (aswell as the option to preinstall rice dotfiles!)

# fully disable ipv6 (easy) (disable in both sysctl and kernel args)
# Optional detached luks header (mid) << THIS NEEDS TO BE DONE ASAP!!! (IN THE EVENT OF HEADER CORRUPTION DATA RECOVERY WOULD BE IMPOSSIBLE WITHOUT BACKUP!) (BACKUP TO USB DURING FIRST INSTALL!)


###VARIABLES_START
# Version info
rel_date="UPDATE TIME; May 14, 09:02 PM EDT (2025)"
SCRIPT_VERSION="v1.9b"
ARCH_VERSION="2025.05.01"

# Configuration Variables
WIFI_SSID="redacted"
KERNEL="linux-zen" # linux/linux-lts/linux-zen/linux-hardened
DRIVE_ID="/dev/mmcblk0"; part_prefix="p" # sda=noprefix, nvme/mmcblk=p
is_ssd="true" # enable ssd trim
gamermode="true"; GPU_TYPE="nvidia" # (nvidia, intel, amd)
CPU_TYPE="amd" # (intel, amd)
#auto_login="false" # untested
enable_32b_mlib=true # required for some software like steam aswell as 32bit nvidia drivers
use_LUKS=true # use luks encryption for root partition
use_SWAP=true

# Login
HOSTNAME="archlinux-box"
USERNAME="archie"
USER_PASSWD="redacted"
ROOT_PASSWD="redacted"

# Drive Patition Sizes
boot_size_mb="512"
swap_size_gb="20" 
root_size_gb="220"
#auto_part_sizing=false # NOT IMPLEMENTED!

# Packages
yay_packages="sublime-text-4 librewolf"
base_packages="base base-devel linux-firmware nano grub efibootmgr networkmanager "$CPU_TYPE"-ucode sudo"
custom_packages="wget git curl screen nano konsole thunar net-tools bc jq go htop neofetch"
#env_type="" # desktop/tiling # not used yet...
DESKTOP_ENVIRONMENT="plasma" # (cinnamon, gnome, plasma, lxde, mate, xfce) ****ALSO**** (budgie, cosmic, cutefish, deepin, enlightment, gnome-flashback, pantheon, phosh, sugar, ukui)
#TILING_ENVIRONMENT="" # (dwm, i3) ****ALSO**** (awesome, bspwm, frankenwm, herbsluftwm, leftwm, notion, qtile, ratpoison, snapwm, spectrwm, stumpwm, xmonad)

# Boring shit (should't usually need changed.)
lang="en_US.UTF-8"
timezone="America/New_York"
ROOT_ID="root_crypt"
GRUB_ID="GRUB"
yay_aur_helper=true # automatically installs yay aur helper
#SILENCE=false # appends '>/dev/null 2>&1' to the end of noisy commands ## UNTESTED!
###VARIABLES_END

# Function to check for internet connection
sanity_check() {
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
        if ! iwctl station $wifi_adapter connect "$WIFI_SSID"; then
            echo "ERROR: Failed to connect to WiFi!"
            exit 1
        fi
        sleep 10 # Wait for DHCP and IP assignment
        local_ipv4=$(ip -4 addr show up | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n 1)
        echo "Local IPv4 address: $local_ipv4"
    fi

    if [[ $USER_PASSWD == "redacted" || $ROOT_PASSWD == "redacted" ]]; then
        echo "it seems to forgot to set the user or root password, be sure to change it from redacted!"
        exit 1
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
    read -p "PRESS ENTER TO PARTITION ($DRIVE_ID) DANGER!!! (ELSE PRESS CTRL+C TO EXIT)"

    # Convert gb to mb
    swap_size_mb=$((swap_size_gb * 1024))
    root_size_mb=$((root_size_gb * 1024))

    # Clear drive and create new gpt partition table (REMOVES ALL DATA)
    sgdisk --zap-all "$DRIVE_ID" $NULL_VAR
    parted "$DRIVE_ID" mklabel gpt $NULL_VAR

    # Create and format first partition for grub bootloader
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
    case $DESKTOP_ENVIRONMENT in
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
        plasma)
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
        if [[ $GPU_TYPE == "nvidia" ]]; then
            gpu_drivers="nvidia-dkms libglvnd nvidia-utils nvidia-settings lib32-libglvnd lib32-nvidia-utils lib32-opencl-nvidia"
        if [[ $GPU_TYPE == "intel" ]]; then
            gpu_drivers="mesa vulkan-intel lib32-vulkan-intel lib32-mesa"
        if [[ $GPU_TYPE == "amd" ]]; then
            gpu_drivers="mesa vulkan-radeon lib32-vulkan-radeon lib32-mesa" # may needs to use (amdvlk and lib32-amdvlk)
    fi; fi; fi; fi

    pacstrap -i /mnt $base_packages $desktop_packages $custom_packages $gpu_drivers --noconfirm
}

# Function to generate fstab
generate_fstab() {
    echo "Generating fstab..."
    genfstab -U /mnt >> /mnt/etc/fstab
}

# Function to finalize installation in chroot environment
chroot_setup() {
    echo "Finalizing Installation in chroot environment!"

    seed="#" # we must use a seed or sed detects its own lines as triggers
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
exit; exit; exit; exit; exit # (just making sure we exitied, as everything past here is strictly meant for the chroot environment!)

######### PART 2

###PART2_START
#!/bin/bash
source variables

if [[ $SILENCE == true ]]; then
    NULL_VAR=">/dev/null 2>&1"
else
    NULL_VAR=""
fi

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
    if [[ $is_ssd == "true" ]]; then
        systemctl enable fstrim.timer $NULL_VAR
    fi

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
    useradd -mG sudo "$USERNAME" $NULL_VAR
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
        if [[ $GPU_TYPE == "nvidia" ]]; then
            sed -i '/^MODULES=/ s/)$/nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' "/etc/mkinitcpio.conf"
    fi; fi

    mkinitcpio -P $KERNEL

    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id="$GRUB_ID" $NULL_VAR

    # Set up cryptdevice if using LUKS and home partition
    ROOT_UUID=$(blkid -s UUID -o value "$DRIVE_ID$root_part")
    if [[ $use_LUKS == true ]]; then
        new_value="cryptdevice=UUID=$ROOT_UUID:$ROOT_ID root=/dev/mapper/$ROOT_ID"
    else
        new_value="root=UUID=$ROOT_UUID"
    fi

    if [[ $gamermode == "true" ]]; then
        if [[ $GPU_TYPE == "nvidia" ]]; then
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
    fi; fi

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

    #### Testing (auto generate xorg nvidia config) << THIS MAY NEED TO BE RAN AFTER A REAL BOOT
    nvidia-xconfig

    # Restore sudoers configuration
    #sed -i 's/%sudo ALL=(ALL) NOPASSWD: ALL/%sudo ALL=(ALL) ALL/g' /etc/sudoers

    # Clean up
    cd /
    rm variables
    rm $0
}

arch_chroot
exit 0
###PART2_END
