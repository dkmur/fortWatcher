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
webhook=""
fence=$(query "select fence from geofences where ST_CONTAINS(st, point($lat,$lon)) and type='mon';")
if [[ -z $fence ]] ;then
  webhook=$unfenced_webhook
else
  webhook=$(query "select webhook from webhooks where fence='$fence';")
fi
}

get_address(){
if [[ ! -z $nominatim_url && ! -z $webhook ]] ;then
  address=$(curl -s "$nominatim_url/reverse?format=jsonv2&lat=$lat&lon=$lon" | jq -r '.address.road + " " + .address.house_number + ", " + .address.town + .address.village + .address.city')
fi
}

get_staticmap(){
if [[ ! -z $tileserver_url && ! -z $webhook ]] ;then
  if [[ $type == "pokestop" ]] ;then
    pregen=$(curl -s "$tileserver_url/staticmap/pokemon?lat=$lat&lon=$lon&img=https://raw.githubusercontent.com/nileplumb/PkmnShuffleMap/master/UICONS/pokestop/0.png&pregenerate=true")
  else
    pregen=$(curl -s "$tileserver_url/staticmap/pokemon?lat=$lat&lon=$lon&img=https://raw.githubusercontent.com/nileplumb/PkmnShuffleMap/master/UICONS/gym/0.png&pregenerate=true")
  fi
fi
}

## execution

# create table
query "CREATE TABLE IF NOT EXISTS webhooks (area varchar(40) NOT NULL,fence varchar(40) DEFAULT Area,webhook varchar(150)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;"

# start receiver and process
while true ;do
  while read -r line ;do
#    echo $line | jq >> $folder/logs/stops.log
    change_type=$(echo $line| jq -r '.change_type')

    if [[ $change_type == "removal" ]] ;then
      id=$(echo $line| jq -r '.old.id')
      type=$(echo $line| jq -r '.old.type')
      name=$(echo $line| jq -r '.old.name')
      image_url=$(echo $line| jq -r '.old.image_url')
      lat=$(echo $line| jq -r '.old.location.lat')
      lon=$(echo $line| jq -r '.old.location.lon')
      get_monfence
      get_address
      get_staticmap
      echo "[$(date '+%Y%m%d %H:%M:%S')] removed $type \"$name\", id=$id at $lat,$lon. Fence=$fence" >> $folder/logs/stops.log
      if [[ ! -z $webhook ]] ;then
        cd $folder && ./discord.sh --username "$change_type $type" --color "16711680" --avatar "https://i.imgur.com/I4s5Z43.png" --thumbnail "$image_url" --image "$tileserver_url/staticmap/pregenerated/$pregen" --webhook-url "$webhook" --description "Name: $name\nLocation: $lat,$lon\nFence: $fence\n\n$address\n[Google](https://www.google.com/maps/search/?api=1&query=$lat,$lon) | [$map_name]($map_url/@/$lat/$lon/16)"
      fi
    elif [[ $change_type == "new" ]] ;then
      id=$(echo $line| jq -r '.new.id')
      type=$(echo $line| jq -r '.new.type')
      name=$(echo $line| jq -r '.new.name')
      if [[ $name == "null" ]] ;then
        name="Unknown"
      fi
      image_url=$(echo $line| jq -r '.new.image_url')
      if [[ $image_url == "null" && type == "pokestop" ]] ;then
        image_url="https://raw.githubusercontent.com/nileplumb/PkmnShuffleMap/master/UICONS/pokestop/0.png"
      else
        image_url="https://raw.githubusercontent.com/nileplumb/PkmnShuffleMap/master/UICONS/gym/0.png"
      fi
      lat=$(echo $line| jq -r '.new.location.lat')
      lon=$(echo $line| jq -r '.new.location.lon')
      get_monfence
      get_address
      get_staticmap
      echo "[$(date '+%Y%m%d %H:%M:%S')] added $type \"$name\", id=$id at $lat,$lon. Fence=$fence" >> $folder/logs/stops.log
      if [[ ! -z $webhook ]] ;then
        cd $folder && ./discord.sh --username "$change_type $type" --color "65280" --avatar "https://i.imgur.com/I4s5Z43.png" --thumbnail "$image_url" --image "$tileserver_url/staticmap/pregenerated/$pregen" --webhook-url "$webhook" --description "Name: $name\nLocation: $lat,$lon\nFence: $fence\n\n$address\n[Google](https://www.google.com/maps/search/?api=1&query=$lat,$lon) | [$map_name]($map_url/@/$lat/$lon/16)"
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
      get_address
      get_staticmap
      echo $line | jq >> $folder/logs/stops.log
      echo "[$(date '+%Y%m%d %H:%M:%S')] edit $type. Fence=$fence " >> $folder/logs/stops.log
      if [[ ! -z $webhook ]] ;then
        if [[ $oldname != $name ]] ;then
          cd $folder && ./discord.sh --username "$change_type $type" --color "15237395" --avatar "https://i.imgur.com/I4s5Z43.png" --thumbnail "$image_url" --image "$tileserver_url/staticmap/pregenerated/$pregen" --webhook-url "$webhook" --description "Old name: $oldname\nNew name: $name\nLocation: $lat,$lon\nFence: $fence\n\n$address\n[Google](https://www.google.com/maps/search/?api=1&query=$lat,$lon) | [$map_name]($map_url/@/$lat/$lon/16)"
        elif [[ $oldlat != $lat || $oldlon != $lon ]] ;then
          cd $folder && ./discord.sh --username "$change_type $type" --color "15237395" --avatar "https://i.imgur.com/I4s5Z43.png" --thumbnail "$image_url" --image "$tileserver_url/staticmap/pregenerated/$pregen" --webhook-url "$webhook" --description "Name: $name\nOld location: $oldlat,$oldlon\nNew location: $lat,$lon\nFence: $fence\n\n$address\n[Google](https://www.google.com/maps/search/?api=1&query=$lat,$lon) | [$map_name]($map_url/@/$lat/$lon/16)"
        elif [[ $oldtype != $type ]] ;then
         cd $folder && ./discord.sh --username "$oldtype => $type" --color "15237395" --avatar "https://i.imgur.com/I4s5Z43.png" --thumbnail "$image_url" --image "$tileserver_url/staticmap/pregenerated/$pregen" --webhook-url "$webhook" --description "Name: $name\nOld type: $oldtype\nNew type: $type\nFence: $fence\n\n$address\n[Google](https://www.google.com/maps/search/?api=1&query=$lat,$lon) | [$map_name]($map_url/@/$lat/$lon/16)"
        fi
      fi
    else
      echo "THIS SHOULD NOT HAPPEN" >> $folder/logs/stops.log
      echo $line | jq >> $folder/logs/stops.log
    fi

  done < <(netcat -l $receiver_port < response.txt | grep { | jq -c '.[] | .message')
done
