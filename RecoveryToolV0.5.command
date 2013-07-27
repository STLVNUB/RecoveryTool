#!/bin/bash
#V0.6 STLVNUB
workingDirectory="`dirname \"$0\"`"
theBS="$workingDirectory"/com.apple.recovery.boot/BaseSystem.dmg
theTool="$workingDirectory"/TOOLS/dmtest
appDIR="$workingDirectory"/Apps
kextDIR="$workingDirectory"/Kexts
installDIR="$workingDirectory"/Installation
toolBoxDIR="$workingDirectory"/ToolBox
# files needed to build com.apple.recovery.boot, rest can be copied from OS X
carbDIR="$workingDirectory"/carb 
#files that need to be copied from OS X, boot.efi PlatformSupport.plist SystemVersion.plist
theprogs="boot.efi PlatformSupport.plist SystemVersion.plist"
#files that need to be grabbed from Install OS X Mountain Lion.app, kernelcache BaseSystem.dmg
theOutput="$workingDirectory"/BaseSystem.dmg

theSystem=$(uname -r)
theSystem="${theSystem:0:2}"
case "${theSystem}" in
    [0-10]) rootSystem="unsupported" ;;
    11) export rootSystem="Lion" ;;
    12)	export rootSystem="Mountain Lion" ;;
    13)	export rootSystem="Mavericks" ;;
    [14-20]) rootSystem="Unknown" ;;
esac
[ "$rootSystem" == unsupported ] && echo "For Lion-Mavericks Only!!" && exit 1
function makeRecovery(){
if [ ! -f "$workingDirectory"/com.apple.recovery.boot/BaseSystem.dmg ]; then
	if [ -e /Applications/"Install OS X Mountain Lion.app" ]; then
		echo "Step 1: Making com.apple.recovery.boot Folder"
		[ ! -d "$workingDirectory"/com.apple.recovery.boot ] && mkdir "$workingDirectory"/com.apple.recovery.boot
		echo "Copy some files"
		cp -R "${carbDIR}"/ "$workingDirectory"/com.apple.recovery.boot
		open /Applications/"Install OS X $rootSystem".app/Contents/SharedSupport/InstallESD.dmg
		while [ ! -d /Volumes/"Mac OS X Install ESD"/System/Library/CoreServices/ ]; do
			wait
		done
		for prog in $theprogs; do
				cp /Volumes/"Mac OS X Install ESD"/System/Library/CoreServices/"$prog" "$workingDirectory"/com.apple.recovery.boot/
		done
		echo "Grabbing BaseSystem.dmg and kernelcache"
		cp /Volumes/"Mac OS X Install ESD"/BaseSystem.dmg "$workingDirectory"/com.apple.recovery.boot/
		cp /Volumes/"Mac OS X Install ESD"/kernelcache "$workingDirectory"/com.apple.recovery.boot/
		hdiutil detach /Volumes/"Mac OS X Install ESD"
		echo "Step 1: Done…"
	else
		echo "Please download 'Install OS X $rootSystem.app' from the App store"
	fi	
fi
echo "Step 2: BaseSystem.dmg found, attaching with shadow..."
hdiutil attach -nobrowse -owners on "$theBS" -shadow
[ ! -d /Volumes/"Mac OS X Base System"/ToolBox/ ] && mkdir -p /Volumes/"Mac OS X Base System"/ToolBox/
if [ $1 == 2 ]; then # 1 = vanilla, 2 = modified
	echo "Copy some apps and stuff and chown them"
	sudo cp -R "${appDIR}"/ /Volumes/"Mac OS X Base System"/Applications/
	sudo chown -R root:wheel /Volumes/"Mac OS X Base System"/Applications/
	sudo cp -R "${installDIR}"/ /Volumes/"Mac OS X Base System"/System/Installation/CDIS/
	sudo chown -R root:wheel /Volumes/"Mac OS X Base System"/System/Installation/CDIS/
	sudo cp -R "${toolBoxDIR}" /Volumes/"Mac OS X Base System"/
fi	
echo "Copy FakeSMC and chown it"
sudo cp -R "${kextDIR}" /Volumes/"Mac OS X Base System"/ToolBox/
sudo chown -R root:wheel /Volumes/"Mac OS X Base System"/Toolbox/
echo "Detaching…"
hdiutil detach /Volumes/"Mac OS X Base System"
echo "Converting back to readonly"
hdiutil convert -format UDZO -o "$theOutput" "$theBS" -shadow
echo "asr checksumming…"
asr -imagescan "$theOutput"
echo "fixing..."
sudo $theTool ensureRecoveryPartition / "$theOutput" 0 0 "$workingDirectory"/com.apple.recovery.boot/BaseSystem.chunklist
echo "done"
tput bel
rm -rf "$theBS".shadow
rm -rf "$workingDirectory"/BaseSystem.dmg
}

