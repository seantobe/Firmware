#!/bin/bash

set -e

rc_script=$1
debugger=$2
program=$3
model=$4
build_path=$5
curr_dir=`pwd`

echo SITL ARGS
echo rc_script: $rc_script
echo debugger: $debugger
echo program: $program
echo model: $model
echo build_path: $build_path

tmp_dir=$build_path/devel/tmp
rootfs=$tmp_dir/rootfs
sitl_bin=$build_path/devel/bin/px4

mkdir -p $tmp_dir
mkdir -p $rootfs/fs/microsd
mkdir -p $rootfs/eeprom
touch $rootfs/eeprom/parameters

if [ "$chroot" == "1" ]
then
	chroot_enabled=-c
	sudo_enabled=sudo
else
	chroot_enabled=""
	sudo_enabled=""
fi

if [ "$model" == "" ] || [ "$model" == "none" ]
then
	echo "empty model, setting iris as default"
	model="iris"
fi

if [ "$#" -lt 5 ]
then
	echo usage: sitl_run.sh rc_script debugger program model build_path
	echo ""
	exit 1
fi

command_exists () {
    type "$1" &> /dev/null ;
}

# kill process names that might stil
# be running from last time
pgrep gazebo && pkill gazebo
pgrep px4 && pkill px4
if command_exits jps
then
	jmavsim_pid=`jps | grep Simulator | cut -d" " -f1`
	if [ -n "$jmavsim_pid" ]
	then
		kill $jmavsim_pid
	fi
fi

cd $build_path/..
cp Tools/posix_lldbinit $tmp_dir/.lldbinit
cp Tools/posix.gdbinit $tmp_dir/.gdbinit

SIM_PID=0

if [ "$program" == "jmavsim" ] && [ ! -n "$no_sim" ]
then
	cd Tools/jMAVSim
	ant create_run_jar copy_res
	cd out/production
	java -Djava.ext.dirs= -jar jmavsim_run.jar -udp 127.0.0.1:14560 &
	SIM_PID=`echo $!`
	cd ../..
elif [ "$program" == "gazebo" ] && [ ! -n "$no_sim" ]
then
	if [ -x "$(command -v gazebo)" ]
	then
		# Set the plugin path so Gazebo finds our model and sim
		source /usr/share/gazebo/setup.sh
		source $build_path/devel/share/mavlink_sitl_gazebo/setup.sh
		# The next line would disable online model lookup, can be commented in, in case of unstable behaviour.
		# export GAZEBO_MODEL_DATABASE_URI=""
		gzserver --verbose worlds/${model}.world &
		SIM_PID=`echo $!`

		if [[ -n "$HEADLESS" ]]; then
			echo "not running gazebo gui"
		else
			gzclient --verbose &
			GUI_PID=`echo $!`
		fi
	else
		echo "You need to have gazebo simulator installed!"
		exit 1
	fi
elif [ "$program" == "replay" ] && [ ! -n "$no_sim" ]
then
	echo "Replaying logfile: $logfile"
	# This is not a simulator, but a log file to replay

	# Check if we need to creat a param file to allow user to change parameters
	if ! [ -f "$rootfs/replay_params.txt" ]
		then
		touch $rootfs/replay_params.txt
	fi
fi

cd $build_path/devel/tmp

if [ "$logfile" != "" ]
then
	cp $logfile $rootfs/replay.px4log
fi

# Do not exit on failure now from here on because we want the complete cleanup
set +e

# Start Java simulator
if [ "$debugger" == "lldb" ]
then
	lldb -- $sitl_bin ../share/px4/${rc_script}_${program}_${model}
elif [ "$debugger" == "gdb" ]
then
	gdb --args $sitl_bin ../share/px4/${rc_script}_${program}_${model}
elif [ "$debugger" == "ddd" ]
then
	ddd --debugger gdb --args px4 ../share/px4/${rc_script}_${program}_${model}
elif [ "$debugger" == "valgrind" ]
then
	valgrind $sitl_bin ../share/px4/${rc_script}_${program}_${model}
else
	$sudo_enabled $sitl_bin $chroot_enabled ../share/px4/${rc_script}_${program}_${model}
fi

if [ "$program" == "jmavsim" ]
then
	kill -9 $SIM_PID
elif [ "$program" == "gazebo" ]
then
	kill -9 $SIM_PID
	if [[ ! -n "$HEADLESS" ]]; then
		kill -9 $GUI_PID
	fi
fi
