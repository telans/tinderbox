#!/bin/bash
# set -x


# start tinderbox chroot image/s


function __is_running() {
  [[ -d "/run/tinderbox/${1##*/}.lock" ]]
}


set -euf
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/opt/tb/bin"
export LANG=C.utf8


if [[ ! "$(whoami)" = "tinderbox" ]]; then
  echo " you must be tinderbox"
  exit 1
fi

for i in ${@:-$(ls ~/run 2>/dev/null)}
do
  echo -n "$(date +%X) "

  mnt="$(ls -d ~tinderbox/img{1,2}/${i##*/} 2>/dev/null || true)"

  if [[ -z "$mnt" || ! -d "$mnt" || -L "$mnt" || $(stat -c '%u' "$mnt") -ne 0 ]]; then
    echo "no valid mount point found for $i"
    continue
  fi

  if [[ "$mnt" =~ ".." || "$mnt" =~ "//" || "$mnt" =~ [[:space:]] || "$mnt" =~ '\' ]]; then
    echo "illegal character(s) in mount point $mnt"
    continue
  fi

  if __is_running "$mnt" ; then
    echo " image is locked:  $mnt"
    continue
  fi

  if [[ -f $mnt/var/tmp/tb/STOP ]]; then
    echo " has STOP file: $mnt"
    continue
  fi

  if [[ $(cat $mnt/var/tmp/tb/backlog{,,1st,.upd} /var/tmp/tb/task 2>/dev/null | wc -l) -eq 0 ]]; then
    echo " all backlogs are empty: $mnt"
    continue
  fi

  echo " starting: $mnt"

  # nice makes reading of sysstat numbers easier
  nice -n 1 sudo /opt/tb/bin/bwrap.sh -m "$mnt" -s "/opt/tb/bin/job.sh" &> ~/logs/${mnt##*/}.log &
done

# avoid an invisible prompt
echo