getBootedHD(){
DEVBooted=`diskutil info / | grep 'Part of Whole:'` # get disk theat we booted from
DEVBooted="${DEVBooted:29:5}"
}

function deleteRecovery(){
DevRoot=`diskutil list | grep Recovery | cut -c 69-74`

# isolate the last digit of that partition ID
DevID=`diskutil list | grep Recovery | cut -c 75`
# set the variable which contains the FULL drive ID of the recovery partition
recoveryPart="$DevRoot$DevID"
echo "The recovery partition we're erasing is: $recoveryPart"

# we know the main partition is one digit LESS on the chain
let mergeID=DevID-1

# set the variable for the drive partition into which we'd like to merge
mergePart="$DevRoot$mergeID"
echo "The partition into which we're merging is: $mergePart"

# find the NAME of the merge partition by setting variable
mergeName=`diskutil list | grep $mergePart | cut -c 34-57`
echo "The name of the merge partition is: $mergeName"
choice=
read -p "Press 'c' key to continue, any other to exit" choice
if [ $choice != c ]; then
	exit 1
fi	


echo "The Following Recovery Partition(s) has been found:"
echo $recoveryPart
echo ""

diskutil eraseVolume HFS+ Blank $recoveryPart
echo ""

echo "Now merging the space from $recoveryPart into $mergePart"
diskutil mergePartitions HFS+ $mergeName $mergePart $recoveryPart
echo ""

echo "Merging is complete. Recovery Partition has been removed."
}

function checkDisks(){
disks=(`diskutil list | grep "GUID_partition_scheme" | awk '{print $5}'`)

if [ "${#disks[@]}" != 1 ]; then
	echo -e "\n \n"
	echo -e "You have multiple disks attached to your Mac.\nI will assume that disk0 is your Macintosh HD boot volume."
else
	echo -e "\n \n"
	echo "Preparing to check your hard drive for errors."
fi
diskutil verifyDisk $DEVBooted
RetVal=`echo $?`
if [ $RetVal == 1 ]; then
    echo -e "Macintosh HD needs to be repaired.\nThe easiest way to do this is to boot off another drive or boot disk running Lion or Mountain Lion."
    exit 1

else
    echo -e "\n \n"
    echo "Your disk appears to be OK.  The script will now continue."
fi
sleep 2
}

function menu(){
	echo -e "\n \n"
	echo "Running on $rootSystem"
	echo -e "This script does one of the following:"
	echo "  1) Installs a 'vanilla' recovery partition, with FakeSMC"
	echo "  2) Installs a 'modified' recovery partition, with FakeSMC and Tools"
	echo "  3) Removes recovery partition"
	echo "  4) Exit"  
	read -p "Please select '1 - 4'? " choice

	case "$choice" in
  	1|2 ) echo "Choice 1: Install"
  	sleep 1
  	checkDisks
  	makeRecovery $choice;;
  	3 ) echo "Choice 2: Removing"
  	deleteRecovery;;
  	4 ) echo "Bye";exit 1
  	esac
  	menu
}
getBootedHD
menu