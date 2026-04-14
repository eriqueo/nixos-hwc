Linux Patch
Jump to navigationJump to search

Contents
1	eXoDOS Linux Patch
1.1	Overview
1.2	Installation Process
1.2.1	Step 1 - Extracting Zip Archive
1.2.2	Step 2 - Installing System Dependencies
1.2.3	Step 3 - Installing eXoDOS
1.3	Using eXoDOS
1.3.1	exogui
1.3.2	Creating Desktop Shortcuts
1.4	Changelog
1.4.1	Changes to the eXoDOS 6.04 Linux Patch
1.5	Files
1.5.1	eXoDOS 6.4 Linux Patch.zip
1.5.2	util_linux.zip
1.5.3	Development Scripts
1.5.4	eXo/util/converter.bash
1.5.4.1	convertScript Function
1.5.5	eXo/util/regenerate.bash
1.6	Linux Flatpaks
1.7	Linux Update and Patch Files
1.8	Preparing For Manual Conversion
1.9	Packaging Files For Release
eXoDOS Linux Patch
Overview
The eXoDOS Linux patch is a complete conversion to make all features of eXoDOS work on Linux systems just as they would in Windows, including both the lite and full versions. An official Linux frontend, called exogui, is included as part of this conversion. Additionally, the patch is written to ensure that the collection works as expected in dual-boot environments. After the Linux patch is installed, if eXoDOS is updated or games are installed, this will be reflected in both Linux and Windows environments.

As it is encouraged to seed the collection, installing the Linux patch will not alter any torrent files. The patch does not change the existing eXoDOS framework, but instead supplements it.

At this time of this writing, the latest eXoDOS Linux Patch is for version 6.4.

An add-on zip is also available as a separate download to add Linux support to the Media Pack.

*Note: The German Language Pack has not yet been converted*



Supported distributions include:

Arch / Manjaro Linux / SteamOS
Fedora
Ubuntu (and Ubuntu-based distributions) / Debian
Nearly any x86_64 distro that has flatpak support
Unsupported:

ARM, IBM Power, and RISC-V computers and devices are not supported at this time. This includes the Raspberry Pi. We need someone to volunteer to build ARM versions of the flatpaks for support to be added.
macOS and BSD are also unsupported at this time. Until we have a volunteer to add macOS support to the frontend, this is unlikely to change. Backend support exists for the eXoDREAMM project, and the backend for eXoDOS has been partially converted in case we get a volunteer.
Installation Process
Step 1 - Extracting Zip Archive
First, the eXoDOS 6.4 Linux Patch.zip file must be extracted to the correct location.
Copy the eXoDOS 6.4 Linux Patch.zip file to the root directory of your freshly downloaded eXoDOS 6.4 collection. (This is where files such as eXoDOS Catalog.pdf and Setup.bat are located)
Then, in your file manager, right click on the eXoDOS 6.4 Linux Patch.zip file and select "Extract Here" or "Extract > Extract archive here", depending on what you are using.
Alternatively, you may open the zip with a utility such as Ark, and drag the files and folders into the root eXoDOS directory.
The important thing is to ensure the files are extracted into the root directory of the collection, and not into a newly created subdirectory.
If you have also downloaded the eXoDOS Media Pack, ensure it has been downloaded the the same directory as the base eXoDOS collection. Then, download and place the "DOS_linux_Magazines.zip" file in the Content directory. Do not unzip this file.
After this has been done, proceed to the next step.
Step 2 - Installing System Dependencies
The next step is to install the software needed to run the collection. The install_dependencies.command script will run you through a guided setup to do this.
Note: If you are using Thunar or XFCE, you will first need to enable running shell files as executables. To do this, open a terminal and run the following command: xfconf-query --channel thunar --property /misc-exec-shell-scripts-by-default --create --type bool --set true

In your file manager, double-click on install_dependencies.command to start the dependency installer. If you are asked whether you want to execute the file, click yes.
If you are using Nautilus or Gnome and are not given this option to run by double-clicking, right click the file and select Run as Program.
Note: This step will need to be done on any Linux computer that has not previously ran eXoDOS 6, even if the full setup has already been completed on a portable drive. Also note that the flatpaks are installed at a user level. As such, other users will need to run the dependency installer separately as well. If you update your video drivers, you may also need to follow that up with a flatpak update. Rerunning a dependency installer installation will handle that for you.

