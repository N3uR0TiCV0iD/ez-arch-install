#!/bin/bash

#archlinux_environment_check(activityName)
archlinux_environment_check() {
  if ! is_running_archlinux; then
    print_error "ERROR: Cannot proceed with $1 - Must be running Arch Linux."
    continue_prompt
    return 1
  fi

  if in_live_iso && ! has_chrooted; then
    print_error "ERROR: Cannot proceed with $1 - Currently in Live ISO environment."
    continue_prompt
    return 1
  fi
  return 0
}

is_running_archlinux() {
  if grep -q 'ID=arch' /etc/os-release; then
    return 0
  fi
  return 1
}

in_live_iso() {
  if [[ -d /run/archiso/bootmnt ]] || grep -q "archiso" /proc/cmdline; then
    return 0
  fi
  return 1
}

#mount_install_partitions(rootPartition, bootPartition, homePartition)
mount_install_partitions() {
  local bootMountOptions=""
  if is_efi_system; then
    bootMountOptions="uid=0,gid=0,fmask=0077,dmask=0077"
  fi
  try_mount "$1" "/mnt" || return 1
  try_mount "$2" "/mnt/boot" "$bootMountOptions" || return 1
  try_mount "$3" "/mnt/home" || return 1
}

#install_packages_list(title, filePath, skipPackageCheck=0)
install_packages_list() {
  local packages
  if ! packages=$(tr -d '\r' < "$2" | tr '\n' ' '); then
    print_error "Failed to read package list from '$2'."
    return 1
  fi

  update_pacman_ifneeded
  if [[ $? -eq 2 ]]; then
    return 2
  fi

  if [[ -z $3 ]]; then
    if ! verify_packages_list "$1" "$2"; then
      return 3
    fi
  fi

  print_info "Installing $1 packages..."
  if ! pacman -Su --noconfirm --needed $packages; then
    print_error "Failed to install packages."
    return 4
  fi

  if [[ -z $3 ]]; then
    echo ""
    print_success "Successfully installed $1 packages!"
    continue_prompt
  fi
}

#verify_packages_list(title, filePath)
verify_packages_list() {
  local packages
  if ! packages=$(tr -d '\r' < "$2" | tr '\n' ' '); then
    print_error "Failed to read package list from '$2'."
    return 1
  fi

  update_pacman_ifneeded
  if [[ $? -eq 2 ]]; then
    return 2
  fi

  print_info "Validating $1 packages..."
  local hasError package
  for package in $packages; do
    if ! package_exists "$package"; then
      if [[ -z $hasError ]]; then
        echo ""
      fi
      print_error "Package '$package' is not available."
      hasError=true
    fi
  done

  if [[ $hasError ]]; then
    return 3
  fi
  return 0
}

#update_pacman_ifneeded(threshold=3600)
update_pacman_ifneeded() {
  local lastSyncTime
  if ! lastSyncTime=$(stat -c %Y /var/lib/pacman/sync/* 2>/dev/null | sort -n | tail -1); then
    print_error "Error accessing pacman database."
    echo ""
    return 2
  fi

  local threshold="${1:-3600}"
  local currentTime=$(date +%s)
  local timeDiff=$(( currentTime - lastSyncTime ))
  if (( timeDiff > threshold )); then
    print_info "Refreshing pacman database..."
    echo ""
    pacman -Sy
    touch "/var/lib/pacman/sync/core.db" #Ensure the timestamp changes, in case "pacman -Sy" doesn't change it.
    echo ""
    return 0
  fi
  return 1
}

#package_exists(packageName)
package_exists() {
  if pacman -Si "$1" &> /dev/null || pacman -Sg "$1" &> /dev/null; then
    return 0
  fi
  return 1
}

#install_package_prompt(packageName, promptText="...")
install_package_prompt() {
  $promptText=$2
  if [[ -z $promptText ]]; then
    promptText="The '$1' package is not installed. Would you like to install it now? [Y/n]: "
  fi

  if ! yesno_prompt "$promptText"; then
    return 1
  fi

  pacman -Sy --noconfirm "$1"
  if [[ $? -ne 0 ]]; then
    return 1
  fi
  return 0
}
