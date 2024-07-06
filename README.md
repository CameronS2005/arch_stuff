# arch_stuff
A collection of my arch linux install scripts

Testbench: Dell Chromebook 3100, MFG YR: 2021 (Fleex Motherboard)
Testbench 2: Dell Chromebook 11 3180, MFG YR: 2017 (Kefka Motherboard)

Arch Version: 2024.06.01, Kernel: 6.9.3

## CURRENT VARIANT(s);
- installer.sh
 
## Depreacted Scripts;
- setup.sh
- setup_pt2.sh
- full_setup.sh
- test.sh
- arch_install.sh
- optimized_installer.sh
- ai_optimized_installer.sh
# -------------------------------- #

BE CAREFUL WITH THESE SCRIPTS AS THEY COULD CAUSE DAMAGE TO YOUR DATA IF NOT CONFIGURED PROPERLEY!

to use on a fresh copy of the archiso, simply modify the variables in the config of the script, and run "curl -s arch_install.sh -fsSL https://raw.githubusercontent.com/CameronS2005/arch_stuff/main/arch_install.sh; chmod +x arch_install.sh; ./arch_install.sh" and follow the directions!

# -------------------------------- #

References;

https://wiki.archlinux.org/title/installation_guide

https://www.youtube.com/watch?v=_JYIAaLrwcY&t=2412s 
(SomeOrdinaryGamers : "Muta" : I Installed The Hardest System Known To Man...)
^^ big fan btw lol <3

https://www.youtube.com/watch?v=XNJ4oKla8B0 
(EF - Linux Made Simple : Arch Linux Base Install on UEFI with LUKS Encryption)
^^ VERY HELPFUL getting luksformat to work! (turn out it was very simple it was just my first time using cryptsetup without a gui lol)
