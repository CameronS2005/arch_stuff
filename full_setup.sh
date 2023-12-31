#!/bin/bash
rel_date="UPDATE TIME; Aug 11, 10:51 AM EDT"
## VERSION (SED COMMANDS WILL MOST LIKELY NEED UPDATED WITH UPDATES!)

#### HOLY FUCK TRY THIS chroot /path/to/chroot/env /bin/bash <<EOF   CHROOT CODE    EOF
### ^^^ THIS WORKS HOLY SHIT!!!

#### NOTES
# add support for kernel compression
## BOOT PARTITION SIZE NEEDS TO BE HARDCODED AS BIGGER DRIVES WILL WASTE A BUNCH ON part1

## ALOT OF THESE COMMANDS NEED SILENCED!

##### ADD AUTO BACKUP OF HEADER.bin (cryptsetup luksHeaderBackup $DRIVEID$ROOT_PART --header-backup-file HEADER_BACKUP.bin)

### ORGANIZE CONFIG BETTER!
## CONFIG ## BE SURE BOTH CONFIGS MATCH UNTIL WE FIND A WAY TO FIX THIS...
WIFI_SSID="WiFi-2.4"
DRIVE_ID="/dev/mmcblk0"
#keymap= # not implemented as we use default...
lang="en_US" # IS HARDCODED TO BE UTF-8 (MAY ADD ISO SOON)
timezone="America/New_York"

use_LUKS=false # disabled for testing 
#LUKS_header=false
#header_dir="~/tmp"
use_SWAP=true
######## WHEN ADDING THE HOME & DATA DIRECTORIES IT WILL BE EASIEST TO REMOVE HARDCODED PERCENTS AND ASK USER!
#use_HOME=false
#use_DATA=false

ROOT_ID="root_crypt"
#HOME_ID="home_crypt"
#DATA_ID="data_crypt"

HOSTNAME="Archie"
USERNAME="Archie"
auto_login=true # cause of current boot error ## POSSIBLE FIX
#BOOTLOADER="GRUB"
enable_32b_mlib=true
GRUB_ID="GRUB"
#OS_PROBER=false
#is_AMD=false

## NOT IMPLEMENTED
boot_size_mb=""
swap_size_gb=""
root_size_gb=""
#home_size_gb="2"
#data_size_gb="2"

base_packages="base linux linux-firmware nano grub efibootmgr networkmanager intel-ucode" # 148/126?? pkgs (UEFI-BOOT+WIFI+UCODE)
#base_packages="base linux linux-firmware nano grub efibootmgr" # 126?? pkgs (UEFI-BOOT)

2nd_config() { # this is so annoying...
cat << EOF > /mnt/variables
DRIVE_ID="$DRIVE_ID"
lang="$lang"
use_LUKS="$use_LUKS"
LUKS_header="$LUKS_header"
header_dir="$header_dir"
use_SWAP="$use_SWAP"
use_HOME="$use_HOME"
use_DATA="$use_DATA"
ROOT_ID="$ROOT_ID"
HOSTNAME="$HOSTNAME"
USERNAME="$USERNAME"
auto_login="$auto_login"
BOOTLOADER="$BOOTLOADER"
enable_32b_mlib=$enable_32b_mlib
GRUB_ID="$GRUB_ID"
OS_PROBER="$OS_PROBER"
is_AMD="$is_AMD"
boot_size_mb="$boot_size_mb"
swap_size_gb="$swap_size_gb"
root_size_gb="$root_size_gb"
home_size_gb="$home_size_gb"
data_size_gb="$data_size_gb"
#root_part="$root_part" # currently reset in pt 2 as i think it causes a boot error
EOF
}

if [[ $use_SWAP == true ]]; then # current hotfix for not using swap.. (this is quite lazy..)
	root_part="p3" # the p is because i use a chromebook with emmc storage with is detected as /dev/mmcblk0 and parts a mmcblk0p1 and so on
else
	root_part="p2"
fi

### START OF SCRIPT

cat << EOF
RELEASE DATE; ($rel_date)

FYI LUKS IS $use_LUKS
FYI SWAP IS $use_SWAP
Battery is at $(cat /sys/class/power_supply/BAT0/capacity)%
EOF

## SIMPLE BIOS CHECK!
if [ ! "$(ls -A /sys/firmware/efi/efivars)" ]; then # do plan to add support in the future.. current bench doesnt support legacy/bios booting
	echo "ERROR THIS SCRIPT DOESNT SUPPORT BIOS YET!"
	exit
fi

sleep 5

