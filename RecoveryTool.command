#!/bin/bash
#STLVNUB
verS="RecoveryTool V0.c"
workingDirectory="`dirname \"$0\"`"
theBS="$workingDirectory"/com.apple.recovery.boot/BaseSystem.dmg
theTool="$workingDirectory"/TOOLS/dmtest
appDIR="$workingDirectory"/Apps
kextDIR="$workingDirectory"/Kexts
installDIR="$workingDirectory"/Installation
toolBoxDIR="$workingDirectory"/ToolBox
preheatDIR="$workingDirectory"/Files/LML
# files needed to build com.apple.recovery.boot, rest can be copied from OS X
carbDIR="$workingDirectory"/carb 
#files that need to be copied from OS X, boot.efi PlatformSupport.plist SystemVersion.plist
theprogs="boot.efi PlatformSupport.plist SystemVersion.plist"
#files that need to be grabbed from Install OS X Mountain Lion.app, kernelcache BaseSystem.dmg
theOutput="$workingDirectory"/BaseSystem.dmg
theSystem=$(uname -r)
theSystem="${theSystem:0:2}"
theBaseSystem="Mac OS X Base System"
theESD="Mac OS X Install ESD"
case "${theSystem}" in
    [0-10]) rootSystem="unsupported" ;;
    11) export rootSystem="Lion" ;;
    12)	export rootSystem="Mountain Lion" ;;
    13)	export rootSystem="Mavericks"; theBaseSystem="OS X Base System"; theESD="OS X Install ESD"; preheatDIR="$workingDirectory"/Files/Mvrks;;
    [14-20]) rootSystem="Unknown" ;;
esac
[ "$rootSystem" == unsupported ] && echo "For Lion-Mavericks Only!!" && exit 1
b=1
function makeRecovery(){
if [ ! -f "$workingDirectory"/com.apple.recovery.boot/BaseSystem.dmg ]; then
	if [ -e /Applications/"Install OS X $rootSystem.app" ]; then
		echo "Step 1: Making com.apple.recovery.boot Folder"
		[ ! -d "$workingDirectory"/com.apple.recovery.boot ] && mkdir "$workingDirectory"/com.apple.recovery.boot
		echo "Copy some files"
		cp -R "${carbDIR}"/ "$workingDirectory"/com.apple.recovery.boot
		echo "open Install OS X $rootSystem.app/Contents/SharedSupport/InstallESD.dmg"
		open /Applications/"Install OS X $rootSystem".app/Contents/SharedSupport/InstallESD.dmg
		while [ ! -d /Volumes/"$theESD"/System/Library/CoreServices/ ]; do
			wait
		done
		for prog in $theprogs; do
			if [ -f $prog ]; then
				echo "cp $prog"
				cp /Volumes/"$theESD"/System/Library/CoreServices/"$prog" "$workingDirectory"/com.apple.recovery.boot/
			fi	
		done
		echo "Grab BaseSystem.dmg, boot.efi and kernelcache"
		cp /Volumes/"$theESD"/BaseSystem.dmg "$workingDirectory"/com.apple.recovery.boot/
		cp /Volumes/"$theESD"/kernelcache "$workingDirectory"/com.apple.recovery.boot/
		cp /Volumes/"$theESD"/boot.efi "$workingDirectory"/com.apple.recovery.boot/
		echo "detach..."
		hdiutil detach /Volumes/"$theESD"
		echo "Step $b: Done…"; let b++
	else
		echo "Please download '$theESD $rootSystem.app' from the App store"
		exit 1
	fi
else
	echo "Local Recovery Folder Found"
	echo "Will use 'com.apple.recovery.boot/BaseSystem.dmg' as the source"
fi
echo "Step $b: BaseSystem.dmg found, attaching with shadow…"; let b++
hdiutil attach -nobrowse -owners on "$theBS" -shadow
[ ! -d /Volumes/"$theBaseSystem"/ToolBox/ ] && mkdir -p /Volumes/"$theBaseSystem"/ToolBox/
if [ $1 == Modified ]; then
	echo "Step $b: Copy some apps and stuff and chown them..."; let b++
	sudo cp -R "${appDIR}"/ /Volumes/"$theBaseSystem"/Applications/
	sudo chown -R root:wheel /Volumes/"$theBaseSystem"/Applications/
	sudo cp -R "${toolBoxDIR}" /Volumes/"$theBaseSystem"/
	sudo cp -R "${installDIR}"/ /Volumes/"$theBaseSystem"/System/Installation/CDIS/
fi
echo "Step $b: Copy preheat.sh, chmod and chown it..."; let b++
sudo cp -R "${preheatDIR}"/preheat.sh /Volumes/"$theBaseSystem"/System/Installation/CDIS/preheat.sh
sudo chmod +x /Volumes/"$theBaseSystem"/System/Installation/CDIS/preheat.sh
sudo chown -R root:wheel /Volumes/"$theBaseSystem"/System/Installation/CDIS/
echo "Step $b: Copy Kexts,chown them, and detach..."; let b++
sudo cp -R "${kextDIR}" /Volumes/"$theBaseSystem"/ToolBox/
sudo chown -R root:wheel /Volumes/"$theBaseSystem"/Toolbox/
echo "Detaching…"
hdiutil detach /Volumes/"$theBaseSystem"
echo "Step $b: Converting back to readonly..."; let b++
hdiutil convert -format UDZO -o "$theOutput" "$theBS" -shadow
echo "Step $b: asr checksumming…"; let b++
asr -imagescan "$theOutput"
echo "Step $b: Make Recovery Partiion..."; let b++
sudo $theTool ensureRecoveryPartition / "$theOutput" 0 0 "$workingDirectory"/com.apple.recovery.boot/BaseSystem.chunklist
echo "Step $b: remove temp files..."
rm -rf "$theBS".shadow
rm -rf "$workingDirectory"/BaseSystem.dmg
echo "done"
tput bel
}

