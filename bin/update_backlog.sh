#!/bin/sh
#
# set -x

# pick up latest changed ebuilds and merge them into backlog.upd
#

if [[ ! "$(whoami)" = "tinderbox" ]]; then
  echo "You must be the tinderbox user !"
  exit 1
fi

# list of added/changed/modified/renamed ebuilds
#
acmr=/tmp/$(basename $0).acmr

cd /usr/portage/

# add 1 hour to let mirrors be in sync
#
git diff --diff-filter=ACMR --name-status "@{ ${1:-2} hour ago }".."@{ 1 hour ago }" 2>/dev/null |\
grep -F -e '/files/' -e '.ebuild' | cut -f2- -s | xargs -n 1 | cut -f1-2 -d'/' -s | sort --unique |\
grep -v -f ~/tb/data/IGNORE_PACKAGES > $acmr

# mix current changes into each backlog
#
if [[ -s $acmr ]]; then
  for i in $(ls ~/run)
  do
    bl=~/run/$i/tmp/backlog.upd
    sort --unique --random-sort $bl $acmr > $bl.tmp && cp $bl.tmp $bl && rm $bl.tmp
  done
fi
