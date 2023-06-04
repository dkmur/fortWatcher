#!/bin/bash

folder="$(pwd)"
source $folder/config.ini

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
  for i in $(query "select ifnull(webhook,''),ifnull(subdomain,''),ifnull(chatid,''),addPortal,addFort,editName,editLocation,editDescription,editImage,removeFort,convertFort,editNameASadded,area from webhooks where fence='$fence';" | sed 's/\t/dkmurrie/g') ;do
    webhook=$(echo $i | awk -F 'dkmurrie' '{print $1}')
    subdomain=$(echo $i | awk -F 'dkmurrie' '{print $2}')
    chatid=$(echo $i | awk -F 'dkmurrie' '{print $3}')
    addPortal=$(echo $i | awk -F 'dkmurrie' '{print $4}')
    addFort=$(echo $i | awk -F 'dkmurrie' '{print $5}')
    editName=$(echo $i | awk -F 'dkmurrie' '{print $6}')
    editLocation=$(echo $i | awk -F 'dkmurrie' '{print $7}')
    editDescription=$(echo $i | awk -F 'dkmurrie' '{print $8}')
    editImage=$(echo $i | awk -F 'dkmurrie' '{print $9}')
    removeFort=$(echo $i | awk -F 'dkmurrie' '{print $10}')
    convertFort=$(echo $i | awk -F 'dkmurrie' '{print $11}')
    editNameASadded=$(echo $i | awk -F 'dkmurrie' '{print $12}')
    area=$(echo $i | awk -F 'dkmurrie' '{print $13}')
  done
# Fences added to blissey but not yet in webhooks table
  if [[ -z $addPortal ]] ;then
    echo "[$(date '+%Y%m%d %H:%M:%S')] mon fence was added to blissey but not to webhooks table, handling as unfenced !!" >> $folder/logs/fortwatcher.log
    webhook=$unfenced_webhook
    chatid=$unfenced_chatid
    addPortal=1
    addFort=1
    editName=1
    editLocation=1
    editDescription=1
    editImage=1
    removeFort=1
    convertFort=1
    editNameASadded=0
  fi
else
  webhook=$unfenced_webhook
  chatid=$unfenced_chatid
  fence="unfenced"
  area="unfenced"
  addPortal=1
  addFort=1
  editName=1
  editLocation=1
  editDescription=1
  editImage=1
  removeFort=1
  convertFort=1
  editNameASadded=0
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
if [[ ! -z $nominatim_url ]] ;then
  if [[ $timing == "true" ]] ;then nomstart=$(date '+%Y%m%d %H:%M:%S.%3N') ;fi
  address=$(curl -s "$nominatim_url/reverse?format=jsonv2&lat=$lat&lon=$lon" | jq -r '.address.road + " " + .address.house_number + ", " + .address.town + .address.village + .address.city')
  if [[ $timing == "true" ]] ;then
    nomstop=$(date '+%Y%m%d %H:%M:%S.%3N')
    nomdiff=$(date -d "$nomstop $(date -d "$nomstart" +%s.%N) seconds ago" +%s.%3N)
  fi
fi
}

get_staticmap(){
if [[ ! -z $tileserver_url ]] ;then
  if [[ $timing == "true" ]] ;then tilestart=$(date '+%Y%m%d %H:%M:%S.%3N') ;fi
  if [[ $type == "pokestop" ]] ;then
    pregen=$(curl -s "$tileserver_url/staticmap/pokemon?lat=$lat&lon=$lon&img=https://raw.githubusercontent.com/nileplumb/PkmnShuffleMap/master/UICONS/pokestop/0.png&pregenerate=true")
  elif [[ $type == "gym" ]] ;then
    pregen=$(curl -s "$tileserver_url/staticmap/pokemon?lat=$lat&lon=$lon&img=https://raw.githubusercontent.com/nileplumb/PkmnShuffleMap/master/UICONS/gym/0.png&pregenerate=true")
  else
    pregen=$(curl -s "$tileserver_url/staticmap/pokemon?lat=$lat&lon=$lon&img=https://raw.githubusercontent.com/nileplumb/PkmnShuffleMap/master/UICONS/misc/portal.png&pregenerate=true")
  fi
  if [[ ! -z $chatid ]] ;then tpregen=$(sed 's/+/%2B/g' <<< $pregen) ;fi
  if [[ $write_raw == "true" ]] ;then echo "$id $pregen" >> $folder/logs/raw.log ;fi
  if [[ $timing == "true" ]] ;then
    tilestop=$(date '+%Y%m%d %H:%M:%S.%3N')
    tilediff=$(date -d "$tilestop $(date -d "$tilestart" +%s.%N) seconds ago" +%s.%3N)
  fi
fi
}

