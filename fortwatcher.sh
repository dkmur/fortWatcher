#!/bin/bash

folder="$(pwd)"
source $folder/config.ini

## Logging
mkdir -p $folder/logs
# rename log
if [[ -f $folder/logs/stops.log ]] ;then mv $folder/logs/stops.log $folder/logs/fortwatcher.log ;fi
# log start
echo "[$(date '+%Y%m%d %H:%M:%S')] fortwatcher (re)started" >> $folder/logs/fortwatcher.log
# stderr to logfile
exec 2>> $folder/logs/fortwatcher.log


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
if [[ $timing == "true" ]] ;then sqlstart=$(date '+%Y%m%d %H:%M:%S.%3N') ;fi

fence="" && webhook="" && map_urll="" && subdomain="" && chatid=""

fence=$(query "select fence from geofences where ST_CONTAINS(st, point($lat,$lon)) and type='mon';")
if [[ ! -z $fence ]] ;then
  webhook=$(query "select ifnull(webhook,'') from webhooks where fence='$fence';")
  subdomain=$(query "select ifnull(subdomain,'') from webhooks where fence='$fence';")
  chatid=$(query "select ifnull(chatid,'') from webhooks where fence='$fence';")
else
  webhook=$unfenced_webhook
  chatid=$unfenced_chatid
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
if [[ $timing == "true" ]] ;then
  sqlstop=$(date '+%Y%m%d %H:%M:%S.%3N')
  sqldiff=$(date -d "$sqlstop $(date -d "$sqlstart" +%s.%N) seconds ago" +%s.%3N)
fi
}

get_address(){
if [[ ! -z $nominatim_url ]] && [[ ! -z $webhook || ! -z $chatid ]] ;then
  if [[ $timing == "true" ]] ;then nomstart=$(date '+%Y%m%d %H:%M:%S.%3N') ;fi
  address=$(curl -s "$nominatim_url/reverse?format=jsonv2&lat=$lat&lon=$lon" | jq -r '.address.road + " " + .address.house_number + ", " + .address.town + .address.village + .address.city')
  if [[ $timing == "true" ]] ;then
    nomstop=$(date '+%Y%m%d %H:%M:%S.%3N')
    nomdiff=$(date -d "$nomstop $(date -d "$nomstart" +%s.%N) seconds ago" +%s.%3N)
  fi
fi
}

get_staticmap(){
if [[ ! -z $tileserver_url ]] && [[ ! -z $webhook || ! -z $chatid ]] ;then
  if [[ $timing == "true" ]] ;then tilestart=$(date '+%Y%m%d %H:%M:%S.%3N') ;fi
  if [[ $type == "pokestop" ]] ;then
    pregen=$(curl -s "$tileserver_url/staticmap/pokemon?lat=$lat&lon=$lon&img=https://raw.githubusercontent.com/nileplumb/PkmnShuffleMap/master/UICONS/pokestop/0.png&pregenerate=true")
  elif [[ $type == "gym" ]] ;then
    pregen=$(curl -s "$tileserver_url/staticmap/pokemon?lat=$lat&lon=$lon&img=https://raw.githubusercontent.com/nileplumb/PkmnShuffleMap/master/UICONS/gym/0.png&pregenerate=true")
  else
    pregen=$(curl -s "$tileserver_url/staticmap/pokemon?lat=$lat&lon=$lon&img=https://i.imgur.com/vB3E31G.png&pregenerate=true")
  fi
  if [[ $timing == "true" ]] ;then
    tilestop=$(date '+%Y%m%d %H:%M:%S.%3N')
    tilediff=$(date -d "$tilestop $(date -d "$tilestart" +%s.%N) seconds ago" +%s.%3N)
  fi
fi
}

discord(){
#echo discord.sh --username \"$username\" --color \"$color\" --avatar \"$avatar\" --thumbnail "$image_url" --image "$tileserver_url/staticmap/pregenerated/$pregen" --webhook-url "$webhook" --footer "Fence: $fence Location: $lat,$lon" --description \"$descript\"
cd $folder && ./discord.sh --username "$username" --color "$color" --avatar "$avatar" --thumbnail "$image_url" --image "$tileserver_url/staticmap/pregenerated/$pregen" --webhook-url "$webhook" --footer "Fence: $fence Location: $lat,$lon" --description "$descript" >> $folder/logs/fortwatcher.log
}

