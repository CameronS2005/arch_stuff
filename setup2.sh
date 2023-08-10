#!/bin/bash
## UPDATE TIME; Aug 10, 08:23 AM EDT

## CONFIG
DRIVE_ID="/dev/mmcblk0"
ROOTCRYPT_ID="rootcrypt"

USERNAME="Archie" # your non-root users name
HOSTNAME="$USERNAME" # for testing... as idc ab username or hostname
#HOSTNAME="Archie" # your installs hostname

GRUB_ID="GRUB" # grub entry name


## START OF SCRIPT

arch_chroot() {
	#genfstab -U /mnt >> /mnt/etc/fstab # generate fstab file (magically handles swap lol)

	#arch-chroot /mnt
	echo "Will be prompted to enter new root password"
	passwd

	#swapon ""$DRIVE_ID"p2"

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

	#### HOW TO UNCOMMENT WHEELS LINE IN VISUDO WITHOUT INTERACTING!!!
	## USER WILL NOT BE IN SUDOERS UNTIL THIS IS FIXED!

	echo "Configuring Bootloader!"
	sed -i '/^HOOKS=/ s/)$/ encrypt)/' "/etc/mkinitcpio.conf" # adds encrypt to hooks
	mkinitcpio -p linux

	grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=$GRUB_ID
	grub-mkconfig -o /boot/grub/grub.cfg

	## UNTESTED! #### NEED TO SET UUID
	CRYPT_UUID=$(blkid -s UUID -o value ""$DRIVE_ID"p3")
	new_value="cryptdevice=UUID=$CRYPT_UUID:$ROOTCRYPT_ID root=/dev/mapper/$ROOTCRYPT_ID"
	#################################### THIS NEEDS FIXED AS CURRENTLY THE BOOTLOADER DOESNT EVEN TRY TO DECRYPT THE ROOT DRIVE WHICH MEANS IT'LL NEVER FIND THE UUID OF THE DECRYPTED PARTITION
	#sed -i "s/^GRUB_CMDLINE_LINUX=\"[^\"]*\"/GRUB_CMDLINE_LINUX=\"$new_value\"/" /etc/default/grub # THIS LINE DOESNT WORK
	#sed -i 's/^GRUB_CMDLINE_LINUX="[^"]*"/GRUB_CMDLINE_LINUX="'"$new_value"'"/' /etc/default/grub # THIS LINE DOESNT WORK...
	#sed -i 's/GRUB_CMDLINE_LINUX="[^"]*"/GRUB_CMDLINE_LINUX="'"$new_value"'"/' "/etc/default/grub" ### THIS DOESNT WORK THIS IS THE FINAL ISSUE...
	sed -i "s/^GRUB_CMDLINE_LINUX=\"[^\"]*\"/GRUB_CMDLINE_LINUX=\"$new_value\"/" /etc/default/grub
	echo "UUID IS $CRYPT_UUID RIGHT???"
	
	### TESTING HERE!!!
	grub-mkconfig -o "/boot/grub/grub.cfg" # UNCOMMENT THIS AFTER FIXING THE SED LINE ABOVE ^^

	systemctl enable NetworkManager
	#systemctl enable bluetooth
	#rm $0 # removes pt 2 of the install as it was in the new partition
	#exit
}
arch_chroot

## END OF SCRIPT
