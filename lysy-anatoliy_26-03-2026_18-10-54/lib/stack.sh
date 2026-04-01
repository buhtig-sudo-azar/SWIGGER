#!/bin/bash
start_flask() {   
local port=$1
local app_path=$2
python3 "$app_path" &
PIDS+=($!)
}
start_nginx()  {
 local port=$1
 local conf_path=$2
 nginx -c "$conf_path" &
 PIDS+=($!)
   }
