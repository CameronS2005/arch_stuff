#!/bin/bash
## UPDATE TIME; Aug 10, 10:37 AM EDT
## CURRENTLY QUITE LITERALLY JUST A COMBINED VERSION OF THE TWO PART INSTALLER (NOT OPTIMIZED YET!)

#### FIRST RELEASE ALMOST READY!!!!!! sed commands were a bitch...

## DONT MAKE TYPOS!!!!

#### NOTES
# add support for kernel compression
## transfer archinstalliso wpa_supplicant config to new partion for auto-wifi?
## ADD IN AUTO-LOGIN SUPPORT
## CREATE CUSTOM MOTD THAT GETS BROADCASTED ON TTY1 ON BOOT AND DOWNLOAD IT HERE! (ADD CONTROL VARIABLE)
## ECHO CONFIG INTO SOURCED EXPORT FILE INTO MOUNT SO WE DONT HAVE TO DEFINE VARIABLES TWICE...

#### NEED TO TRANSFER PT2 to mnt directory for execution (REST CAN BE HANDLED AT END OF SCRIPT AND SHALL BE AUTORAN ON EXITING CHROOT!)
## ^^ WITHOUT SECOND SCRIPT ADD CODE IN HERE AND USE SED TO PULL FROM START AND END TAGS

## CONFIG
WIFI_SSID="WiFi-2.4" # your wifi ssid # (only needed if not using ethernet) # also this script can only handle wifi using DHCP (static needs done manually)

DRIVE_ID="/dev/mmcblk0"
use_LUKS=false # use luksFormat Encryption on your root partition # idk how ill do this when i seperate my root and home partition!
# ^^ off for testing ...
ROOT_ID="rootcrypt"

USERNAME="Archie" # your non-root users name
HOSTNAME="$USERNAME" # for testing... as idc ab username or hostname
#auto_login=false # auto-login to your new non-root user # false/true
#HOSTNAME="Archie" # your installs hostname

GRUB_ID="ARCHIE" # grub entry name

### TESTING BASE PACKAGE LISTS ## THESE ARE THE ONLY PACKAGES INSTALLED AT ALL!
#base_packages="linux linux-firmware base base-devel nano vim intel-ucode grub efibootmgr networkmanager network-manager-applet wireless_tools wpa_supplicant dialog mtools dosfstools linux-headers git curl wget bluez bluez-utils pulseaudio-bluetooth xdg-utils xdg-user-dirs" # 310 pkgs
#base_packages="linux linux-firmware base base-devel nano vim intel-ucode grub efibootmgr networkmanager network-manager-applet wpa_supplicant wireless_tools net-tools dialog bash-completion" # 262 pkgs
#base_packages="linux linux-firmware base base-devel nano grub efibootmgr networkmanager iwd wpa_supplicant dhcpcd" # 173 pkgs

#base_packages="linux linux-firmware base nano grub efibootmgr networkmanager dhcpcd intel-ucode" # >150 pkgs (WIFI+DHCP+BOOT+UCODE)
base_packages="linux linux-firmware base nano grub efibootmgr networkmanager intel-ucode" # >150 pkgs (WIFI+BOOT+UCODE)
#base_packages="linux linux-firmware base nano grub efibootmgr" # <154 pkgs (BOOT)

### START OF SCRIPT

echo "FYI LUKS IS $use_LUKS"; sleep 3

## Handle wifi connection (if no ethernet dhcp)
wifi() {
	if ! ping 1.1.1.1 -c 1 &> /dev/null; then
		echo "1.1.1.1 PING FAILED! Attempting wireless config!"
		
		wifi_adapter=$(iwconfig 2>/dev/null | grep -o '^[a-zA-Z0-9]*')
		echo "Wireless Adapter Name: $wifi_adapter"
	
		echo "You will be prompted for your wifi password if needed!"
		if ! iwctl station $wifi_adapter connect $WIFI_SSID; then ## can just use this command to connect to wifi (replace $VARIABLES obvi)
		echo "WIFI CONN ERROR!"
		wifi
	fi
		sleep 10 # modify to a wait command for ipv6 with a timeout of 30s (as we need to wait for dhcp and some are slower than others...)
	
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

	# Calculate partition sizes (2% for ESP/BOOT, 15% for swap, rest for root) # LEGACY/BIOS MAY REQUIRE MORE THAN 2% FOR BOOT DIR
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
	if [[ $use_LUKS == true ]]; then
	encrypt_root
	mkfs.ext4 "/dev/mapper/$ROOTCRYPT_ID"
else
	mkfs.ext4 ""$DRIVE_ID"p3"
fi

	# Format partitions
	echo "Formatting Partitions!"
	mkfs.fat -F32 ""$DRIVE_ID"p1"  			# Format EFI System Partition as FAT32
	mkswap ""$DRIVE_ID"p2"         			# Format swap partition
	swapon ""$DRIVE_ID"p2"					# Enable swap partition
	#mkfs.ext4 "/dev/mapper/$ROOTCRYPT_ID"   # Format root partition as ext4 (could experiment with btrfs and kernel compression? to save space)
}
auto_partition

