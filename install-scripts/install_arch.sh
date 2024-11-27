#!/bin/bash

check_required_mounts() {
  check_required_mount "/mnt" || return 1
  check_required_mount "/mnt/boot" || return 1
  check_required_mount "/mnt/home" || return 1
  return 0
}

#check_required_mount(mountPoint)
check_required_mount() {
  if ! has_mount "$1"; then
    print_error "ERROR: $1 is not mounted. Installation cannot proceed."
    return 1
  fi
  return 0
}

#has_linux_installation(folderPath)
has_linux_installation() {
  if [[ -d "$1/etc" && -f "$1/etc/os-release" && -d "$1/boot" ]]; then
    return 0
  fi
  return 1
}

reformat_and_remount_partitions() {
  local rootPartition=$(get_device_from_mount "/mnt")
  local bootPartition=$(get_device_from_mount "/mnt/boot")
  local homePartition=$(get_device_from_mount "/mnt/home")
  
  echo ""
  try_unmount "/mnt/home" || return 1
  try_unmount "/mnt/boot" || return 1
  try_unmount "/mnt" || return 1

  echo ""
  print_info "Reformatting '$rootPartition'..."
  if ! mkfs.ext4 "$rootPartition" &> /dev/null; then
    echo ""
    print_error "Failed to reformat '$rootPartition'."
    print_error "Aborting..."
    sleep 2
    return 1
  fi
  print_success "Partition reformatted successfully."

  echo ""
  mount_install_partitions "$rootPartition" "$bootPartition" "$homePartition"

  echo ""
  print_success "Partitions remounted successfully."
  echo ""
  return 0
}

bootloader_entries_prompt() {
  local valid
  echo "Would you like to add bootloader entries for GUI, CLI, or both?"
  while [[ -z $valid ]]; do
    echo ""
    read -p "Choice (gui/cli/both): " _returnValue
    case "$_returnValue" in
      gui|GUI|cli|CLI|both|BOTH) valid=true ;;
      *) print_error "Invalid option. Please try again." ;;
    esac
  done
}

start_dhcp() {
  #Makes sure the "dhcpcd" service is running
  echo "Starting DHCP client..."
  systemctl start dhcpcd
}

internet_test() {
  echo "Checking internet connectivity..."
  ping -c 1 8.8.8.8 &> /dev/null
  return $?
}

setup_network() {
  local hasConnection
  local hasWirelessAdapter

  if has_wireless_adapter; then
    hasWirelessAdapter=true
  fi

  local skipRetryPrompt
  while [[ -z $hasConnection ]]; do
    print_error "Failed to connect to the internet."

    if [[ $hasWirelessAdapter ]]; then
      echo ""
      if yesno_prompt "Would you like to configure your wireless adapter? [Y/n]: "; then
        show_iwctl_help
        clear
        print_info "Starting wireless service..."
        systemctl start iwd
        echo ""
        iwctl
        skipRetryPrompt=true
      else
        skipRetryPrompt=""
      fi
    fi

    if [[ -z $skipRetryPrompt ]]; then
      continue_prompt "Press any key to retry or Ctrl+C to cancel..."
      echo ""
      echo ""
    fi

    if ! internet_test; then
      continue
    fi
    hasConnection=true
  done
}

has_wireless_adapter() {
  if has_command "iw" && iw dev | grep -q 'Interface'; then
    return 0
  fi
  return 1
}

show_iwctl_help() {
  local noColor='\033[0m'
  local green='\033[0;32m'
  local purple='\033[0;35m'
  local SSID="${green}{ssid}${noColor}"
  local DEVICE="${green}{device}${noColor}"
  clear
  echo "How to connect to a WiFi network using iwctl:"
  echo "============================================="
  echo -e "1. Use '${purple}device list${noColor}' to view available wireless devices."
  echo -e "2. Use '${purple}station ${DEVICE} ${purple}scan${noColor}' to scan for networks, replace ${DEVICE} with the device name from step 1."
  echo -e "3. Then, use '${purple}station ${DEVICE} ${purple}get-networks${noColor}' to list the networks."
  echo -e "4. To connect to a network, use '${purple}station ${DEVICE} ${purple}connect ${SSID}', replace ${SSID} with the desired network name."
  echo -e "5. If the network is protected, you will be prompted to enter the password."
  echo -e "6. You can check your connection status with '${purple}station ${DEVICE} ${purple}show${noColor}'."
  echo -e "7. Type '${purple}exit${noColor}' to leave iwctl when done."
  echo "============================================="
  continue_prompt
}

