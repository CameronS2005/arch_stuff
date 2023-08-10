#!/bin/bash
## UPDATE TIME; Aug 10, 14:19 PM EDT
## VERSION (SED COMMANDS WILL MOST LIKELY NEED UPDATED WITH UPDATES!)

## NOT BOOTING...

## DONT MAKE TYPOS!!!!

#### NOTES
# add support for kernel compression
## BOOT PARTITION SIZE NEEDS TO BE HARDCODED AS BIGGER DRIVES WILL WASTE A BUNCH ON part1

## THIS SCRIPT WILL NEVER SUPPORT NVIDIA AS I DONT HAVE ANY TESTBENCHES TO WORK ON WITH NVIDIA I WILL BE TESTING WITH INTEL & AMD
## ^^ AMD WILL BE ADDED ITF!

## ALOT OF THESE COMMANDS NEED SILENCED!
#### INCREASE THE AUTOMATION!!!

## CONFIG ## BE SURE BOTH CONFIGS MATCH UNTIL WE FIND A WAY TO FIX THIS...
WIFI_SSID="WiFi-2.4" # your wifi ssid # (only needed if not using ethernet) # also this script can only handle wifi using DHCP (static needs done manually)
DRIVE_ID="/dev/mmcblk0"
use_LUKS=false # use luksFormat Encryption on your root partition # idk how ill do this when i seperate my root and home partition!
use_SWAP=true # create a swap partition (currently 15% of specified drive) 
ROOT_ID="rootcrypt"
HOSTNAME="Arch-Box"
USERNAME="Archie" # your non-root users name
GRUB_ID="ARCHIE" # grub entry name

2nd_config() { # this is so annoying...
cat << EOF > /mnt/variables
DRIVE_ID="/dev/mmcblk0"
use_LUKS=false
use_SWAP=false
ROOT_ID="rootcrypt"
HOSTNAME="Arch-Box"
USERNAME="Archie"
auto_login=true
enable_32b_mlib=true
GRUB_ID="ARCHIE"
root_part="$root_part"
EOF
}

### TESTING BASE PACKAGE LISTS ## THESE ARE THE ONLY PACKAGES INSTALLED AT ALL!
#base_packages="linux linux-firmware base base-devel nano vim intel-ucode grub efibootmgr networkmanager network-manager-applet wireless_tools wpa_supplicant dialog mtools dosfstools linux-headers git curl wget bluez bluez-utils pulseaudio-bluetooth xdg-utils xdg-user-dirs" # 310 pkgs
#base_packages="linux linux-firmware base base-devel nano vim intel-ucode grub efibootmgr networkmanager network-manager-applet wpa_supplicant wireless_tools net-tools dialog bash-completion" # 262 pkgs
#base_packages="linux linux-firmware base base-devel nano grub efibootmgr networkmanager iwd wpa_supplicant dhcpcd" # 173 pkgs

#base_packages="linux linux-firmware base nano grub efibootmgr networkmanager dhcpcd intel-ucode" # >150 pkgs (WIFI+DHCP+BOOT+UCODE)
base_packages="linux linux-firmware base nano grub efibootmgr networkmanager intel-ucode" # 148 pkgs (WIFI+BOOT+UCODE)
#base_packages="linux linux-firmware base nano grub efibootmgr intel-ucode" # <154 pkgs (BOOT+UCODE)

### START OF SCRIPT

cat << EOF
FYI LUKS IS $use_LUKS
FYI SWAP IS $use_SWAP
Battery is at $(cat /sys/class/power_supply/BAT0/capacity)%
EOF

## SIMPLE BIOS CHECK!
if [ ! "$(ls -A /sys/firmware/efi/efivars)" ]; then
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

	echo "Calculating Partition Sizes Based on Drive Size!"
	esp_size=$((drive_size_mib * 2 / 100))

	if [[ $use_SWAP == true ]]; then
	swap_size=$((drive_size_mib * 15 / 100))
	root_size=$((drive_size_mib - esp_size - swap_size))
