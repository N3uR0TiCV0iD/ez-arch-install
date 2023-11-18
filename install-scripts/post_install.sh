#!/bin/bash

show_menu() {
  local exited
  while [[ -z $exited ]]; do
    clear
    echo "Post install tasks"
    echo "------------------"
    echo "1) Install Dev packages"
    echo "2) Install GUI packages"
    echo "0) Exit"
    echo "------------------"
    read_key
    case "$_returnValue" in
        1) install_packages_list "development" "./setup/dev-packages.txt" ;;
        2) install_packages_list "GUI" "./setup/gui-packages.txt" ;;
        0) exited=true ;;
        *) play_beep ;;
    esac
  done
}

#=========
#Show menu
#=========

clear
if ! archlinux_environment_check "post-install tasks"; then
  return
fi

show_menu
