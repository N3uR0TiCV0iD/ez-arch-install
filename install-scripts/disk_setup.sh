#!/bin/bash

show_menu() {
  local exited
  while [[ -z $exited ]]; do
    clear
    echo "Disk management"
    echo "---------------------"
    echo "1) Manage partitions"
    echo "2) Format partitions"
    echo "3) Mount partitions"
    echo "0) Exit to main menu"
    echo "---------------------"
    read_key
    case "$_returnValue" in
      1) manage_partitions ;;
      2) partition_formatting ;;
      3)
        if partition_mounting; then
          exited=true #Also exit, we can assume the user is done :)
        fi
        ;;
      0) exited=true ;;
      *) play_beep ;;
    esac
  done
}

#=================
#Manage partitions
#=================

manage_partitions() {
  clear
  select_disk
  if [[ -n "$_returnValue" ]]; then
    if is_efi_system; then
      show_gpt_partition_help
      cgdisk /dev/$_returnValue
    else
      show_mbr_partition_help
      cfdisk /dev/$_returnValue
    fi
  fi
}

select_disk() {
  #Exclude devices with major number 7 (loop devices)
  lsblk -e7 -o NAME,PARTLABEL,RM,SIZE,TYPE,RO,FSTYPE,LABEL,MOUNTPOINT
  while true; do
    echo ""
    read -rp "Enter the disk to manage or leave empty to exit: " _returnValue
    if [[ -z $_returnValue ]]; then
      return 1
    fi
    
    if is_valid_disk "$_returnValue"; then
      return 0
    fi

    print_error "Invalid selection or disk is mounted. Please try again."
  done
}

#is_valid_disk(disk)
is_valid_disk() {
  if [[ ! -b "/dev/$1" ]]; then
    return 1
  fi

  #"head -n 1" to retrieve only the disk's info, excluding its partitions
  local diskType mountPoint
  read -r diskType mountPoint < <(lsblk -no TYPE,MOUNTPOINT "/dev/$1" | head -n 1)
  if [[ "$diskType" != "disk" || $mountPoint ]]; then
    return 1
  fi

  return 0
}

show_gpt_partition_help() {
  local RESET='\033[0m'
  local BOLD='\033[1m'
  local CYAN='\033[0;36m'
  local WHITE='\033[1;37m'
  local MAGENTA='\033[0;35m'
  local ramGBSize=$(awk '/MemTotal/ { printf "%.0f", $2 / 1024 / 1024 + 0.5 }' /proc/meminfo)
  clear
  echo "Partition recommendations:"
  echo "=========================="
  echo -e "${MAGENTA}boot|efi${RESET}: 512 MiB - 1 GiB"
  echo -e "${CYAN}swap${RESET}: $ramGBSize GiB (Based on your RAM)"
  echo -e "${WHITE}root|system${RESET}: 16 GiB - 64 GiB"
  echo -e "${WHITE}home${RESET}: Remainder of the disk"
  echo ""
  echo "Partition type codes:"
  echo "--------------------------"
  echo -e "[${MAGENTA}EF00${RESET}] EFI System"
  echo -e "[${CYAN}8200${RESET}] Linux swap"
  echo -e "[${WHITE}8300${RESET}] Linux filesystem"
  echo "=========================="
  continue_prompt
}

show_mbr_partition_help() {
  local RESET='\033[0m'
  local BOLD='\033[1m'
  local CYAN='\033[0;36m'
  local WHITE='\033[1;37m'
  local ramGBSize=$(awk '/MemTotal/ { printf "%.0f", $2 / 1024 / 1024 + 0.5 }' /proc/meminfo)
  clear
  echo "Partition recommendations:"
  echo "=========================="
  echo -e "${WHITE}boot${RESET}: 256 MiB - 512 MiB"
  echo -e "${CYAN}swap${RESET}: $ramGBSize GiB (Based on your RAM)"
  echo -e "${WHITE}root|system${RESET}: 16 GiB - 64 GiB"
  echo -e "${WHITE}home${RESET}: Remainder of the disk"
  echo ""
  echo "Partition type codes:"
  echo "--------------------------"
  echo -e "[${CYAN}82${RESET}] Linux swap"
  echo -e "[${WHITE}83${RESET}] Linux filesystem"
  echo "=========================="
  echo ""
  echo -e "${BOLD}IMPORTANT: Non-UEFI BIOS detected. Please choose the 'dos' label type!${RESET}"
  continue_prompt
}

