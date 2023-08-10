#!/bin/bash
## UPDATE TIME; Aug 10, 05:30 AM EDT

## DONT MAKE TYPOS!!!!

#### NOTES
## THIS SCRIPT 100% DOES NOT SUPPORT NVIDIA DRIVER DETECTION NOR AUTO CONFIGURE
# Currently this uses grub and not Muta's BL as it would be a bit harder to automate and not neccessary AFAIK
# add support for kernel compression
#### NEED TO TRANSFER PT2 to mnt directory for execution (REST CAN BE HANDLED AT END OF SCRIPT AND SHALL BE AUTORAN ON EXITING CHROOT!)

## CONFIG
WIFI_SSID="WiFi-2.4" # your wifi ssid # (only needed if not using ethernet) # also this script can only handle wifi using DHCP (static needs done manually)
#WIFI_PASSWD=""

DRIVE_ID="/dev/mmcblk0"
ROOTCRYPT_ID="rootcrypt"

USERNAME="Archie" # your non-root users name
HOSTNAME="$USERNAME" # for testing... as idc ab username or hostname
#HOSTNAME="Archie" # your installs hostname

GRUB_ID="GRUB" # grub entry name

### TESTING BASE PACKAGE LISTS
#base_packages="linux linux-firmware base base-devel nano vim intel-ucode grub efibootmgr networkmanager network-manager-applet wireless_tools wpa_supplicant dialog mtools dosfstools linux-headers git curl wget bluez bluez-utils pulseaudio-bluetooth xdg-utils xdg-user-dirs" # 310 pkgs
#base_packages="linux linux-firmware base base-devel nano vim intel-ucode grub efibootmgr networkmanager network-manager-applet wpa_supplicant wireless_tools net-tools dialog bash-completion" # 262 pkgs
base_packahes="linux linux_firmware base nano grub efibootmgr networkmanager iwd wpa_supplicant" # testing
#base_packages="linux linux-firmware base base-devel nano vim intel-ucode grub efibootmgr" # 154 pkgs (NO WIFI)

### START OF SCRIPT

## Handle wifi connection (if no ethernet dhcp)
wifi() {
	if ! ping 1.1.1.1 -c 1 &> /dev/null; then
		echo "1.1.1.1 PING FAILED! Attempting wireless config!"
		
		wifi_adapter=$(iwconfig 2>/dev/null | grep -o '^[a-zA-Z0-9]*')
		echo "Wireless Adapter Name: $wifi_adapter"
	
		echo "You will be prompted for your wifi password if needed!"
		iwctl station $wifi_adapter connect $WIFI_SSID ## can just use this command to connect to wifi (replace $VARIABLES obvi)

		sleep 10 # modify to a wait command for ipv6 with a timeout of 30s
	
		local_ipv4=$(ip -4 addr show up | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n 1)
		echo "Local IPv4 address: $local_ipv4"
	fi
}
wifi # can comment out if using ethernet # really this function is useless considering you prob configured wifi to get the script

## Quick way of selecting best mirrors
#rank_mirrors() { # rewatch mutas video cause i messed this up...
#	pacman -Syy pacman-contrib # IDK ABOUT THIS ORDER
#	#pacman -Syyy
#	cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.bak # backup mirrorlist in case we fucked up
#
#	rankmirrors -n 6 /etc/pacman.d/mirrorlist.bak > /etc/pacman.d/mirrorlist # inputs bakup mirrorlist into ranked mirrors and writes to mirrorfile
#}
#rank_mirrors # this is hardly needed (like not at all...) # can comment out if you dont care...

