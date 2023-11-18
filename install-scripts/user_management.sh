#!/bin/bash

show_menu() {
  local exited
  while [[ -z $exited ]]; do
    clear
    echo "User Management"
    echo "---------------"
    echo "1) Configure users"
    echo "2) Configure groups"
    echo "3) Setup sudo"
    echo "0) Exit"
    echo "---------------"
    read_key
    case "$_returnValue" in
      1) configure_users ;;
      2) configure_groups ;;
      3) setup_sudo ;;
      0) exited=true ;;
      *) play_beep ;;
    esac
  done
}

#===============
#Configure users
#===============

configure_users() {
  local exited
  while [[ -z $exited ]]; do
    clear
    show_users
    echo ""
    echo "[a]dd, [m]odify, [r]emove, [q]uit"
    read_key
    case "$_returnValue" in
      a) add_user ;;
      m) modify_user ;;
      r) remove_user ;;
      q) exited=true ;;
      *) play_beep ;;
    esac
  done
}

show_users() {
  printf "%-30s %-20s %-30s %-20s\n" "Username" "User Type" "Home Directory" "Shell"
  printf '%.0s-' {1..90} #NOTE: There is no new line here!
  print_usertype_list "Regular Users" 1000 60000
  print_usertype_list "Super-users" 0 0
  print_usertype_list "System Users" 1 999
}

#print_usertype_list(userType, minUID, maxUID)
print_usertype_list() {
  echo ""
  awk -F ":" -v userType="$1" -v minUID="$2" -v maxUID="$3" '
    ($3 >= minUID && $3 <= maxUID) {
      printf("%-30s %-20s %-30s %-20s\n", $1, userType, $6, $7)
    }
  ' /etc/passwd
}

add_user() {
  local validUser
  while [[ -z $validUser ]]; do
    username_prompt
    case "$?" in
      0)
        print_error "Username already exists."
        ;;
      1) validUser=true ;; # Username does not exist
      2) return 1 ;; # User chose to cancel
    esac
  done

  local username=$_returnValue
  password_prompt "empty to cancel"
  if [[ -z $_returnValue ]]; then
    return 1
  fi

  local password=$_returnValue
  echo ""
  usergroup_prompt "empty for default"
  local mainGroup=$_returnValue

  local DEFAULT_GROUPS="wheel, storage, power"
  usergroups_prompt
  local groups=$_returnValue
  if [[ -z $groups ]]; then
    echo ""
    if yesno_prompt "Include user in default groups '$DEFAULT_GROUPS'? [Y/n]: "; then
      groups=$(collapse_usergroups "$DEFAULT_GROUPS")
    fi
  fi

  local DEFAULT_SHELL="/bin/bash"
  echo ""
  shell_prompt "empty for $DEFAULT_SHELL"
  local shell=$_returnValue
  if [[ -z $shell ]]; then
    shell="$DEFAULT_SHELL"
  fi

  local createHomeDir=false
  echo ""
  if yesno_prompt "Would you like to create a home directory for the user? [Y/n]: "; then
    createHomeDir=true
  fi

  echo ""
  if ! create_user "$username" "$password" "$mainGroup" "$groups" "$shell" $createHomeDir; then
    print_error "Failed to create user '$username'."
    sleep 2
    return 1
  fi

  print_success "User '$username' created successfully."
  sleep 2
  return 0
}

#username_prompt() -> 0 (true) if exists, 1 (false) if nonexistent, 2 (false) user cancels | $_returnValue = result
username_prompt() {
  while true; do
    echo ""
    read -rp "Enter username (empty to cancel): " _returnValue
    if [[ -z $_returnValue ]]; then
      return 2
    fi

    if ! is_valid_username "$_returnValue"; then
      print_error "Name must start with a letter. Only lowercase, numbers, '-' & '_' are allowed."
      continue
    fi

    if ! is_existing_user "$_returnValue"; then
      return 1
    fi

    return 0
  done
}

#is_valid_username(username)
is_valid_username() {
  if ! [[ $1 =~ ^[a-zA-Z][a-zA-Z0-9_-]*$ ]]; then
    return 1
  fi
  return 0
}

#is_existing_user(username)
is_existing_user() {
  if id "$1" &>/dev/null; then
    return 0
  fi
  return 1
}

#shell_prompt(customInfo)
shell_prompt() {
  while true; do
    read -rp "Enter the shell path ($1): " _returnValue
    if [[ -z $_returnValue ]]; then
      return 1
    fi

    if [[ ! -f "$_returnValue" ]] || [[ ! -x "$_returnValue" ]]; then
      print_error "The specified shell is invalid or not executable."
      echo ""
      continue
    fi

    return 0
  done
}

#usergroup_prompt(customInfo)
usergroup_prompt() {
  while true; do
    read -rp "Enter usergroup ($1): " _returnValue
    if [[ -z $_returnValue ]]; then
      return 1
    elif is_existing_usergroup $_returnValue; then
      return 0
    fi
    print_error "The usergroup '$_returnValue' does not exist."
    echo ""
  done
}