discord(){
cd $folder && ./discord.sh --username "$username" --color "$color" --avatar "$avatar" --thumbnail "$image_url" --image "$tileserver_url/staticmap/pregenerated/$pregen" --webhook-url "$webhook" --footer "Fence: $fence Location: $lat,$lon" --description "$descript" >> $folder/logs/fortwatcher.log
}

telegram(){
cd $folder && ./telegram.sh $verbose --chatid $chatid --bottoken $telegram_token --title "$username" --text "$text" >> $folder/logs/fortwatcher.log
}

process(){
for i in $1 ;do
    totstart=$(date '+%Y%m%d %H:%M:%S.%3N')
    Sreceive=0 && Sstopremove=0 && Sgymremove=0 && Ssend=0 && Snohook=0 && Sskip=0 && Sstopadd=0 && Sgymadd=0 && Sportaladd=0 && Snamedit=0 && Slocedit=0 && Sconvert=0 && Simageedit=0 && Sdescedit=0
    Sreceive=1
    if [[ $write_raw == "true" ]] ;then
      echo "[$totstart] processing started" >> $folder/logs/raw.log
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
          image_url="https://raw.githubusercontent.com/nileplumb/PkmnShuffleMap/master/UICONS/misc/pokestop.png"
        elif [[ $type == "gym" ]] ;then
          image_url="https://raw.githubusercontent.com/nileplumb/PkmnShuffleMap/master/UICONS/misc/gym.png"
        else
          image_url="https://raw.githubusercontent.com/nileplumb/PkmnShuffleMap/master/UICONS/misc/portal.png"
        fi
      fi
      lat=$(echo $line| jq -r '.old.location.lat' | xargs printf "%.*f\n" 6)
      lon=$(echo $line| jq -r '.old.location.lon' | xargs printf "%.*f\n" 6)
      if [[ $type == "pokestop" ]] ;then Sstopremove=1 ;elif [[ $type == "gym" ]] ;then Sgymremove=1 ;fi
      get_monfence
      l2="removed $type id: $id fence: $fence name: \"$name\""
      if [[ $removeFort == "1" ]] ;then
        if [[ ! -z $webhook ]] || [[ ! -z $chatid ]] ;then
          get_address && get_staticmap
          if [[ $timing == "true" ]] ;then hookstart=$(date '+%Y%m%d %H:%M:%S.%3N') ;fi
          l1="Send" && Ssend=1
          if [[ ! -z $chatid ]] ;then tname=$(echo $name | sed 's/(/\\(/g' | sed 's/)/\\)/g') ;fi
          username="${change_type^} ${type^}"
          color="16711680"
          avatar="https://cdn.discordapp.com/attachments/657164868969037824/1104477454313197578/770615.png"
          descript="Name: **$name**\\n\\n$address\\n[Google](https://www.google.com/maps/search/?api=1&query=$lat,$lon) | [Apple](https://maps.apple.com/maps?daddr=$lat,$lon) | [$map_name]($map_urll/@/$lat/$lon/16)"
          text="[\u200A]($tileserver_url/staticmap/pregenerated/$tpregen)\nName: $tname\n\n$address\n[Google](https://www.google.com/maps/search/?api=1%26amp;query=$lat,$lon) \| [Apple](https://maps.apple.com/maps?daddr=$lat,$lon) \| [$map_name]($map_urll/@/$lat/$lon/16)"
          if [[ ! -z $webhook ]] ;then discord ;fi
          if [[ ! -z $chatid ]] ;then telegram ;fi
          if [[ $timing == "true" ]] ;then
            hookstop=$(date '+%Y%m%d %H:%M:%S.%3N')
            hookdiff=$(date -d "$hookstop $(date -d "$hookstart" +%s.%N) seconds ago" +%s.%3N)
          fi
        else
          l1="noHook" && Snohook=1
        fi
      else
        l1="Skip" && Sskip=1
      fi
    elif [[ $change_type == "new" ]] ;then
      id=$(echo $line| jq -r '.new.id')
      type=$(echo $line| jq -r '.new.type')
      name=$(echo $line| jq -r '.new.name' | sed 's/\"/\\\"/g' | sed 's/\//\\\//g')
      if [[ $name == "null" ]] ;then name="Unknown" ;fi
      description=$(echo $line| jq -r '.new.description' | sed 's/\"/\\\"/g' | sed 's/\//\\\//g')
      if [[ $description == "null" ]] ;then description="Unknown" ;fi
      image_url=$(echo $line| jq -r '.new.image_url')
      if [[ $image_url == "null" ]] ;then
        if [[ $type == "pokestop" ]] ;then
          image_url="https://raw.githubusercontent.com/nileplumb/PkmnShuffleMap/master/UICONS/misc/pokestop.png"
        elif [[ $type == "gym" ]] ;then
          image_url="https://raw.githubusercontent.com/nileplumb/PkmnShuffleMap/master/UICONS/misc/gym.png"
        else
          image_url="https://raw.githubusercontent.com/nileplumb/PkmnShuffleMap/master/UICONS/misc/portal.png"
        fi
      fi
      lat=$(echo $line| jq -r '.new.location.lat' | xargs printf "%.*f\n" 6)
      lon=$(echo $line| jq -r '.new.location.lon' | xargs printf "%.*f\n" 6)
      if [[ $type == "pokestop" ]] ;then Sstopadd=1 ;elif [[ $type == "gym" ]] ;then Sgymadd=1 ;elif [[ $type == "portal" ]] ;then Sportaladd=1 ;fi
      get_monfence
      l2="added $type id: $id fence: $fence name: \"$name\""

      if [[ $ignore_existing_portal == "true" && $type == "portal" ]] ;then
        exists=$(query "select count(id) from (select id from $golbatdb.pokestop where id='$id' union all select id from $golbatdb.gym where id='$id') t group by id;")
        if [[ ! -z $exists ]] ;then
          webhook=""
          chatid=""
          l1="Skip" && Sskip=1
        fi
      fi

      if [[ $addPortal  == "1" || $addFort = "1" ]] ;then
        if [[ ! -z $webhook ]] || [[ ! -z $chatid ]] ;then
          get_address && get_staticmap
          if [[ $timing == "true" ]] ;then hookstart=$(date '+%Y%m%d %H:%M:%S.%3N') ;fi
          if [[ -z $l1 ]] ;then l1="Send" && Ssend=1 ;fi
          amessage="Name: $name"
          if [[ $editDescription == "1" ]] ;then amessage="${amessage}\n\nDescription:\n$description" ;fi
          tamessage=$(echo $amessage | sed 's/(/\\(/g' | sed 's/)/\\)/g')
          username="${change_type^} ${type^}"
          descript="$amessage\n\n$address\n[Google](https://www.google.com/maps/search/?api=1&query=$lat,$lon) | [Apple](https://maps.apple.com/maps?daddr=$lat,$lon) | [$map_name]($map_urll/@/$lat/$lon/16)"
          text="[\u200A]($tileserver_url/staticmap/pregenerated/$tpregen)\n$tamessage\n\n$address\n[Google](https://www.google.com/maps/search/?api=1%26amp;query=$lat,$lon) \| [Apple](https://maps.apple.com/maps?daddr=$lat,$lon) \| [$map_name]($map_urll/@/$lat/$lon/16)"
          if [[ $type == "portal" ]] ;then
            color="12609532"
            avatar="https://raw.githubusercontent.com/nileplumb/PkmnShuffleMap/master/UICONS/misc/portal.png"
            if [[ ! -z $webhook && $addPortal == "1" ]] ;then discord ;fi
            if [[ ! -z $chatid && $addPortal == "1" ]] ;then telegram ;fi
          else
            if [[ $editNameASadded == "0" ]] ;then
              color="65280"
              avatar="https://cdn.discordapp.com/attachments/657164868969037824/1104477454313197578/770615.png"
              if [[ ! -z $webhook && $addFort == "1" ]] ;then discord ;fi
              if [[ ! -z $chatid && $addFort == "1" ]] ;then telegram ;fi
            else
              l1="Skip" && Sskip=1
            fi
          fi
          if [[ $timing == "true" ]] ;then
            hookstop=$(date '+%Y%m%d %H:%M:%S.%3N')
            hookdiff=$(date -d "$hookstop $(date -d "$hookstart" +%s.%N) seconds ago" +%s.%3N)
          fi
        else
          if [[ -z $l1 ]] ;then l1="noHook" && Snohook=1 ;fi
        fi
      else
        l1="Skip" && Sskip=1
      fi
    elif [[ $change_type == "edit" ]] ;then
      edit_types=$(echo $line| jq -r '.edit_types')

      oldid=$(echo $line| jq -r '.old.id')
      oldtype=$(echo $line| jq -r '.old.type')
      oldname=$(echo $line| jq -r '.old.name' | sed 's/\"/\\\"/g' | sed 's/\//\\\//g')
      if [[ $oldname == "null" ]] ;then oldname="Unknown" ;fi
      olddescription=$(echo $line| jq -r '.old.description' | sed 's/\"/\\\"/g' | sed 's/\//\\\//g')
      if [[ $olddescription == "null" ]] ;then olddescription="Unknown" ;fi
      oldimage_url=$(echo $line| jq -r '.old.image_url')
      oldlat=$(echo $line| jq -r '.old.location.lat' | xargs printf "%.*f\n" 6)
      oldlon=$(echo $line| jq -r '.old.location.lon' | xargs printf "%.*f\n" 6)

      id=$(echo $line| jq -r '.new.id')
      type=$(echo $line| jq -r '.new.type')
      name=$(echo $line| jq -r '.new.name' | sed 's/\"/\\\"/g' | sed 's/\//\\\//g')
      if [[ $name == "null" ]] ;then name="Unknown" ;fi
      description=$(echo $line| jq -r '.new.description' | sed 's/\"/\\\"/g' | sed 's/\//\\\//g')
      if [[ $description == "null" ]] ;then description="Unknown" ;fi
      image_url=$(echo $line| jq -r '.new.image_url')
      if [[ $image_url == "null" ]] ;then
        if [[ $type == "pokestop" ]] ;then
          image_url="https://raw.githubusercontent.com/nileplumb/PkmnShuffleMap/master/UICONS/misc/pokestop.png"
        elif [[ $type == "gym" ]] ;then
          image_url="https://raw.githubusercontent.com/nileplumb/PkmnShuffleMap/master/UICONS/misc/gym.png"
        else
          image_url="https://raw.githubusercontent.com/nileplumb/PkmnShuffleMap/master/UICONS/misc/portal.png"
        fi
      fi
      lat=$(echo $line| jq -r '.new.location.lat' | xargs printf "%.*f\n" 6)
      lon=$(echo $line| jq -r '.new.location.lon' | xargs printf "%.*f\n" 6)

      get_monfence

      if [[ $editName == "1" || $editLocation == "1" || $editImage == "1" || $editDescription == "1" || $convertFort == "1" ]] ;then
        if [[ ! -z $webhook ]] || [[ ! -z $chatid ]] ;then get_address && get_staticmap ;fi
        if [[ $timing == "true" ]] ;then hookstart=$(date '+%Y%m%d %H:%M:%S.%3N') ;fi
        color="15237395"
        avatar="https://cdn.discordapp.com/attachments/657164868969037824/1104477454313197578/770615.png"

        elog="(" && etitle="("
        if [[ $oldname != $name ]] ;then
          elog="${elog}Name"
          Snamedit=1
          if [[ $editName == "1" ]] ;then
            l1="Send" && Ssend=1
            emessage="Name\nOld: $oldname\nNew: $name"
            etitle="${etitle}Name"
          fi
        else
          emessage="Name: $name"
        fi
        if [[ $oldlat != $lat || $oldlon != $lon ]] ;then
          elog="${elog}Location"
          Slocedit=1
          if [[ $editLocation == "1" ]] ;then
            l1="Send" && Ssend=1
            emessage="${emessage}\n\nLocation\nOld: $oldlat,$oldlon\nNew: $lat,$lon"
            etitle="${etitle}Location"
          fi
        fi
        if [[ $oldtype != $type ]] ;then
          elog="${elog}Conversion"
          Sconvert=1
          if [[ $convertFort == "1" ]] ;then
            l1="Send" && Ssend=1
            emessage="${emessage}\n\nConversion\nFrom: $oldtype\nTo: $type"
            etitle="${etitle}Conversion"
          fi
        fi
        if [[ $oldimage_url != $image_url ]] ;then
          elog="${elog}Image"
          Simageedit=1
          if [[ $editImage == "1" ]] ;then
            l1="Send" && Ssend=1
            etitle="${etitle}Image"
          fi
        fi
        if [[ $olddescription != $description ]] ;then
          elog="${elog}Description"
          Sdescedit=1
          if [[ $editDescription == "1" ]] ;then
            l1="Send" && Ssend=1
            emessage="${emessage}\n\nDescription\nOld: $olddescription\nNew: $description"
            etitle="${etitle}Description"
          fi
        fi
        etitle="${etitle})" && etitle=$(echo $etitle | sed 's/\([A-Z]\)/,\1/g' | sed 's/(,/(/g')
        elog="${elog})" && elog=$(echo $elog | sed 's/\([A-Z]\)/,\1/g' | sed 's/(,/(/g')

        l2="edit $type id: $id fence: $fence name: \"$name\""
        if [[ $etitle == "()" ]] ;then
          l1="Skip" && Sskip=1
        elif [[ -z $webhook ]] && [[ -z $chatid ]] ;then
          l1="noHook" && Snohook=1
        else
          descript="$emessage\n\n$address\n[Google](https://www.google.com/maps/search/?api=1&query=$lat,$lon) | [Apple](https://maps.apple.com/maps?daddr=$lat,$lon) | [$map_name]($map_urll/@/$lat/$lon/16)"
          temessage=$(echo $emessage | sed 's/(/\\(/g' | sed 's/)/\\)/g')
          text="[\u200A]($tileserver_url/staticmap/pregenerated/$tpregen)\n$temessage\n\n$address\n[Google](https://www.google.com/maps/search/?api=1%26amp;query=$lat,$lon) \| [Apple](https://maps.apple.com/maps?daddr=$lat,$lon) \| [$map_name]($map_urll/@/$lat/$lon/16)"
          if [[ $oldname != $name ]] && [[ $editNameASadded == "1" ]] ;then
            color="65280"
            username="New ${type^}"
            if [[ ! -z $webhook ]] ;then discord ;fi
            if [[ ! -z $chatid  ]] ;then telegram ;fi
          else
            username="Edit ${type^} $etitle"
            if [[ ! -z $webhook ]] ;then username="Edit ${type^} $etitle" && discord ;fi
            if [[ ! -z $chatid  ]] ;then tetitle=$(echo $etitle | sed 's/(/\\(/g' | sed 's/)/\\)/g') && username="Edit ${type^} $tetitle" && telegram ;fi
          fi
        fi
        if [[ $timing == "true" ]] ;then
          hookstop=$(date '+%Y%m%d %H:%M:%S.%3N')
          hookdiff=$(date -d "$hookstop $(date -d "$hookstart" +%s.%N) seconds ago" +%s.%3N)
        fi
      fi

    else
      echo "THIS SHOULD NOT HAPPEN" >> $folder/logs/fortwatcher.log
      echo $line | jq >> $folder/logs/fortwatcher.log
    fi
    totstop=$(date '+%Y%m%d %H:%M:%S.%3N')
    totdiff=$(date -d "$totstop $(date -d "$totstart" +%s.%N) seconds ago" +%s.%3N)
    echo "[$(date '+%Y%m%d %H:%M:%S')] $l1 $l2 time: ${totdiff}s $elog" >> $folder/logs/fortwatcher.log

    if [[ $timing == "true" ]] ;then
      echo "[$(date '+%Y%m%d %H:%M:%S.%3N')] $id Total $totdiff sql $sqldiff nominatim $nomdiff tileserver $tilediff webhook $hookdiff" >> $folder/logs/timing.log
    fi

    if [[ $write_stats == "true" ]] ;then query "INSERT INTO stats_forts (datetime,rpl,area,fence,webhook_received,webhook_send,webhook_skip,webhook_nohook,stop_remove,gym_remove,fort_conversion,portal_add,stop_add,gym_add,name_edit,location_edit,image_edit,description_edit) VALUES (concat(date(now() - interval 0 minute),' ', (SEC_TO_TIME((TIME_TO_SEC(time(now() - interval 0 minute)) DIV 900) * 900))),15,'$area','$fence',$Sreceive,$Ssend,$Sskip,$Snohook,$Sstopremove,$Sgymremove,$Sconvert,$Sportaladd,$Sstopadd,$Sgymadd,$Snamedit,$Slocedit,$Simageedit,$Sdescedit) ON DUPLICATE KEY UPDATE webhook_received=webhook_received+VALUES(webhook_received),webhook_send=webhook_send+VALUES(webhook_send),webhook_skip=webhook_skip+VALUES(webhook_skip),webhook_nohook=webhook_nohook+VALUES(webhook_nohook),stop_remove=stop_remove+VALUES(stop_remove),gym_remove=gym_remove+VALUES(gym_remove),fort_conversion=fort_conversion+VALUES(fort_conversion),portal_add=portal_add+VALUES(portal_add),stop_add=stop_add+VALUES(stop_add),gym_add=gym_add+VALUES(gym_add),name_edit=name_edit+VALUES(name_edit),location_edit=location_edit+VALUES(location_edit),image_edit=image_edit+VALUES(image_edit),description_edit=description_edit+VALUES(description_edit);" ;fi
done
}

