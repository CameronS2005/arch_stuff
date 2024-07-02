#!/bin/bash

#### TDL
## Code to fix; (auto_login, luks_header_dump, data_partition, password mismatch loops, silence commands)

###VARIABLES_START
# Define global variables
rel_date="UPDATE TIME; Jul 02, 10:05 PM EDT (2024)"
SCRIPT_VERSION="0.1a"
ARCH_VERSION="2024.06.01"
WIFI_SSID="dacrib"
DRIVE_ID="/dev/mmcblk0"
lang="en_US.UTF-8"
timezone="America/New_York"
use_LUKS=true
use_SWAP=true
use_HOME=false
ROOT_ID="root_crypt"
HOME_ID="home_crypt"
HOSTNAME="Archie"
USERNAME="Archie"
enable_32b_mlib=true
GRUB_ID="GRUB"
DESKTOP_ENVIRONMENT="xfce" # none/plasma/gnome/xfce/lxqt/cinnamon/mate
## Manual drive config
boot_size_mb="500"
swap_size_gb="4"; swap_size_mb=$((swap_size_gb * 1024))
root_size_gb="10"; root_size_mb=$((root_size_gb * 1024))
# Base packages for installation
base_packages="base base-devel linux linux-firmware nano grub efibootmgr networkmanager intel-ucode sudo"
# Desktop environment base packages
xorg_base="xorg-server xorg-apps xorg-xinit xorg-twm xorg-xclock xterm"
plasmaD="plasma-meta sddm"
gnomeD="gnome gdm"
xfceD="xfce4 lightdm"
lxqtD="lxqt lightdm"
cinnamonD="cinnamon lightdm"
mateD="mate lightdm"
###VARIABLES_END

# Function to print release date and current configuration
print_info() {
    cat << EOF
RELEASE DATE; ($rel_date)

CURRENT CONFIG;
-------------------------------------------------
DRIVE_ID="$DRIVE_ID"
lang="$lang"

use_LUKS="$use_LUKS"
use_SWAP="$use_SWAP"
use_HOME="$use_HOME"

ROOT_ID="$ROOT_ID"
HOME_ID="$HOME_ID"

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
    
        echo "You will be prompted for your wifi password if needed!"
        if ! iwctl station $wifi_adapter connect $WIFI_SSID; then
            echo "WIFI CONN ERROR!"
            wifi_connect
        fi
        sleep 10 # Wait for DHCP and IP assignment
        local_ipv4=$(ip -4 addr show up | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n 1)
        echo "Local IPv4 address: $local_ipv4"
    fi
}

# Function to rank pacman mirrors
rank_mirrors() {
    echo "Installing rankedmirrors to get the best mirrors for a faster install!"
    pacman -Syyy pacman-contrib
    cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.bak
    sleep 3
    echo "UPDATING PACMAN MIRRORS! THIS MAY TAKE AWHILE!!"
    rankmirrors -n 6 /etc/pacman.d/mirrorlist.bak > /etc/pacman.d/mirrorlist
}

