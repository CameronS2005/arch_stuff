#!/bin/bash

## DONT MAKE TYPOS!!!!
### encrypt needs auto added to mkinitcpio conf (HOOKS)

## CONFIG
WIFI_SSID="WiFi-2.4" # your wifi ssid # (only needed if not using ethernet) # also this script can only handle wifi using DHCP (static needs done manually)
#WIFI_PASSWD=""

DRIVE_ID="/dev/mmcblk0"
ROOTCRYPT_ID="rootcrypt"

USERNAME="Archie" # your non-root users name
HOSTNAME="Archie" # your installs hostname

base_packages="linux linux-firmware base base-devel encrypt nano vim intel-ucode grub efibootmgr networkmanager network-manager-applet wireless_tools wpa_supplicant dialog mtools dosfstools linux-headers git curl wget bluez bluez-utils pulseaudio-bluetooth xdg-utils xdg-user-dirs" 


### START OF SCRIPT

## Handle wifi connection (if no ethernet dhcp)
wifi() {
	if ! ping 1.1.1.1 -c 1 &> /dev/null; then
		echo "1.1.1.1 PING FAILED! Attempting wireless config!"
		
		wifi_adapter=$(iwconfig 2>/dev/null | grep -o '^[a-zA-Z0-9]*')
		echo "Wireless Adapter Name: $wifi_adapter"
	
		echo "You will be prompted for your wifi password if needed!"
		iwctl station $wifi_adapter connect $WIFI_SSID 

		sleep 10 # modify to a wait command for ipv6 with a timeout of 30s
	
		local_ipv4=$(ip -4 addr show up | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n 1)
		echo "Local IPv4 address: $local_ipv4"
	fi
}
wifi # can comment out if using ethernet

## Quick way of selecting best mirrors
rank_mirrors() {
	pacman -Syy rankmirrors # IDK ABOUT THIS ORDER
	pacman -Syyy
	cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.bak # backup mirrorlist in case we fucked up

	rankmirrors -n 6 /etc/pacman.d/mirrorlist.bak /etc/pacman.d/mirrorlist # inputs bakup mirrorlist into ranked mirrors and writes to mirrorfile
}
#rank_mirrors # this is hardly needed (like not at all...) # can comment out if you dont care...

## Handle drive partitioning ## IN THE FUTURE MODIFY TO SUPPORT SEPERATE home PARTITION AND PERHAPS A data PARTITION
auto_partition() { # rename to auto drive & add to handle encryption and mounting
	read -p "PRESS ENTER TO PARTITION ($DRIVE_ID)" # could modify to an if check then read for inputting a new drive id (same with wifi ssid if failed to connect?)

	# Remove existing partitions (WARNING: This will delete all data on the drive)
	echo "Performing Partition & MBR Wipe & Creating GPT Partition Table!"
	
	sgdisk --zap-all "$DRIVE_ID"
	parted "$DRIVE_ID" mklabel gpt  # Create a new GPT partition table to remove existing partitions
	
	# Get the total size of the drive in MiB
	drive_size_mib=$(parted -s "$DRIVE_ID" print | awk '/Disk/ {print $3}' | sed 's/[^0-9]//g')
	
	# Calculate partition sizes (5% for ESP, 15% for swap, rest for root)
	echo "Calculating Partition Sizes Based on Drive Size!"
	esp_size=$((drive_size_mib * 5 / 100))
	swap_size=$((drive_size_mib * 15 / 100))
	root_size=$((drive_size_mib - esp_size - swap_size))

	
	# Create partitions
	## USE EQUATION TO DETERMINE SWAP SIZE (BASED ON DISK SIZE AND RAM AMOUNT)
	echo "Creating New Partitions!"
	parted "$DRIVE_ID" mkpart ESP fat32 1MiB "${esp_size}MiB"  # Create EFI System Partition
	parted "$DRIVE_ID" set 1 boot on  # Set the boot flag for ESP
	parted "$DRIVE_ID" mkpart primary linux-swap "${esp_size}MiB" "$((esp_size + swap_size))MiB"  # Create swap partition
	parted "$DRIVE_ID" mkpart primary ext4 "$((esp_size + swap_size))MiB" 100%  # Create root partition
	# ^^ THIS IS UNTESTED AND IDK IF THE PERCENTAGES OF THE DRIVE WILL WORK CORRECTLY

	## Handle root partition encryption ## this could use some modifying... # this may need to be before formatting?
	encrypt_root() {
		echo "Will Be Prompted for Encrypted Phrase!"
		cryptsetup -y -v luksFormat ""$DRIVE_ID"p3"
	
		echo "Will Be Prompted to Decrypt the Encrypted Partiton!"
		cryptsetup open ""$DRIVE_ID"p3" "$ROOTCRYPT_ID"
	}
	encrypt_root

	# Format partitions
	echo "Formatting Partitions!"
	mkfs.fat -F32 ""$DRIVE_ID"p1"  # Format EFI System Partition as FAT32
	mkswap ""$DRIVE_ID"p2"         # Format swap partition
	mkfs.ext4 "/dev/mapper/$ROOTCRYPT_ID"      # Format root partition as ext4 (could experiment with btrfs and kernel compression? to save space)
}
auto_partition

