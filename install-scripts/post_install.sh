#!/bin/bash

show_menu() {
  local exited
  local vmType=$(systemd-detect-virt)
  while [[ -z $exited ]]; do
    clear
    echo "Post install tasks"
    echo "------------------"
    echo "1) Install Dev packages"
    echo "2) Install GUI packages"
    if [[ -n "$vmType" && "$vmType" != "none" ]]; then
      echo "9) Setup VM features"
    fi
    echo "0) Exit"
    echo "------------------"
    read_key
    case "$_returnValue" in
        1) install_packages_list "development" "./setup/dev-packages.txt" ;;
        2) install_packages_list "GUI" "./setup/gui-packages.txt" ;;
        9) setup_vm_features "$vmType" ;;
        0) exited=true ;;
        *) play_beep ;;
    esac
  done
}

#=================
#Setup VM Features
#=================

setup_vm_features() {
  if [[ -z "$vmType" || "$vmType" == "none" ]]; then
    play_beep
    return
  fi

  local exited
  while [[ -z $exited ]]; do
    clear
    echo "Setup VM features"
    echo "-----------------"
    echo "1) Setup shared folders"
    echo "2) Add clipboard support"
    echo "3) Install display auto-resizer"
    echo "0) Exit"
    echo "------------------"
    read_key
    case "$_returnValue" in
        1) vm_setup_shared_folders "$1" ;;
        2) vm_add_clipboard_support "$1" ;;
        3) vm_install_display_resizer "$1" ;;
        0) exited=true ;;
        *) play_beep ;;
    esac
  done
}

vm_setup_shared_folders() {
  local mountCommand
  mkdir -p /srv/vmshare
  if ! shared_folder_prompt mountCommand "$1"; then
    return 2
  fi

  echo ""
  print_info "Creating systemd service \"vmshare\" to auto-mount shared folder..."
  (
    #NOTE: "STDIN" here is what is known as a "Heredoc". More info here: https://tldp.org/LDP/abs/html/here-docs.html
    cat <<STDIN
[Unit]
Description=Mount VM Shared Folder to /srv/vmshare
Requires=vmtoolsd.service
After=vmtoolsd.service

[Service]
Type=oneshot
ExecStart=$mountCommand
ExecStop=/usr/bin/umount /srv/vmshare
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
STDIN
  ) > /etc/systemd/system/vmshare.service

  sudo systemctl enable --now vmshare

  echo ""
  print_success "Shared folder '$_returnValue' successfully mounted at \"/srv/vmshare\"!"
  continue_prompt
  return 0
}

shared_folder_prompt() {
  local -n mountCMD=$1
  echo ""
  while true; do
    read -rp "Enter shared folder name (empty to cancel): " _returnValue
    if [[ -z $_returnValue ]]; then
      return 1
    fi

    case "$2" in
      vmware)
        if ! maybe_install "open-vm-tools"; then
          return 1
        fi
        mountCMD="/usr/bin/vmhgfs-fuse .host:/$_returnValue /srv/vmshare -o allow_other"
      ;;
      *)
        print_error "Unsupported VM type: '$2'"
        return 1
      ;;
    esac

    umount /srv/vmshare 2>/dev/null # Ensure no mountpoint already exists

    if ! eval "$mountCMD" 2>/dev/null || ! mountpoint -q /srv/vmshare; then
      print_error "Shared folder '$_returnValue' does not exist or cannot be mounted."
      umount /srv/vmshare 2>/dev/null # Clean up any potential ghost/broken mountpoint
      echo ""
      continue
    fi

    umount /srv/vmshare
    return 0
  done
}

vm_add_clipboard_support() {
  local missingPackages=0
  case "$1" in
    vmware)
      if ! maybe_install "gtkmm3" missingPackages ||
         ! maybe_install "open-vm-tools" missingPackages; then
         return 1
      fi
    ;;
    *)
      print_error "Unsupported VM type: '$1'"
      return 1
    ;;
  esac

  if [[ $missingPackages -ne 0 ]]; then
    echo ""
    print_success "Clipboard integration installed successfully!"
  else
    print_info "Clipboard integration is already set up."
  fi
  sleep 2
  return 0
}

vm_install_display_resizer() {
  local serviceName="display-autoresize"
  local serviceScript="/opt/display-autoresize.sh"
  local servicePath="/etc/systemd/user/$serviceName.service"
  if [[ -f "$servicePath" ]]; then
    print_info "Display autoresize service is already installed."
    sleep 2
    return 0
  fi

  echo ""
  echo "This will install a background script & systemd user service."
  echo ""
  if ! yesno_prompt "Do you wish to continue? [Y/n]: "; then
    return 2
  fi

  echo ""
  print_info "Installing background script at \"$serviceScript\"..."
  (
    #NOTE: "STDIN" here is what is known as a "Heredoc". More info here: https://tldp.org/LDP/abs/html/here-docs.html
    cat <<STDIN
#!/bin/bash

echo "Starting display autoresizer..."
udevadm monitor --kernel --subsystem-match=drm | while read -r line; do
    sleep 1
    echo "Resizing display..."
    xrandr --output Virtual-1 --auto
done
STDIN
  ) > $serviceScript

  chmod +x $serviceScript

  echo ""
  print_info "Creating systemd service \"$serviceName\"..."
  (
    #NOTE: "STDIN" here is what is known as a "Heredoc". More info here: https://tldp.org/LDP/abs/html/here-docs.html
    cat <<STDIN
[Unit]
Description=Automatically resizes display resolution when screen changes
After=graphical.target

[Service]
ExecStart=$serviceScript
Restart=always
Environment=DISPLAY=:0.0

[Install]
WantedBy=default.target
STDIN
) > $servicePath

  systemctl --global enable $serviceName

  echo ""
  print_success "Display autoresize service installed successfully!"
  continue_prompt
  return 0
}

#=========
#Show menu
#=========

clear
if ! archlinux_environment_check "post-install tasks"; then
  return
fi

show_menu