#=================
#Format partitions
#=================

partition_formatting() {
  local -A partitionReformats
  suggest_partition_formatting partitionReformats
  while true; do
    show_formatting_partitions partitionReformats
    echo ""
    echo "[a]djust, [f]ormat, [q]uit"
    read_key
    case "$_returnValue" in
      a) adjust_partition_format partitionReformats ;;
      f)
        echo ""
        if yesno_prompt "Are you sure you want to apply these formatting changes? [Y/n]: "; then
          reformat_partitions partitionReformats
          return 0
        fi
        ;;
      q) return 1 ;;
      *) play_beep ;;
    esac
  done
}

#Suggests partition reformatting based on their label
#suggest_partition_formatting(*suggestedFormats)
suggest_partition_formatting() {
  local -a partitions
  local -n suggestedFormats=$1
  readarray -t partitions < <(lsblk -rno NAME,PARTLABEL,FSTYPE,TYPE | awk '
    {
      currCharIndex = 1
      for (columnIndex = 1; columnIndex <= NF; columnIndex++) {
        probeChar = substr($0, currCharIndex, 1)
        gsub(/ /, "", probeChar) #Remove spaces
        while (length(probeChar) == 0) {
          printf(" ;")
          currCharIndex++
          probeChar = substr($0, currCharIndex, 1)
          gsub(/ /, "", probeChar) #Remove spaces
        }

        printf("%s;", $columnIndex)
        currCharIndex += length($columnIndex) + 1
      }
      printf("\n")
    }
  ')

  local partitionInfo partition label fsType blockType
  for partitionInfo in "${partitions[@]}"; do
    #Temporarily sets the IFS (internal field separator) & splits "partitionInfo"
    IFS=';' read -r partition label fsType blockType <<< "$partitionInfo"
    if [[ "$blockType" != "part" ]]; then
      continue
    fi

    if [[ -z "${fsType// /}" ]]; then
      #Partition has no filesystem, apply a suggested filesystem
      suggestedFormats["$partition"]=$(fstype_from_label "$label")
    else
      #Partition already has a filesystem, suggest no action
      suggestedFormats["$partition"]=""
    fi
  done
}

#fstype_from_label(label)
fstype_from_label() {
  case "$1" in
    efi|boot) echo "vfat" ;;
    swap) echo "swap" ;;
    *) echo "ext4" ;;
  esac
}

