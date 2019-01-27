#!/bin/bash
#
# set -x

# create or modify a bug report at http://bugzilla.gentoo.org
#

# typical call:
#
#  bgo.sh -d ~/run/desktop-unstable_20160916-100730/tmp/issues/20160918-113424_sci-chemistry_reduce-3.16.111118 -b 582084


function Warn() {
  rc=$1

  echo "
  *
  failed with error code $rc
  *

  "
  tail -v bugz.*
}


function Error() {
  rc=$1
  Warn $rc
  exit $rc
}


#######################################################################
#

# work around a DNS issue
#
host bugs.gentoo.org 2>/dev/null | grep -q 'has address'
if [[ $? -ne 0 ]]; then
  Error "DNS issue appeared"
fi

id=""
block=""
comment=""
issuedir=""
severity="Normal"

newbug=1    # if set to 1 then do neither change To: nor Cc:

while getopts a:b:c:d:i:s: opt
do
  case $opt in
    i)  id="$OPTARG"            # (i)d of an existing bug
        newbug=0
        ;;
    b)  block="$OPTARG";;       # (b)lock that bug (id or alias)
    c)  comment="$OPTARG";;     # (c)omment, used with -a
    d)  issuedir="$OPTARG";;    # (d)irectory with all files
    s)  severity="$OPTARG";;    # "normal", "QA" and so on
    *)  echo " not implemented !"; exit 1;;
  esac
done

if [[ -z "$issuedir" ]]; then
  echo "no issuedir given"
  exit 1
fi

cd $issuedir
if [[ $? -ne 0 ]]; then
  echo "cannot cd into '$issuedir'"
  exit 2
fi

if [[ -f ./.reported ]]; then
  echo "already reported ! remove $issuedir/.reported before retrying !"
  exit 3
fi

if [[ ! -f ./issue ]]; then
  echo "did not found ./issue !"
  exit 4
fi

# pick up after from a previous call
#
rm -f bugz.{out,err}

if [[ -n "$id" ]]; then
  # modify an existing bug report
  #
  if [[ -z "$comment" ]]; then
    comment="appeared recently at the tinderbox image $(realpath $issuedir | cut -f5 -d'/')"
  fi
  timeout 60 bugz modify --status CONFIRMED --comment "$comment" $id 1>bugz.out 2>bugz.err || Error $?

  grep -q "fails with FEATURES=test" $issuedir/title && timeout 60 bugz modify --set-keywords TESTFAILURE $id

else
  # create a new bug report
  #
  timeout 60 bugz post \
    --product "Gentoo Linux"          \
    --component "Current packages"    \
    --version "unspecified"           \
    --title "$(cat ./title)"          \
    --op-sys "Linux"                  \
    --platform "All"                  \
    --priority "Normal"               \
    --severity "$severity"            \
    --alias ""                        \
    --description-from "./issue"      \
    --batch                           \
    --default-confirm n               \
    1>bugz.out 2>bugz.err || Error $?

  id=$(grep ' * Bug .* submitted' bugz.out | sed 's/[^0-9]//g')
  if [[ -z "$id" ]]; then
    echo
    echo "empty bug id"
    echo
    Error 4
  fi

  if [[ -n "$comment" ]]; then
    timeout 60 bugz modify --status CONFIRMED --comment "$comment" $id 1>bugz.out 2>bugz.err || Error $?
  fi
fi

# avoid duplicate reports
#
touch ./.reported

echo
echo "https://bugs.gentoo.org/show_bug.cgi?id=$id"

if [[ -s bugz.err ]]; then
  Error 5
fi

if [[ -f emerge-info.txt ]]; then
  timeout 60 bugz attach --content-type "text/plain" --description "" $id emerge-info.txt 1>bugz.out 2>bugz.err || Warn $?
fi

if [[ -d ./files ]]; then
  echo
  for f in ./files/*
  do
    # max. size from b.g.o. is 1 MB
    #
    if [[ $(wc -c < $f) -lt 1048576 ]]; then
      # this matches both *.bz2 and *.tbz2
      #
      echo "$f" | grep -q "bz2$" && ct="application/x-bzip" || ct="text/plain"
      echo "  $f"
      timeout 60 bugz attach --content-type "$ct" --description "" $id $f 1>bugz.out 2>bugz.err || Warn $?
    fi
  done
fi

if [[ -n "$block" ]]; then
  timeout 60 bugz modify --add-blocked "$block" $id 1>bugz.out 2>bugz.err || Warn $?
fi

bzgrep -q " \* ERROR:.* failed (test phase):" $issuedir/_emerge_* 2>/dev/null
if [[ $? -eq 0 ]]; then
  timeout 60 bugz modify --set-keywords TESTFAILURE $id 1>bugz.out 2>bugz.err || Warn $?
fi

# set assignee and cc as the last step (requested by prometheanfire via IRC)
# to reduce the bot email amount to the only one email sent out
# when all data are attached to the report
# but only if we opened the bug
#
if [[ $newbug -eq 1 ]]; then
  a="-a $(cat ./assignee)"
  if [[ -s ./cc ]]; then
    # entries in cc are space separated and have to be prefixed with --add-cc each
    #
    c="--add-cc $(cat ./cc | sed 's/ / --add-cc /g')"
  fi
  timeout 60 bugz modify $a $c $id 1>bugz.out 2>bugz.err || Warn $?
fi

echo