else
	root_size=$((drive_size_mib - esp_size))
fi

	# Create partitions
	## USE EQUATION TO DETERMINE SWAP SIZE (BASED ON DISK SIZE AND RAM AMOUNT)
	echo "Creating New Partitions!"
	parted "$DRIVE_ID" mkpart ESP fat32 1MiB "${esp_size}MiB"  # Create EFI System Partition
	parted "$DRIVE_ID" set 1 boot on  # Set the boot flag for ESP
	if [[ $use_SWAP == true ]]; then
	parted "$DRIVE_ID" mkpart primary linux-swap "${esp_size}MiB" "$((esp_size + swap_size))MiB"  # Create swap partition
	parted "$DRIVE_ID" mkpart primary ext4 "$((esp_size + swap_size))MiB" 100%  # Create root partition
else
	parted "$DRIVE_ID" mkpart primary ext4 "$((esp_size))MiB" 100%  # Create root partition
fi

if [[ $use_SWAP == true ]]; then
	root_part="p3"
else
	root_part="p2"
fi

	## Handle root partition encryption ## this could use some modifying...
	encrypt_root() {
		echo "Will Be Prompted for Encrypted Phrase!"
		cryptsetup -y -v luksFormat "$DRIVE_ID$root_part"
	
		echo "Will Be Prompted to Decrypt the Encrypted Partiton!"
		cryptsetup open "$DRIVE_ID$root_part" "$ROOTCRYPT_ID"
	}
	# Format partitions
	echo "Formatting Partitions!"
	
	if [[ $use_LUKS == true ]]; then
	encrypt_root
	mkfs.ext4 "/dev/mapper/$ROOTCRYPT_ID"
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
	mount "/dev/mapper/$ROOTCRYPT_ID" /mnt
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

## post chroot commands (we're finished here!)
post_chroot() {
	echo "UNMOUNTING FS AND REQUESTING REBOOT!"
	umount -a
	if [[ $use_SWAP == true ]]; then
	swapoff ""$DRIVE_ID"p2"
fi
	echo "YOU CAN REBOOT NOW"
	#read -p "PRESS ENTER TO REBOOT"
	#reboot now
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

if [[ $use_SWAP == true ]]; then
	root_part="p3"
else
	root_part="p2"
fi

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

	if [[ $enable_32b_mlib == true ]]; then
	sed -i '90 s/^#//' "/etc/pacman.conf"
	sed -i '91 s/^#//' "/etc/pacman.conf"
	#pacman -Syyy # ?? hopefully this fixes current boot issue
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
		echo "Configuring Autologin for ($USERNAME)"
		sed -i 's|^ExecStart=-/sbin/agetty \(.*\)|ExecStart=-/sbin/agetty --autologin $USERNAME \1|' "/etc/systemd/system/getty.target.wants/getty@tty1.service"
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

	if [[ $use_LUKS == true ]]; then
	new_value="cryptdevice=UUID=$ROOT_UUID:$ROOT_ID root=/dev/mapper/$ROOT_ID"
	sed -i '7c\GRUB_CMDLINE_LINUX="'"$new_value"'"' "/etc/default/grub" # ...
else
	new_value="root=UUID=$ROOT_UUID" # is this the best way to do this?
	sed -i '7c\GRUB_CMDLINE_LINUX="'"$new_value"'"' "/etc/default/grub" # ...
fi

	grub-mkconfig -o "/boot/grub/grub.cfg"
	
	systemctl enable NetworkManager
	#systemctl enable dhcpcd
	#systemctl enable iwd 
	#systemctl enable bluetooth

	rm variables
	rm $0 # 
	echo "FINISHED! EXITING CHROOT!"
	exit # we need to exit chroot here not just the script...
}
arch_chroot
exit
#END_TAG