## execution

## Logging
mkdir -p $folder/logs
# rename log
if [[ -f $folder/logs/stops.log ]] ;then mv $folder/logs/stops.log $folder/logs/fortwatcher.log ;fi
# log start
echo "[$(date '+%Y%m%d %H:%M:%S')] fortwatcher (re)started" >> $folder/logs/fortwatcher.log
# stderr to logfile
exec 2>> $folder/logs/fortwatcher.log

# create table wehooks
query "CREATE TABLE IF NOT EXISTS webhooks (area varchar(40) NOT NULL,fence varchar(40) DEFAULT Area,webhook varchar(150),subdomain varchar(20)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;"
# table updates webhooks
query "alter table webhooks add column if not exists subdomain varchar(40), add column if not exists chatid varchar(40), add column if not exists addPortal tinyint(1) default 1, add column if not exists addFort tinyint(1) default 1, add column if not exists editName tinyint(1) default 1, add column if not exists editLocation tinyint(1) default 1, add column if not exists editDescription tinyint(1) default 0, add column if not exists editImage tinyint(1) default 0, add column if not exists removeFort tinyint(1) default 1, add column if not exists convertFort tinyint(1) default 1, add column if not exists editNameASadded tinyint(1) default 0;"
# create table stats_forts
query "CREATE TABLE IF NOT EXISTS stats_forts (datetime datetime NOT NULL,rpl smallint(6) NOT NULL,area varchar(40) NOT NULL,fence varchar(40) DEFAULT Area,webhook_received int DEFAULT 0,webhook_send int DEFAULT 0,webhook_skip int DEFAULT 0,webhook_nohook int DEFAULT 0,stop_remove int DEFAULT 0,gym_remove int DEFAULT 0,fort_conversion int DEFAULT 0,portal_add int DEFAULT 0,stop_add int DEFAULT 0,gym_add int DEFAULT 0,name_edit int DEFAULT 0,location_edit int DEFAULT 0,image_edit int DEFAULT 0,description_edit int DEFAULT 0,PRIMARY KEY (datetime,rpl,area,fence)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;"

