#!/bin/bash
rel_date="UPDATE TIME; Jun 30, 04:20 PM EDT (2024)"

SCRIPT_VERSION="0.1a"

ARCH_VERSION="2024.06.01"

#### URL == "https://raw.githubusercontent.com/CameronS2005/arch_stuff/main/test.sh"

## VERSION (SED COMMANDS WILL MOST LIKELY NEED UPDATED WITH UPDATES!) << use tag strings instead of line numbers...

#### HOLY FUCK TRY THIS 
#chroot /path/to/chroot/env /bin/bash <<EOF   
#CHROOT CODE    
#EOF
### ^^^ THIS WORKS HOLY SHIT!!!

##### ADD AUTO BACKUP OF HEADER.bin (cryptsetup luksHeaderBackup $DRIVEID$ROOT_PART --header-backup-file HEADER_BACKUP.bin)
##### ADD AUTO EXECUTION OF PART 2 OF SETUP!
##### Fix auto_login & luks header dump
##### FIX OPTION FOR DATA PARTITION
##### FIX OPTION TO INCLUDE BOTH WIFI SSID & PASSWORD IN CONFIG!

############ RENAME VARIABLES AND CLEAN UP CODE!!!

### ORGANIZE CONFIG BETTER!
## CONFIG ## BE SURE BOTH CONFIGS MATCH UNTIL WE FIND A WAY TO FIX THIS...
WIFI_SSID="dacrib"
#WIFI_PASSWORD="redacted"
DRIVE_ID="/dev/mmcblk0"
#keymap= # not implemented as we use default...
lang="en_US" # UTF-8
timezone="America/New_York"

use_LUKS=true
#LUKS_header_backup=false ## (THIS WILL CREATE A BACKUP OF LUKS HEADER FOR ALL ENCRYPTED PARTITIONS, BACKUPS WILL BE PLACED IN ROOT PARTITION OF THE NEW INSTALL, THEY MUST BE COPIED ELSEWHERE IN ORDER TO BE USEFUL FOR A RECOVERY!)
#header_dir="~/tmp"
use_SWAP=true 
use_HOME=true
#use_DATA=false # NOT IMPLEMENTED

ROOT_ID="root_crypt"
HOME_ID="home_crypt"
#DATA_ID="data_crypt"

HOSTNAME="Archie"
USERNAME="Archie"
#auto_login=false # currently causes a boot error when enabled ### NEEDS FIXED ## SKIPPING FOR NOW AS ITS EATING UP TOO MUCH TIME AND IM A SED NOVICE!
#BOOTLOADER="GRUB" # SCRIPT ONLY SUPPORTS GRUB RIGHT NOW
enable_32b_mlib=true
GRUB_ID="GRUB"
#OS_PROBER=false # NOT IMPLEMENTED
#is_AMD=false # NOT IMPLEMENTED (WILL CHOOSE BETWEEN GRAPHICS DRIVERS AND UCODE)

## NOT IMPLEMENTED ## CURRENTLY TESTING (PERCENTAGE CODE IS COMPLETELY COMMENTED OUT WHILE TESTING!)
boot_size_mb="500"
swap_size_gb="4"; swap_size_mb=$((swap_size_gb * 1024)) # at this point i might aswell make a simple function to convert from gb to mb and reverse
root_size_gb="1"; root_size_mb=$((root_size_gb * 1024))
home_size_gb="10"; home_size_mb=$((home_size_gb * 1024)) # CURRENTLY NOT EVEN USED AT THE LAST DIRECTORY ENDS UP USING THE REST OF THE SPACE I THINK!
#data_size_gb="2"

base_packages="base base-devel linux linux-firmware nano grub efibootmgr networkmanager intel-ucode sudo" # 148/126?? pkgs (UEFI-BOOT+WIFI+UCODE)
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
HOME_ID="$HOME_ID"
DATA_ID="$DATA_ID"
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

### START OF SCRIPT

