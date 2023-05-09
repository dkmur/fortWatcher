#!/bin/bash

folder="$(pwd)"
source $folder/config.ini

## Logging
mkdir -p $folder/logs
# log start
echo "[$(date '+%Y%m%d %H:%M:%S')] fortwatcher (re)started" >> $folder/logs/stops.log
# stderr to logfile
exec 2>> $folder/logs/stops.log


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
map_urll=""
fence=$(query "select fence from geofences where ST_CONTAINS(st, point($lat,$lon)) and type='mon';")
subdomain=$(query "select ifnull(subdomain,'') from webhooks where fence='$fence';")
if [[ ! -z $fence ]] ;then
  webhook=$(query "select webhook from webhooks where fence='$fence';")
else
  webhook=$unfenced_webhook
  fence="unfenced"
fi
if [[ -z $subdomain ]] ;then
   map_urll=$map_url
else
  if [[ $subdomain != http* ]] ;then
    map_urll=$(echo $map_url | sed "s/\(.*\/\/\)\(.*\)/\1$subdomain.\2/g")
  else
    map_urll=$subdomain
  fi
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
  elif [[ $type == "gym" ]] ;then
    pregen=$(curl -s "$tileserver_url/staticmap/pokemon?lat=$lat&lon=$lon&img=https://raw.githubusercontent.com/nileplumb/PkmnShuffleMap/master/UICONS/gym/0.png&pregenerate=true")
  else
    pregen=$(curl -s "$tileserver_url/staticmap/pokemon?lat=$lat&lon=$lon&img=https://i.imgur.com/vB3E31G.png&pregenerate=true")
#    pregen=$(curl -s "$tileserver_url/staticmap/pokemon?lat=$lat&lon=$lon&img=https://raw.githubusercontent.com/nileplumb/PkmnShuffleMap/master/UICONS/spawnpoint/0.png&pregenerate=true")
  fi
fi
}

## execution

# create table
query "CREATE TABLE IF NOT EXISTS webhooks (area varchar(40) NOT NULL,fence varchar(40) DEFAULT Area,webhook varchar(150),subdomain varchar(20)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;"
# table updates
query "alter table webhooks add column if not exists subdomain varchar(40);"

# start receiver and process
while true ;do
  while read -r line ;do
#    echo $line | jq >> $folder/logs/stops.log
    change_type=$(echo $line| jq -r '.change_type')

    if [[ $change_type == "removal" ]] ;then
      id=$(echo $line| jq -r '.old.id')
      type=$(echo $line| jq -r '.old.type')
      name=$(echo $line| jq -r '.old.name' | sed 's/\"/\\\"/g')
      image_url=$(echo $line| jq -r '.old.image_url')
      lat=$(echo $line| jq -r '.old.location.lat' | xargs printf "%.*f\n" 6)
      lon=$(echo $line| jq -r '.old.location.lon' | xargs printf "%.*f\n" 6)
      get_monfence
      get_address
      get_staticmap
      echo "[$(date '+%Y%m%d %H:%M:%S')] removed $type id: $id location: $lat,$lon fence: $fence name: \"$name\"" >> $folder/logs/stops.log
      if [[ ! -z $webhook ]] ;then
        cd $folder && ./discord.sh --username "${change_type^} ${type^}" --color "16711680" --avatar "https://cdn.discordapp.com/attachments/657164868969037824/1104477454313197578/770615.png" --thumbnail "$image_url" --image "$tileserver_url/staticmap/pregenerated/$pregen" --webhook-url "$webhook" --footer "Fence: $fence Location: $lat,$lon" --description "Name: **$name**\n\n$address\n[Google](https://www.google.com/maps/search/?api=1&query=$lat,$lon) | [Apple](https://maps.apple.com/maps?daddr=$lat,$lon) | [$map_name]($map_urll/@/$lat/$lon/16)" >> $folder/logs/stops.log
      fi
    elif [[ $change_type == "new" ]] ;then
      id=$(echo $line| jq -r '.new.id')
      type=$(echo $line| jq -r '.new.type')
      name=$(echo $line| jq -r '.new.name' | sed 's/\"/\\\"/g')
      if [[ $name == "null" ]] ;then
        name="Unknown"
      fi
      image_url=$(echo $line| jq -r '.new.image_url')
      if [[ $image_url == "null" ]] ;then
        if [[ $type == "pokestop" ]] ;then
          image_url="https://raw.githubusercontent.com/nileplumb/PkmnShuffleMap/master/UICONS/pokestop/0.png"
        elif [[ $type == "gym" ]] ;then
          image_url="https://raw.githubusercontent.com/nileplumb/PkmnShuffleMap/master/UICONS/gym/0.png"
        else
          image_url="https://i.imgur.com/HwRhTBF.png"
        fi
      fi
      lat=$(echo $line| jq -r '.new.location.lat' | xargs printf "%.*f\n" 6)
      lon=$(echo $line| jq -r '.new.location.lon' | xargs printf "%.*f\n" 6)
      get_monfence
      get_address
      get_staticmap
      echo "[$(date '+%Y%m%d %H:%M:%S')] added $type id: $id location: $lat,$lon fence: $fence name: \"$name\"" >> $folder/logs/stops.log
      if [[ ! -z $webhook ]] ;then
        if [[ $type == "portal" ]] ;then
          cd $folder && ./discord.sh --username "${change_type^} ${type^}" --color "12609532" --avatar "https://i.imgur.com/HwRhTBF.png" --thumbnail "$image_url" --image "$tileserver_url/staticmap/pregenerated/$pregen" --webhook-url "$webhook" --footer "Fence: $fence Location: $lat,$lon" --description "Name: $name\n\n$address\n[Google](https://www.google.com/maps/search/?api=1&query=$lat,$lon) | [Apple](https://maps.apple.com/maps?daddr=$lat,$lon) | [$map_name]($map_urll/@/$lat/$lon/16)" >> $folder/logs/stops.log
        else
          cd $folder && ./discord.sh --username "${change_type^} ${type^}" --color "65280" --avatar "https://cdn.discordapp.com/attachments/657164868969037824/1104477454313197578/770615.png" --thumbnail "$image_url" --image "$tileserver_url/staticmap/pregenerated/$pregen" --webhook-url "$webhook" --footer "Fence: $fence Location: $lat,$lon" --description "Name: $name\n\n$address\n[Google](https://www.google.com/maps/search/?api=1&query=$lat,$lon) | [Apple](https://maps.apple.com/maps?daddr=$lat,$lon) | [$map_name]($map_urll/@/$lat/$lon/16)" >> $folder/logs/stops.log
        fi
      fi
    elif [[ $change_type == "edit" ]] ;then
      edit_types=$(echo $line| jq -r '.edit_types')