#show_formatting_partitions(*partitionReformats)
show_formatting_partitions() {
  clear
  build_dictionary_string $1
  lsblk -e7 -i -o NAME,PARTLABEL,RM,SIZE,TYPE,RO,FSTYPE,LABEL,MOUNTPOINT | awk -v dictionaryStr="$_returnValue" '
    BEGIN {
      totalPairs = split(dictionaryStr, keyValuePairs, "¬")
      for (pairIndex = 1; pairIndex <= totalPairs; pairIndex++) {
        keyValue = keyValuePairs[pairIndex]
        substringStart = index(keyValue, "=")
        key = substr(keyValue, 1, substringStart - 1)
        value = substr(keyValue, substringStart + 1)
        partitionReformats[key] = value
      }
    }
    {
      if (NR == 1) {
        #Prints all columns & keeps track of string positions
        printf("%s;", $1)
        totalColumns = NF
        columnStarts[1] = 1
        columnMinSize[1] = length($1)
        for (columnIndex = 2; columnIndex <= NF; columnIndex++) {
          match($0, " "$columnIndex)
          columnStarts[columnIndex] = RSTART + 1 #Add 1 since "match" returns 0-based index
          columnMinSize[columnIndex] = length($columnIndex)

          printf("%s;", $columnIndex)
        }
        printf("NEW_FSTYPE\n")
      } else {
        missingColumns = 0
        for (columnIndex = 1; columnIndex <= totalColumns; columnIndex++) {
          columnProbe = substr($0, columnStarts[columnIndex], columnMinSize[columnIndex])
          gsub(/ /, "", columnProbe) #Remove spaces
          if (length(columnProbe) == 0) {
            printf(";")
            missingColumns++
          } else {
            printf("%s;", $(columnIndex - missingColumns))
          }
        }
        device = $1
        gsub(/^[-|`]+/, "", device)
        printf("%s\n", partitionReformats[device])
      }
    }
  ' | column -t -s ';'
}

#adjust_partition_format(*partitionReformats)
adjust_partition_format() {
  local -a validPartitions
  local -n _partitionReformats=$1
  readarray -t validPartitions < <(lsblk -rno NAME,TYPE | awk '$2 == "part" { print $1 }')

  local partitionName
  while true; do
    echo ""
    read -rp "Enter the partition to adjust or leave empty to exit: " partitionName
    if [[ -z "$partitionName" ]]; then
      return 1
    fi

    #NOTE: The extra spaces in the string ensure "sda1" matches only "sda1" and not "sda10"
    if ! [[ " ${validPartitions[*]} " =~ " $partitionName " ]]; then
      print_error "Invalid partition name. Please try again."
      continue
    fi

    local fsType
    while true; do
      read -rp "Filesystem type (vfat, swap, ext4) or empty to remove: " fsType
      if [[ -z $fsType ]] || is_valid_fs "$fsType"; then
        _partitionReformats["$partitionName"]=$fsType
        return 0
      fi
      print_error "Invalid filesystem type. Please try again."
      echo ""
    done
  done
}

#is_valid_fs(fsType)
is_valid_fs() {
  case "$1" in
    vfat|swap|ext4) return 0 ;;
    *) return 1 ;;
  esac
}

#reformat_partitions(*partitionReformats)
reformat_partitions() {
  local partition
  local -n _partitionReformats=$1
  echo ""
  for partition in "${!_partitionReformats[@]}"; do
    local fsType=${_partitionReformats[$partition]}
    if [[ -n "$fsType" ]]; then
      format_partition "/dev/$partition" $fsType
    fi
  done
  continue_prompt
}

#format_partition(partitionPath, fsType) {
format_partition() {
  echo "Formatting $1 as $2..."
  case "$2" in
    vfat) mkfs.fat -F32 "$1" &> /dev/null ;;
    swap) mkswap "$1" &> /dev/null ;;
    ext4) mkfs.ext4 "$1" &> /dev/null ;;
  esac
}

#================
#Mount partitions
#================

partition_mounting() {
  local -A partitionMounts
  suggest_partition_mounts partitionMounts
  while true; do
    show_mounting_partitions partitionMounts
    echo ""
    echo "[a]djust, [m]ount, [q]uit"
    read_key
    case "$_returnValue" in
      a) adjust_partition_mount partitionMounts ;;
      m)
        echo ""
        if ! are_mounts_set partitionMounts; then
          continue_prompt
          continue
        fi

        if yesno_prompt "Are you sure you want to apply these mounting changes? [Y/n]: "; then
          if ! mount_partitions partitionMounts; then
            continue_prompt
            return 1
          fi
          continue_prompt
          return 0
        fi
        ;;
      q) return 2 ;;
      *) play_beep ;;
    esac
  done
}

#Suggests partition mounts based on their label
#suggest_partition_mounts(*suggestedMounts)
suggest_partition_mounts() {
  local -a partitions
  local -n suggestedMounts=$1
  readarray -t partitions < <(lsblk -rno NAME,PARTLABEL,FSTYPE,TYPE | awk '
    {
      currCharIndex = 1
      for (columnIndex = 1; columnIndex <= NF; columnIndex++) {
        probeChar = substr($0, currCharIndex, 1)
        gsub(/ /, "", probeChar) #Remove spaces
        while (length(probeChar) == 0) {
          printf(" ;")
          currCharIndex++
          probeChar = substr($0, currCharIndex, 1)
          gsub(/ /, "", probeChar) #Remove spaces
        }

        printf("%s;", $columnIndex)
        currCharIndex += length($columnIndex) + 1
      }
      printf("\n")
    }
  ')

  local partitionInfo partition label fsType blockType
  for partitionInfo in "${partitions[@]}"; do
    #Temporarily sets the IFS (internal field separator) & splits "partitionInfo"
    IFS=';' read -r partition label fsType blockType <<< "$partitionInfo"
    if [[ "$blockType" != "part" ]]; then
      continue
    fi

    if [[ "$fsType" == "swap" ]]; then
      suggestedMounts["swap"]=$partition
      continue
    fi

    case "$label" in
      boot|efi)
        if [[ "$fsType" == "vfat" ]]; then
          suggestedMounts["boot"]=$partition
        fi
        ;;
      root|system)
        if is_linux_filesystem "$fsType"; then
          suggestedMounts["root"]=$partition
        fi
        ;;
      home)
        if is_linux_filesystem "$fsType"; then
          suggestedMounts["home"]=$partition
        fi
        ;;
    esac
  done
}

#is_linux_filesystem(fsType)
is_linux_filesystem() {
  case "$1" in
    ext4|btrfs|f2fs|xfs) return 0 ;;
    *) return 1 ;;
  esac
}

#show_mounting_partitions(*partitionMounts)
show_mounting_partitions() {
  clear
  lsblk -e7 -o NAME,PARTLABEL,RM,SIZE,TYPE,RO,FSTYPE,LABEL,MOUNTPOINT
  echo ""
  print_partition_mount $1 root /mnt
  print_partition_mount $1 boot /mnt/boot
  print_partition_mount $1 home /mnt/home
  print_partition_mount $1 swap "[SWAP]"
}

#print_partition_mount(*partitionMounts, mountType, mountTarget)
print_partition_mount() {
  local -n _partitionMounts=$1
  local partitionName=${_partitionMounts[$2]}
  if [[ -n "$partitionName" ]]; then
    echo "[$2] /dev/$partitionName will be mounted as $3"
  else
    echo "[$2] No partition set"
  fi
}

#are_mounts_set(*partitionMounts)
are_mounts_set() {
  local hasMissing
  local -n _partitionMounts=$1
  for mountType in "boot" "root" "home" "swap"; do
    if [[ -z "${_partitionMounts[$mountType]}" ]]; then
      print_error "Mount type '$mountType' is not set."
      hasMissing=true
    fi
  done
  if [[ $hasMissing ]]; then
    return 1
  fi
  return 0
}

#adjust_partition_mount(*partitionMounts)
adjust_partition_mount() {
  local -A partitions
  local -n _partitionMounts=$1

  local partitionName fsType
  while read -r partitionName fsType; do
    partitions["$partitionName"]="$fsType"
  done < <(lsblk -rno NAME,TYPE,FSTYPE | awk '$2 == "part" { print $1 " " $3 }')

  while true; do
    echo ""
    read -rp "Enter the partition to adjust or leave empty to exit: " partitionName
    if [[ -z "$partitionName" ]]; then
      return 1
    fi

    fsType="${partitions["$partitionName"]}"
    if [[ -z "$fsType" ]]; then
      print_error "Invalid partition name. Please try again."
      continue
    fi

    case "$fsType" in
      vfat)
        _partitionMounts["boot"]=$partitionName
        return 0
        ;;
      swap)
        _partitionMounts["swap"]=$partitionName
        return 0
        ;;
    esac

    local mountType
    while true; do
      read -rp "Enter the new mount type (boot|root|home): " mountType
      case "$mountType" in
        boot|root|home)
          local oldMountType=$(find_partition_mount "$partitionName" $1)
          if [[ $oldMountType ]]; then
            _partitionMounts["$oldMountType"]=""
          fi
          _partitionMounts["$mountType"]=$partitionName
          return 0
          ;;
        *)
          print_error "Invalid mount type. Please try again."
          echo ""
          ;;
      esac
    done
  done
}

#find_partition_mount(partitionName, *partitionMounts)
find_partition_mount() {
  local -n _partitionMounts=$2
  for mountType in "boot" "root" "home" "swap"; do
    if [[ "${_partitionMounts[$mountType]}" == "$1" ]]; then
      echo "$mountType"
      return 0
    fi
  done
  echo ""
  return 1
}

#mount_partitions(*partitionMounts)
mount_partitions() {
  local -n _partitionMounts=$1
  if has_mount "/mnt"; then
    echo ""
  fi
  safe_unmount "/mnt/home" || return 1
  safe_unmount "/mnt/boot" || return 1
  safe_unmount "/mnt" || return 1
  echo ""

  mount_install_partitions "/dev/${_partitionMounts["root"]}" \
                           "/dev/${_partitionMounts["boot"]}" \
                           "/dev/${_partitionMounts["home"]}"
  enable_swap "/dev/${_partitionMounts["swap"]}" || return 1
  return 0
}

#safe_unmount(mountPoint)
safe_unmount() {
  if ! has_mount "$1"; then
    return 0
  elif ! try_unmount "$1"; then
    return 1
  fi
  return 0
}

#enable_swap(partitionPath)
enable_swap() {
  echo "Enabling swap on '$1'"
  swapon "$1" > /dev/null || return 1
  return 0
}

#=========
#Show menu
#=========

show_menu
