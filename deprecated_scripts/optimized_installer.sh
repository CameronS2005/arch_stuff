#!/bin/bash

## Code to fix/add; (auto_login, luks_header_dump, home_partition, data_partition, auto_part_sizing, password mismatch loops (script breaks if passwords mismatch happens...)

## More shit to add; (bios support (currently only supports ueif...), Account Password Hash Injection(Required for unattended))

## (Add quiet/verbose option, only input and function calls shall be shown in quiet!)

#### COMAND SILENCING: << MAKE AS MUCH OF THE SCRIPT SILENCE << (ADD ERROR CHECKS IN THE FUTURE SINCE WE WONT SEE THE OUTPUT...)
# Redirect stdout and stderr to /dev/null
# command >/dev/null 2>&1

##### FIND A WAY TO AUTOMATE AS MUCH AS POSSIBLE!! << MAKE SCRIPT UNATTENDED!!!

##### UNATTENDED TDL;
# - pacstrap installs << DONE
# - yay compile (makepkg -si) << fixing...
# - password sets (passwd $USERNAME) << DONE

###VARIABLES_START
# Define global variables
rel_date="UPDATE TIME; Jul 06, 2:47 PM EDT (2024)"
SCRIPT_VERSION="v1.5" # 5th iteration of arch install script (CURRENT)
ARCH_VERSION="2024.06.01" # Linux Kernel 6.9.7
##
WIFI_SSID="dacrib"
DRIVE_ID="/dev/mmcblk0" # CHECK THIS!! THIS IS THE INSTALL DRIVE!! FOR ME ITS MY CHROMEBOOKS EMMC
lang="en_US.UTF-8"
timezone="America/New_York" # i dont think time is currently getting set correctly...
HOSTNAME="Archie Box"
USERNAME="Archie"
USER_PASSWD="password123"
ROOT_PASSWD="password123"
#USER_PASSWD_HASH="" ## <<< NOT IMPLEMENTED YET... :(
#ROOT_PASSWD_HASH="" ## <<< NOT IMPLEMENTED YET... :(
#auto_login=false ## <<< NOT IMPLEMENTED YET... :(
enable_32b_mlib=true
#luks_header_dump=false ## <<< NOT IMPLEMENTED YET... :(
#BIOS="uefi" ## <<< NOT IMPLEMENTED YET... :( << ADD SUPPORT FOR bios and others
GRUB_ID="GRUB"
DESKTOP_ENVIRONMENT="gnome" # none/plasma/gnome/xfce/lxqt/cinnamon/mate
#logging="verbose" # quiet/verbose

## Manual drive config
use_LUKS=true
use_SWAP=true
#use_HOME=false ## testing << NEEDS FIXED, CURRENTLY WHEN ENABLED INSTEAD OF BOOTING TO DECRYPT ROOTS IT SHOWS UP TO DECRYPT HOME AND AFTER FAILS TO BOOT
#use_DATA=false ## <<< NOT IMPLEMENTED YET... :(
ROOT_ID="root_crypt"
#HOME_ID="home_crypt"
#DATA_ID="data_crypt"
#auto_part_sizing=false ## <<< NOT IMPLEMENTED YET... :(
boot_size_mb="500" # TOTAL: 14.7gb (used 14.5gb)
swap_size_gb="4"; swap_size_mb=$((swap_size_gb * 1024)) # this math can be done elsewhere...
root_size_gb="10"; root_size_mb=$((root_size_gb * 1024))
#home_size_gb="00"; home_size_mb=$((home_size_gb * 1024))
#data_size_gb="00"; data_size_mb=$((data_size_gb * 1024))

# Base packages for installation
base_packages="base base-devel linux linux-firmware nano grub efibootmgr networkmanager intel-ucode sudo" # 173 packages
custom_packages="wget git curl screen nano firefox konsole thunar openssh net-tools wireguard-tools bc go"
yay_aur_helper=true # install yay? ## TEMPORARILY DISABLED WHILE TESTING UNATTENDED INSTALL!
yay_packages="sublime-text-4" ## can install pretty much anything here...