#      oldid=$(echo $line| jq -r '.old.id')
      oldtype=$(echo $line| jq -r '.old.type')
      oldname=$(echo $line| jq -r '.old.name' | sed 's/\"/\\\"/g')
      if [[ $oldname == "null" ]] ;then
        oldname="Unknown"
      fi
#      oldimage_url=$(echo $line| jq -r '.old.image_url')
      oldlat=$(echo $line| jq -r '.old.location.lat' | xargs printf "%.*f\n" 6)
      oldlon=$(echo $line| jq -r '.old.location.lon' | xargs printf "%.*f\n" 6)
      id=$(echo $line| jq -r '.new.id')
      type=$(echo $line| jq -r '.new.type')
      name=$(echo $line| jq -r '.new.name' | sed 's/\"/\\\"/g')
      image_url=$(echo $line| jq -r '.new.image_url')
      lat=$(echo $line| jq -r '.new.location.lat' | xargs printf "%.*f\n" 6)
      lon=$(echo $line| jq -r '.new.location.lon' | xargs printf "%.*f\n" 6)
      get_monfence
      get_address
      get_staticmap
#      echo $line | jq >> $folder/logs/stops.log
#      echo "[$(date '+%Y%m%d %H:%M:%S')] edit $type id: $id fence: $fence name: \"$name\"" >> $folder/logs/stops.log
      if [[ ! -z $webhook ]] ;then
        if [[ $oldname != $name ]] ;then
          echo "[$(date '+%Y%m%d %H:%M:%S')] edit $type name id: $id fence: $fence name: \"$name\" oldname: \"$oldname\"" >> $folder/logs/stops.log
          cd $folder && ./discord.sh --username "${type^} name change" --color "15237395" --avatar "https://cdn.discordapp.com/attachments/657164868969037824/1104477454313197578/770615.png" --thumbnail "$image_url" --image "$tileserver_url/staticmap/pregenerated/$pregen" --webhook-url "$webhook" --footer "Fence: $fence Location: $lat,$lon" --description "Old: $oldname\nNew: **$name**\n\n$address\n[Google](https://www.google.com/maps/search/?api=1&query=$lat,$lon) | [Apple](https://maps.apple.com/maps?daddr=$lat,$lon) | [$map_name]($map_urll/@/$lat/$lon/16)" >> $folder/logs/stops.log
        elif [[ $oldlat != $lat || $oldlon != $lon ]] ;then
          echo "[$(date '+%Y%m%d %H:%M:%S')] edit $type location id: $id fence: $fence name: \"$name\" oldloc: $oldlat,$oldlon" >> $folder/logs/stops.log
#          echo $line | jq >> $folder/logs/stops.log
          cd $folder && ./discord.sh --username "${type^} location change" --color "15237395" --avatar "https://cdn.discordapp.com/attachments/657164868969037824/1104477454313197578/770615.png" --thumbnail "$image_url" --image "$tileserver_url/staticmap/pregenerated/$pregen" --webhook-url "$webhook" --footer "Fence: $fence Location: $lat,$lon" --description "Name: **$name**\nOld: $oldlat,$oldlon\nNew: \`$lat,$lon\`\n\n$address\n[Google](https://www.google.com/maps/search/?api=1&query=$lat,$lon) | [Apple](https://maps.apple.com/maps?daddr=$lat,$lon) | [$map_name]($map_urll/@/$lat/$lon/16)" >> $folder/logs/stops.log
        elif [[ $oldtype != $type ]] ;then
          echo "[$(date '+%Y%m%d %H:%M:%S')] edit oldtype conversion name id: $id fence: $fence name: \"$name\" newtype: $type" >> $folder/logs/stops.log
         cd $folder && ./discord.sh --username "Conversion" --color "15237395" --avatar "https://cdn.discordapp.com/attachments/657164868969037824/1104477454313197578/770615.png" --thumbnail "$image_url" --image "$tileserver_url/staticmap/pregenerated/$pregen" --webhook-url "$webhook" --footer "Fence: $fence Location: $lat,$lon" --description "Name: **$name**\nOld type: $oldtype\nNew type: **$type**\n\n$address\n[Google](https://www.google.com/maps/search/?api=1&query=$lat,$lon) | [Apple](https://maps.apple.com/maps?daddr=$lat,$lon) | [$map_name]($map_urll/@/$lat/$lon/16)" >> $folder/logs/stops.log
        fi
      fi
    else
      echo "THIS SHOULD NOT HAPPEN" >> $folder/logs/stops.log
      echo $line | jq >> $folder/logs/stops.log
    fi

  done < <(ncat -l $receiver_port < response.txt | grep { | jq -c '.[] | .message')
done
