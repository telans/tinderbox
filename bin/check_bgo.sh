#!/bin/bash
# set -x

# check buzilla.gentoo.org whether issue was already reported


function SearchForMatchingBugs() {
  local bsi=$issuedir/bugz_search_items     # use the title as a set of space separated search patterns

  # get away line numbers, certain special terms et al
  sed -e 's,&<[[:alnum:]].*>,,g'  \
      -e 's,/\.\.\./, ,'          \
      -e 's,:[[:alnum:]]*:[[:alnum:]]*: , ,g' \
      -e 's,.* : ,,'              \
      -e 's,[<>&\*\?\!], ,g'      \
      -e 's,[\(\)], ,g'           \
      -e 's,  *, ,g'              \
      $issuedir/title > $bsi

  local output=$(mktemp /tmp/$(basename $0)_XXXXXX.log) # just needed to test for success of bugz

  # search first for the same version, if unsuccessful then repeat with category/package name only
  for i in $pkg $pkgname
  do
    bugz -q --columns 400 search --show-status -- $i "$(cat $bsi)" | grep -e " CONFIRMED " -e " IN_PROGRESS " |\
        sort -u -n -r | head -n 10 | tee $output
    if [[ -s $output ]]; then
      rm $output
      return
    fi

    for s in FIXED WORKSFORME DUPLICATE
    do
      bugz -q --columns 400 search --show-status --resolution $s --status RESOLVED -- $i "$(cat $bsi)" |\
          sort -u -n -r | head -n 10 | sed "s,^,$s  ," | tee $output
      if [[ -s $output ]]; then
        break 2
      fi
    done
  done

  if [[ ! -s $output ]]; then
    # if no findings till now, so search for any bug of that category/package

    local h='https://bugs.gentoo.org/buglist.cgi?query_format=advanced&short_desc_type=allwordssubstr'
    local g='stabilize|Bump| keyword| bump'

    echo -e "\nOPEN:     $h&resolution=---&short_desc=$pkgname\n"
    bugz -q --columns 400 search --show-status     $pkgname | grep -v -i -E "$g" |\
        sort -u -n -r | head -n 10 | tee $output
    if [[ ! -s $output ]]; then
      echo
      echo -e "RESOLVED: $h&bug_status=RESOLVED&short_desc=$pkgname\n"
      bugz -q --columns 400 search --status RESOLVED $pkgname | grep -v -i -E "$g" |\
          sort -u -n -r | head -n 10
    fi
  fi

  echo -en "\n\n    bgo.sh -d $issuedir"
  if [[ -n $blocker_bug_no ]]; then
    echo -e " -b $blocker_bug_no"
  fi
  echo -e "\n"
  rm  $output
}


# test title against known blocker
# the BLOCKER file contains paragraphs like:
#   # comment
#   <bug id>
#   <pattern string ready for grep -E>
# if <pattern> is defined more than once then the first makes it
function LookupForABlocker() {
  if [[ ! -s $issuedir/title ]]; then
    return 1
  fi

  while read line
  do
    if [[ $line =~ ^# || "$line" = "" ]]; then
      continue
    fi

    if [[ $line =~ ^[0-9].*$ ]]; then
      number=$line
      continue
    fi

    if grep -q -E "$line" $issuedir/title; then
      blocker_bug_no=$number
      break
    fi
  done < <(grep -v -e '^#' -e '^$' ~tinderbox/tb/data/BLOCKER)
}


function SetAssigneeAndCc() {
  local assignee
  local cc
  local m=$(equery meta -m $pkgname | grep '@' | xargs)

  if [[ -z "$m" ]]; then
    assignee="maintainer-needed@gentoo.org"
    cc=""

  elif [[ "$blocker_bug_no" = "561854" ]]; then
    assignee="libressl@gentoo.org"
    cc="$m"

  elif [[ ! $repo = "gentoo" ]]; then
    if [[ $repo = "science" ]]; then
      assignee="sci@gentoo.org"
    else
      assignee="$repo@gentoo.org"
    fi
    cc="$m"

  elif [[ $name =~ "musl" ]]; then
    assignee="musl@gentoo.org"
    cc="$m"

  else
    assignee=$(echo "$m" | cut -f1 -d' ')
    cc=$(echo "$m" | cut -f2- -d' ' -s)
  fi

  # for a file collision report both involved sites
  if grep -q 'file collision with' $issuedir/title; then
    local collision_partner=$(sed -e 's,.*file collision with ,,' < $issuedir/title)
    if [[ -n "$collision_partner" ]]; then
      cc="$cc $(equery meta -m $collision_partner | grep '@' | xargs)"
    fi
  fi

  echo "$assignee" > $issuedir/assignee
  if [[ -n "$cc" ]]; then
    echo "$cc" | xargs -n 1 | sort -u | grep -v "^$assignee$" | xargs > $issuedir/cc
  else
    rm -f $issuedir/cc
  fi
}



#######################################################################
set -euf
export LANG=C.utf8

issuedir=$(realpath $1)

cd $issuedir || exit 1
if [[ ! -s $issuedir/title ]]; then
  exit 1
fi
echo

name=$(cat $issuedir/../../../../../etc/conf.d/hostname)      # eg.: 17.1-20201022-101504
repo=$(cat $issuedir/repository)                              # eg.: gentoo
pkg=$(basename $issuedir | cut -f3- -d'-' -s | sed 's,_,/,')  # eg.: net-misc/bird-2.0.7
pkgname=$(qatom $pkg | cut -f1-2 -d' ' -s | tr ' ' '/')       # eg.: net-misc/bird

echo -n "    versions: "
eshowkw --overlays --arch amd64 $pkgname |\
    grep -v -e '^  *|' -e '^-' -e '^Keywords' |\
    awk '{ if ($3 == "+") { print $1 } else if ($3 == "o") { print "**"$1 } else { print $3$1 } }' |\
    xargs
echo    "    title:    $(cat $issuedir/title)"

blocker_bug_no=""
LookupForABlocker
SetAssigneeAndCc
echo "    devs:     $(cat $issuedir/{assignee,cc} 2>/dev/null | xargs)"
echo
SearchForMatchingBugs
echo
