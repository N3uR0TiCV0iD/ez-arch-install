#!/bin/bash

show_menu() {
  local exited
  while [[ -z $exited ]]; do
    clear
    echo "System configuration"
    echo "--------------------"
    echo "1) Set Locale"
    echo "2) Set Timezone"
    echo "3) Set Keyboard"
    echo "4) Set Hostname"
    echo "5) Toggle Multilib Repository"
    echo "0) Exit"
    echo "--------------------"
    read_key
    case "$_returnValue" in
      1) set_locale ;;
      2) set_timezone ;;
      3) set_keyboard ;;
      4) set_hostname ;;
      5) toggle_multilib ;;
      0) exited=true ;;
      *) play_beep ;;
    esac
  done
}

#======
#Locale
#======

set_locale() {
  while true; do
    echo ""
    if ! locale_prompt; then
      return 2
    fi

    local locale="$_returnValue.UTF-8"
    if ! is_valid_locale "$locale"; then
      echo ""
      print_error "The '$locale' locale is not available."
      continue
    fi

    echo ""
    echo "Updating locale file..."
    if ! update_locale_file "$locale"; then
      print_error "Failed to update '/etc/locale.gen'."
      sleep 2
      return 1
    fi

    if ! locale-gen; then
      echo ""
      print_error "Failed to generate the locale configuration with 'locale-gen'."
      sleep 2
      return 1
    fi
    echo "LANG=$locale" > /etc/locale.conf
    export LANG=$locale

    echo ""
    print_success "Locale succesfully set to '$locale'!"
    sleep 2
    return 0
  done
}

locale_prompt() {
  local language
  echo "Enter your language (e.g., 'en' for English)"
  read -p "Choice (empty to cancel): " language
  if [[ -z $language ]]; then
    _returnValue=""
    return 1
  fi

  local country
  echo ""
  echo "Enter your country code (e.g., 'GB' for Great Britain)"
  read -p "Choice: " country
  _returnValue="${language}_${country}"
}

#is_valid_locale(locale)
is_valid_locale() {
  if grep -q "^#*$1" /etc/locale.gen; then
    return 0
  fi
  return 1
}

#update_locale_file(locale)
update_locale_file() {
  cp /etc/locale.gen /etc/locale_BAK.gen

  # Comment out all locales
  sed -i 's/^[^#]/#&/' /etc/locale_BAK.gen

  # Uncomment the specified locale
  sed -i "/#.*\b$1\b/s/^#//" /etc/locale_BAK.gen

  if ! cp /etc/locale_BAK.gen /etc/locale.gen; then
    return 1
  fi
  rm "/etc/locale_BAK.gen"
  return 0
}

#========
#Timezone
#========

set_timezone() {
  if ! timezone_prompt; then
    return 1
  fi

  ln -sf "/usr/share/zoneinfo/$_returnValue" /etc/localtime
  echo "$_returnValue" > /etc/timezone
  hwclock --systohc
  echo ""
  print_success "Timezone has been set to $_returnValue."
  sleep 2
  return 0
}

timezone_prompt() {
  while true; do
    if ! region_prompt; then
      return 1
    fi

    local region=$_returnValue
    echo ""
    if ! city_prompt "$region"; then
      clear
      continue
    fi
    _returnValue="$region/$_returnValue"
    return 0
  done
}

region_prompt() {
  local excludedDirs='right|Etc|posix|SystemV'
  local options=($(get_directories "/usr/share/zoneinfo/" | grep -vE "$excludedDirs" | sort))
  echo ""
  echo "Available regions:"
  if ! custom_select "Select your timezone region (empty to cancel): " options 5; then
    return 1
  fi
  return 0
}

#city_prompt(region)
city_prompt() {
  local options=($(ls /usr/share/zoneinfo/"$1"))
  echo ""
  echo "Available cities/areas:"
  if ! custom_select "Select your city (empty to return): " options; then
    return 1
  fi
  return 0
}

#========
#Keyboard
#========

set_keyboard() {
  if ! keyboard_prompt; then
    return 2
  fi

  echo ""
  if ! loadkeys "$_returnValue"; then
    echo ""
    print_error "Failed to set keyboard layout..."
    sleep 2
    return 1
  fi
  echo "KEYMAP=$_returnValue" > /etc/vconsole.conf
  export KEYMAP=$_returnValue

  if has_command "setxkbmap" && ! update_x11_keyboard_file "$_returnValue"; then
    echo ""
    print_error "Failed to update the X11 locale configuration."
    sleep 2
    return 1
  fi

  print_success "Keyboard layout has been set to '$_returnValue'."
  sleep 2
  return 0
}

