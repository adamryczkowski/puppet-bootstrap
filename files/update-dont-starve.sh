#!/bin/bash

steamcmd +login anonymous +force_install_dir /opt/dst  +app_update 343050 validate +quit
cd /opt/dst/bin 
cp ~/.klei/DoNotStarveTogether/WAM/dedicated_server_mods_setup.lua  /opt/dst/mods/dedicated_server_mods_setup.lua

/opt/dst/bin/dontstarve_dedicated_server_nullrenderer -only_update_server_mods -cluster WAM -shard 13

