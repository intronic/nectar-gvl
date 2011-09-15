#!/bin/bash

# Instructions from  http://cssoss.wordpress.com/2011/04/27/openstack-beginners-guide-for-ubuntu-11-04-image-management/
# cant create 15G vm; 10G is the limit: kvm-img create -f raw server.img 15G
kvm-img create -f raw server.img 10G

# I used an au mirror
wget http://releases.ubuntu.com/natty/ubuntu-11.04-server-amd64.iso

# make sure you arent already running virt-manager or a VM already or you get an address in use error
sudo kvm -m 256 -cdrom ubuntu-11.04-server-amd64.iso -drive   file=server.img,if=scsi,index=0 -boot d -net nic -net user -nographic  -vnc :0

# in another window start up the vncviewer as console
# check your command-line options, and IP, could be something like:
vncviewer 10.10.10.4 :0
vncviewer 192.168.0.188:0

# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
# !! NOTE ** when you set up the file system, dont create a swap partition, or /boot, or LVM, 
# just create one big file EXT4 system for /

# once you are done, you can use this to reboot & log in
sudo kvm -m 256 -drive file=server.img,if=scsi,index=0,boot=on -boot c -net nic -net user -nographic -vnc :0

# Using vncviewer is a pain, you cant copy/paste in the two different vnc clients I tried
# Probably should have tried ssh.

# If you want you can update
# /etc/apt/sources.list according to: https://launchpad.net/ubuntu/+mirror/mirror.aarnet.edu.au-archive
# to have the following pairs of repos at the top of the file:
#deb http://mirror.aarnet.edu.au/pub/ubuntu/archive/ natty main restricted
#deb-src http://mirror.aarnet.edu.au/pub/ubuntu/archive/ natty main restricted
#deb http://mirror.aarnet.edu.au/pub/ubuntu/archive/ natty-updates main restricted
#deb-src http://mirror.aarnet.edu.au/pub/ubuntu/archive/ natty-updates main restricted

# then I did:
sudo apt-get update
sudo apt-get upgrade
sudo apt-get install openssh-server cloud-init

# remove network persistence rules 
sudo rm -rf /etc/udev/rules.d/70-persistent-net.rules

# then shutdown the image
sudo shutdown -h now

#####
# Now on the host OS, extract the EXT4 image
sudo losetup  -f  server.img
sudo losetup -a
sudo fdisk -cul /dev/loop0

# Disk /dev/loop0: 16.1 GB, 16106127360 bytes
# 255 heads, 63 sectors/track, 1958 cylinders, total 31457280 sectors
# Units = sectors of 1 * 512 = 512 bytes
# Sector size (logical/physical): 512 bytes / 512 bytes
# I/O size (minimum/optimal): 512 bytes / 512 bytes
# Disk identifier: 0x000ebf53

#       Device Boot      Start         End      Blocks   Id  System
# /dev/loop0p1   *        2048    31455231    15726592   83  Linux

# Make a note of the starting sector of the /dev/loop0p1 partition i.e the partition whose ID is 83. This number should be multiplied by 512 to obtain the correct value. In this case: 2048 x 512 = 1048576

# unmount loop0
sudo losetup -d /dev/loop0

# mount the partition from before:
sudo losetup -f -o 1048576 server.img

# Check it,
sudo losetup -a

# I see this:
# /dev/loop0: [0806]:8132782 (/home/mikep/tmp/server.img), offset 1048576

# Copy the entire partition to a new .raw file
sudo dd if=/dev/loop0 of=serverfinal.img

# Now we have our ext4 filesystem image i.e serverfinal.img

#Unmount the loop0 device
sudo losetup -d /dev/loop0

# 31455232+0 records in
# 31455232+0 records out
# 16105078784 bytes (16 GB) copied, 151.742 s, 106 MB/s

# You will need to tweak /etc/fstab to make it suitable for a cloud instance. 
# Loop mount the serverfinal.img, by running

sudo mount -o loop serverfinal.img /mnt

# Edit /mnt/etc/fstab and modify the line for mounting root partition(which may look like the following)
# UUID=e7f5af8d-5d96-45cc-a0fc-d0d1bde8f31c  /               ext4    errors=remount-ro  0       1
# to
# LABEL=uec-rootfs              /          ext4           defaults     0    0

# Mine was/is:
# UUID=cdbe4d9d-7ca0-4601-8350-4ead4e733c6d /               ext4    errors=remount-ro 0       1
# LABEL=rootfs    /       ext4    defaults        0       0

# Copy the kernel and the initrd image from /mnt/boot to user home directory. These will be used later for creating and uploading a complete virtual image to OpenStack.
# sudo cp /mnt/boot/vmlinuz-2.6.38-7-server /home/localadmin
# sudo cp /mnt/boot/initrd.img-2.6.38-7-server /home/localadmin

# mine was:
sudo cp /mnt/boot/vmlinuz-2.6.38-8-server .
sudo cp /mnt/boot/initrd.img-2.6.38-8-server .

# Unmount the Loop partition
sudo umount  /mnt

# Change the filesystem label of serverfinal.img to ‘uec-rootfs’
# sudo tune2fs -L uec-rootfs serverfinal.img
# Mine was:
sudo tune2fs -L rootfs serverfinal.img

# Now, we have all the components of the image ready to be uploaded to OpenStack imaging server.

############################
# Registering with OpenStack
uec-publish-image -t image --kernel-file vmlinuz-2.6.38-8-server --ramdisk-file initrd.img-2.6.38-8-server amd64 serverfinal.img mjp-image-01

# Following suggestions at : http://www.rc.nectar.org.au/redmine/issues/146

# Required env vars
export EC2_URL=http://nova.rc.nectar.org.au:8773/services/Cloud
export S3_URL=http://115.146.90.152:3333
export EC2_SECRET_KEY=xxxx
export EC2_ACCESS_KEY=xxxx:galaxy
export EC2_CERT=$HOME/.euca/euca2-admin-ce968c56-cert.pem
export EC2_PRIVATE_KEY=$HOME/.euca/euca2-admin-ce968c56-pk.pem
export EUCALYPTUS_CERT=$HOME/.euca/cloud-cert.pem
export EC2_USER_ID=42

uec-publish-image -t image --kernel-file vmlinuz-2.6.38-8-server --ramdisk-file initrd.img-2.6.38-8-server amd64 serverfinal.img mjp-image-01



# failed: euca-bundle-image --destination /tmp/uec-publish-image2.gmGXOC --arch x86_64 --image /tmp/uec-publish-image2.gmGXOC/.rename.ShoqA5/serverfinal.img --kernel eki-xxxxxxxx --ramdisk eri-xxxxxxxx
# x86_64
# cert must be specified.
# private key must be specified.
# user must be specified.
# ec2cert must be specified.

# Bundles an image for use with Eucalyptus or Amazon EC2.

# euca-bundle-image -i, --image image_path -u, --user user [-c, --cert cert_path] 
# [-k, --privatekey private_key_path] [-p, --prefix prefix] [--kernel kernel_id] 
# [--ramdisk ramdisk_id] [-B, --block-device-mapping mapping] 
# [-d, --destination destination_path] [--ec2cert ec2cert_path] 
# [-r, --arch target_architecture] [--batch] [-h, --help] [--version] [--debug] 