## Handle wifi connection (if no ethernet dhcp)
wifi() {
	if ! ping 1.1.1.1 -c 1 &> /dev/null; then
		echo "1.1.1.1 PING FAILED! Attempting wireless config!"
		
		wifi_adapter=$(iwconfig 2>/dev/null | grep -o '^[a-zA-Z0-9]*')
		echo "Wireless Adapter Name: $wifi_adapter"
	
		echo "You will be prompted for your wifi password if needed!"
		if ! iwctl station $wifi_adapter connect $WIFI_SSID; then
		echo "WIFI CONN ERROR!"
		wifi
	fi
		sleep 10 # modify to a wait command for ipv4 with a timeout of 30s (as we need to wait for dhcp and some are slower than others...)
	
		local_ipv4=$(ip -4 addr show up | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n 1)
		echo "Local IPv4 address: $local_ipv4"
	fi
}
wifi

## Quick way of selecting best mirrors # gracias Muta
rank_mirrors() {
	echo "Installing rankedmirrors to get the best mirrors for a faster install!"
	pacman -Syyy pacman-contrib
	cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.bak
	sleep 3
	echo "UPDATING PACMAN MIRRORS! THIS MAY TAKE AWHILE!!"
	rankmirrors -n 6 /etc/pacman.d/mirrorlist.bak > /etc/pacman.d/mirrorlist
}
#rank_mirrors # this could be disabled as the time it takes might out-weight the time it saves...

## Handle drive partitioning ## IN THE FUTURE MODIFY TO SUPPORT SEPERATE home PARTITION AND PERHAPS A data PARTITION
auto_partition() { # rename to auto drive & add to handle encryption and mounting
	read -p "PRESS ENTER TO PARTITION ($DRIVE_ID)"

	# Remove existing partitions (WARNING: This will delete all data on the drive)
	echo "Performing Partition & MBR Wipe & Creating GPT Partition Table!"
	
	sgdisk --zap-all "$DRIVE_ID"
	parted "$DRIVE_ID" mklabel gpt

	# Get the total size of the drive in MiB
	drive_size=$(parted -s "$DRIVE_ID" print | awk '/Disk/ {print $3}' | sed 's/[^0-9]//g')
	drive_size_mib=$((drive_size / 10 * 1024))

	## CALCULATE PARTITION SIZES (boot is 2%, swap is 15%, root is rest)
	echo "Calculating Partition Sizes Based on Drive Size!"
	boot_size=$((drive_size_mib * 2 / 100))

	if [[ $use_SWAP == true ]]; then
	swap_size=$((drive_size_mib * 15 / 100))
	root_size=$((drive_size_mib - boot_size - swap_size))
else
	root_size=$((drive_size_mib - boot_size))
fi

	## HANDLE OVERRIDES
#if [[ ! -z "$boot_size_mb" ]]; then
#	echo "OVERRIDDEN BOOT PART SIZE!"
#	boot_size="$boot_size_mb"
#fi; if [[ ! -z "$swap_size_gb" && $use_SWAP == true ]]; then
#	echo "OVERRIDDEN SWAP PART SIZE!"
#	swap_size=$((swap_size_gb * 1024)) # gb to mb
#fi; if [[ ! -z "$root_size_gb" ]]; then	
#	echo "OVERRIDDEN ROOT PART SIZE!"
#	root_size=$((root_size_gb * 1024)) # gb to mb
#fi


	# Create partitions
	## USE EQUATION TO DETERMINE SWAP SIZE (BASED ON DISK SIZE AND RAM AMOUNT)
	echo "Creating New Partitions!"
	parted "$DRIVE_ID" mkpart ESP fat32 1MiB "${boot_size}MiB"  # Create EFI System Partition
	parted "$DRIVE_ID" set 1 boot on  # Set the boot flag for ESP

	if [[ $use_SWAP == true ]]; then
	parted "$DRIVE_ID" mkpart primary linux-swap "${boot_size}MiB" "$((boot_size + swap_size))MiB"  # Create swap partition
	parted "$DRIVE_ID" mkpart primary ext4 "$((boot_size + swap_size))MiB" 100%  # Create root partition
else
	parted "$DRIVE_ID" mkpart primary ext4 "$((boot_size))MiB" 100%  # Create root partition
fi

#if [[ $use_SWAP == true ]]; then
#	root_part="p3"
#else
#	root_part="p2"
#fi

	## Handle root partition encryption ## this could use some modifying...
	encrypt_root() {
		echo "Will Be Prompted for Encrypted Phrase!"
		cryptsetup -y -v luksFormat "$DRIVE_ID$root_part"
	
		echo "Will Be Prompted to Decrypt the Encrypted Partiton!"
		cryptsetup open "$DRIVE_ID$root_part" "$ROOT_ID"
		sleep 3
	}
	# Format partitions
	echo "Formatting Partitions!"
	
	if [[ $use_LUKS == true ]]; then
	encrypt_root
	mkfs.ext4 "/dev/mapper/$ROOT_ID"
else
	mkfs.ext4 "$DRIVE_ID$root_part"
fi
	mkfs.fat -F32 ""$DRIVE_ID"p1"
	
	if [[ $use_SWAP == true ]]; then
	mkswap ""$DRIVE_ID"p2"
	swapon ""$DRIVE_ID"p2"
fi
}
auto_partition

