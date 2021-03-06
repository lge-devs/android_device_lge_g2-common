#!/sbin/sh

# /sbin/sh runs out of TWRP.. use it.

PROGS="sgdisk toybox resize2fs e2fsck mke2fs"
RC=0
# Check for my needed programs
for PROG in ${PROGS} ; do
   if [ ! -x "/tmp/${PROG}" ] ; then
      echo "Missing: /tmp/${PROG}"
      RC=9
   fi
done
#
# all prebuilt
if [ ${RC} -ne 0 ] ; then
   echo "Aborting.."
   exit 7
fi

TOYBOX="/tmp/toybox"

# Get bootdevice.. don't assume /dev/block/sda
DISK=`${TOYBOX} readlink /dev/block/platform/msm_sdcc.1/by-name/system | ${TOYBOX} sed -r 's/p[0-9]+//g'`

# Check for /vendor existence
VENDOR=`/tmp/sgdisk --pretend --print ${DISK} | ${TOYBOX} grep -c vendor`

if [ ${VENDOR} -ge 1 ] ; then
   # If vendor does not have a ext4 filesystem, mke2fs it then
   if [ `${TOYBOX} blkid /dev/block/platform/msm_sdcc.1/by-name/vendor | ${TOYBOX} egrep -c ext4` -eq 0 ] ; then
      /tmp/mke2fs -t ext4 /dev/block/platform/msm_sdcc.1/by-name/vendor
   fi
# Got it, we're done...
   exit 0
fi

# Missing... need to create it..
${TOYBOX} echo "/vendor missing"
#
# Get next partition...
LAST=`/tmp/sgdisk --pretend --print ${DISK} | ${TOYBOX} tail -1 | ${TOYBOX} tr -s ' ' | ${TOYBOX} cut -d' ' -f2`
NEXT=`${TOYBOX} expr ${LAST} + 1`
NUMPARTS=`/tmp/sgdisk --pretend --print ${DISK} | ${TOYBOX} grep 'holds up to' | ${TOYBOX} tr -s ' ' | ${TOYBOX} cut -d' ' -f6`

# Check if we need to expand the partition table
RESIZETABLE=""
if [ ${NEXT} -gt ${NUMPARTS} ] ; then
   RESIZETABLE=" --resize-table=${NEXT}"
fi

# Get /system partition #, start, ending, code
SYSPARTNUM=`/tmp/sgdisk --pretend --print ${DISK} | ${TOYBOX} grep system | ${TOYBOX} tr -s ' ' | ${TOYBOX} cut -d' ' -f2`
SYSSTART=`/tmp/sgdisk --pretend --print ${DISK} | ${TOYBOX} grep system | ${TOYBOX} tr -s ' ' | ${TOYBOX} cut -d' ' -f3`
SYSEND=`/tmp/sgdisk --pretend --print ${DISK} | ${TOYBOX} grep system | ${TOYBOX} tr -s ' ' | ${TOYBOX} cut -d' ' -f4`
SYSCODE=`/tmp/sgdisk --pretend --print ${DISK} | ${TOYBOX} grep system | ${TOYBOX} tr -s ' ' | ${TOYBOX} cut -d' ' -f7`

# Get sector size
SECSIZE=`/tmp/sgdisk --pretend --print ${DISK} | ${TOYBOX} grep 'sector size' | ${TOYBOX} tr -s ' ' | ${TOYBOX} cut -d' ' -f4`

## Resize part..
/tmp/e2fsck /dev/block/platform/msm_sdcc.1/by-name/system

# 256 = 256mb..
VENDORSIZE=`${TOYBOX} expr 256 \* 1024 \* 1024 / ${SECSIZE}`

NEWEND=`${TOYBOX} expr ${SYSEND} - ${VENDORSIZE}`
VENDORSTART=`${TOYBOX} expr ${NEWEND} + 1`

NEWSYSSIZE=`${TOYBOX} expr ${NEWEND} - ${SYSSTART} + 1`
MINSYSSIZE=`/tmp/resize2fs -P /dev/block/platform/msm_sdcc.1/by-name/system 2>/dev/null | ${TOYBOX} grep minimum | ${TOYBOX} tr -s ' ' | ${TOYBOX} cut -d' ' -f7`

# Check if /system will shrink to small
if [ ${NEWSYSSIZE} -lt 0 ] ; then
   echo "ERROR: /system will be smaller than 0."
   exit 9
fi
if [ ${NEWSYSSIZE} -lt ${MINSYSSIZE} ] ; then
   echo "ERROR: /system will be smaller than the minimum allowed."
   exit 9
fi

# Resize /system, this will preserve the data and shrink it.
${TOYBOX} echo "*********Resize /system to ${NEWSYSSIZE} = ${NEWEND} - ${SYSSTART} + 1 (inclusize) = ${NEWSYSSIZE}"

/tmp/e2fsck -y -f /dev/block/platform/msm_sdcc.1/by-name/system
/tmp/resize2fs /dev/block/platform/msm_sdcc.1/by-name/system ${NEWSYSSIZE}

/tmp/sgdisk ${RESIZETABLE} --delete=${SYSPARTNUM} --new=${SYSPARTNUM}:${SYSSTART}:${NEWEND} --change-name=${SYSPARTNUM}:system --new=${NEXT}:${VENDORSTART}:${SYSEND} --change-name=${NEXT}:vendor --print ${DISK}

${TOYBOX} yes | /tmp/mke2fs -t ext4 ${DISK}p${SYSPARTNUM}
# We cannot run `/tmp/mke2fs -t ext4 ${DISK}p${NEXT}` here, kernel needs to be rebooted first
echo "*** Vendor partition created ***"
echo "Going down for reboot"
sleep 2
reboot recovery