# Function to automate disk partitioning
auto_partition() {
    read -p "PRESS ENTER TO PARTITION ($DRIVE_ID) DANGER!!!"

    echo "Performing Partition & MBR Wipe & Creating GPT Partition Table!"
    sgdisk --zap-all "$DRIVE_ID"
    parted "$DRIVE_ID" mklabel gpt

    echo "Creating Partitions!"
    parted "$DRIVE_ID" mkpart ESP fat32 1MiB "${boot_size_mb}MiB"  # ESP Partition
    parted "$DRIVE_ID" set 1 boot on

    if [[ $use_SWAP == true ]]; then
        parted "$DRIVE_ID" mkpart primary linux-swap "${boot_size_mb}MiB" "$((boot_size_mb + swap_size_mb))MiB"
        parted "$DRIVE_ID" mkpart primary ext4 "$((boot_size_mb + swap_size_mb))MiB" "$((boot_size_mb + swap_size_mb + root_size_mb))MiB"
    else
        parted "$DRIVE_ID" mkpart primary ext4 "${boot_size_mb}MiB" "$((boot_size_mb + root_size_mb))MiB"
    fi

    if [[ $use_HOME == true ]]; then
        if [[ $use_SWAP == true ]]; then
        	#home_part="p4"
            parted "$DRIVE_ID" mkpart primary ext4 "$((boot_size_mb + root_size_mb + swap_size_mb))MiB" 100%
        else
        	#home_part="p3"
            parted "$DRIVE_ID" mkpart primary ext4 "$((boot_size_mb + root_size_mb))MiB" 100%
        fi
    fi

    # Encrypt partitions if LUKS is enabled
    if [[ $use_LUKS == true ]]; then
        echo "Encrypting Partitions!"
        cryptsetup luksFormat "$DRIVE_ID"p3
        cryptsetup luksOpen "$DRIVE_ID"p3 "$ROOT_ID"
        mkfs.ext4 "/dev/mapper/$ROOT_ID"

        if [[ $use_HOME == true ]]; then
            cryptsetup luksFormat "$DRIVE_ID"p4
            cryptsetup luksOpen "$DRIVE_ID"p4 "$HOME_ID"
            mkfs.ext4 "/dev/mapper/$HOME_ID"
        fi
    else
        mkfs.ext4 "$DRIVE_ID"p2
        if [[ $use_HOME == true ]]; then
            mkfs.ext4 "$DRIVE_ID"p3
        fi
    fi

    mkfs.fat -F32 "$DRIVE_ID"p1

    if [[ $use_SWAP == true ]]; then
        mkswap "$DRIVE_ID"p2
        swapon "$DRIVE_ID"p2
    fi
}

# Function to mount partitions
auto_mount() {
    echo "Mounting Partitions!"
    if [[ $use_LUKS == true ]]; then
        mount "/dev/mapper/$ROOT_ID" /mnt
        if [[ $use_HOME == true ]]; then
            mkdir /mnt/home
            mount "/dev/mapper/$HOME_ID" /mnt/home
        fi
    else
        mount "$DRIVE_ID"p2 /mnt
        if [[ $use_HOME == true ]]; then
            mkdir /mnt/home
            mount "$DRIVE_ID"p3 /mnt/home
        fi
    fi
    mkdir /mnt/boot
    mount "$DRIVE_ID"p1 /mnt/boot
    sleep 10
}

# Function to perform pacstrap installation
pacstrap_install() {
    echo "Installing Base System Packages!"
    pacstrap -i /mnt $base_packages
}

# Function to generate fstab
generate_fstab() {
    echo "Generating fstab!"
    genfstab -U /mnt >> /mnt/etc/fstab
}

# Function to finalize installation in chroot environment
chroot_setup() {
    echo "Finalizing Installation in chroot environment!"

 	seed="#"
	sed -n "/$seed##VARIABLES_START/,/$seed##VARIABLES_END/p" "$0" > /mnt/variables
	sed -n "/$seed##PART2_TAG/,/$seed##PART2_TAG/p" "$0" > /mnt/setup.sh

    # Execute part 2 script inside chroot
    arch-chroot /mnt /bin/bash -c "chmod +x setup.sh && ./setup.sh"
}

# Function to run post-chroot commands
post_chroot() {
    echo "Unmounting filesystems and preparing for reboot!"
    umount -R /mnt
    if [[ $use_SWAP == true ]]; then
        swapoff "$DRIVE_ID"p2
    fi
    echo "You can now safely reboot your system."
    read -p "PRESS ENTER TO REBOOT"
    reboot
}

### Script Execution Starts Here ###

# Print initial information
print_info

# Check EFI firmware presence
if [ ! -d /sys/firmware/efi/efivars ]; then
    echo "ERROR: This script does not support BIOS systems yet!"
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
exit 0
exit 0

######### PART 2

###PART2_TAG
#!/bin/bash
source variables # created by 2nd_config function in pt1

if [[ $use_SWAP == true ]]; then # current hotfix for not using swap.. (this is quite lazy..)
	root_part="p3" # the p is because i use a chromebook with emmc storage with is detected as /dev/mmcblk0 and parts a mmcblk0p1 and so on
	if [[ $use_HOME == true ]]; then
		home_part=p4
	fi
else
	root_part="p2"
	if [[ $use_HOME ]]; then
		home_part=p3
	fi
fi

