#
# Build and Setup U-Boot
#

# Load utility functions
. ./functions.sh

#Get kernel version 
KERNEL_VERSION=$(cat ${R}/boot/kernel.release)

# Fetch and build U-Boot bootloader
if [ "$ENABLE_UBOOT" = true ] ; then

  # Install c/c++ build environment inside the chroot
  chroot_install_cc

  # Copy existing U-Boot sources into chroot directory
  if [ -n "$UBOOTSRC_DIR" ] && [ -d "$UBOOTSRC_DIR" ] ; then
    # Copy local U-Boot sources
    cp -r "${UBOOTSRC_DIR}" "${R}/tmp"
  else
    # Create temporary directory for U-Boot sources
    temp_dir=$(as_nobody mktemp -d)

    # Fetch U-Boot sources
    as_nobody git -C "${temp_dir}" clone "${UBOOT_URL}"

    # Copy downloaded U-Boot sources
    mv "${temp_dir}/u-boot" "${R}/tmp/"

    # Set permissions of the U-Boot sources
    chown -R root:root "${R}/tmp/u-boot"

    # Remove temporary directory for U-Boot sources
    rm -fr "${temp_dir}"
  fi

  # Build and install U-Boot inside chroot
  chroot_exec make -j${KERNEL_THREADS} -C /tmp/u-boot/ ${UBOOT_CONFIG} all

  # Copy compiled bootloader binary and set config.txt to load it
  install_exec "${R}/tmp/u-boot/tools/mkimage" "${R}/usr/sbin/mkimage"
  install_readonly "${R}/tmp/u-boot/u-boot.bin" "${BOOT_DIR}/u-boot.bin"
  printf "\n# boot u-boot kernel\nkernel=u-boot.bin\n" >> "${BOOT_DIR}/config.txt"

  # Install and setup U-Boot command file
  install_readonly files/boot/uboot.mkimage "${BOOT_DIR}/uboot.mkimage"
  printf "# Set the kernel boot command line\nsetenv bootargs \"earlyprintk ${CMDLINE}\"\n\n$(cat ${BOOT_DIR}/uboot.mkimage)" > "${BOOT_DIR}/uboot.mkimage"

  if [ "$ENABLE_INITRAMFS" = true ] ; then
    # Convert generated initramfs for U-Boot using mkimage
    chroot_exec /usr/sbin/mkimage -A "${KERNEL_ARCH}" -T ramdisk -C none -n "initrd.img-${KERNEL_VERSION}" -d "/boot/initrd.img-${KERNEL_VERSION}" "/boot/initrd.img-${KERNEL_VERSION}.uboot"

    # Remove original initramfs file
    rm -f "${BOOT_DIR}/initrd.img-${KERNEL_VERSION}"
    sed '/initramfs/d' -i "${BOOT_DIR}/config.txt"

    # Configure U-Boot to load generated initramfs
    printf "# Set initramfs file\nsetenv initramfs initrd.img-${KERNEL_VERSION}.uboot\n\n$(cat ${BOOT_DIR}/uboot.mkimage)" > "${BOOT_DIR}/uboot.mkimage"
    printf "\nbootz \${kernel_addr_r} \${ramdisk_addr_r} \${fdt_addr_r}" >> "${BOOT_DIR}/uboot.mkimage"
    
  else # ENABLE_INITRAMFS=false
  
    # Remove initramfs from U-Boot mkfile
    sed -i '/.*initramfs.*/d' "${BOOT_DIR}/uboot.mkimage"

    if [ "$BUILD_KERNEL" = false ] ; then
      # Remove dtbfile from U-Boot mkfile
      sed -i '/.*dtbfile.*/d' "${BOOT_DIR}/uboot.mkimage"
      printf "\nbootz \${kernel_addr_r}" >> "${BOOT_DIR}/uboot.mkimage"
    else
      printf "\nbootz \${kernel_addr_r} - \${fdt_addr_r}" >> "${BOOT_DIR}/uboot.mkimage"
    fi
  fi

  # Set mkfile to use the correct dtb file
  sed -i "s/^\(setenv dtbfile \).*/\1${DTB_FILE}/" "${BOOT_DIR}/uboot.mkimage"

  # Set mkfile to use kernel image
  sed -i "s/^\(fatload mmc 0:1 \${kernel_addr_r} \).*/\1${KERNEL_IMAGE}/" "${BOOT_DIR}/uboot.mkimage"

  # Remove all leading blank lines
  sed -i "/./,\$!d" "${BOOT_DIR}/uboot.mkimage"

  # Generate U-Boot bootloader image
  chroot_exec /usr/sbin/mkimage -A "${KERNEL_ARCH}" -O linux -T script -C none -a 0x00000000 -e 0x00000000 -n "RPi${RPI_MODEL}" -d "/boot/uboot.mkimage" "/boot/boot.scr"

  # Remove U-Boot sources
  rm -fr "${R}/tmp/u-boot"
fi