telegram(){
echo ""
echo telegram.sh $verbose\--chatid $chatid --bottoken $telegram_token --title "$username" --text "$text"
echo ""
echo $text
cd $folder && ./telegram.sh $verbose --chatid $chatid --bottoken $telegram_token --title "$username" --text "$text" >> $folder/logs/fortwatcher.log
# --text \"$text\"
}

process(){
for i in $1 ;do
    totstart=$(date '+%Y%m%d %H:%M:%S.%3N')
    if [[ $write_raw == "true" ]] ;then
      echo $totstart >> $folder/logs/raw.log
      echo $line | jq >> $folder/logs/raw.log
    fi
    change_type=$(echo $line| jq -r '.change_type')

    if [[ $change_type == "removal" ]] ;then
      id=$(echo $line| jq -r '.old.id')
      type=$(echo $line| jq -r '.old.type')
      name=$(echo $line| jq -r '.old.name' | sed 's/\"/\\\"/g' | sed 's/\//\\\//g')
      image_url=$(echo $line| jq -r '.old.image_url')
      if [[ $image_url == "null" ]] ;then
        if [[ $type == "pokestop" ]] ;then
          image_url="https://raw.githubusercontent.com/nileplumb/PkmnShuffleMap/master/UICONS/pokestop/0.png"
        elif [[ $type == "gym" ]] ;then
          image_url="https://raw.githubusercontent.com/nileplumb/PkmnShuffleMap/master/UICONS/gym/0.png"
        else
          image_url="https://i.imgur.com/HwRhTBF.png"
        fi
      fi
      lat=$(echo $line| jq -r '.old.location.lat' | xargs printf "%.*f\n" 6)
      lon=$(echo $line| jq -r '.old.location.lon' | xargs printf "%.*f\n" 6)
      get_monfence
      get_address
      get_staticmap
      l2="removed $type id: $id location: $lat,$lon fence: $fence name: \"$name\""
      if [[ ! -z $webhook ]] || [[ ! -z $chatid ]] ;then
        if [[ $timing == "true" ]] ;then hookstart=$(date '+%Y%m%d %H:%M:%S.%3N') ;fi
        l1="Send"
        username="${change_type^} ${type^}"
        color="16711680"
        avatar="https://cdn.discordapp.com/attachments/657164868969037824/1104477454313197578/770615.png"
        descript="Name: **$name**\\n\\n$address\\n[Google](https://www.google.com/maps/search/?api=1&query=$lat,$lon) | [Apple](https://maps.apple.com/maps?daddr=$lat,$lon) | [$map_name]($map_urll/@/$lat/$lon/16)"
        text="[\u200A]($tileserver_url/staticmap/pregenerated/$pregen)\nName: $name\n\n$address\n[Google](https://www.google.com/maps/search/?api=1%26amp;query=$lat,$lon) \| [Apple](https://maps.apple.com/maps?daddr=$lat,$lon) \| [$map_name]($map_urll/@/$lat/$lon/16)"
        if [[ ! -z $webhook ]] ;then discord ;fi
        if [[ ! -z $chatid ]] ;then pregen=$(sed 's/+/%2B/g' <<< $pregen) && telegram ;fi
        if [[ $timing == "true" ]] ;then
          hookstop=$(date '+%Y%m%d %H:%M:%S.%3N')
          hookdiff=$(date -d "$hookstop $(date -d "$hookstart" +%s.%N) seconds ago" +%s.%3N)
        fi
      else
        l1="noHook"
      fi
    elif [[ $change_type == "new" ]] ;then
      id=$(echo $line| jq -r '.new.id')
      type=$(echo $line| jq -r '.new.type')
      name=$(echo $line| jq -r '.new.name' | sed 's/\"/\\\"/g' | sed 's/\//\\\//g')
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
      l2="added $type id: $id location: $lat,$lon fence: $fence name: \"$name\""

      if [[ $ignore_existing_portal == "true" && $type == "portal" ]] ;then
        exists=$(query "select count(id) from (select id from $golbatdb.pokestop where id='$id' union all select id from $golbatdb.gym where id='$id') t group by id;")
        if [[ ! -z $exists ]] ;then
          webhook=""
          chatid=""
          l1="Skipped"
        fi
      fi

      if [[ ! -z $webhook ]] || [[ ! -z $chatid ]] ;then
        if [[ $timing == "true" ]] ;then hookstart=$(date '+%Y%m%d %H:%M:%S.%3N') ;fi
        if [[ -z $l1 ]] ;then l1="Send" ;fi
        username="${change_type^} ${type^}"
        descript="Name: **$name**\n\n$address\n[Google](https://www.google.com/maps/search/?api=1&query=$lat,$lon) | [Apple](https://maps.apple.com/maps?daddr=$lat,$lon) | [$map_name]($map_urll/@/$lat/$lon/16)"
        text="[\u200A]($tileserver_url/staticmap/pregenerated/$pregen)\nName: $name\n\n$address\n[Google](https://www.google.com/maps/search/?api=1%26amp;query=$lat,$lon) \| [Apple](https://maps.apple.com/maps?daddr=$lat,$lon) \| [$map_name]($map_urll/@/$lat/$lon/16)"
        if [[ $type == "portal" ]] ;then
          color="12609532"
          avatar="https://i.imgur.com/HwRhTBF.png"
          if [[ ! -z $webhook ]] ;then discord ;fi
          if [[ ! -z $chatid ]] ;then pregen=$(sed 's/+/%2B/g' <<< $pregen) && telegram ;fi
        else
          color="65280"
          avatar="https://cdn.discordapp.com/attachments/657164868969037824/1104477454313197578/770615.png"
          if [[ ! -z $webhook ]] ;then discord ;fi
          if [[ ! -z $chatid ]] ;then pregen=$(sed 's/+/%2B/g' <<< $pregen) && telegram ;fi
        fi
        if [[ $timing == "true" ]] ;then
          hookstop=$(date '+%Y%m%d %H:%M:%S.%3N')
          hookdiff=$(date -d "$hookstop $(date -d "$hookstart" +%s.%N) seconds ago" +%s.%3N)
        fi
      else
        if [[ -z $l1 ]] ;then l1="noHook" ;fi
      fi
    elif [[ $change_type == "edit" ]] ;then
      edit_types=$(echo $line| jq -r '.edit_types')

      oldid=$(echo $line| jq -r '.old.id')
      oldtype=$(echo $line| jq -r '.old.type')
      oldname=$(echo $line| jq -r '.old.name' | sed 's/\"/\\\"/g' | sed 's/\//\\\//g')
      if [[ $oldname == "null" ]] ;then oldname="Unknown" ;fi
      olddescription=$(echo $line| jq -r '.old.description')
      oldimage_url=$(echo $line| jq -r '.old.image_url')
      oldlat=$(echo $line| jq -r '.old.location.lat' | xargs printf "%.*f\n" 6)
      oldlon=$(echo $line| jq -r '.old.location.lon' | xargs printf "%.*f\n" 6)

      id=$(echo $line| jq -r '.new.id')
      type=$(echo $line| jq -r '.new.type')
      name=$(echo $line| jq -r '.new.name' | sed 's/\"/\\\"/g' | sed 's/\//\\\//g')
      if [[ $name == "null" ]] ;then name="Unknown" ;fi
      description=$(echo $line| jq -r '.new.description')
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

      if [[ ! -z $webhook ]] || [[ ! -z $chatid ]] ;then
        l1="Send"
        if [[ $timing == "true" ]] ;then hookstart=$(date '+%Y%m%d %H:%M:%S.%3N') ;fi
        if [[ $oldname != $name ]] ;then
          l2="edit $type name id: $id fence: $fence name: \"$name\" oldname: \"$oldname\""
          if [[ ! -z $webhook ]] ;then cd $folder && ./discord.sh --username "${type^} name change" --color "15237395" --avatar "https://cdn.discordapp.com/attachments/657164868969037824/1104477454313197578/770615.png" --thumbnail "$image_url" --image "$tileserver_url/staticmap/pregenerated/$pregen" --webhook-url "$webhook" --footer "Fence: $fence Location: $lat,$lon" --description "Old: $oldname\nNew: **$name**\n\n$address\n[Google](https://www.google.com/maps/search/?api=1&query=$lat,$lon) | [Apple](https://maps.apple.com/maps?daddr=$lat,$lon) | [$map_name]($map_urll/@/$lat/$lon/16)" >> $folder/logs/fortwatcher.log ;fi
          if [[ ! -z $chatid ]] ;then pregen=$(sed 's/+/%2B/g' <<< $pregen) && cd $folder && ./telegram.sh $verbose\--chatid $chatid --bottoken $telegram_token --title "${type^} name change" --text "[\u200A]($tileserver_url/staticmap/pregenerated/$pregen)\nOld: $oldname\nNew: $name\n\n$address\n[Google](https://www.google.com/maps/search/?api=1%26amp;query=$lat,$lon) \| [Apple](https://maps.apple.com/maps?daddr=$lat,$lon) \| [$map_name]($map_urll/@/$lat/$lon/16)" >> $folder/logs/fortwatcher.log ;fi
        elif [[ $oldlat != $lat || $oldlon != $lon ]] ;then
          l2="edit $type location id: $id fence: $fence name: \"$name\" oldloc: $oldlat,$oldlon"
          if [[ ! -z $webhook ]] ;then cd $folder && ./discord.sh --username "${type^} location change" --color "15237395" --avatar "https://cdn.discordapp.com/attachments/657164868969037824/1104477454313197578/770615.png" --thumbnail "$image_url" --image "$tileserver_url/staticmap/pregenerated/$pregen" --webhook-url "$webhook" --footer "Fence: $fence Location: $lat,$lon" --description "Name: **$name**\nOld: $oldlat,$oldlon\nNew: \`$lat,$lon\`\n\n$address\n[Google](https://www.google.com/maps/search/?api=1&query=$lat,$lon) | [Apple](https://maps.apple.com/maps?daddr=$lat,$lon) | [$map_name]($map_urll/@/$lat/$lon/16)" >> $folder/logs/fortwatcher.log ;fi
          if [[ ! -z $chatid ]] ;then pregen=$(sed 's/+/%2B/g' <<< $pregen) && cd $folder && ./telegram.sh $verbose\--chatid $chatid --bottoken $telegram_token --title "${type^} location change" --text "[\u200A]($tileserver_url/staticmap/pregenerated/$pregen)\nOld: $oldlat,oldlon\nNew: $lat,$lon\n\n$address\n[Google](https://www.google.com/maps/search/?api=1%26amp;query=$lat,$lon) \| [Apple](https://maps.apple.com/maps?daddr=$lat,$lon) \| [$map_name]($map_urll/@/$lat/$lon/16)" >> $folder/logs/fortwatcher.log ;fi
        elif [[ $oldtype != $type ]] ;then
          l2="edit oldtype conversion name id: $id fence: $fence name: \"$name\" newtype: $type"
          if [[ ! -z $webhook ]] ; then cd $folder && ./discord.sh --username "Conversion" --color "15237395" --avatar "https://cdn.discordapp.com/attachments/657164868969037824/1104477454313197578/770615.png" --thumbnail "$image_url" --image "$tileserver_url/staticmap/pregenerated/$pregen" --webhook-url "$webhook" --footer "Fence: $fence Location: $lat,$lon" --description "Name: **$name**\nOld type: $oldtype\nNew type: **$type**\n\n$address\n[Google](https://www.google.com/maps/search/?api=1&query=$lat,$lon) | [Apple](https://maps.apple.com/maps?daddr=$lat,$lon) | [$map_name]($map_urll/@/$lat/$lon/16)" >> $folder/logs/fortwatcher.log ;fi
          if [[ ! -z $chatid ]] ;then pregen=$(sed 's/+/%2B/g' <<< $pregen) && cd $folder && ./telegram.sh $verbose\--chatid $chatid --bottoken $telegram_token --title "Conversion" --text "[\u200A]($tileserver_url/staticmap/pregenerated/$pregen)\nOld: $oldtype\nNew: $type\n\n$address\n[Google](https://www.google.com/maps/search/?api=1%26amp;query=$lat,$lon) \| [Apple](https://maps.apple.com/maps?daddr=$lat,$lon) \| [$map_name]($map_urll/@/$lat/$lon/16)" >> $folder/logs/fortwatcher.log ;fi
        elif [[ $oldimage_url != $image_url ]] ;then
          l1="Skipped"
          l2="edit $type image id: $id fence: $fence name: \"$name\""
        elif [[ $olddescription != $description ]] ;then
          l1="Skipped"
          l2="edit $type description id: $id fence: $fence name: \"$name\""
        elif [[ $oldid != $id ]] ;then
          l1="Skipped"
          l2="edit $type id id: $id fence: $fence name: \"$name\""
        else
          l2="THIS SHOULD NOT HAPPEN, what was edited?"
          echo $line| jq >> $folder/logs/fortwatcher.log
        fi
        if [[ $timing == "true" ]] ;then
          hookstop=$(date '+%Y%m%d %H:%M:%S.%3N')
          hookdiff=$(date -d "$hookstop $(date -d "$hookstart" +%s.%N) seconds ago" +%s.%3N)
        fi
      else
        l1="noHook"
        if [[ $oldname != $name ]] ;then
          l2="edit $type name id: $id fence: $fence name: \"$name\" oldname: \"$oldname\""
        elif [[ $oldlat != $lat || $oldlon != $lon ]] ;then
          l2="edit $type location id: $id fence: $fence name: \"$name\" oldloc: $oldlat,$oldlon"
        elif [[ $oldtype != $type ]] ;then
          l2="edit oldtype conversion name id: $id fence: $fence name: \"$name\" newtype: $type"
        elif [[ $oldimage_url != $image_url ]] ;then
          l2="edit $type image id: $id fence: $fence name: \"$name\""
        elif [[ $olddescription != $description ]] ;then
          l2="edit $type description id: $id fence: $fence name: \"$name\""
        elif [[ $oldid != $id ]] ;then
          l2="edit $type id id: $id fence: $fence name: \"$name\""
        else
          l2="THIS SHOULD NOT HAPPEN, what was edited?"
          echo $line| jq >> $folder/logs/fortwatcher.log
        fi
      fi
    else
      echo "THIS SHOULD NOT HAPPEN" >> $folder/logs/fortwatcher.log
      echo $line | jq >> $folder/logs/fortwatcher.log
    fi
    totstop=$(date '+%Y%m%d %H:%M:%S.%3N')
    totdiff=$(date -d "$totstop $(date -d "$totstart" +%s.%N) seconds ago" +%s.%3N)
    echo "[$(date '+%Y%m%d %H:%M:%S')] $l1 $l2 time: $totdiff s" >> $folder/logs/fortwatcher.log

    if [[ $timing == "true" ]] ;then
      echo "[$(date '+%Y%m%d %H:%M:%S.%3N')] $id Total $totdiff sql $sqldiff nominatim $nomdiff tileserver $tilediff webhook $hookdiff" >> $folder/logs/timing.log
    fi
done
}