# Desktop environment base packages ## Broke desktops... (mate)
xorg_base="xorg-server xorg-apps xorg-xinit xorg-twm xorg-xclock xterm"
plasmaD="plasma-meta sddm"
gnomeD="gnome gdm"
xfceD="xfce4 sddm"
lxqtD="lxqt sddm"
cinnamonD="cinnamon sddm"
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

# Function to handle WiFi connection #### MAY REMOVE AS WIFI MUST BE CONFIGURED BEFORE GETTING THE SCRIPT ANYWAYS...
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
rank_mirrors() { ## FUNCTION UNTESTED
    echo "Installing rankedmirrors to get the best mirrors for a faster install!"
    pacman -Syyy pacman-contrib --noconfirm
    cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.bak
    sleep 3
    echo "UPDATING PACMAN MIRRORS! THIS MAY TAKE AWHILE!!"
    rankmirrors -n 6 /etc/pacman.d/mirrorlist.bak > /etc/pacman.d/mirrorlist

    #clear
}

# Function to automate disk partitioning
auto_partition() {
    read -p "PRESS ENTER TO PARTITION ($DRIVE_ID) DANGER!!!"

    echo "Performing Partition & MBR Wipe & Creating GPT Partition Table!"
    sgdisk --zap-all "$DRIVE_ID" >/dev/null 2>&1
    parted "$DRIVE_ID" mklabel gpt >/dev/null 2>&1

    echo "Creating Partitions!"
    parted "$DRIVE_ID" mkpart ESP fat32 1MiB "${boot_size_mb}MiB" >/dev/null 2>&1  # ESP Partition
    parted "$DRIVE_ID" set 1 boot on >/dev/null 2>&1

    if [[ $use_SWAP == true ]]; then
        parted "$DRIVE_ID" mkpart primary linux-swap "${boot_size_mb}MiB" "$((boot_size_mb + swap_size_mb))MiB" >/dev/null 2>&1
        parted "$DRIVE_ID" mkpart primary ext4 "$((boot_size_mb + swap_size_mb))MiB" "$((boot_size_mb + swap_size_mb + root_size_mb))MiB" >/dev/null 2>&1
    else
        parted "$DRIVE_ID" mkpart primary ext4 "${boot_size_mb}MiB" "$((boot_size_mb + root_size_mb))MiB" >/dev/null 2>&1
    fi

    if [[ $use_HOME == true ]]; then
        if [[ $use_SWAP == true ]]; then
        	#home_part="p4"
            parted "$DRIVE_ID" mkpart primary ext4 "$((boot_size_mb + root_size_mb + swap_size_mb))MiB" 100% #>/dev/null 2>&1
        else
        	#home_part="p3"
            parted "$DRIVE_ID" mkpart primary ext4 "$((boot_size_mb + root_size_mb))MiB" 100% #>/dev/null 2>&1
        fi
    fi

    # Encrypt partitions if LUKS is enabled
    if [[ $use_LUKS == true ]]; then
        echo "Encrypting Partitions!"
        cryptsetup luksFormat "$DRIVE_ID"p3
        cryptsetup luksOpen "$DRIVE_ID"p3 "$ROOT_ID"
        mkfs.ext4 "/dev/mapper/$ROOT_ID" >/dev/null 2>&1

        if [[ $use_HOME == true ]]; then
            cryptsetup luksFormat "$DRIVE_ID"p4
            cryptsetup luksOpen "$DRIVE_ID"p4 "$HOME_ID"
            mkfs.ext4 "/dev/mapper/$HOME_ID" >/dev/null 2>&1
        fi
    else
        mkfs.ext4 "$DRIVE_ID"p2 >/dev/null 2>&1
        if [[ $use_HOME == true ]]; then
            mkfs.ext4 "$DRIVE_ID"p3 >/dev/null 2>&1
        fi
    fi

    mkfs.fat -F32 "$DRIVE_ID"p1 >/dev/null 2>&1

    if [[ $use_SWAP == true ]]; then
        mkswap "$DRIVE_ID"p2 >/dev/null 2>&1
        swapon "$DRIVE_ID"p2 >/dev/null 2>&1
    fi

    #clear
}

