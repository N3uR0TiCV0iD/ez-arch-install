#!/bin/bash

if [[ "$EUID" -ne 0 ]]; then
  echo "Root privileges required. Please rerun this script as root."
  exit 1
fi

scriptDir=$(dirname "$(readlink -f "$0")")

cd "$scriptDir"
source "./utils/utils.sh"
source "./utils/system_utils.sh"
source "./utils/installer_utils.sh"

if has_chrooted && [[ $1 ]]; then
  bootloaderEntries=$1
  source "./install-scripts/install_arch.sh"
fi

show_menu() {
  local exited
  while [[ -z $exited ]]; do
    clear
    echo "Arch Linux Installation Wizard"
    echo "-------------------------------"
    echo "1) Disk setup"
    echo "2) Install Arch Linux"
    echo "3) Configure system"
    echo "4) User management"
    echo "5) Post install tasks"
    echo "6) Reboot system"
    echo "0) Exit"
    echo "-------------------------------"
    read_key
    case "$_returnValue" in
      1) source "./install-scripts/disk_setup.sh" ;;
      2)
        bootloaderEntries=""
        source "./install-scripts/install_arch.sh"
        ;;
      3) source "./install-scripts/config_system.sh" ;;
      4) source "./install-scripts/user_management.sh" ;;
      5) source "./install-scripts/post_install.sh" ;;
      6)
         if has_chrooted; then
          # We are in a chroot context, delegate it to the caller (see "install_arch.sh")
          exit 101
         fi
         reboot_system
         ;;
      0) exited=true ;;
      *) play_beep ;;
    esac
  done
}

reboot_system() {
  print_info "Rebooting system..."
  umount -R /mnt
  reboot
}

show_menu