## execution

# create table
query "CREATE TABLE IF NOT EXISTS webhooks (area varchar(40) NOT NULL,fence varchar(40) DEFAULT Area,webhook varchar(150),subdomain varchar(20)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;"
# table updates
query "alter table webhooks add column if not exists subdomain varchar(40), add column if not exists chatid varchar(40), add column if not exists addPortal tinyint(1) default 1, add column if not exists addFort tinyint(1) default 1, add column if not exists editName tinyint(1) default 1, add column if not exists editLocation tinyint(1) default 1, add column if not exists editDescription tinyint(1) default 0, add column if not exists editImage tinyint(1) default 0, add column if not exists removeFort tinyint(1) default 1, add column if not exists convertFort tinyint(1) default 1, add column if not exists editNameASadded tinyint(1) default 0;"

# set telegram loglevel
if [[ $telegram_verbose_logging == "true" ]] ;then verbose="--verbose " ;fi

# start receiver and process
while true ;do
  if [[ $timing == "true" ]] ;then echo "[$(date '+%Y%m%d %H:%M:%S.%3N')] Main loop" >> $folder/logs/timing.log ;fi
  while read -r line ;do
    process $line &
  done < <(ncat -l $receiver_port < response.txt | grep { | jq -c '.[] | .message')
done
