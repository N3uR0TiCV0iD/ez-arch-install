#!/bin/bash

is_efi_system() {
  if [[ -d /sys/firmware/efi ]]; then
    return 0
  fi
  return 1
}

has_chrooted() {
  if [[ "$(stat -c %i /)" != "$(stat -c %i /proc/1/root/.)" ]]; then
    #Has changed root
    return 0
  fi
  return 1
}

#change_password(user, password)
change_password() {
  if ! echo "$1:$2" | chpasswd; then
    return 1
  fi
  return 0
}

#has_mount(mountPoint)
has_mount() {
  if mountpoint -q "$1"; then
    return 0
  fi
  return 1
}

#try_mount(partitionPath, mountPoint, [mountOptions])
try_mount() {
  echo "Mounting '$1' as '$2'..."
  if ! mkdir -p "$2"; then
    print_error "Failed to create directory: $2"
    echo ""
    return 1
  fi

  local -a command=("mount")
  if [[ $3 ]]; then
    command+=("-o" "$3")
  fi

  command+=("$1" "$2")
  if ! "${command[@]}"; then
    print_error "Failed to mount '$1' as '$2'"
    echo ""
    return 1
  fi
  return 0
}

#try_unmount(mountPoint)
try_unmount() {
  echo "Unmounting: $1"
  if ! umount "$1"; then
    print_error "Failed to unmount: $1"
    echo ""
    return 1
  fi
  return 0
}
