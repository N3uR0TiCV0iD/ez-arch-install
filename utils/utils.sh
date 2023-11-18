#!/bin/bash

#read_key(prompt="")
read_key() {
  read -n 1 -sp "$1" _returnValue
}

play_beep() {
  echo -ne "\007"
}

#yesno_prompt(prompt, default="Y") {
yesno_prompt() {
  local response
  local default="${2:-Y}"
  while true; do
    read -rp "$1" response
    case "$response" in
      [Yy]|Yes|yes) return 0 ;;
      [Nn]|No|no) return 1 ;;
      "")
        if [[ $default == [Yy] ]]; then
          return 0
        fi
        return 1
        ;;
      *) echo "Please answer Y[es] or N[o].";;
    esac
  done
}

#index_of(item, *array)
index_of() {
  local index
  local -n _array=$2
  for index in "${!_array[@]}"; do
    if [[ "${_array[$index]}" == "$1" ]]; then
      echo "$index"
      return 0
    fi
  done
  echo "-1"
  return 1
}

#build_dictionary_string(*dictionary) {
build_dictionary_string() {
  local -n dictionary=$1
  _returnValue=""
  for key in "${!dictionary[@]}"; do
    _returnValue+="$key=${dictionary[$key]}¬"
  done
  _returnValue="${_returnValue%¬}" #Remove trailing '¬'
}

#get_directories(folderPath)
get_directories() {
  find "$1" -maxdepth 1 -mindepth 1 -type d -exec basename {} \;
}

#has_command(command)
has_command() {
  if command -v $1 &> /dev/null; then
    return 0
  fi
  return 1
}

#password_prompt(customInfo)
password_prompt() {
  local customInfo=""
  if [[ $1 ]]; then
    customInfo=" ($1)"
  fi
  while true; do
    read -rsp "Enter password$customInfo:" _returnValue
    echo ""
    if [[ -z $_returnValue ]]; then
      return 1
    fi

    local passwordConfirm
    read -rsp "Confirm password:" passwordConfirm
    echo ""
    if [[ "$_returnValue" == "$passwordConfirm" ]]; then
      return 0
    fi
    print_error "Passwords do not match. Please try again."
    echo ""
  done
}

#custom_select(prompt, *options, maxColumns)
custom_select() {
  local -n _options=$2
  local maxColumns=$3
  local terminalWidth=$(tput cols)
  local optionsCount=${#_options[@]}

  local maxDigits=${#optionsCount} #Essentially "ceil(log_10(n))": 5 => 1 | 14 => 2 | 105 => 3
  local maxLength=$(max_itemlength $2)
  local columnWidth=$(( maxDigits + 2 + maxLength + 2 )) #Accounts for "N) " and adds padding
  local displayColumns=$(( terminalWidth / columnWidth ))
  if [[ $maxColumns ]] && (( maxColumns > 0 && displayColumns > maxColumns )); then
    displayColumns=$maxColumns
  fi
  if (( displayColumns == 0 )); then
    displayColumns=1 #Prevent division by zero
  fi

  local index=0
  local nextIndex=1
  while ((index < optionsCount)); do
    local paddedNumber=$(printf "%${maxDigits}d" $nextIndex)
    local itemText="$paddedNumber) ${_options[index]}"
    printf "%-${columnWidth}s" "$itemText"
    if (( nextIndex % displayColumns == 0 || nextIndex == optionsCount )); then
      echo ""
    fi
    index=$nextIndex
    nextIndex=$(( index + 1 ))
  done

  local choice
  while true; do
    echo ""
    read -p "$1" choice
    if [[ -z $choice ]]; then
      return 1
    fi

    if [[ $choice =~ ^[1-9][0-9]*$ ]] && (( choice <= optionsCount )); then
      index=$((choice - 1))
      _returnValue="${_options[index]}"
      return 0
    fi

    index=$(index_of "$choice" $2)
    if (( index != -1 )); then
      _returnValue="$choice"
      return 0
    fi

    echo ""
    print_error "Invalid selection. Please try again."
  done
}

#max_itemlength(*array)
max_itemlength() {
  local maxLength=0
  local -n _array=$1
  local item itemLength
  for item in "${_array[@]}"; do
    itemLength=${#item}
    if (( itemLength > maxLength )); then
      maxLength=$itemLength
    fi
  done
  echo "$maxLength"
}

#create_group_dictionary(*sortedList, *targetDictionary, groupDelimiter="")
create_group_dictionary() {
  local -n _sortedList=$1
  local -n _targetDictionary=$2

  local item splitItem dummy
  for item in "${_sortedList[@]}"; do
    IFS="$3" read -r splitItem dummy <<< "$item"
    
    local groupKey=$(find_group_key $2 "$splitItem")
    if [[ -z $groupKey ]]; then
      groupKey="$splitItem"
      _targetDictionary[$groupKey]="$item" #Initialize a new list for the group
      continue
    fi
    
    local groupList="${_targetDictionary[$groupKey]}"
    _targetDictionary[$groupKey]="$groupList¬$item"
  done
}

#find_group_key(*dictionary, item)
find_group_key() {
  local -n _dictionary=$1
  for key in "${!_dictionary[@]}"; do
    if [[ "$2" == "$key"* ]]; then
      echo "$key"
      return 0
    fi
  done
  return 1
}

#count_files(folderPath, filter="*")
count_files() {
  local filter="${2:-*}"
  find "$1" -name "$filter" | wc -l
}

#continue_prompt(prompt="Press any key to continue...")
continue_prompt() {
  prompt=$1
  if [[ -z $prompt ]]; then
    prompt="Press any key to continue..."
  fi
  echo ""
  read -n 1 -sp "$prompt"
}

#print_info(text...)
print_info() {
  local noColor='\033[0m'
  local cyanColor='\033[0;36m'
  echo -e "${cyanColor}$*${noColor}"
}

#print_success(text...)
print_success() {
  local noColor='\033[0m'
  local greenColor='\033[0;32m'
  echo -e "${greenColor}$*${noColor}"
}

#print_warning(text...)
print_warning() {
  local noColor='\033[0m'
  local yellowColor='\033[1;33m'
  echo -e "${yellowColor}WARNING: ${noColor}$*"
}

#print_error(text...)
print_error() {
  local noColor='\033[0m'
  local redColor='\033[0;31m'
  echo -e "${redColor}$*${noColor}" >&2
}