## Handle root partition encryption ## this could use some modifying... # this may need to be before formatting?
#encrypt_root() {
#	echo "Will Be Prompted for Encrypted Phrase!"
#	cryptsetup -y -v luksFormat ""$DRIVE_ID"p3"
#
#	echo "Will Be Prompted to Decrypt the Encrypted Partiton!"
#	cryptsetup open ""$DRIVE_ID"p3" "$ROOTCRYPT_ID"
#}
#encrypt_root

## mount the new partitions
auto_mount() { # havent tested this...
	#mount ""$DRIVE_ID"p3" /mnt
	mount "/dev/mapper/$ROOTCRYPT_ID" /mnt
	mkdir /mnt/boot
	mount ""$DRIVE_ID"p1" /mnt/boot
	#swapon ""$DRIVE_ID"p2"
}
#auto_mount

## BASE PACSTRAP INSTALL
pacstrap_install() {
	pacstrap -K /mnt $base_packages
}
#pacstrap_install

## here we finally chroot into out new FS
arch_chroot() {
	genfstab -U /mnt >> /mnt/etc/fstab # generate fstab file

	arch-chroot /mnt
	echo "Will be prompted to enter new root password"
	passwd

	swapon ""$DRIVE_ID"p2"

	sed -i 's/^#\(en_US.UTF-8 UTF-8\)/\1/' /etc/locale.gen # THIS IS UNTESTED
	locale-gen
	echo "LANG=en_US.UTF-8" >> /etc/locale.conf

	echo "Setting System Time & Hostname!"
	ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime # check this command
	hwclock --systohc --EDT # check 2nd argument
	echo "$HOSTNAME" > /etc/hostname

	echo "Configuring Hosts File With Hostname: ($HOSTNAME)!"
	cat << EOF >> /etc/hosts
127.0.0.1 		localhost
::1 			localhost
127.0.1.1 		$HOSTNAME.localdomain	$HOSTNAME
EOF

	echo "Configuring Bootloader!"
	#### THIS NEEDS DONE ASAP
	sed ### sed some bs from /etc/mkinitcpio.conf for adding encrypt to hooks list
	mkinitcpio -p linux

	grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
	# ADD VARIABLE FOR ENTRY NAME!
	grub-mkconfig -o /boot/grub/grub.cfg

	## UNTESTED!
	new_value="cryptdevice=UUID=$CRYPT_UUID:$ROOTCRYPT_ID root=/dev/mapper/$ROOTCRYPT_ID"
	sed -i "s/^GRUB_CMDLINE_LINUX=\"[^\"]*\"/GRUB_CMDLINE_LINUX=\"$new_value\"/" /etc/default/grub
	grub-mkconfig -o /boot/grub/grub.cfg

	systemctl enable NetworkManager
	systemctl enable bluetooth

	echo "Creating & Configuring non-root User: ($USERNAME)"
	useradd -mG wheel $USERNAME
	echo "Will be prompted to enter new password for ($USERNAME)"
	passwd $USERNAME

	#### HOW TO UNCOMMENT WHEELS LINE IN VISUDO WITHOUT INTERACTING!!!
	## USER WILL NOT BE IN SUDOERS UNTIL THIS IS FIXED!
}
#arch_chroot

## post chroot commands (we're finished here!)
post_chroot() {
	exit
	sudo umount -a
	read -p "PRESS ENTER TO REBOOT"
	sudo reboot now
}
#post_chroot

### END OF SCRIPT
