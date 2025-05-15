# arch_stuff
Work in progress arch linux automated installer script.

Arch Version: 2025.05.01, Kernel: 6.14.4

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

https://www.youtube.com/watch?v=_JYIAaLrwcY&t=2412s 
(SomeOrdinaryGamers : "Muta" : I Installed The Hardest System Known To Man...)
^^ big fan btw <3

https://www.youtube.com/watch?v=XNJ4oKla8B0 
(EF - Linux Made Simple : Arch Linux Base Install on UEFI with LUKS Encryption)
^^ VERY HELPFUL getting luksformat to work! (turn out it was very simple it was just my first time using cryptsetup without a gui lol)