usergroups_prompt() {
  while true; do
    read -rp "Enter additional user groups (can be empty): " _returnValue
    if [[ -z $_returnValue ]]; then
      return 1
    fi

    local invalidGroup
    if ! are_existing_usergroups "$_returnValue" invalidGroup; then
      print_error "The usergroup '$invalidGroup' does not exist."
      echo ""
      continue
    fi

    _returnValue=$(collapse_usergroups "$_returnValue")
    return 0
  done
}

#collapse_usergroups(usergroups)
collapse_usergroups() {
  echo "$1" | tr -d ' ' #Remove spaces
}

#are_existing_usergroups(groupNames, *invalidGroup)
are_existing_usergroups() {
  local -a groups
  local -n _invalidGroup=$2

  #Temporarily sets the IFS (internal field separator) & splits "partitionInfo"
  IFS=',' read -ra groups <<< "$1"

  local group
  for group in "${groups[@]}"; do
    group=$(echo "$group" | xargs) #Trim whitespace
    if [[ -z $group ]] || ! is_existing_usergroup "$group"; then
      _invalidGroup=$group
      return 1
    fi
  done
  return 0
}

#is_existing_usergroup(groupName)
is_existing_usergroup() {
  if getent group "$1" > /dev/null 2>&1; then
    return 0
  fi
  return 1
}

#create_user(username, password, mainGroup, groups, shell, createHomeDir)
create_user() {
  local command=("useradd")
  if [[ "$6" == "true" ]]; then
    command+=("-m")
  fi

  if [[ $3 ]]; then
    command+=("-g" "$3")
  fi

  if [[ $4 ]]; then
    command+=("-G" "$4")
  fi

  local encryptedPassword=$(openssl passwd -6 "$2")
  command+=("-p" "$encryptedPassword" "-s" "$5" "$1")
  if ! "${command[@]}"; then
    return 1
  fi
  return 0
}

#===========
#Modify user
#===========

modify_user() {
  local validUser
  while [[ -z $validUser ]]; do
    username_prompt
    case "$?" in
      0) validUser=true ;; # Username exists
      1)
        print_error "Username does not exist."
        ;;
      2) return 1 ;; # User chose to cancel
    esac
  done
  user_modification_menu $_returnValue
}

#user_modification_menu(username)
user_modification_menu() {
  local exited
  while [[ -z $exited ]]; do
    clear
    echo "Modifying user: '$1'"
    echo "==========================="
    show_user_info "$1"
    echo "---------------------------"
    echo "1) Update password"
    echo "2) Change primary group"
    echo "3) Change additional groups"
    echo "4) Modify default shell"
    echo "0) Exit"
    echo "---------------------------"
    read_key
    case "$_returnValue" in
      1) update_password "$1" ;;
      2) change_primary_group "$1" ;;
      3) change_addtional_groups "$1" ;;
      4) modify_default_shell "$1" ;;
      0) exited=true ;;
      *) play_beep ;;
    esac
  done
}

#show_user_info(username)
show_user_info() {
  local primaryGroup=$(id -gn "$1")
  local additionalGroups=$(id -Gn "$1" | sed "s/$primaryGroup //g") #Removes the primary group from the list
  local userShell=$(getent passwd "$1" | cut -d: -f7)
  print_user_info "Primary Group:" "$primaryGroup"
  print_user_info "Additional Groups:" "$additionalGroups"
  print_user_info "Default Shell:" "$userShell"
}

#print_user_info(title, value)
print_user_info() {
  printf "%-20s %s\n" "$1" "$2"
}

#update_password(username)
update_password() {
  password_prompt "empty to cancel"
  if [[ -z $_returnValue ]]; then
    return 2
  fi

  echo ""
  if ! change_password "$1" "$_returnValue"; then
    echo ""
    print_error "The password of '$1' was NOT updated."
    sleep 2
    return 1
  fi
  
  print_success "The password of '$1' was updated successfully."
  sleep 2
  return 0
}

#change_primary_group(username)
change_primary_group() {
  usergroup_prompt "empty to cancel"
  if [[ -z $_returnValue ]]; then
    return 1
  fi

  echo ""
  if ! usermod -g "$_returnValue" "$1"; then
    print_error "Failed to change primary group for user '$1'."
    sleep 2
    return 1
  fi

  print_success "Primary group for user '$1' changed to '$_returnValue'."
  sleep 2
  return 0
}

#change_addtional_groups(username)
change_addtional_groups() {
  usergroups_prompt
  if [[ -z $_returnValue ]]; then
    echo ""
    if ! yesno_prompt "Are you sure you want to remove all additional groups? [y/N]: " "N"; then
      #User did not intend to remove all additional groups
      return 1
    fi
  fi

  echo ""
  if ! usermod -G "$_returnValue" "$1"; then
    print_error "Failed to change additional group for user '$1'."
    sleep 2
    return 1
  fi

  print_success "Additional groups for user '$1' changed to '$_returnValue'."
  sleep 2
  return 0
}

