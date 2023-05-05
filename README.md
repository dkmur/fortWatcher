# fortWatcher

WIP  
check Golbat fort_update webhook against blisseydb mon area fences and send discord notification 

- install jq
- install ncat
- copy config and fill it out
- add golbat webhook:  
```
[[webhooks]]
url = "http://127.0.0.1:fortWatcher_receiver_port"
types = ["fort_update"]
```
- fire it up like `pm2 start stops.sh --name fortWatcher`
- after first start blisseydb table webhooks will be created. Add your mon area/fence names with their respective discord channel webhook