## mount the new partitions
auto_mount() { # havent tested this...
	echo "Mounting Partitions!"
	#mount ""$DRIVE_ID"p3" /mnt
	if [[ $use_LUKS == true ]]; then
	mount "/dev/mapper/$ROOTCRYPT_ID" /mnt
else
	mount ""$DRIVE_ID"p3" /mnt
fi
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

#curl -o /mnt/setup -fsSL https://raw.githubusercontent.com/CameronS2005/arch_stuff/main/setup2.sh; sleep 5 # get part 2 of the setup
seed="#"
sed -n "/$seed#START_TAG/,/$seed#END_TAG/p" $0 > /mnt/setup

arch-chroot /mnt

## post chroot commands (we're finished here!)
post_chroot() {
#	exit
	echo "UNMOUNTING FS AND REQUESTING REBOOT!"
	sudo umount -a
	echo "REBOOT NOW"
	#read -p "PRESS ENTER TO REBOOT"
	#sudo reboot now
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
DRIVE_ID="/dev/mmcblk0"
ROOT_ID="rootcrypt"
USERNAME="Archie"
HOSTNAME="$USERNAME"
#auto_login=false
#HOSTNAME="Archie"
GRUB_ID="ARCHIE"
arch_chroot() {
	echo "Will be prompted to enter new root password"
	passwd

	sed -i 's/^#\(en_US.UTF-8 UTF-8\)/\1/' "/etc/locale.gen"
	locale-gen
	echo "LANG=en_US.UTF-8" > "/etc/locale.conf"
	export "LANG=en_US.UTF-8"

	echo "Setting System Time & Hostname!"
	ln -sf "/usr/share/zoneinfo/America/New_York" "/etc/localtime"
	hwclock --systohc --utc # check 2nd argument # why is this utc?
	echo "$HOSTNAME" > "/etc/hostname"

	systemctl enable fstrim.timer # ssd trimming? # add check to see if even using ssd

	#sed -i '/^\s*#[multilib]/ s/^#//' "/etc/pacman.conf" # this doesnt work so fix it to automatically allow 32 bit support!
	#pacman -Sy

	#[multilib]
	#Include = /etc/pacman.d/mirrorlist

	echo "Configuring Hosts File With Hostname: ($HOSTNAME)!"
	cat << EOF >> "/etc/hosts"
127.0.0.1 		localhost
::1 			localhost
127.0.1.1 		$HOSTNAME.localdomain	$HOSTNAME
EOF

	echo "Creating & Configuring non-root User: ($USERNAME)"
	useradd -mG wheel $USERNAME # modify user permissions here
	echo "Will be prompted to enter new password for ($USERNAME)"
	passwd $USERNAME

	# we shall not automatically tamper with suderos
	#EDITOR=nano visudo 
	### add variable and check if enabled for enabling auto login for new user!

	#### HOW TO UNCOMMENT WHEELS LINE IN VISUDO WITHOUT INTERACTING!!!
	## USER WILL NOT BE IN SUDOERS UNTIL THIS IS FIXED!

	echo "Configuring Bootloader!"
	if [[ $use_LUKS == true ]]; then
	sed -i '/^HOOKS=/ s/)$/ encrypt)/' "/etc/mkinitcpio.conf" # adds encrypt to hooks
	fi
	mkinitcpio -p linux

	grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=$GRUB_ID
	grub-mkconfig -o /boot/grub/grub.cfg

	ROOT_UUID=$(blkid -s UUID -o value ""$DRIVE_ID"p3")

	if [[ $use_LUKS == true ]]; then
	new_value="cryptdevice=UUID=$ROOT_UUID:$ROOT_ID root=/dev/mapper/$ROOT_ID"

	sed -i '7c\GRUB_CMDLINE_LINUX="'"$new_value"'"' "/etc/default/grub" # ...
else
	new_value="root=UUID=$ROOT_UUID" # testing this
	true # this sed command needs fixed! #<< its actually the new_value's values
	sed -i '7c\GRUB_CMDLINE_LINUX="'"$new_value"'"' "/etc/default/grub" # ...
fi

	grub-mkconfig -o "/boot/grub/grub.cfg"
	
	systemctl enable NetworkManager
	systemctl enable dhcpcd
	#systemctl enable iwd 
	#systemctl enable bluetooth
	rm $0 # removes pt 2 of the install as it was in the new partition
	exit
	echo "FINISHED! EXITING CHROOT!"
}
arch_chroot
#END_TAG