keyboard_prompt() {
  local excludedLayouts=(
    "3l" "pc110"
    "ANSI" "unicode"
    "applkey" "backspace" "ctrl" "keypad" "windowkeys"
    "bashkir" "kazakh" "kyrgyz"
    "koy" "mod" "tralt" "wangbe"
    "ttwin_" "ky_alt_sh"
  )
  local excludedLayoutsRegex=$(printf "%s*|" "${excludedLayouts[@]}")
  excludedLayoutsRegex="${excludedLayoutsRegex%|}" #Remove trailing '|'

  local -A layoutGroups
  local keyboardLayouts=($(get_keyboards | grep -vE "$excludedLayoutsRegex"))
  create_group_dictionary keyboardLayouts layoutGroups "-"

  local sortedKeys=($(printf "%s\n" "${!layoutGroups[@]}" | sort))
  while true; do
    echo ""
    echo "Available keyboard groups:"
    if ! custom_select "Select your keyboard group (empty to cancel): " sortedKeys 5; then
      return 1
    fi

    local keyboardGroup=$_returnValue
    echo ""
    echo "Available keyboard layouts:"

    local options
    IFS='¬' read -ra options <<< "${layoutGroups[$keyboardGroup]}"
    if ! custom_select "Select your keyboard layout (empty to return): " options 5; then
      clear
      continue
    fi

    return 0
  done
}

get_keyboards() {
  if ! in_live_iso; then
    localectl list-keymaps
  else
    find /usr/share/kbd/keymaps/ -type f -name "*.map.gz" -exec basename {} .map.gz \; | sort
  fi
}

#update_x11_keyboard_file(layout)
update_x11_keyboard_file() {
  local x11KeyboardFile="/etc/X11/xorg.conf.d/00-keyboard.conf"
  if [[ -f "$x11KeyboardFile" ]]; then
    sed -i "s/Option \"XkbLayout\" \".*\"/Option \"XkbLayout\" \"$1\"/" "$x11KeyboardFile"
  else
      (
      #NOTE: "STDIN" here is what is known as a "Heredoc". More info here: https://tldp.org/LDP/abs/html/here-docs.html
      cat <<STDIN
Section "InputClass"
    Identifier "system-keyboard"
    MatchIsKeyboard "on"
    Option "XkbLayout" "$1"
EndSection

STDIN
    ) > "$x11KeyboardFile"
  fi
  return $?
}

#========
#Hostname
#========

set_hostname() {
  if ! hostname_prompt; then
    return 2
  fi

  echo ""
  apply_hostname "$_returnValue"
  return $?
}

hostname_prompt() {
  while true; do
    read -rp "Enter hostname (empty to cancel): " _returnValue
    if [[ -z $_returnValue ]]; then
      return 1
    fi

    if ! is_valid_hostname $_returnValue; then
      print_error "Invalid hostname. Use up to 253 alphanum characters. No starting OR ending hyphens."
      echo ""
      continue
    fi

    return 0
  done
}

#is_valid_hostname(hostname)
is_valid_hostname() {
  local hostnameLength=${#1}
  if (( hostnameLength > 253 )); then
    return 1
  fi

  #NOTE: Hyphen placement (before [A-Za-z0-9]) ensures labels cannot end with a hyphen.
  local labelRegex="[A-Za-z0-9]+(-[A-Za-z0-9]+)*"
  local hostnameRegex="^$labelRegex(\.$labelRegex)*$"
  if ! [[ $1 =~ $hostnameRegex ]]; then
    return 1
  fi
  return 0
}

#apply_hostname(hostname)
apply_hostname() {
  if in_live_iso; then
    echo "$1" > /etc/hostname
  elif ! hostnamectl set-hostname "$1"; then
    echo ""
    print_error "Failed to set hostname..."
    sleep 2
    return 1
  fi
  print_success "Hostname has been set to '$1'."
  sleep 2
  return 0
}

#=============
#Miscellaneous
#=============

toggle_multilib() {
  local tempFile=$(mktemp)

  if ! cp "/etc/pacman.conf" "$tempFile"; then
    print_error "Failed to copy '/etc/pacman.conf'."
    sleep 2
    return 1
  fi

  local action
  local MULTILIB_PATTERN="\[multilib\]"
  local INCLUDE_PATTERN="Include = /etc/pacman.d/mirrorlist"
  if grep -Pzq "$MULTILIB_PATTERN\n$INCLUDE_PATTERN" /etc/pacman.conf; then
    disable_multilib "$tempFile"
    action="disabled"
  else
    enable_multilib "$tempFile"
    action="enabled"
  fi

  if ! cp "$tempFile" "/etc/pacman.conf"; then
    print_error "Failed to write '/etc/pacman.conf'."
    sleep 2
    return 1
  fi

  print_info "Multilib repository has been $action."
  rm "$tempFile"
  echo ""
  echo "Updating pacman database..."
  pacman -Sy
  continue_prompt
}

#enable_multilib(tempFilePath)
enable_multilib() {
  awk '
    /^#?\[/ {
      #Start of a new block (eg: [extra-testing])
      in_multilib = 0
    }
    /^#\[multilib\]/ {
      print substr($0, 2)
      in_multilib = 1
      next
    }
    /^#Include *=/ && in_multilib {
      print substr($0, 2)
      next
    }
    {
      print $0
    }
  ' /etc/pacman.conf > "$1"
}

#disable_multilib(tempFilePath)
disable_multilib() {
  awk '
    /^#?\[/ {
      #Start of a new block (eg: [extra-testing])
      in_multilib = 0
    }
    /^\[multilib\]/ {
      print "#" $0
      in_multilib = 1
      next
    }
    /^Include *=/ && in_multilib {
      print "#" $0
      next
    }
    {
      print $0
    }
  ' /etc/pacman.conf > "$1"
}

#=========
#Show menu
#=========

clear
if ! archlinux_environment_check "system configuration"; then
  return
fi

show_menu
