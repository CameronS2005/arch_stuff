# arch_stuff
Arch Version: 2025.05.01, Kernel: 6.14.4
----------------------------------------
Work in progress arch linux automated installer script.

Features;
---------
- FULLY CONFIGURABLE VARIABLES (most are easy to decipher)
- AMD/INTEL CPU SUPPORT
- AMD/INTEL/NVIDIA GPU SUPPORT
- EXTENSIVE LIST OF SUPPORTED DESKTOP ENVIRONMENT AND TILING MANAGERS!
- LUKS ENCRYPTION FOR ROOT PARTITION
- T2-MAC SUPPORT

WIP Features;
-------------
- LUKS HEADER BACKUP DURING INSTALL
- AUTO PARTITION SIZING BASED ON DISK SIZE
- AUTO DETECT CPU AND GPU
- AUTO DETECT SSD (FOR TRIM)
- AUTO DETECT T2-MAC
- AUTO DETECT DRIVE ID, AND PARTITION PREFIX


## CURRENT VARIANT(s);
- archinstaller.sh
 
## Depreacted Scripts;
- setup.sh
- setup_pt2.sh
- full_setup.sh
- test.sh
- arch_install.sh
- optimized_installer.sh
- ai_optimized_installer.sh
- installer.sh

# -------------------------------- #

BE CAREFUL WITH THESE SCRIPTS AS THEY COULD CAUSE DAMAGE TO YOUR DATA IF NOT CONFIGURED PROPERLEY! (I am not responsible for any damage caused to you're systems or you're data, you've been warned that this code is not production ready and may have bugs or compatibility issues!)

to use on a fresh copy of the archiso, simply modify the variables in the config of the script, and run "curl -o archinstaller.sh -fsSL https://raw.githubusercontent.com/CameronS2005/arch_stuff/main/archinstaller.sh; chmod +x archinstaller.sh; ./archinstaller.sh"

# -------------------------------- #

References;

https://wiki.archlinux.org/title/installation_guide

https://wiki.t2linux.org/distributions/arch/installation/

https://www.youtube.com/watch?v=_JYIAaLrwcY&t=2412s 
(SomeOrdinaryGamers : "Muta" : I Installed The Hardest System Known To Man...)
^^ big fan btw <3

https://www.youtube.com/watch?v=XNJ4oKla8B0 
(EF - Linux Made Simple : Arch Linux Base Install on UEFI with LUKS Encryption)
^^ VERY HELPFUL getting luksformat to work! (turn out it was very simple it was just my first time using cryptsetup without a gui lol)
