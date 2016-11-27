#!/bin/bash

email="steeve.mccauley@gmail.com"
hostname=$(hostname -s)

info() {
	echo -e "$*"
}

err() {
	info "Error: $*"	
}

die() {
	code=$1
	shift
	if [ $code -eq 0 ]; then
		info $*
	else
		err "$*"
		echo "$*" | mail -s "$hostname: $0 failed" $email
	fi
	exit $code
}

_help_() {
	cat -<< HELP
	$(basename $0) [OPTS]

	-c client
	-r run
	-u update
	-h help
	-v verbose

HELP
	exit 0
}

tclients=""
clients=""
options=":hvc:ru"
run=false
update=false
while getopts "$options" optchar; do
	case "${optchar}" in
		h)
			_help_
			;;
		v)
			verbose=true
			;;
		c)
			clients="$clients -c $OPTARG"
			tclients="$tclients $OPTARG"
			;;
		r)
			run=true
			;;
		u)
			update=true
			;;
		*)
			die 1 "Unknown options: $optchar"
			;;
	esac
done

[ -z "$clients" ] && die 1 "no clients specified"

op=""
if [ $run == true ]; then
	op="run"
elif [ $update == true ]; then
	op="update"
fi

[ -z "$op" ] && die 1 "Must specify either -r (run) or -u (update)"

tmp="/var/tmp/rubac"
mkdir -p $tmp
[ $? -ne 0 ] && die 1 "Failed to create $tmp"

bdir=$(rubac -l | grep "dest=" | cut -f2 -d'=')
[ ! -d "$bdir" ] && die 1 "Backup doesn't seem to be mounted at $bdir"
for c in $tclients; do
	info "Testing client $c"
	if [ -d "$bdir/$c" ]; then
		latest="$bdir/$c/latest"
		stat -L $latest > /dev/null
		[ $? -ne 0 ] && die 1 "latest not found for client $c: $latest"
	fi
	ssh -q -o "BatchMode=yes" -i ~/.ssh/id_rsa "$c" exit
	[ $? -ne 0 ] && die 1 "ssh test to $c failed"
done

now=$(date +%Y%m%d)
log=$tmp/rubac.$now.$op.out
#rubac -c valium -c linguini -c woot --run  >> rubac.$(date +%Y%m%d).out 2>&1 &
info rubac $clients --$op
info logging to $log
nohup rubac $clients --$op >> $log 2>&1 &

sleep 2

less $log