#modify_default_shell(username)
modify_default_shell() {
  shell_prompt "empty to cancel"
  if [[ -z $_returnValue ]]; then
    return 1
  fi

  echo ""
  if ! usermod -s "$_returnValue" "$1"; then
    print_error "Failed to change default shell for user '$1'."
    sleep 2
    return 1
  fi

  print_success "Default shell for user '$1' changed to '$_returnValue'."
  sleep 2
  return 0
}

#===========
#Delete user
#===========

remove_user() {
  local validUser
  while [[ -z $validUser ]]; do
    username_prompt
    case "$?" in
      0) validUser=true ;; # Username exists
      1)
        print_error "Username does not exist."
        ;;
      2) return 2 ;; # User chose to cancel
    esac
  done

  echo ""
  if ! yesno_prompt "Are you sure you want to remove '$_returnValue'? [y/N]: " "N"; then
    return 2
  fi

  if ! delete_user "$_returnValue"; then
    print_error "Failed to delete user '$_returnValue'."
    sleep 2
    return 1
  fi

  print_success "User '$_returnValue' deleted successfully."
  sleep 2
  return 0
}

#delete_user(username)
delete_user() {
  local command=("userdel")
  if yesno_prompt "Delete home directory and mail as well? [Y/n]: "; then
    command+=("-r")
  fi
  echo ""
  command+=("$1")
  if ! "${command[@]}" &> /dev/null; then
    return 1
  fi
  return 0
}

#================
#Group management
#================

configure_groups() {
  local exited
  while [[ -z $exited ]]; do
    clear
    show_groups
    echo ""
    echo "[a]dd, [r]emove, [q]uit"
    read_key
    case "$_returnValue" in
      a) add_usergroup ;;
      r) remove_usergroup ;;
      q) exited=true ;;
      *) play_beep ;;
    esac
  done
}

show_groups() {
  echo "Current groups on the system:"
  echo "-----------------------------"
  print_grouptype "Regular" 1000 60000
  echo ""
  print_grouptype "System" 0 999
}

#print_grouptype(groupType, minGID, maxGID)
print_grouptype() {
  awk -F ":" -v minGID="$2" -v maxGID="$3" '($3 >= minGID && $3 <= maxGID)' /etc/group \
  | sort \
  | awk -v groupType="$1" -F ":" '
    {
      numMembers = split($4, members, ",")
      columnText = $1 " (" groupType ") [" numMembers "]"
      printf("%-45s", columnText)
      if (NR % 3 == 0) {
        printf("\n")
      }
    }
    END {
      if (NR % 3 != 0) {
        printf("\n")
      }
    }
  '
}

add_usergroup() {
  local groupName
  while true; do
    echo ""
    read -rp "New usergroup name (empty to cancel): " groupName
    if [[ -z $groupName ]]; then
      return 1
    fi

    if ! is_valid_usergroup "$groupName"; then
      print_error "Name must start with a letter/underscore. Only lowercase, numbers, '-' & '_' are allowed."
      continue
    fi

    echo ""
    groupadd "$groupName"
    if [[ $? -ne 0 ]]; then
      print_error "Failed to create group '$groupName'."
      echo ""
      return 1
    fi

    print_success "Group '$groupName' created successfully."
    sleep 2
    return 0
  done
}

#is_valid_usergroup(groupName)
is_valid_usergroup() {
  if [[ $1 =~ ^[a-z_][a-z0-9_-]*$ ]]; then
    return 0 #Group name is valid
  fi
  return 1
}

remove_usergroup() {
  echo ""
  usergroup_prompt "empty to cancel"
  if [[ -z $_returnValue ]]; then
    return 1
  fi

  echo ""
  if ! groupdel "$_returnValue"; then
    print_error "Failed to remove group '$_returnValue'."
    sleep 2
    return 1
  fi

  print_success "Group '$_returnValue' removed successfully."
  sleep 2
  return 0
}

#===============
#Sudo management
#===============

setup_sudo() {
  if ! has_command "sudo" && ! install_package_prompt "sudo"; then
    #User did not have sudo and it was not installed
    return 1
  fi

  local editor="nano"
  if ! has_command "nano"; then
    echo "The recommended 'nano' text editor package is not installed."
    if ! install_package_prompt "nano" "Install 'nano' for simpler sudoers file editing? [Y/n]: "; then
      echo ""
      echo "The 'vi' text editor will be used instead... (May the force be with you)"
      continue_prompt
      editor=vi
    fi
  fi

  #Open the sudoers file with "$editor" for editing
  local lineNumber=$(sed -n '/%wheel/=' "/etc/sudoers" | head -n 1)
  EDITOR="$editor +$lineNumber" visudo
}

#=========
#Show menu
#=========

clear
if ! archlinux_environment_check "user management"; then
  return
fi

show_menu