# checks
if [[ -z $(which curl) ]] ;then echo "[$(date '+%Y%m%d %H:%M:%S')] curl not installed, exit script" >> $folder/logs/fortwatcher.log && exit ;fi
if [[ -z $(which ncat) ]] ;then echo "[$(date '+%Y%m%d %H:%M:%S')] ncat not installed, exit script" >> $folder/logs/fortwatcher.log && exit ;fi
if [[ -z $(which jq) ]] ;then echo "[$(date '+%Y%m%d %H:%M:%S')] jq not installed, exit script" >> $folder/logs/fortwatcher.log && exit ;fi
if [[ -z $(which ts) ]] ;then echo "[$(date '+%Y%m%d %H:%M:%S')] ts (moreutils) not installed, exit script" >> $folder/logs/fortwatcher.log && exit ;fi

# set telegram loglevel
if [[ $telegram_verbose_logging == "true" ]] ;then verbose="--verbose " ;fi

# start receiver and process
while true ;do
  if [[ $timing == "true" ]] ;then echo "[$(date '+%Y%m%d %H:%M:%S.%3N')] Main loop" >> $folder/logs/timing.log ;fi
  while read -r line ;do
    process $line &
  done < <(ncat -l -p $receiver_port -i 100ms 2> /dev/null | if [[ $write_raw == "true" ]] ;then tee >(ts '[%Y%m%d %H:%M:%.S]' >> $folder/logs/raw.log) | grep { | jq -c '.[] | .message' && echo "" >> $folder/logs/raw.log ;else grep { | jq -c '.[] | .message' ;fi)
done