arch_chroot() {
	echo "Will be prompted to enter new root password"
	if ! passwd; then # TESTING THIS LOOP IN CASE A VERIFY FAILS
		echo "PASSWORD MUST MATCH..."
		passwd
	fi

	sed -i "s/^#\($lang.UTF-8 UTF-8\)/\1/" "/etc/locale.gen"
	locale-gen
	echo "LANG=$lang.UTF-8" > "/etc/locale.conf"
	export "LANG=$lang.UTF-8"

	echo "Setting System Time & Hostname!"
	ln -sf "/usr/share/zoneinfo/$timezone" "/etc/localtime"
	#hwclock --systohc --utc # check 2nd argument # why is this utc? # i dont even use utc...
	sudo hwclock --systohc --localtime
	echo "$HOSTNAME" > "/etc/hostname"

	systemctl enable fstrim.timer # ssd trimming? # add check to see if even using ssd

	if [[ $enable_32b_mlib == true ]]; then
	sed -i '90 s/^#//' "/etc/pacman.conf"
	sed -i '91 s/^#//' "/etc/pacman.conf"
	pacman -Sy
	fi

	echo "Configuring Hosts File With Hostname: ($HOSTNAME)"
	cat << EOF >> "/etc/hosts"
127.0.0.1 		localhost
::1 			localhost
127.0.1.1 		$HOSTNAME.localdomain	$HOSTNAME
EOF

	echo "Creating & Configuring non-root User: ($USERNAME)"
	useradd -mG wheel $USERNAME # modify user permissions here
	#useradd -m -y users -G wheel,storage,power -s /bin/bash $USERNAME

	if [[ $auto_login == true ]]; then
		new_getty_args="ExecStart=-/sbin/agetty -o '-p -f -- \\u' --noclear --autologin username %I \$TERM"

		echo "new_getty_args are >> $new_getty_args << END HERE !!"
		echo "Configuring Autologin for ($USERNAME)"
		#sed -i "s|^ExecStart=-/sbin/agetty \(.*\)|ExecStart=-/sbin/agetty $new_getty_args \1|" "/etc/systemd/system/getty.target.wants/getty@tty1.service"
		#sed -i "s|^ExecStart=-/sbin/agetty \(.*\)|ExecStart=-/sbin/agetty $new_getty_args \\1|" "/etc/systemd/system/getty.target.wants/getty@tty1.service"
		#sed -i "38c\$new_agetty" "/etc/systemd/system/getty.target.wants/getty@tty1.service"

		sed -i '38c\'"$new_getty_args"'' "/etc/systemd/system/getty.target.wants/getty@tty1.service"
	fi

	echo "Will be prompted to enter new password for ($USERNAME)"
	if ! passwd $USERNAME; then
		echo "PASSWORD MUST MATCH..."
		passwd $USERNAME
	fi

	echo "Configuring Bootloader!"
	if [[ $use_LUKS == true ]]; then
	sed -i '/^HOOKS=/ s/)$/ encrypt)/' "/etc/mkinitcpio.conf" # adds encrypt to hooks
	fi
	mkinitcpio -p linux

	grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id="$GRUB_ID"
	grub-mkconfig -o "/boot/grub/grub.cfg"

	ROOT_UUID=$(blkid -s UUID -o value "$DRIVE_ID$root_part")
	HOME_UUID=$(blkid -s UUID -o value "$DRIVE_ID$home_part")

	if [[ $use_LUKS == true ]]; then # can test adding multiple encrypted drives here
	if [[ $use_HOME == true ]]; then
	new_value="cryptdevice=UUID=$ROOT_UUID:$ROOT_ID root=/dev/mapper/$ROOT_ID cryptdevice=UUID=$HOME_UUID:$HOME_ID home=/dev/mapper/$HOME_ID" # TESTING THIS LINE!
else
	new_value="cryptdevice=UUID=$ROOT_UUID:$ROOT_ID root=/dev/mapper/$ROOT_ID"
fi
else
	new_value="root=UUID=$ROOT_UUID" # is this the best way to do this?
fi

	sed -i '7c\GRUB_CMDLINE_LINUX="'"$new_value"'"' "/etc/default/grub" # ...
	grub-mkconfig -o "/boot/grub/grub.cfg"
	
	systemctl enable NetworkManager
	#systemctl enable dhcpcd
	#systemctl enable iwd 
	#systemctl enable bluetooth

	rm variables
	rm $0 # 
	echo "FINISHED! EXITING CHROOT!"
	exit # we need to exit chroot here not just the script... << NOT WORKING
}
arch_chroot
exit
###PART2_TAG