Upon running the dependency installer, you will be prompted with a guided setup that gives the following options:
The "[D]ownload the latest setup" option will only grab the newest version of the eXo Dependency Installer, not eXoDOS itself. This may be useful if there is a problem with the dependency installer or if new flatpaks are needed. If the dependency installer is updated, it should be reran to launch the new version. To proceed with installing the dependencies, choose "[P]roceed with installation" and follow the on-screen instruction.
[P]roceed with installation
[D]ownload the latest setup
[R]emove all installed eXo packages
[A]bort installation
The "[D]ownload the latest setup" option will only grab the newest version of the eXo Dependency Installer, not eXoDOS itself. This may be useful if there is a problem with the dependency installer or if new flatpaks are needed. If the dependency installer is updated, it should be reran to launch the new version. To proceed with installing the dependencies, choose "[P]roceed with installation" and follow the on-screen instructions.
Step 3 - Installing eXoDOS
The final step is to run the eXoDOS Setup.
In your file manager, double-click on the eXoDOS Setup.command file to start the setup, and then follow the on-screen instructions. If you are asked whether you want to execute the file, click yes. If you are using Nautilus or Gnome and are not given this option, right click the file and select Run as Program.
The setup file will check for required files and warn you if any are missing. It will also check for files from the Media Pack Add-On.
This will unpack the required eXoDOS files, including the LaunchBox assets and the games front end assets/configs to run the collection. In addition, it will extract the Linux game launcher and setup files. It will make the collection work on both Windows and Linux computers.
It is important to run the setup and not extract any files manually. Not only are the files location sensitive, but the setup makes some changes to them.
The eXoDOS Setup will give you the opportunity to customize your set. This includes the option to remove Adult games from the exogui and LaunchBox menu. This removes games with sex or nudity from the LaunchBox XML file. This does not remove violent games. Please make use of the ratings category in LaunchBox if you would like to filter the games further.
You will also be prompted as to if you would like your global defaults to be Fullscreen or Windowed and whether or not you would like to default to Aspect Ratio On or Off.
Once it is complete, run exogui to dive right in.
Note: The eXoDOS collection can be run from any directory, as all launch files are designed to use relative paths to each other. However, if you choose to add a desktop shortcut to exogui and then later move eXoDOS to a new location, you will need to run the eXoDOS Updater to update the shortcut to point to the new location. The eXoDOS Updater will allow you to reconfigure all of the installation options instead of running through the entire setup process again.
Using eXoDOS
exogui
The official Linux frontend is exogui, a fork of Flashpoint Launcher. A member of our Discord, jelcynek, created exogui and has continued to maintain it over the years. More recently, Colin, the main Flashpoint Launcher developer, has also contributed to exogui. Together, they have made a very solid frontend. We are still looking for more volunteers to improve the UI experience, especially on the Steam Deck.
Simply double-click on the eXoDOS desktop icon, or execute the exogui.command file to launch the frontend. You will be presented with a list of all included games.
The website for exogui can be found at https://github.com/margorski/exodos-launcher/. At this time, jelcynek is looking for volunteers to help in the development of the frontend. If you are interested, please reach out to him in the #linux_port_for_nerds channel of our Discord.
The first time you attempt to run a game it will ask if you want to install it. Subsequent runs will directly launch the game.
Initial install may take some time depending on the size (a few of these games are upwards of 8 CDs!). During install you will be prompted to choose whether or not to enforce aspect ratio, full screen or windowed mode, and if you would like to apply a scaler. Scalers can smooth pixels, making older pixelated games look a bit more modern. The default setting is normal2x.
If you run the install file a second time, it will ask if you would like to uninstall the game. Choosing "yes" will erase the installed files from your disk, but keep the original ZIP file. You will be given an option to keep your saved games. If you choose not to uninstall the game you will get the chance to choose full screen or windowed again and another opportunity to change the scaler.
To launch a game or its setup from exogui, click on the game to select it, and then click on the 'Install', 'Play', or 'Setup' button in the right-hand pane.
Creating Desktop Shortcuts
If you would like to create a desktop shortcut to a specific game, open a plain text editor, such as gedit or kate, and create a file with the .desktop extension and the following contents, making changes to the Exec, Icon, and Name lines as appropriate:
[Desktop Entry]
Encoding=UTF-8
Version=1.0
Type=Application
Terminal=false
Exec="/home/username/eXoDOS/eXo/eXoDOS/!dos/mi1/Secret of Monkey Island, The (1990).command"
Icon=/usr/share/icons/Some Monkey Island Icon.png
Name[EN_US]=Secret of Monkey Island
Name=Secret of Monkey Island
Changelog
Changes to the eXoDOS 6.04 Linux Patch
Launch scripts directly from any file-manager: Files ending in the *.command extension can be launched directly from any file manager.
Revamped dependency installer with update support: For many distributions, sudo access is no longer needed.
Improved compatibility: The eXoDOS Linux patch will now run on virtually any x86_64 distro with flatpak support, including the Steam Deck.
Improved frontend: The exogui frontend is now feature packed with full support for extras, filters, images, playlists, and videos.
Improved backend: The backend has been completely revamped to include all eXoDOS 6 features.
Bug Squash: Hundreds of previously broken games have been fixed after thorough testing
Files
eXoDOS 6.4 Linux Patch.zip
eXoDOS 6.4 Linux Patch.zip contains the following files and directories:
├── Content
│   ├── !DOS_linux_metadata.zip
│   └── XODOS_linux_Metadata.zip
├── eXo
│   └── util
│       ├── eXoMerge.bsh
│       ├── install_dependencies.bsh
│       ├── Setup eXoDOS.bsh
│       └── utilDOS_linux.zip
├── eXoDOS Linux ReadMe.txt
├── eXoMerge.command
├── install_dependencies.command
└── Setup eXoDOS.command
This builds upon the existing file and directory structure of eXoDOS.
Content/!DOS_linux_metadata.zip - This contains DOSBox configuration files as well as the launcher and setup files (bsh, command, conf) for games.
Content/XODOS_linux_Metadata.zip - This contains the exogui files and some xml scripts.
eXo/util/eXoMerge.bsh - This is a support file for eXoMerge.command.
eXo/util/install_dependencies.bsh - This is a support file for install_dependencies.command.
eXo/util/Setup eXoDOS.bsh - This is a support file for Setup eXoDOS.command.
eXo/util/utilDOS_linux.zip - This contains the eXoDOS Linux backend files.
eXoMerge.command - This script is used to help merge two eXo collections that have already been installed.
install_dependencies.command - This launches the Linux/macOS setup to install system dependencies needed for eXo collections.
Setup eXoDOS.command - This launches the Linux/macOS setup for eXoDOS. While you cannot currently run eXoDOS on macOS, you can still install it for other systems.
util_linux.zip
util_linux.zip contents:
!english/texts_linux.txt - support file for the eXoDOS Updater
!languagepacks/Alternate Launcher.bsh - language pack support file for Linux alternate launcher (called by bsh script in the game Extras directory)
!languagepacks/Alternate Launcher.msh - language pack support file for macOS alternate launcher (called by msh script in the game Extras directory)
!languagepacks/install.bsh - language pack support file for Linux game installer (called by bsh script in game directory)
!languagepacks/install.msh - language pack support file for macOS game installer (called by msh script in game directory)
!languagepacks/ip.bsh - language pack support file to determine IP address for multiplayer games in Linux (called by the launch.bsh script in the same directory)
!languagepacks/ip.msh - language pack support file to determine IP address for multiplayer games in macOS (called by the launch.msh script in the same directory)
!languagepacks/launch.bsh - language pack support file to launch games in Linux (called by the <game name>.bsh script in the game directory)
!languagepacks/launch.msh - language pack support file to launch games in macOS (called by the <game name>.msh script in the game directory)
Sumatra/CallSumatra.bsh - Linux support file for CallSumatra.command
Sumatra/CallSumatra.command - exogui calls this to launch Sumatra for magazine articles in Linux
AltLauncher.bsh - support file for Linux alternate launcher (called by bsh script in the game Extras directory)
AltLauncher.msh - support file for macOS alternate launcher (called by msh script in the game Extras directory)
EXTDOS_linux.zip - contains Linux flatpaks, update files, AppImages, and emulator support files (bak, bsh, command, conf, txt)
alt_dosbox_linux.txt - defines the command to launch DOSBox for the alternate launcher (must be DOSBox Staging to not break conf files)
alt_launch_linux.txt - defines the directory containing the DOSBox Staging resource folder used by eXoDOS for the alternate launcher
converter.bash - support file for regenerate.bash that converts bat files to bash files using a long series of substitution commands
dosbox_linux.txt - defines what version of DOSBox is used by each game in Linux
eXoLBpm_linux.py - The LaunchBox Parents.xml merging tool for Linux
eXoLPLBXMLedit_linux.py - The eXoDOS Language Pack LaunchBox XML edit tool for Linux
eXoLPPPM_linux.py - The eXoDOS Language Pack Playlist Parents Merger tool for Linux
exodos.png - png file that can be used as a custom icon in Steam
exodosvi_cover.jpg - Box art image that can be used as a custom background in Steam
install.bsh - support file for Linux game install scripts (gets called by the install.bsh script in the game directory)
install.msh - support file for macOS game install scripts (gets called by the install.msh script in the game directory)
ip.bsh - support file to determine IP address for multiplayer games in Linux (called by the launch.bsh script in the same directory)
ip.msh - support file to determine IP address for multiplayer games in macOS (called by the launch.msh script in the same directory)
launch.bsh - support file to launch games in Linux (called by the <game name>.bsh script in the game directory)
launch.msh - support file to launch games in macOS (called by the <game name>.msh script in the game directory)
regenerate.bash - location sensitive development script used to convert unzipped files from eXo collections to Linux and macOS
version.bsh - Linux support file for version.command
version.command - This tells the currently installed version of eXoDOS
version.msh - macOS support file for version.command
Content/DOS_linux_Magazines.zip - Linux supplement for the Media Pack - This contains Linux DOSBox configuration, launcher, and cue files related to magazines and disk magazines (bat, bsh, command, conf, cue).