cat << EOF
RELEASE DATE; ($rel_date)

CURRENT CONFIG;

# ---------------------------------------------------------------- #

DRIVE_ID="$DRIVE_ID"
lang="$lang"

use_LUKS="$use_LUKS"
LUKS_header="$LUKS_header"
header_dir="$header_dir"

use_SWAP="$use_SWAP"
use_HOME="$use_HOME"
use_DATA="$use_DATA"

ROOT_ID="$ROOT_ID"
HOME_ID="$HOME_ID"
DATA_ID="$DATA_ID"

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
	read -p "PRESS ENTER TO PARTITION ($DRIVE_ID) DANGER!!!"

	# Remove existing partitions (WARNING: This will delete all data on the drive)
	echo "Performing Partition & MBR Wipe & Creating GPT Partition Table!"
	
	sgdisk --zap-all "$DRIVE_ID"
	parted "$DRIVE_ID" mklabel gpt

	# Get the total size of the drive in MiB
	drive_size=$(parted -s "$DRIVE_ID" print | awk '/Disk/ {print $3}' | sed 's/[^0-9]//g')
	drive_size_mib=$((drive_size / 10 * 1024))

#	## CALCULATE PARTITION SIZES (boot is 2%, swap is 15%, root is rest)
#	echo "Calculating Partition Sizes Based on Drive Size!"
#	boot_size=$((drive_size_mib * 2 / 100))
#
#	if [[ $use_SWAP == true ]]; then
#	swap_size=$((drive_size_mib * 15 / 100))
#	root_size=$((drive_size_mib - boot_size_mb - swap_size))
#else
#	root_size=$((drive_size_mib - boot_size))
#fi

	## HANDLE OVERRIDES # if hardcoded sizes are empty use them instead of percentage size
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

	#boot_size="$boot_size_mb"
	#swap_size="$swap_size_gb"
	#root_size="$root_size_gb"
	#home_size="$home_size_gb"
	#data_size="$data_size_gb"

	# Create partitions
	## USE EQUATION TO DETERMINE SWAP SIZE (BASED ON DISK SIZE AND RAM AMOUNT) << THIS WOULD BE NICE!bi
	echo "Creating New Partitions!"
	parted "$DRIVE_ID" mkpart ESP fat32 1MiB "${boot_size_mb}MiB"  # Create ESP Partition
	parted "$DRIVE_ID" set 1 boot on  # Set the boot flag for the ESP partition

	if [[ $use_SWAP == true ]]; then
		root_part="p3"
		if [[ $use_HOME == true ]]; then
			home_part="p4"
			parted "$DRIVE_ID" mkpart primary linux-swap "${boot_size_mb}MiB" "$((boot_size_mb + swap_size_mb))MiB" # Create swap partition
			parted "$DRIVE_ID" mkpart primary ext4 "$((boot_size_mb + swap_size_mb))MiB" "$((boot_size_mb + swap_size_mb + root_size_mb))MiB"  # Create root partition
			parted "$DRIVE_ID" mkpart primary ext4 "$((boot_size_mb + swap_size_mb + root_size_mb))MiB" 100% # Create home partition
		else
			parted "$DRIVE_ID" mkpart primary linux-swap "${boot_size_mb}MiB" "$((boot_size_mb + swap_size_mb))MiB" # Create swap partition
			parted "$DRIVE_ID" mkpart primary ext4 "$((boot_size_mb + swap_size_mb))MiB" 100%  # Create root partition
		fi
	else
		root_part="p2"
		if [[ $use_HOME == true ]]; then
			home_part="p3"
			parted "$DRIVE_ID" mkpart primary ext4 "$((boot_size))MiB" "$((boot_size_mb + root_size_mb))MiB" # Create root partition
			parted "$DRIVE_ID" mkpart primary ext4 "$((boot_size_mb + root_size_mb))MiB" 100% # Create home partition
		else
			parted "$DRIVE_ID" mkpart primary ext4 "$((boot_size))MiB" 100% # Create root partition
		fi
	fi



	if [[ $use_SWAP == true ]]; then
	parted "$DRIVE_ID" mkpart primary linux-swap "${boot_size_mb}MiB" "$((boot_size_mb + swap_size))MiB"  # Create swap partition
	parted "$DRIVE_ID" mkpart primary ext4 "$((boot_size_mb + swap_size))MiB" 100%  # Create root partition
