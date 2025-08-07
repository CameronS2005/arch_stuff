#!/bin/bash

#### TDL;

# fully disable ipv6 (easy) (disable in both sysctl and kernel args)
# Optional detached luks header
# Add support for installing multiple desktop environments (should be able to choose in sddm or switch to lxde?)

###VARIABLES_START
# Version info
rel_date="UPDATE TIME; Aug 07, 03:36 PM EDT (2025)"
SCRIPT_VERSION="v1.9b"
ARCH_VERSION="2025.08.01"

# Configuration Variables
WIFI_SSID="redacted"
KERNEL="linux-hardend" # linux/linux-lts/linux-zen/linux-hardened
DRIVE_ID="/dev/nvme0n1"; part_prefix="p" # sda=noprefix, nvme/mmcblk=p
is_ssd="true" # enable ssd trim
is_t2mac="false" # use for intel based macs with the t2 security implementation
gamermode="true"; GPU_TYPE="nvidia" # (nvidia, intel, amd)
DESKTOP_ENVIRONMENT="plasma" # (gnome, plasma, xfce, i3-wm, etc...)
CPU_TYPE="intel" # (intel, amd)
#auto_login="false" # untested
enable_32b_mlib=true # required for some software like steam aswell as 32bit drivers
use_LUKS=false # use luks encryption for root partition
use_SWAP=true
use_RICER=false # currently only support i3-wm

# Login
hostname="archlinux-box"
USERNAME="archie"
USER_PASSWD="redacted"
ROOT_PASSWD="redacted"

# Drive Patition Sizes
boot_size_mb="512"
swap_size_gb="20" 
root_size_gb="200"
#auto_part_sizing=false # NOT IMPLEMENTED!

# Packages
yay_packages="sublime-text-4"
base_packages="base linux-firmware iwd networkmanager grub efibootmgr "$CPU_TYPE"-ucode sudo konsole"
t2_base_packages="base linux-firmware iwd networkmanager grub efibootmgr intel-ucode sudo konsole linux-t2 linux-t2-headers apple-t2-audio-config apple-bcm-firmware t2fanrd" # we could just add these onto base_packages if is t2-mac
custom_packages="base-devel wget git curl screen nano zip unzip thunar net-tools openssh bc jq go htop fastfetch firefox feh python-pywal"

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
    read -p "PRESS ANY KEY TO PARTITION ($DRIVE_ID) DANGER!!! (ELSE PRESS CTRL+C TO EXIT)"

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

mac_partition() {
    echo "Setting up linux dual boot environment for t2-mac..."
    echo "ENSURE YOU HAVE ALREADY MANUALLY PARTITIONED THE DRIVE AS THE SCRIPT EXPECTS (p1=boot,p2=macos,p3=swap,p4=root"
    read -p "PRESS ANY KEY TO PARTITION ($DRIVE_ID) DANGER!!! (ELSE PRESS CTRL+C TO EXIT)"

    # Convert gb to mb
    swap_size_mb=$((swap_size_gb * 1024))
    root_size_mb=$((root_size_gb * 1024))

    # Determine root and home partitions based on conditions
    if [[ $use_SWAP == true ]]; then
        #if [[ $is_t2mac == true ]]; then
        #    root_part=""$part_prefix"4" # t2 with swap
        #else
            root_part=""$part_prefix"3" # non t2 with swap
        #fi
    else
        #if [[ $is_t2mac == "true" ]]; then
        #    root_part=""$part_prefix"3" # t2 no swap
        #else
            root_part=""$part_prefix"2" # non t2 no swap
        #fi
    fi

    # Encrypt partitions if LUKS is enabled
    if [[ $use_LUKS == true ]]; then
        cryptsetup luksFormat "$DRIVE_ID""$root_part"
        cryptsetup luksOpen "$DRIVE_ID""$root_part" "$ROOT_ID"
        mkfs.ext4 "/dev/mapper/$ROOT_ID" $NULL_VAR
    else
        mkfs.ext4 "$DRIVE_ID""$root_part" $NULL_VAR
    fi

    # Handle swap
    if [[ $use_SWAP == true ]]; then
        mkswap "$DRIVE_ID""$part_prefix"3 $NULL_VAR
        swapon "$DRIVE_ID""$part_prefix"3 $NULL_VAR
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
    mkdir -p /mnt/boot/efi
    mount "$DRIVE_ID""$part_prefix"1 /mnt/boot/efi
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
        i3-wm)
            desktop_packages="i3-wm i3status dmenu sddm" # first tiling manager test!
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

    # Enable 32-bit multilib if necessary
    if [[ $enable_32b_mlib == true ]]; then
        sed -i '92,93 s/^#//' "/etc/pacman.conf"
        yes | pacman -Sy $NULL_VAR
    fi

    if [[ $gamermode == "true" ]]; then ## add proper driver to package list for nvidia rtx 4060
        if [[ $GPU_TYPE == "nvidia" ]]; then
            gpu_drivers="nvidia-dkms libglvnd nvidia-utils nvidia-settings lib32-libglvnd lib32-nvidia-utils lib32-opencl-nvidia"
        if [[ $GPU_TYPE == "intel" ]]; then
            gpu_drivers="mesa vulkan-intel lib32-vulkan-intel lib32-mesa"
        if [[ $GPU_TYPE == "amd" ]]; then
            gpu_drivers="mesa vulkan-radeon lib32-vulkan-radeon lib32-mesa" # may needs to use (amdvlk and lib32-amdvlk)
    fi; fi; fi; fi

    if [[ $is_t2mac == "true" ]]; then
        base_packages="$t2_base_packages"

        cat <<EOF >> "/etc/pacman.conf"
