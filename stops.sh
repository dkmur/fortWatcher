#!/bin/bash

folder="$(pwd)"
source $folder/config.ini

# Logging
mkdir -p $folder/logs

## functions
if [[ -z $sqlpass ]] ;then
  query(){
  mysql -u$sqluser -h$dbip -P$dbport $blisseydb -NB -e "$1;"
  }
else
  query(){
  mysql -u$sqluser -p$sqlpass -h$dbip -P$dbport $blisseydb -NB -e "$1;"
  }
fi

get_monfence(){
fence=""
hook=""
fence=$(query "select fence from geofences where ST_CONTAINS(st, point($lat,$lon)) and type='mon';")
if [[ -z $fence ]] ;then
  webhook=$unfenced_webhook
else
  webhook=$(query "select webhook from webhooks where fence='$fence';")
fi
}

## execution

# create table
query "CREATE TABLE IF NOT EXISTS `webhooks` (`area` varchar(40) NOT NULL,`fence` varchar(40) DEFAULT `Area`,`webhook` varchar(150)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;"

# start receiver and process
while true ;do
  while read -r line ;do
    change_type=$(echo $line| jq -r '.change_type')

    if [[ $change_type == "removal" ]] ;then
      id=$(echo $line| jq -r '.old.id')
      type=$(echo $line| jq -r '.old.type')
      name=$(echo $line| jq -r '.old.name')
      image_url=$(echo $line| jq -r '.old.image_url')
      lat=$(echo $line| jq -r '.old.location.lat')
      lon=$(echo $line| jq -r '.old.location.lon')
      get_monfence
      echo "[$(date '+%Y%m%d %H:%M:%S')] removed $type \"$name\", id=$id at $lat,$lon. Fence=$fence" >> $folder/logs/stops.log
      if [[ ! -z $webhook ]] ;then
        cd $folder && ./discord.sh --username "$change_type $type" --color "16711680" --avatar "https://i.imgur.com/I4s5Z43.png" --thumbnail "$image_url" --webhook-url "$webhook" --description "Name: $name\nLocation: $lat,$lon\nFence: $fence"
      fi
    elif [[ $change_type == "new" ]] ;then
      id=$(echo $line| jq -r '.new.id')
      type=$(echo $line| jq -r '.new.type')
      name=$(echo $line| jq -r '.new.name')
      image_url=$(echo $line| jq -r '.new.image_url')
      lat=$(echo $line| jq -r '.new.location.lat')
      lon=$(echo $line| jq -r '.new.location.lon')
      get_monfence
      echo "[$(date '+%Y%m%d %H:%M:%S')] added $type \"$name\", id=$id at $lat,$lon. Fence=$fence" >> $folder/logs/stops.log
      if [[ ! -z $webhook ]] ;then
        cd $folder && ./discord.sh --username "$change_type $type" --color "65280" --avatar "https://i.imgur.com/I4s5Z43.png" --thumbnail "$image_url" --webhook-url "$webhook" --description "Name: $name\nLocation: $lat,$lon\nFence: $fence"
      fi
    elif [[ $change_type == "edit" ]] ;then
      edit_types=$(echo $line| jq -r '.edit_types')
      oldid=$(echo $line| jq -r '.old.id')
      oldtype=$(echo $line| jq -r '.old.type')
      oldname=$(echo $line| jq -r '.old.name')
      oldimage_url=$(echo $line| jq -r '.old.image_url')
      oldlat=$(echo $line| jq -r '.old.location.lat')
      oldlon=$(echo $line| jq -r '.old.location.lon')
      id=$(echo $line| jq -r '.new.id')
      type=$(echo $line| jq -r '.new.type')
      name=$(echo $line| jq -r '.new.name')
      image_url=$(echo $line| jq -r '.new.image_url')
      lat=$(echo $line| jq -r '.new.location.lat')
      lon=$(echo $line| jq -r '.new.location.lon')
      get_monfence
      echo $line | jq >> $folder/logs/stops.log
      echo "[$(date '+%Y%m%d %H:%M:%S')] edit $type. Fence=$fence " >> $folder/logs/stops.log
      if [[ ! -z $webhook ]] ;then
        if [[ $oldname != $name ]] ;then
          cd $folder && ./discord.sh --username "$change_type $type" --color "15237395" --avatar "https://i.imgur.com/I4s5Z43.png" --thumbnail "$image_url" --webhook-url "$webhook" --description "Old name: $oldname\nNew name: $name\nLocation: $lat,$lon\nFence: $fence"
        elif [[ $oldlat != $lat || $oldlon != $lon ]] ;then
          cd $folder && ./discord.sh --username "$change_type $type" --color "15237395" --avatar "https://i.imgur.com/I4s5Z43.png" --thumbnail "$image_url" --webhook-url "$webhook" --description "Name: $name\nOld location: $oldlat,$oldlon\nNew location: $lat,$lon\nFence: $fence"
        fi
      fi
    else
      echo "THIS SHOULD NOT HAPPEN" >> $folder/logs/stops.log
      echo $line | jq >> $folder/logs/stops.log
    fi

  done < <(netcat -l $receiver_port < response.txt | grep { | jq -c '.[] | .message')
done