else
	if [[ $use_HOME == false ]]; then
	parted "$DRIVE_ID" mkpart primary ext4 "$((boot_size))MiB" 100%
else
	#parted "$DRIVE_ID" mkpart primary ext4 "$((boot_size))MiB" 100%
	parted "$DRIVE_ID" mkpart primary ext4 "$((boot_size))MiB" "$((boot_size_mb + $home_size * 1024))MiB" # testing this line
fi; 
fi

	if [[ $use_HOME == true ]]; then # TESTING HOME DIRECTORY
		if [[ $use_SWAP == true ]]; then
			home_part="p4"
		else
			home_part="p3"
		fi

		parted "$DRIVE_ID" mkpart primary ext4 "$((boot_size_mb + $home_size_gb * 1024))MiB" 100%
	fi

	## Handle root partition encryption ## this could use some modifying...
	encrypt_root() { ## <<< DOESNT PROPERLEY RESET IF PASSWORDS DONT MATCH... Same with user creation function...
		echo "Will Be Prompted for Encrypted Phrase! (ROOT PARTITION ($root_part))"
		if ! cryptsetup -y -v luksFormat "$DRIVE_ID$root_part"; then
			echo "PASSWORDS MUST MATCH DUMBASS"
			encrypt_root
		fi
	
		echo "Will Be Prompted to Decrypt the Encrypted Partiton!"
		if ! cryptsetup open "$DRIVE_ID$root_part" "$ROOT_ID"; then
			echo "PASSWORDS MUST MATCH DUMBASS"
			encrypt_root
		fi

		if [[ $use_HOME == false ]]; then
			sleep 3
		fi
	}

	## Handle home partition encryption
	encrypt_home() {
		echo "Will Be Prompted for Encrypted Phrase! (HOME PARTITION ($home_part))"
		if ! cryptsetup -y -v luksFormat "$DRIVE_ID$home_part"; then
			echo "PASSWORDS MUST MATCH DUMBASS"
			encrypt_home
		fi
	
		echo "Will Be Prompted to Decrypt the Encrypted Partiton!"
		if ! cryptsetup open "$DRIVE_ID$home_part" "$HOME_ID"; then
			sleep 3
			echo "PASSWORDS MUST MATCH DUMBASS"
			encrypt_home
		fi
	}

	# Format partitions
	echo "Formatting Partitions!"
	
	if [[ $use_LUKS == true ]]; then
	encrypt_root
	mkfs.ext4 "/dev/mapper/$ROOT_ID"

	if [[ $use_HOME == true ]]; then
		encrypt_home
		mkfs.ext4 "/dev/mapper/$HOME_ID"
	fi

else
	mkfs.ext4 "$DRIVE_ID$root_part"
	if [[ $use_HOME == true ]]; then
		mkfs.ext4 "$DRIVE_ID$home_part"
	fi
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
	if [[ $use_HOME == true ]]; then
		mkdir /mnt/home #???
		mount "/dev/mapper/$HOME_ID" /mnt/home
	fi

else
	mount "$DRIVE_ID$root_part" /mnt
	if [[ $use_HOME == true ]]; then
		mkdir /mnt/home #???
		mount "$DRIVE_ID$home_part" /mnt/home
	fi
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
sed -n "/$seed#START_TAG/,/$seed#END_TAG/p" "$0" > /mnt/setup # the tags must be seeded or sed detects this line as the occurences!

arch-chroot /mnt ## FINISH INSTALL IN NEWLY INSTALLED ENVIRONMENT!

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
#END_TAG