getBootedHD(){
DEVBooted=`diskutil info / | grep 'Device Identifier:'` # get disk that we booted from
DEVBoot="${DEVBooted:29:8}"
DEVSlice="${DEVBoot:6:1}"
DEVBooted="${DEVBooted:29:5}"
let DEVSlice++
DEVREC="${DEVBooted}s$DEVSlice"
DEVBootedName=`diskutil info / | grep 'Volume Name:'`
DEVBootedName="${DEVBootedName:15:40}"
}

function findRecovery(){
recoveryPart=
DevRecs=`diskutil list | grep Recovery | cut -c 69-75`
for therec in $DevRecs; do
	if [ "${DEVREC}" == "$therec" ]; then
		DevRoot="${DEVBooted}s" #`diskutil list | grep Recovery | cut -c 69-74`# isolate the last digit of that partition ID
		DevID="${DEVSlice}" #`diskutil list | grep Recovery | cut -c 75`
		# set the variable which contains the FULL drive ID of the recovery partition
		recoveryPart="$DevRoot$DevID"
		return
	fi
done
}

function deleteRecovery(){
echo "The recovery partition we're erasing is: $recoveryPart"

# we know the main partition is one digit LESS on the chain
let mergeID=DevID-1

# set the variable for the drive partition into which we'd like to merge
mergePart="$DevRoot$mergeID"
echo "The partition into which we're merging is: $mergePart"

# find the NAME of the merge partition by setting variable
mergeName=$DEVBootedName # `diskutil list | grep $mergePart | cut -c 34-57`
echo "The name of the merge partition is: $mergeName"
choice=
read -p "Press 'c' key to continue, any other to exit" choice
if [ $choice != c ]; then
	exit 1
fi	

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
	echo -e "You have multiple disks attached to your Mac.\nI will assume that $DEVBooted is your Macintosh HD boot volume."
else
	echo -e "\n \n"
	echo "Preparing to check your hard drive for errors."
fi
diskutil verifyDisk $DEVBooted
RetVal=`echo $?`
if [ $RetVal == 1 ]; then
    echo -e "$DEVBootedName needs to be repaired.\nThe easiest way to do this is to boot off another drive or boot disk running Lion or Mountain Lion."
    exit 1

else
    echo -e "\n \n"
    echo "Your disk appears to be OK.  The script will now continue."
fi
sleep 2
}

function Vanilla(){
	checkDisks
	makeRecovery $a # pass argument, Vanilla OR Modified
}

function Modified(){
	Vanilla
}

function Delete(){
	deleteRecovery
}

function Exit(){
	echo "Bye"
	exit 1
}		

function menu(){
	findRecovery
	echo -e "\n \n"
	if [ "$recoveryPart" != "" ]; then
		mess="The Following Recovery Partition has been found: $recoveryPart"
		CHOICE2="Vanilla Modified Delete Exit"
		choice3="* Removes recovery partition                                       *"
	else
		mess="No Recovery Found…"
		CHOICE2="Vanilla Modified Exit"
		choice3=""
	fi	
	echo -e "Running '$verS' on '$rootSystem' with disk '${DEVBooted}'"
	echo "$mess"
	echo -e "*************** This script does one of the following:**************"
	echo "* Installs a 'vanilla' recovery partition, with FakeSMC            *"
	echo "* Installs a 'modified' recovery partition, with FakeSMC and Tools *"
	echo -e "$choice3"
	echo "*************** Please Select from the following list **************"
	echo; printf '\a'
	PS3='Enter your choice as a numeric value: '
	select a in $CHOICE2
	do
	case "$a"  in
	"") echo "You must select one of the above!";echo "Hit Enter to see menu again!" ;;
	"$a" ) break ;;
	esac
	done
	"$a"
	wait
	menu
}
getBootedHD
menu