#===============
#OS Installation
#===============

rank_mirrors() {
  print_info "Installing pacman-contrib (for mirror ranking)"
  pacman -Sy --noconfirm --needed pacman-contrib > /dev/null

  echo ""
  print_info "Ranking download mirrors..."
  cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist_BAK
  rankmirrors -n 6 /etc/pacman.d/mirrorlist_BAK > /etc/pacman.d/mirrorlist
}

update_keyring() {
  print_info "Updating archlinux-keyring (to ensure latest trusted keys)"
  pacman -Sy --noconfirm --needed archlinux-keyring > /dev/null
}

#verify_required_packages(bootloaderEntries)
verify_required_packages()  {
  if ! verify_packages_list "system" "./setup/system-packages.txt"; then
    return 1
  fi

  case "$1" in
    gui|GUI|both|BOTH)
      if ! verify_packages_list "GUI environment" "./setup/gui-environment.txt"; then
        return 1
      fi
      ;;
  esac

  return 0
}

install_arch() {
  print_info "Installing Arch Linux..."
  pacstrap -K /mnt base linux linux-firmware
}

generate_fstab() {
  print_info "Generating fstab..."
  genfstab -U -p /mnt >> /mnt/etc/fstab
}

#switch_to_arch(bootloaderEntries)
switch_to_arch() {
  print_info "Booting into Arch Linux..."
  cp -r "$scriptDir/" "/mnt/root/ez-arch-install/"
  arch-chroot /mnt /root/ez-arch-install/$(basename "$0") "$1" #Script "re-takes" control

  exitCode=$?
  rm -rf "/mnt/root/ez-arch-install"
  return $exitCode
}

#================
#Bootloader setup
#================

#setup_bootloader(bootloaderEntries)
setup_bootloader() {
  local bootloader=$(get_bootloader)
  if [[ -z $bootloader ]]; then
    if ! install_bootloader; then
      echo ""
      print_error "Bootloader installation failed."
      print_error "Aborting..."
      echo ""
      exit 1 #Yes, abort completely...
    fi
    bootloader=$_returnValue
  else
    print_info "Found existing $bootloader bootloader..."
  fi
  setup_bootloader_entries "$bootloader" "$1"
  configure_bootloader "$bootloader" "$1"
}

get_bootloader() {
  if [[ -d /boot/grub ]] || [[ -d /boot/efi/EFI/grub ]]; then
    echo "GRUB"
  elif [[ -d /boot/loader ]] || [[ -d /boot/efi/EFI/systemd ]]; then
    echo "systemd-boot"
  elif efibootmgr -v 2>/dev/null | grep -q 'vmlinuz'; then
    echo "EFISTUB"
  else
    echo ""
  fi
}

install_bootloader() {
  if is_efi_system; then
    local mountPoint="/sys/firmware/efi/efivars/"
    print_info "Installing systemd-boot as the bootloader..."
    if ! has_mount "$mountPoint"; then
      mount -t efivarfs efivarfs "$mountPoint"
    fi
    _returnValue="systemd-boot"
    bootctl install
    return $?
  else
    local bootPartition=$(findmnt -n -o SOURCE /boot)
    local bootDrive=$(drive_from_partition "$bootPartition")
    print_info "Installing GRUB as the bootloader..."
    echo ""
    pacman -Sy --noconfirm --needed grub > /dev/null
    _returnValue="GRUB"
    grub-install "$bootDrive"
    return $?
  fi
}

#drive_from_partition(partitionPath)
drive_from_partition() {
  echo "$1" | sed 's/[0-9]*$//'
}

