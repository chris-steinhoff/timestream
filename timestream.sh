#!/bin/bash

################################################################################
# Timestream is used to backup files and directories.
#
# Copyright (C) 2013  Chris Steinhoff
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Lesser General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
################################################################################

BAK=''
SRC=''

# Parse the command line arguments
while [ "$1" != "" ]
do
	case "$1" in
	"-h" | "--help")
		echo "timestream.sh -s src_dir -d dest_dir"
		exit 0
		;;
	"-s" | "--source")
		shift
		if [ "$1" == "" ]
		then
			echo "Please supply a source directory" 1>&2
			exit 1
		else
			SRC=$(readlink -f "$1")
		fi
		;;
	"-d" | "--destination")
		shift
		if [ "$1" == "" ]
		then
			echo "Please supply a destination directory" 1>&2
			exit 2
		else
			BAK=$(readlink -f "$1")
		fi
		;;
	esac
	shift
done

# Verify the user configured a src dir
if [ "$SRC" == "" ]
then
	echo "Please supply a source directory" 1>&2
	exit 1
fi

# Verify the user configured a bak dir
if [ "$BAK" == "" ]
then
	echo "Please supply a destination directory" 1>&2
	exit 2
fi

#echo "BAK = $BAK"
#echo "SRC = $SRC"

# Verify the src dir exists
if ! [ -d "$SRC" ]
then
	echo "The source directory supplied is not a directory" 1>&2
	exit 3
fi

# Verify the bak dir exists
if ! [ -d "$BAK" ]
then
	echo "The destination directory supplied is not a directory" 1>&2
	exit 4
fi

# Format the lock name as: '.lock.' PID '.' random number
LOCK_FILE="$BAK/.lock.$$.$RANDOM"
# Check if a process has already locked this directory
LOCKS="$(ls $BAK/.lock.[0-9]*.[0-9]* 2> /dev/null)"
if [ -n "$LOCKS" ]
then
	echo "It looks like a backup is already running." 1>&2
	echo "If you are sure this is wrong, delete '$LOCKS'" 1>&2
	exit 5
else
	touch "$LOCK_FILE"
fi

# Delete the lock file
unlock () {
	rm -f "$LOCK_FILE"
	exit 0
}

# Catch signals so we can delete the lock file
trap "unlock" SIGHUP SIGINT TERM

# Find the previous backups directory
PREV="$(ls -d $BAK/[0-9][0-9][0-9][0-9] 2>/dev/null | tail -1)"
if [ "$PREV" == "" ]
then
	PREV="$BAK/${RANDOM}${RANDOM}${RANDOM}"
else
	for i in 1 2 3 4 5
	do
		PREV="$(ls -d $PREV/[0-9][0-9] | tail -1)"
	done
fi
unset Y
#echo "$PREV"

# Determin the current dest dir
CURR="$BAK/$(date +%Y/%m/%d/%H/%M/%S)"
mkdir -p "$CURR"
#echo "$CURR"

# Stack to hold the current src dir
SS=("$SRC")
# Stack to hold the previous dest dir
PS=("$PREV")
# Stack to hold the current dest dir
BS=("$CURR")
# Stack index
SI=0
# Value at head of the stack
SPEEK="$SRC"
PPEEK="$PREV"
BPEEK="$CURR"

# Push onto the stack
push () {
	SS[$SI+1]="$SPEEK/$1"
	PS[$SI+1]="$PPEEK/$1"
	BS[$SI+1]="$BPEEK/$1"
	((SI++))
	peek
}

# Pop off the stack
pop () {
	#echo "touch -r '$SPEEK' '$BPEEK'"
	touch -r "$SPEEK" "$BPEEK"
	((SI--))
	peek
}

# Peek the stack
peek () {
	SPEEK="${SS[$SI]}"
	PPEEK="${PS[$SI]}"
	BPEEK="${BS[$SI]}"
	cd "$SPEEK"
}

# Create the destination directory
make_dir () {
	#echo "mkdir '$BPEEK'"
	mkdir "$BPEEK"
}

# Copy the source file to the destination and keep permissions
copy () {
	#echo "cp '$SPEEK/$1' '$BPEEK/$1'"
	cp -p "$SPEEK/$1" "$BPEEK/$1"
}

# Link the backup file to the previous file
link () {
	#echo "ln '$PPEEK/$1' '$BPEEK/$1'"
	ln "$PPEEK/$1" "$BPEEK/$1"
}

# Backup all files in the current directory
# Recurse into subdirectories
backup_dir () {
	# Foreach file and directory
	for f in $(ls -a --group-directories-first)
	do
		# Ignore current and parent directories
		if [ "$f" == "." ] || [ "$f" == ".." ]
		then
			continue
		fi

		# If it's a directory, recurse into it, unless it's a symlink
		if [ -d "$f" ]
		then
			if [ -h "$f" ]
			then
				#echo "[III] Not a regular directory $SPEEK/$f" 1>&2
				:
			else
				push "$f"
				# If the destination exists
				if [ -e "$BPEEK" ]
				then
					# and it's not a directory
					if ! [ -d "$BPEEK" ]
					then
						# Delete the file and make the directory
						#echo "rm -f '$BPEEK'"
						rm -f "$BPEEK"
						make_dir
					fi
				else
					# The destination doesn't exist so create it
					make_dir
				fi
				# Backup this directory and go back up a level
				backup_dir
				pop
			fi
		else
			# If the file's a regular file
			if [ -f "$f" ] && [ ! -h "$f" ]
			then
				# and it can be read
				if [ -r "$f" ]
				then
					# If the destination is a directory
					if [ -d "$BPEEK/$f" ]
					then
						# Delete the directory and copy the file
						#echo "rm -rf '$BPEEK/$f'"
						rm -rf "$BPEEK/$f"
						copy "$f"
					else
						# If the file is newer than the previous backup, copy
						# it, else create a hard-link
						if [ "$f" -nt "$PPEEK/$f" ]
						then
							copy "$f"
						else
							#echo "[III] File hasn't changed $SPEEK/$f" 1>&2
							if [ -e "$PPEEK/$f" ]
							then
								link "$f"
							fi
						fi
					fi
				else 
					echo "[EEE] Cannot read $SPEEK/$f" 1>&2
				fi
			else
				#echo "[III] Not a regular file $SPEEK/$f" 1>&2
				:
			fi
		fi
	done
}

peek
backup_dir

unlock

