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

echo "BAK = $BAK"
echo "SRC = $SRC"

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

LOCK_FILE="$BAK/lock"
if [ -e "$LOCK_FILE" ]
then
	echo "It looks like a backup is already running." 1>&2
	echo "If you are sure this is wrong, delete '$LOCK_FILE'" 1>&2
	exit 5
else
	touch "$LOCK_FILE"
fi

# Stack to hold the current src dir
SS=("$SRC")
# Stack to hold the current dest dir
BS=("$BAK")
# Stack index
SI=0
# Value at head of the stack
SPEEK="$SRC"
BPEEK="$BAK"

# Push onto the stack
push () {
	SS[$SI+1]="$SPEEK/$1"
	BS[$SI+1]="$BPEEK/$1"
	((SI++))
	peek
}

# Pop off the stack
pop () {
	echo "touch -r '$SPEEK' '$BPEEK'"
	touch -r "$SPEEK" "$BPEEK"
	((SI--))
	peek
}

# Peek the stack
peek () {
	SPEEK="${SS[$SI]}"
	BPEEK="${BS[$SI]}"
	cd "$SPEEK"
}

make_dir () {
	echo "mkdir '$BPEEK'"
	mkdir "$BPEEK"
}

copy () {
	echo "cp '$SPEEK/$1' '$BPEEK/$1'"
	cp -p "$SPEEK/$1" "$BPEEK/$1"
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
				echo "[III] Not a regular directory $SPEEK/$f" 1>&2
			else
				push "$f"
				if [ -e "$BPEEK" ]
				then
					if ! [ -d "$BPEEK" ]
					then
						echo "rm -f '$BPEEK'"
						rm -f "$BPEEK"
						make_dir
					fi
				else
					make_dir
				fi
				backup_dir
				pop
			fi
		else
			if [ -f "$f" ] && [ ! -h "$f" ]
			then
				if [ -r "$f" ]
				then
					if [ -d "$BPEEK/$f" ]
					then
						echo "rm -rf '$BPEEK/$f'"
						rm -rf "$BPEEK/$f"
						copy "$f"
					else
						if [ "$f" -nt "$BPEEK/$f" ]
						then
							copy "$f"
						else
							echo "[III] File hasn't changed $SPEEK/$f" 1>&2
						fi
					fi
				else 
					echo "[EEE] Cannot read $SPEEK/$f" 1>&2
				fi
			else
				echo "[III] Not a regular file $SPEEK/$f" 1>&2
			fi
		fi
	done
}

peek
backup_dir

rm -f "$LOCK_FILE"