## mount the new partitions
auto_mount() { # havent tested this...
	echo "Mounting Partitions!"
	if [[ $use_LUKS == true ]]; then
	mount "/dev/mapper/$ROOT_ID" /mnt
else
	mount "$DRIVE_ID$root_part" /mnt
fi
	mkdir /mnt/boot
	mount ""$DRIVE_ID"p1" /mnt/boot
	sleep 10 ## WAS FAILING DUE TO NOT ENOUGH TIME TO REGISTER MOUNTS??
}
auto_mount

2nd_config # creates the variables file to be sourced in the second part

## BASE PACSTRAP INSTALL
pacstrap_install() {
	pacstrap -K /mnt $base_packages
}
pacstrap_install

genfstab -U /mnt >> /mnt/etc/fstab

echo "When in chroot run : chmod +x setup; ./setup"

seed="#"
sed -n "/$seed#START_TAG/,/$seed#END_TAG/p" "$0" > /mnt/setup

arch-chroot /mnt

#arch-chroot /mnt /bin/bash << EOF
#echo "Executing Part 2"
#chmod +x setup; ./setup
#exit
#EOF

## post chroot commands (we're finished here!)
post_chroot() {
	echo "UNMOUNTING FS AND REQUESTING REBOOT!"
	umount -a
	if [[ $use_SWAP == true ]]; then
	swapoff ""$DRIVE_ID"p2"
fi
	echo "YOU CAN REBOOT NOW"
	read -p "PRESS ENTER TO REBOOT"
	reboot
}
post_chroot

exit 0
exit 0
exit 0

### END OF SCRIPT

################################################################
################################################################
################################################################
################################################################
################################################################
################################################################
################################################################

##START_TAG
#!/bin/bash
source variables # created by 2nd_config function in pt1

if [[ $use_SWAP == true ]]; then # current hotfix for not using swap.. (this is quite lazy..)
	root_part="p3" # the p is because i use a chromebook with emmc storage with is detected as /dev/mmcblk0 and parts a mmcblk0p1 and so on
else
	root_part="p2"
fi

arch_chroot() {
	echo "Will be prompted to enter new root password"
	passwd

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
		new_getty_args=" -o '-p -f -- \\u' --noclear --autologin username %I \$TERM"
		echo "new_getty_args are >> $new_getty_args << END HERE !!"
		echo "Configuring Autologin for ($USERNAME)"
		sed -i "s|^ExecStart=-/sbin/agetty \(.*\)|ExecStart=-/sbin/agetty $new_getty_args \1|" "/etc/systemd/system/getty.target.wants/getty@tty1.service"
	fi

	echo "Will be prompted to enter new password for ($USERNAME)"
	passwd $USERNAME

	echo "Configuring Bootloader!"
	if [[ $use_LUKS == true ]]; then
	sed -i '/^HOOKS=/ s/)$/ encrypt)/' "/etc/mkinitcpio.conf" # adds encrypt to hooks
	fi
	mkinitcpio -p linux

	grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id="$GRUB_ID"
	grub-mkconfig -o "/boot/grub/grub.cfg"

	ROOT_UUID=$(blkid -s UUID -o value "$DRIVE_ID$root_part")

	if [[ $use_LUKS == true ]]; then # can test adding multiple encrypted drives here
	new_value="cryptdevice=UUID=$ROOT_UUID:$ROOT_ID root=/dev/mapper/$ROOT_ID"
	#sed -i '7c\GRUB_CMDLINE_LINUX="'"$new_value"'"' "/etc/default/grub" # ...
else
	new_value="root=UUID=$ROOT_UUID" # is this the best way to do this?
	#sed -i '7c\GRUB_CMDLINE_LINUX="'"$new_value"'"' "/etc/default/grub" # ...
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
#END_TAG
