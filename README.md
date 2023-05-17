# fortWatcher

![image](https://github.com/dkmur/fortWatcher/assets/42545952/55687bb8-ff41-411e-88f8-7c1be933d670)



Webhook receiver for Golbat(fort_update) and intelwatcher(new portals).  
Updates will be mapped to blisseydb mon area fences and discord/telegram notification send.

- install jq
- install ncat
- copy config and fill it out
- add golbat webhook:  
```
[[webhooks]]
url = "http://127.0.0.1:fortWatcher_receiver_port"
types = ["fort_update"]
```
- check/add tileserver template pokemon.json, should be:  
```
{
    "style": "osm-bright",
    "latitude": #(lat),
    "longitude": #(lon),
    "zoom": 16,
    "width": 500,
    "height": 300,
    "scale": 2,
    "markers": [
        {
          "url": "#(img)",
          "latitude": #(lat),
          "longitude": #(lon),
          "width": 30,
          "height": 30
        }
    ]
}
```
- fire it up like `pm2 start fortwatcher.sh --name fortWatcher`
- after first start blisseydb table webhooks will be created. Add your mon area/fence names with their respective discord channel webhook and/or telegram chatid.