# Function to mount partitions
auto_mount() {
    echo "Mounting Partitions!"
    if [[ $use_LUKS == true ]]; then
        mount "/dev/mapper/$ROOT_ID" /mnt >/dev/null 2>&1
        if [[ $use_HOME == true ]]; then
            mkdir /mnt/home
            mount "/dev/mapper/$HOME_ID" /mnt/home >/dev/null 2>&1
        fi
    else
        mount "$DRIVE_ID"p2 /mnt
        if [[ $use_HOME == true ]]; then
            mkdir /mnt/home
            mount "$DRIVE_ID"p3 /mnt/home >/dev/null 2>&1
        fi
    fi
    mkdir /mnt/boot
    mount "$DRIVE_ID"p1 /mnt/boot >/dev/null 2>&1
    sleep 10

    #clear
}

# Function to perform pacstrap installation
pacstrap_install() {
    echo "Installing Base System Packages!"

  	case $DESKTOP_ENVIRONMENT in
	 plasma)desktop_packages="$xorg_base $plasmaD"
	    ;;
	 gnome) desktop_packages="$xorg_base $gnomeD"
	    ;;
	 xfce) desktop_packages="$xorg_base $xfceD"
	    ;;
	 lxqt) desktop_packages="$xorg_base $lxqtD"
	    ;;
	 cinnamon) desktop_packages="$xorg_base $cinnamonD"
	    ;;
	 mate) desktop_packages="$xorg_base $mateD"
	    ;;
	 none) desktop_packages=""
		;;
	 *)    echo "Invalid Desktop Environment Option!"
	    ;;
esac

    pacstrap -i /mnt $base_packages $desktop_packages $custom_packages --noconfirm

    #clear
}

# Function to generate fstab
generate_fstab() {
    echo "Generating fstab!"
    genfstab -U /mnt >> /mnt/etc/fstab

    #clear
}

# Function to finalize installation in chroot environment
chroot_setup() {
    echo "Finalizing Installation in chroot environment!"

 	seed="#"
	sed -n "/$seed##VARIABLES_START/,/$seed##VARIABLES_END/p" "$0" > /mnt/variables
	sed -n "/$seed##PART2_START/,/$seed##PART2_END/p" "$0" > /mnt/setup.sh

	echo "RUN: chmod +x setup.sh; ./setup.sh"
	echo "TESTING EDIT: RUN: arch-chroot /mnt"
	exit 
	arch-chroot /mnt # needs fixed...
	#exit 0# TESTING

#    arch-chroot /mnt << EOF
#chmod +x setup.sh && ./setup.sh && exit
#EOF
#clear
}

