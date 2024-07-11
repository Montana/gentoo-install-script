#!/bin/bash

set -e

echo "Updating system clock..."
ntpd -q -g

echo "Partitioning the disk..."
parted /dev/sda --script mklabel gpt
parted /dev/sda --script mkpart primary 1MiB 3MiB
parted /dev/sda --script mkpart primary 3MiB 131MiB
parted /dev/sda --script mkpart primary 131MiB 100%

echo "Formatting the partitions..."
mkfs.fat -F 32 /dev/sda1
mkfs.ext4 /dev/sda2
mkfs.ext4 /dev/sda3

echo "Mounting the filesystems..."
mount /dev/sda3 /mnt/gentoo
mkdir /mnt/gentoo/boot
mount /dev/sda2 /mnt/gentoo/boot
mkdir -p /mnt/gentoo/boot/efi
mount /dev/sda1 /mnt/gentoo/boot/efi

echo "Downloading the stage3 tarball..."
cd /mnt/gentoo
wget http://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64/stage3-amd64-*.tar.xz
echo "Extracting the stage3 tarball..."
tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner

echo "Configuring compile options..."
cat <<EOF > /mnt/gentoo/etc/portage/make.conf
CFLAGS="-march=native -O2 -pipe"
CXXFLAGS="\${CFLAGS}"
MAKEOPTS="-j$(nproc)"
EOF

echo "Copying DNS info..."
cp --dereference /etc/resolv.conf /mnt/gentoo/etc/

echo "Mounting necessary filesystems..."
mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/dev

echo "Entering the chroot environment..."
chroot /mnt/gentoo /bin/bash <<'EOF'
source /etc/profile
export PS1="(chroot) ${PS1}"

echo "Configuring Portage..."
emerge-webrsync

echo "Selecting a profile..."
eselect profile list
eselect profile set 1

echo "Updating the @world set..."
emerge --verbose --update --deep --newuse @world

echo "Setting the timezone..."
echo "America/New_York" > /etc/timezone
emerge --config sys-libs/timezone-data

echo "Setting the locale..."
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
eselect locale set en_US.utf8
env-update && source /etc/profile

echo "Installing kernel sources..."
emerge sys-kernel/gentoo-sources

echo "Configuring the kernel..."
cd /usr/src/linux
make menuconfig

echo "Compiling and installing the kernel..."
make && make modules_install
cp arch/x86/boot/bzImage /boot/kernel-$(make kernelrelease)

echo "Configuring fstab..."
cat <<EOT > /etc/fstab
/dev/sda2   /boot        ext4    defaults,noatime     0 2
/dev/sda3   /            ext4    defaults,noatime     0 1
/dev/sda1   /boot/efi    vfat    defaults,noatime     0 2
EOT

echo "Setting up the network..."
echo "hostname=\"gentoo\"" > /etc/conf.d/hostname
emerge --noreplace net-misc/netifrc
cd /etc/init.d
ln -s net.lo net.eth0
rc-update add net.eth0 default

echo "Setting the root password..."
passwd

echo "Installing GRUB..."
emerge sys-boot/grub
grub-install /dev/sda
grub-mkconfig -o /boot/grub/grub.cfg

EOF

echo "Exiting the chroot environment..."
exit

echo "Unmounting filesystems..."
umount -l /mnt/gentoo/dev{/shm,/pts,}
umount -R /mnt/gentoo

echo "Gentoo installation is complete! Rebooting now..."
reboot
