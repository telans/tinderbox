#!/bin/sh
#
# set -x

# quick & dirty tinderbox statistics
#

# all active|run'ing images
#
function list_images() {
  (
    ls -1d ~/run/* | xargs -n 1 readlink | sed "s,^..,/home/tinderbox,g"
    df -h | grep '/home/tinderbox/img./' | cut -f4-5 -d'/' | sed "s,^,/home/tinderbox/,g"
  ) | sort -u
}


function PrintImageName()  {
  printf "%s\r\t\t\t\t\t               \r\t\t\t\t\t" $(basename $i)
}


# gives sth. like:
#
#  inst fail   day   todo ~/run lock stop
#  4222   44   5.0  16041     y    y      13.0-abi32+64_20170216-202818
#  3267   46   2.9  16897          y      desktop_20170218-203252
#  4363   71   6.0  16667     y    y    y desktop-libressl-abi32+64_20170215-185650
#
function Overall() {
  echo " inst fail   day   todo ~/run lock stop"
  for i in $images
  do
    log=$i/var/log/emerge.log
    if [[ -f $log ]]; then
      inst=$(grep -c '::: completed emerge' $log)
      day=$(echo "scale=1; ($(tail -n1 $log | cut -c1-10) - $(head -n1 $log | cut -c1-10)) / 86400" | bc)
    else
      inst=0
      day=0
    fi
    # count fail packages, but not every failed attempt of the same package version
    #
    if [[ -d $i/tmp/issues ]]; then
      fail=$(ls -1 $i/tmp/issues | xargs -n 1 basename | cut -f2- -d'_' | sort -u | wc -w)
    else
      fail=0
    fi
    todo=$(wc -l < $i/tmp/packages 2>/dev/null)

    [[ -e ~/run/$(basename $i) ]] && run="y"  || run=""
    [[ -f $i/tmp/LOCK ]]          && lock="y" || lock=""
    [[ -f $i/tmp/STOP ]]          && stop="y" || stop=""

    printf "%5i %4i  %4.1f  %5i %5s %4s %4s %s\n" $inst $fail $day $todo "$run" "$lock" "$stop" $(basename $i)
  done
}


# gives sth. like:
#
# 13.0-abi32+64_20170216-202818              0:13 min  >>> (5 of 8) dev-perl/Email-MessageID-1.406.0
# desktop_20170218-203252                   71:51 min  >>> (1 of 1) games-emulation/sdlmame-0.174
# desktop-libressl-abi32+64_20170215-18565   0:32 min  *** dev-ruby/stringex
#
function LastEmergeOperation()  {
  for i in $images
  do
    PrintImageName
    log=$i/var/log/emerge.log
    if [[ ! -f $log ]]; then
      echo
      continue
    fi

    tac $log |\
    grep -m 1 -E -e '(>>>|\*\*\*) emerge' -e ' \*\*\* terminating.' -e '::: completed emerge' |\
    sed -e 's/ \-\-.* / /g' -e 's, to /,,g' -e 's/ emerge / /g' -e 's/ completed / /g' -e 's/ \*\*\* terminating\./ /g' |\
    perl -wane '
      chop ($F[0]);

      my $diff = time() - $F[0];
      my $mm = $diff / 60;
      my $ss = $diff % 60 % 60;

      printf (" %3i:%02i min  %s\n", $mm, $ss, join (" ", @F[1..$#F]));
    '
  done
}


# gives sth. like:
#
# 13.0-abi32+64_20170216-202818             838  998  782  843  732   29
# desktop_20170218-203252                   881 1420  966
# desktop-libressl-abi32+64_20170215-18565  292  729 1186  725  739  625   67
#
function PackagesPerDay() {
  for i in $images
  do
    PrintImageName
    log=$i/var/log/emerge.log
    if [[ ! -f $log ]]; then
      echo
      continue
    fi

    # qlop gives sth like: Fri Aug 19 13:43:15 2016 >>> app-portage/cpuid2cpuflags-1
    #
    grep '::: completed emerge' $log |\
    cut -f1 -d ':' |\
    perl -wane '
      BEGIN { @p = (); $first = 0; }
      {
        $cur = $F[0];
        $first = $cur if ($first == 0);
        my $i = int (($cur-$first)/86400);
        $p[$i]++;
      }

      END {
        foreach my $i (0..$#p) {
          printf ("%5i", $p[$i]);
        }
        print "\n";
      }
    '
  done
}


# gives sth. like:
#
# 13.0-abi32+64_20170216-202818              1:53 min  mail-filter/assp
# desktop_20170218-203252                   72:08 min  sdlmame
# desktop-libressl-abi32+64_20170215-18565   0:03 min  dev-ruby/stringex
#
function CurrentTask()  {
  for i in $images
  do
    PrintImageName
    tsk=$i/tmp/task
    if [[ ! -f $tsk ]]; then
      echo
      continue
    fi

    delta=$(echo "$(date +%s) - $(date +%s -r $tsk)" | bc)
    seconds=$(echo "$delta % 60" | bc)
    minutes=$(echo "$delta / 60" | bc)
    printf " %3i:%02i min  " $minutes $seconds
    cat $i/tmp/task
  done
}


#######################################################################
#
images=$(list_images)

echo
echo "$(echo $images | wc -w) images ($(ls ~/img? | wc -w) at all) :"

while getopts hlopt\? opt
do
  echo
  case $opt in
    l)  LastEmergeOperation
        ;;
    o)  Overall
        ;;
    p)  PackagesPerDay
        ;;
    t)  CurrentTask
        ;;
    *)  echo "call: $(basename $0) [-l] [-o] [-p] [-t]"
        echo
        exit 0
        ;;
  esac
done

echo
