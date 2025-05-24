alias ..="cd -- .."        #go to parent dir
alias ...="cd -- ../.."    #go to grandparent dir
alias ....='cd -- ../../..'
alias .....='cd -- ../../../..'
alias ......='cd -- ../../../../..'

function mkcdir() { mkdir -p -- "$1" && cd -- "$1"; }