## Handle drive partitioning ## IN THE FUTURE MODIFY TO SUPPORT SEPERATE home PARTITION AND PERHAPS A data PARTITION
auto_partition() { # rename to auto drive & add to handle encryption and mounting
	read -p "PRESS ENTER TO PARTITION ($DRIVE_ID)" # could modify to an if check then read for inputting a new drive id (same with wifi ssid if failed to connect?)

	# Remove existing partitions (WARNING: This will delete all data on the drive)
	echo "Performing Partition & MBR Wipe & Creating GPT Partition Table!"
	
	sgdisk --zap-all "$DRIVE_ID"
	parted "$DRIVE_ID" mklabel gpt  # Create a new GPT partition table to remove existing partitions

	# Get the total size of the drive in MiB
	drive_size=$(parted -s "$DRIVE_ID" print | awk '/Disk/ {print $3}' | sed 's/[^0-9]//g')
	drive_size_mib=$((drive_size / 10 * 1024)) # yeah yikes...

	# Calculate partition sizes (2% for ESP/BOOT, 15% for swap, rest for root) # LEGACY MAY REQUIRE MORE THAN 2%
	## SWAP IS SO LOW BECAUSE TESHBENCH ONLY HAS 16gb SSD
	echo "Calculating Partition Sizes Based on Drive Size!"
	esp_size=$((drive_size_mib * 2 / 100))
	swap_size=$((drive_size_mib * 15 / 100))
	root_size=$((drive_size_mib - esp_size - swap_size))

	# Create partitions
	## USE EQUATION TO DETERMINE SWAP SIZE (BASED ON DISK SIZE AND RAM AMOUNT)
	echo "Creating New Partitions!"
	parted "$DRIVE_ID" mkpart ESP fat32 1MiB "${esp_size}MiB"  # Create EFI System Partition
	parted "$DRIVE_ID" set 1 boot on  # Set the boot flag for ESP
	parted "$DRIVE_ID" mkpart primary linux-swap "${esp_size}MiB" "$((esp_size + swap_size))MiB"  # Create swap partition
	parted "$DRIVE_ID" mkpart primary ext4 "$((esp_size + swap_size))MiB" 100%  # Create root partition

	## Handle root partition encryption ## this could use some modifying...
	encrypt_root() {
		echo "Will Be Prompted for Encrypted Phrase!"
		cryptsetup -y -v luksFormat ""$DRIVE_ID"p3"
	
		echo "Will Be Prompted to Decrypt the Encrypted Partiton!"
		cryptsetup open ""$DRIVE_ID"p3" "$ROOTCRYPT_ID"
	}
	encrypt_root

	# Format partitions
	echo "Formatting Partitions!"
	mkfs.fat -F32 ""$DRIVE_ID"p1"  			# Format EFI System Partition as FAT32
	mkswap ""$DRIVE_ID"p2"         			# Format swap partition
	swapon ""$DRIVE_ID"p2"					# Enable swap partition
	mkfs.ext4 "/dev/mapper/$ROOTCRYPT_ID"   # Format root partition as ext4 (could experiment with btrfs and kernel compression? to save space)
}
auto_partition

## mount the new partitions
auto_mount() { # havent tested this...
	echo "Mounting Partitions!"
	#mount ""$DRIVE_ID"p3" /mnt
	mount "/dev/mapper/$ROOTCRYPT_ID" /mnt
	mkdir /mnt/boot
	mount ""$DRIVE_ID"p1" /mnt/boot
	sleep 5 ## WAS FAILING DUE TO NOT ENOUGH TIME TO REGISTER MOUNTS??
}
auto_mount

## BASE PACSTRAP INSTALL
pacstrap_install() {
	pacstrap -K /mnt $base_packages
}
pacstrap_install

genfstab -U /mnt >> /mnt/etc/fstab

echo "When in chroot run : chmod +x setup; ./setup"

curl -o /mnt/setup -fsSL https://raw.githubusercontent.com/CameronS2005/arch_stuff/main/setup2.sh; sleep 5 # get part 2 of the setup

arch-chroot /mnt

## post chroot commands (we're finished here!)
post_chroot() {
#	exit
	sudo umount -a
	read -p "PRESS ENTER TO REBOOT"
	sudo reboot now
}
#post_chroot

### END OF SCRIPT