#setup_bootloader_entries(bootloader, bootloaderEntries)
setup_bootloader_entries() {
  local CLI_OPTIONS="systemd.unit=multi-user.target"
  local GUI_OPTIONS="systemd.unit=graphical.target splash"
  local rootPartitionUUID=$(get_root_partition_uuid)
  echo ""
  case "$2" in
    gui|GUI) add_bootloader_entry $1 $rootPartitionUUID "arch" "Arch Linux" "$GUI_OPTIONS" ;;
    cli|CLI) add_bootloader_entry $1 $rootPartitionUUID "arch" "Arch Linux" "$CLI_OPTIONS" ;;
    both|BOTH)
      add_bootloader_entry $1 $rootPartitionUUID "arch" "Arch Linux" "$GUI_OPTIONS"
      add_bootloader_entry $1 $rootPartitionUUID "arch-cli" "Arch Linux (CLI)" "$CLI_OPTIONS"
      ;;
  esac
}

get_root_partition_uuid() {
  local rootPartition=$(get_device_from_mount "/")
  get_partition_uuid $rootPartition
}

#get_device_from_mount(mountPoint)
get_device_from_mount() {
  df --output=source "$1" | tail -n 1
}

#get_partition_uuid(partitionPath)
get_partition_uuid() {
  blkid -s PARTUUID -o value "$1"
}

#add_bootloader_entry(bootloader, partitionUUID, fileName, title, options)
add_bootloader_entry() {
  case "$1" in
    GRUB)
      if [[ "$4" == "Arch Linux" ]]; then
        #Skip adding the default "Arch Linux" entry as it will be created by GRUB's OS prober.
        return
      fi
      add_grub_boot_entry "$2" "$4" "$5"
      ;;
    systemd-boot) add_systemd_boot_entry "$2" "$3" "$4" "$5" ;;
  esac
  print_success "Added '$4' bootloader entry"
}

#add_grub_boot_entry(partitionUUID, title, options)
add_grub_boot_entry() {
  local GRUB_CUSTOM_FILEPATH="/etc/grub.d/11_custom"

  # Ensure the file exists and is executable
  if [[ ! -x "$GRUB_CUSTOM_FILEPATH" ]]; then
    print_info "Setting up custom GRUB config file..."
    (
      #NOTE: "STDIN" here is what is known as a "Heredoc". More info here: https://tldp.org/LDP/abs/html/here-docs.html
      cat <<STDIN
#!/bin/sh

exec tail -n +3 \$0

# This file provides an easy way to add custom menu entries. Simply type the
# menu entries you want to add after this comment. Be careful not to change
# the 'exec tail' line above.

STDIN
    ) > "$GRUB_CUSTOM_FILEPATH"
    chmod +x "$GRUB_CUSTOM_FILEPATH"
  fi

  local tempFile=$(mktemp)
  (
    #NOTE: "STDIN" here is what is known as a "Heredoc". More info here: https://tldp.org/LDP/abs/html/here-docs.html
    cat <<STDIN

menuentry "$2" {
    search --no-floppy --fs-uuid --set=root $(get_bootfs_uuid)
    linux /vmlinuz-linux root=PARTUUID=$1 rw $3
    initrd /initramfs-linux.img
}

STDIN
  ) > "$tempFile"

  if [[ ! -s "$tempFile" ]]; then
    print_error "Failed to create GRUB entry. Your current boot setup remains unchanged."
    print_error "Aborting..."
    rm "$tempFile"
    echo ""
    exit 1 #Yes, abort completely...
  fi

  cat "$tempFile" >> $GRUB_CUSTOM_FILEPATH
  rm "$tempFile"
}

get_bootfs_uuid() {
  local bootPartition=$(get_device_from_mount "/boot")
  get_filesystem_uuid $bootPartition
}

#get_filesystem_uuid(partitionPath)
get_filesystem_uuid() {
  blkid -s UUID -o value "$1"
}

#add_systemd_boot_entry(partitionUUID, fileName, title, options)
add_systemd_boot_entry() {
  (
    #NOTE: "STDIN" here is what is known as a "Heredoc". More info here: https://tldp.org/LDP/abs/html/here-docs.html
    cat <<STDIN
title   $3
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options root=PARTUUID=$1 rw $4
STDIN
  ) > /boot/loader/entries/$2.conf
}