# Function to run post-chroot commands
post_chroot() {
    echo "Unmounting filesystems and preparing for reboot!"
    umount -R /mnt
    if [[ $use_SWAP == true ]]; then
        swapoff "$DRIVE_ID"p2 >/dev/null 2>&1
    fi
    echo "You can now safely reboot your system."
    #read -p "PRESS ENTER TO REBOOT"
    #reboot
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
#rank_mirrors ## FUNCTION UNTESTED!!

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

###PART2_START
#!/bin/bash
source variables

if [[ $use_SWAP == true ]]; then
	root_part="p3"
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
	echo "root:$ROOT_PASSWD" | chpasswd

	sed -i "s/^#\($lang UTF-8\)/\1/" "/etc/locale.gen"
	locale-gen >/dev/null 2>&1
	echo "LANG=$lang" > "/etc/locale.conf"
	export "LANG=$lang" >/dev/null 2>&1

	echo "Setting System Time & Hostname!"
	ln -sf "/usr/share/zoneinfo/$timezone" "/etc/localtime" >/dev/null 2>&1
	hwclock --systohc --localtime >/dev/null 2>&1
	echo "$HOSTNAME" > "/etc/hostname"

	systemctl enable fstrim.timer >/dev/null 2>&1 # ssd trimming? # add check to see if even using ssd

	if [[ $enable_32b_mlib == true ]]; then
	sed -i '90 s/^#//' "/etc/pacman.conf"
	sed -i '91 s/^#//' "/etc/pacman.conf"
	pacman -Sy --noconfirm >/dev/null 2>&1
	fi

	echo "Configuring Hosts File With Hostname: ($HOSTNAME)"
	cat << EOF >> "/etc/hosts"
127.0.0.1 		localhost
::1 			localhost
127.0.1.1 		$HOSTNAME.localdomain	$HOSTNAME
EOF

	echo "Creating & Configuring non-root User: ($USERNAME)"
	groupadd sudo >/dev/null 2>&1
	useradd -mG wheel,sudo $USERNAME >/dev/null 2>&1

	sed -i '$ a\%sudo ALL=(ALL) NOPASSWD: ALL' /etc/sudoers
	service sudo restart >/dev/null 2>&1

	if [[ $auto_login == true ]]; then ### NEEDS FIXED!!!
		new_getty_args="ExecStart=-/sbin/agetty -o '-p -f -- \\u' --noclear --autologin username %I \$TERM"

		echo "new_getty_args are >> $new_getty_args << END HERE !!"
		echo "Configuring Autologin for ($USERNAME)"
		#sed -i "s|^ExecStart=-/sbin/agetty \(.*\)|ExecStart=-/sbin/agetty $new_getty_args \1|" "/etc/systemd/system/getty.target.wants/getty@tty1.service"
		#sed -i "s|^ExecStart=-/sbin/agetty \(.*\)|ExecStart=-/sbin/agetty $new_getty_args \\1|" "/etc/systemd/system/getty.target.wants/getty@tty1.service"
		#sed -i "38c\$new_agetty" "/etc/systemd/system/getty.target.wants/getty@tty1.service"

		sed -i '38c\'"$new_getty_args"'' "/etc/systemd/system/getty.target.wants/getty@tty1.service"
	fi

	echo "$USERNAME:$USER_PASSWD" | chpasswd

	echo "Configuring Bootloader!"
	if [[ $use_LUKS == true ]]; then
		sed -i '/^HOOKS=/ s/)$/ encrypt)/' "/etc/mkinitcpio.conf" # adds encrypt to hooks
	fi
	mkinitcpio -p linux >/dev/null 2>&1

	grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id="$GRUB_ID" >/dev/null 2>&1
	grub-mkconfig -o "/boot/grub/grub.cfg" >/dev/null 2>&1

	ROOT_UUID=$(blkid -s UUID -o value "$DRIVE_ID$root_part")
	HOME_UUID=$(blkid -s UUID -o value "$DRIVE_ID$home_part")

	if [[ $use_LUKS == true ]]; then
	if [[ $use_HOME == true ]]; then
	new_value="cryptdevice=UUID=$ROOT_UUID:$ROOT_ID root=/dev/mapper/$ROOT_ID cryptdevice=UUID=$HOME_UUID:$HOME_ID home=/dev/mapper/$HOME_ID" # TESTING THIS LINE!
	### ^^ THIS LINE DOESNT WORK, IF LUKS & HOME ARE ENABLED BOOT WILL FAIL! AS WE DONT GET TO DECRYPT ROOT ON HOME
else
	new_value="cryptdevice=UUID=$ROOT_UUID:$ROOT_ID root=/dev/mapper/$ROOT_ID"
fi
else
	new_value="root=UUID=$ROOT_UUID"
fi

	sed -i '7c\GRUB_CMDLINE_LINUX="'"$new_value"'"' "/etc/default/grub"
	grub-mkconfig -o "/boot/grub/grub.cfg" >/dev/null 2>&1
	
	systemctl enable NetworkManager >/dev/null 2>&1
	systemctl enable sddm.service >/dev/null 2>&1
	systemctl enable lightdm.service >/dev/null 2>&1
	systemctl enable gdm.service >/dev/null 2>&1

	if [[ $yay_aur_helper == true ]]; then ## TESTING!!
    	git clone https://aur.archlinux.org/yay.git >/dev/null 2>&1
    	#cd yay
    	mv yay home/$USERNAME/
    	chown -R $USERNAME:$USERNAME home/$USERNAME/yay
    	cd home/$USERNAME/yay
    	#clear
    	yes | sudo -u $USERNAME makepkg -si
    	sudo -u $USERNAME yay -S $yay_packages --noconfirm
    	cd ../
    	rm -rf yay
    fi

    sed -i 's/%sudo ALL=(ALL) NOPASSWD: ALL/%sudo ALL=(ALL) ALL/g' /etc/sudoers ## TESTING THIS LINE!
	service sudo restart >/dev/null 2>&1

    cd /
	rm variables
	rm $0
}
arch_chroot
exit
###PART2_END
