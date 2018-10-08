#!/bin/bash

if [[ "$1" == "new" ]]; then
    echo "REGENERATING WORLDS"
    rm -rf /home/adam/.klei/DoNotStarveTogether/WAM/Main/backup
    rm -rf /home/adam/.klei/DoNotStarveTogether/WAM/Main/save
    rm -rf /home/adam/.klei/DoNotStarveTogether/WAM/11/backup
    rm -rf /home/adam/.klei/DoNotStarveTogether/WAM/11/save
    rm -rf /home/adam/.klei/DoNotStarveTogether/WAM/12/backup
    rm -rf /home/adam/.klei/DoNotStarveTogether/WAM/12/save
    rm -rf /home/adam/.klei/DoNotStarveTogether/WAM/13/backup
    rm -rf /home/adam/.klei/DoNotStarveTogether/WAM/13/save
fi

byobu-tmux new-session -s dst -d
#byobu-tmux set-option -t dst --default-path /opt/games/dontstarve/bin
byobu-tmux new-window -t dst -d -n 'Main' 'cd /opt/dst/bin; ./dontstarve_dedicated_server_nullrenderer -skip_update_server_mods  -cluster WAM -shard Main; bash'
byobu-tmux new-window -t dst -d -n '11' 'cd /opt/dst/bin; ./dontstarve_dedicated_server_nullrenderer -skip_update_server_mods  -cluster WAM -shard 11; bash'
byobu-tmux new-window -t dst -d -n '12' 'cd /opt/dst/bin; ./dontstarve_dedicated_server_nullrenderer -skip_update_server_mods  -cluster WAM -shard 12; bash'
byobu-tmux new-window -t dst -d -n '13' 'cd /opt/dst/bin; ./dontstarve_dedicated_server_nullrenderer -skip_update_server_mods  -cluster WAM -shard 13; bash'