#configure_bootloader(bootloader, bootloaderEntries)
configure_bootloader() {
  case "$1" in
    GRUB)
      echo ""
      print_info "Running 'grub-mkconfig'..."
      echo ""
      grub-mkconfig -o /boot/grub/grub.cfg
      ;;
    systemd-boot)
      local totalEntries=$(count_files "/boot/loader/entries" "*.conf")
      if (( totalEntries > 1 )); then
        configure_systemd_boot
      fi
      ;;
  esac
}

configure_systemd_boot() {
  local configFile="/boot/loader/loader.conf"
  echo ""
  print_info "Configuring systemd-boot..."
  echo ""

  #Check if "timeout" is commented out or not present
  if grep -q "^#timeout [0-9]" "$configFile"; then
    #Remove "timeout" comment
    sed -i '/^#timeout [0-9]/d' "$configFile"
    echo "timeout 5" >> "$configFile"
  fi

  # Ensure that "#console-mode keep" is at the bottom
  if grep -q "#console-mode keep" "$configFile"; then
    #Remove "console-mode" comment
    sed -i '/#console-mode keep/d' "$configFile"
    echo "#console-mode keep" >> "$configFile"
  fi
}

#===========
#Final setup
#===========

enable_services() {
  local service
  print_info "Enabling system services..."
  echo ""
  tr -d '\r' < ./setup/systemd-services.txt \
  | while read -r service; do
    try_enable_service "$service"
  done
}

#try_enable_service(serviceName)
try_enable_service() {
  if systemctl --quiet is-enabled "$1"; then
    echo "The '$1' service is already enabled."
    return 0
  fi

  if systemctl enable "$1" &> /dev/null; then
    print_success "Successfully enabled the '$1' service."
    return 0
  fi
  print_error "Failed to enable the '$1' service."
  return 1
}

set_root_password() {
  local passwordSet
  echo "Please enter a new password for the root user:"
  echo ""
  while [[ -z $passwordSet ]]; do
    if ! password_prompt; then
      print_error "Password cannot be empty."
      echo ""
      continue
    fi

    if ! change_password "root" "$_returnValue"; then
      print_error "Failed to set the root password. Please try again."
      echo ""
      continue
    fi

    print_success "The root password has been set successfully."
    passwordSet=true
  done
}

#=============
#Install start
#=============

if [[ -z $bootloaderEntries ]]; then
  clear
  if ! check_required_mounts; then
    continue_prompt
    return
  fi

  if has_linux_installation "/mnt"; then
    print_warning "Linux installation detected at the target location!"
    echo "A reformat of the partition is required."
    echo ""
    if ! yesno_prompt "Would you like to proceed with the reformat? [y/N]: " "N" || \
       ! yesno_prompt "This action is IRREVERSIBLE. Are you ABSOLUTELY sure? [y/N]: " "N"; then
      return
    fi

    if ! reformat_and_remount_partitions; then
      return
    fi
  fi

  bootloader_entries_prompt
  bootloaderEntries=$_returnValue

  echo ""
  start_dhcp
  if ! internet_test; then
    setup_network
  fi
  print_success "Internet connectivity established!"

  echo ""
  rank_mirrors

  echo ""
  update_keyring

  echo ""
  if ! verify_required_packages $bootloaderEntries; then
    continue_prompt
    return
  fi

  echo ""
  install_arch

  echo ""
  generate_fstab
  switch_to_arch $bootloaderEntries
  if [[ $? == 101 ]]; then
    reboot_system
  fi
  exit 0
fi

echo ""
setup_bootloader $bootloaderEntries

echo ""
install_packages_list "system" "./setup/system-packages.txt" 1

case "$bootloaderEntries" in
  gui|GUI|both|BOTH) install_packages_list "GUI environment" "./setup/gui-environment.txt" 1 ;;
esac

if has_wireless_adapter && ! has_command iwctl; then
  echo ""
  if yesno_prompt "Would you like to install 'iwd' for Wi-Fi management? [Y/n]: "; then
    pacman -S iwd --noconfirm
    systemctl enable iwd
  fi
fi

echo ""
enable_services

echo ""
set_root_password

echo ""
print_success "Installation tasks completed!"
continue_prompt