Development Scripts
Note: For the rest of this document, files will be described using their locations after installing eXoDOS.
eXo/util/converter.bash
The converter.bash script contains the convertScript function, which, when called, will attempt to convert a file's batch code to bash. The file that the convertScript function is ran against is determined by a variable, $currentScript. Note that the converter.bash script is not meant to be executed directly.
To prevent direct execution, the converter.bash script checks that a variable, $hideMessage, has a value of true. Note that even when $hideMessage = true, executing converter.bash does not automatically call the convertScript function. Instead, the source command should be ran against converter.bash to bring the convertScript function into the shell session's memory. Then, assuming the value of $currentScript has been set, the convertScript function should be called.
Example use where bat files in a directory called filesToConvert:
hideMessage='true'
. eXo/util/converter.bash
for file in filesToConvert/*.bat
do
    cp "$file" "${file%.bat}.bsh"
done
chmod +x filesToConvert/*.bsh
for currentScript in filesToConvert/*.bsh
do
    convertScript
done
Normally, the converter.bash script is called by the regenerate.bash script. Details about those scripts will be described later in this document. These scripts are intended for development purposes, and changes periodically have to be made to them to handle any conversions that do not succeed. This could involve anything from fixing case inconsistencies to parsing batch code that was written in an unforeseen way.
convertScript Function
The convertScript function runs a series of sed, ed, and Perl commands to convert a file from batch to bash. As this is a very complex text manipulation process, the order of each command is critically important. It is heavily recommended to add any new substitution commands close to the bottom of the function. Each subsequent text manipulation command may search for and change something that was previously altered, but not yet in a final state. If any existing text manipulation commands are changed or new ones added, everything needs to be very carefully audited. Edge cases are everywhere.
Example code snippet from the convertScript function:
    #escape backslashes in all echoes, change \ to / after the redirects
    sed -i -e '/^echo.*\\/{
                   s|#|##|g;
                   s|\\|/#|g;
                   :a;
                   s|^\(echo.*>.*\)/#\(.*\)|\1/\2|;
                   ta;
                   s|/#|\\\\|g;
                   s|##|#|g;
               }' "$currentScript"

    #escape quotes on echoes without redirects
    sed -i -e "/^echo/{ />/! s/\"/\\\\\"/g }" "$currentScript"
               
    #add a double quote to the beginning of echoes
    sed -i -e "s/^echo /echo \"/" "$currentScript"
    
    #add a double quote to the end of echoes without redirects
    sed -i -e "/^echo/{ />/!s/.$/\"/ }" "$currentScript"
    
    #ensure echo redirects are preceded by spaces
    sed -i -e "/^echo/ {/[^[:space:]]>>/ s/>>/ >>/;}" "$currentScript"
    sed -i -e "/^echo.*[^[:space:]]>/{ />>/! s/>/ >/;}" "$currentScript" 
    
    #add a double quote to the end of echoes with redirects
    sed -i -e "/^echo/ s/ >>/\" >> /" "$currentScript"
    sed -i -e "/^echo.*>/{ />>/! s/ >/\" > /;}" "$currentScript"
    
    #escape all $ characters
    sed -i -e "s/\\$/\\\\$/g" "$currentScript"
    
    #make all occurrences of goto lowercase except on echo and comment lines
    sed -i -e '/^echo\|^#/!s/goto/goto/gI' "$currentScript"
    
    #change all occurrences of GOTO to goto only after echo redirections
    sed -i -e '/^echo.*>.*GOTO/ {
                   s/#/##/g;
                   s/GOTO/goto#/g;
                   :a;
                   s/^\(echo.*>.*\)goto#\(.*\)/\1goto\2/;
                   ta;
                   s/goto#/GOTO/g;
                   s/##/#/g;
               }' "$currentScript"
As shown in the above code snippet, comments are used to tell what every text manipulation operation does. This is necessary to ensure that the script continues to be maintainable.
Note: When doing a systematic conversion of the eXoDOS collection, it is important to remember that the convertScript function is ran against every batch file in eXoDOS, with the exception of those in game archives (e.g. run.bat). Additional game specific text manipulations are written in the regenerate.bash script.
eXo/util/regenerate.bash
The purpose of the regenerate.bash script is to assist in the development of future Linux and macOS patches by automating the conversion of config files and Windows batch files to their Linux and macOS equivalents. This script is not intended for end-users. As new versions of eXoDOS come out, both the regenerate.bash script as well as the converter.bash will need to be altered. It is impossible to predict how the Windows batch files will be written. It is very common for eXo to do some extremely complex operations in batch files that can make updating these scripts very challenging. Version 6 added much more complexity to eXoDOS than had ever previously existed. As a result, from version 5 to version 6, these files grew over 5 and a half times in size and complexity. As time goes on, new challenges are likely to be faced for maintaining these scripts.
The regenerate.bash script first checks that the eXoDOS files are in the correct location in relation to it. Next, it loads the convertScript function into memory, and converts all of the unzipped bat, conf, and other known support files. As case inconsistencies are found, substitutions to correct the inconsistencies are manually placed into the regenerate.bash script.
Most text manipulation for the above steps is done through sed commands, although there are a few situations where ed and Perl are used instead.
In short, when executing the regenerate.bash script, it goes through the following steps:
Gives a disclaimer that running the script will take a VERY long time
Checks that standard eXo files are located in their expected locations in relation to the script
Fixes zip archive references
Fixes batch file reference inconsistencies
Copies bat files to newly created bsh files
Prepares bsh files for conversion
Converts syntax for the Linux shell files (bsh) from Windows batch to bash
Removes unnecessary dependency checks for eXoDREAMM and eXoScummVM
Creates universal launch files for Linux and macOS (command files)
Fixes dosbox.conf typos with known solutions
Fixes dosbox.conf file and directory reference inconsistencies
Creates DOSBox configuration files for Linux
Makes necessary changes to Linux configuration files
Applies Linux-only backend fixes
Applies Linux-only game specific fixes
Converts shell script reference txt files
Prepares macOS shell files (this step is currently skipped for eXoDOS, eXoScummVM, and eXoWin3x)
Corrects xml inconsistencies with known solutions
Removes unnecessary files
Note: All of the case inconsistency fixes and game specific changes are manually added to the regenerate.bash script. There is no magic voodoo code to determine what needs to be changed to make each game work correctly.
Linux Flatpaks
The following flatpaks use org.freedesktop.Platform 24.08:
com.retro_exo.aria2c
com.retro_exo.dosbox-staging-081-2
com.retro_exo.dosbox-x-08220
com.retro_exo.dosbox-x-20240701
com.retro_exo.gzdoom-4-11-3
com.retro_exo.mcomix
com.retro_exo.scummvm-2-2-0
com.retro_exo.scummvm-2-3-0-git15811-gf97bfb7ce1
The following flatpaks use org.freedesktop.Platform 23.08:
com.retro_exo.dosbox-074r3-1
com.retro_exo.dosbox-ece-r4301
com.retro_exo.dosbox-ece-r4358
com.retro_exo.dosbox-ece-r4482
com.retro_exo.dosbox-gridc-4-3-1
com.retro_exo.mpv
com.retro_exo.wine
The following flatpaks use org.gnome.Platform 46:
com.retro_exo.abiword
com.retro_exo.gnumeric
The following flatpaks use org.kde.Platform 6.7:
com.retro_exo.falkon
com.retro_exo.okular
Linux Update and Patch Files
The Update directory is extracted from EXTDOS_linux.zip to the eXo/Update location. It contains the scripts to run the eXoDOS updater as well as subdirectories for updates and patch files. The eXo/Update directory may initially look something like the following:
├── changelog.txt
├── cleanup.bat
├── cleanup.bsh
├── cleanup.command
├── !dos
│   └── linux
│       └── release
│           ├── Battle Isle 2 (1993).zip
│           ├── Breach 2 (1990).zip
│           ├── Carmageddon Max Pack (1998).zip
│           ├── Command and Conquer (1995).zip
│           ├── Command and Conquer - Red Alert (1996).zip
│           ├── Complete Great Naval Battles, The - The Final Fury (1996).zip
│           ├── DOOM - eXoWAD (2021).zip
│           ├── Grand Theft Auto (1997).zip
│           ├── Hard Nova (1990).zip
│           ├── Heroes of Might and Magic II (Deluxe Edition) (1998).zip
│           ├── Jane's Combat Simulations Advanced Tactical Fighters (1996).zip
│           ├── Last Half of Darkness (1989).zip
│           ├── Lemmings (1991).zip
│           ├── Lemmings 3 - All New World of Lemmings (1994).zip
│           ├── Leo the Lion (1997).zip
│           ├── Living Ball (1995).zip
│           ├── Mean 18 (1986).zip
│           ├── MechWarrior 2 (Limited Edition) (1996).zip
│           ├── NFL Challenge (1985).zip
│           ├── Normality (1996).zip
│           ├── Picture Perfect Golf (1995).zip
│           ├── Prisoner of Ice (1995).zip
│           ├── Realms of Arkania - Blade of Destiny (1992).zip
│           ├── Resurrection - Rise 2 (1996).zip
│           ├── Sigil (2019).zip
│           ├── Sigil II (2023).zip
│           ├── Star Trek - Judgement Rites CD (1993).zip
│           ├── Time Gate - Knight's Chase (1995).zip
│           ├── Ultima VI - The False Prophet (1990).zip
│           ├── Ultima V - Warriors of Destiny (1988).zip
│           └── Zone of Artificial Resources (1997).zip
├── index.txt
├── restore.exe
├── restore.py
├── update.bat
├── update.bsh
├── update.command
├── update_installed.bat
├── update_installed.bsh
├── update_installed.command
├── update.txt
├── update_xml.bat
├── update_xml.bsh
├── update_xml.command
└── ver
    └── ver.txt
Executing the update.command script will run an update for eXoDOS. This normally will be done in exogui from the eXoDOS game entry. Both the Windows version of eXoDOS and the Linux patch download the same updates. Updates work identically regardless of the operating system.
Files in the eXo/Update/!dos directory are for non-OS specific game file updates.
Files in the eXo/Update/!dos/linux/release directory are Linux specific patch files that are bundled with the eXoDOS Linux patch when you download it.
Files in the eXo/Update/!dos/linux directory are Linux specific update files that are downloaded as part of an eXoDOS update.
All files extracted from Linux specific archives have unique filenames to differentiate them from files that should only be used in Windows.
Files are extracted from these directories in the following order:
eXo/Update/!dos
eXo/Update/!dos/linux/release
eXo/Update/!dos/linux
Preparing For Manual Conversion
to do
Packaging Files For Release
to do along with numerous other sections