[arch-mact2]
Server = https://mirror.funami.tech/arch-mact2/os/x86_64
SigLevel = Never
EOF

        cat <<EOF >> "/mnt/etc/pacman.conf"
[arch-mact2]
Server = https://mirror.funami.tech/arch-mact2/os/x86_64
SigLevel = Never
EOF
    fi

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
    if [[ $use_SWAP == "true" ]]; then
        #if [[ $is_t2mac == "true" ]]; then
        #    swapoff "$DRIVE_ID""$part_prefix"3 $NULL_VAR
        #else
            swapoff "$DRIVE_ID""$part_prefix"2 $NULL_VAR
        #fi
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

#if [[ $is_t2mac == "false" ]]; then
    # Perform auto partitioning
    auto_partition
#else
#    mac_partition # unlike auto partition we expect there to already be a boot loader in the first partition and the root partition for both mac and linux to already exist. (boot=p1, macroot=p2, linuxswap=p3, linuxroot=p4)
#fi

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
    #if [[ $is_t2mac == true ]]; then
    #    root_part=""$part_prefix"4" # t2 with swap
    #else
        root_part=""$part_prefix"3" # non t2 with swap
    #fi
else
    #if [[ $is_t2mac == "true" ]]; then
    #    root_part=""$part_prefix"3" # t2 no swap
    #else
        root_part=""$part_prefix"2" # non t2 no swap
    #fi
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
    echo "$hostname" > "/etc/hostname"

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
127.0.1.1 $hostname.localdomain $hostname" >> "/etc/hosts"

    # Create and configure non-root user
    groupadd sudo $NULL_VAR
    useradd -mG sudo "$USERNAME" $NULL_VAR
    useradd -mG power "$USERNAME" $NULL_VAR
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

    if [[ $is_t2mac == "true" ]]; then
        sed -i '/^MODULES=/ s/)$/apple-bce)/' "/etc/mkinitcpio.conf"
        systemctl enable t2fanrd
    fi

    mkinitcpio -P $KERNEL

    if [[ $is_t2mac == "false" ]]; then
        grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id="$GRUB_ID" $NULL_VAR
    else
        grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id="$GRUB_ID" --removable $NULL_VAR # i dunno shown in the t2 wiki
    fi

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

    if [[ $is_t2mac == "true" ]]; then
        if [[ -z "$new_value" ]]; then
            new_value="intel_iommu=on iommu=pt pcie_ports=compat"
        else
            new_value="$new_value intel_iommu=on iommu=pt pcie_ports=compat"
        fi
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
    #sed -i 's/%sudo ALL=(ALL) NOPASSWD: ALL/%sudo ALL=(ALL) ALL/g' /etc/sudoers

    if [[ $use_RICER == "true" && $DESKTOP_ENVIRONMENT == "i3-wm" ]]; then
        cd /home/$USERNAME/
        sudo -u $USERNAME curl -LO "https://github.com/CameronS2005/arch_stuff/raw/refs/heads/main/wallpapers.zip"
        sudo -u $USERNAME unzip wallpapers.zip && rm wallpapers.zip

        if command -v "feh" &> /dev/null; then
            sudo -u $USERNAME feh --bg-scale "/home/$USERNAME/wallpapers/3840x2160/moon_1.jpg"
        else
            echo "ERRRO! feh not found.."
        fi

        if command -v "wal" &> /dev/null; then
            sudo -u $USERNAME wal -i "/home/$USERNAME/wallpapers/3840x2160/moon_1.jpg"
            sudo -u $USERNAME echo "exec_always --no-startup-id wal -R" >> "/home/$USERNAME/.config/i3/config"
        else
            echo "ERRRO! wal not found.."
        fi

    fi

    if [[ $DESKTOP_ENVIRONMENT == "i3-wm" ]]; then
        echo "exec i3" >> /home/$USERNAME/.xinitrc
    fi

    if [[ $gamermode == "true" && $GPU_TYPE == "nvidia" ]]; then ## TESTING
        echo "RUNNING nvidia-xconfig!"
        nvidia-xconfig
    fi

    # Clean up
    cd /
    rm variables
    rm $0
}

arch_chroot
exit 0
###PART2_END
