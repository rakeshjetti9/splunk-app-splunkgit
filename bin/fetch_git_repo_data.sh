#!/bin/bash

# Copyright 2011 Splunk, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# This script polls a git remote repo for changes and prints the results to standart out in a format splunk easily can read.
# Author: Petter Eriksson, Emre Berge Ergenekon

#Global variables
APP_HOME=$SPLUNK_HOME/etc/apps/Splunkgit
GIT_REPO=`splunk cmd python $APP_HOME/bin/splunkgit_settings.py`
GIT_REPO_FOLDER=`echo $GIT_REPO | sed 's/.*\///'`
GIT_REPOS_HOME=$APP_HOME/git-repositories
chosen_repository=$GIT_REPOS_HOME/$GIT_REPO_FOLDER

#echo $chosen_repository

NUMBER_OF_COMMITS_TO_SKIP=`splunk search "index=splunkgit | stats dc(commit_hash) as commitCount" -auth admin:changeme -app Splunkgit | grep -o -P '[0-9]+'`

main ()
{
if [ -d "$chosen_repository" ]; then
    print_hashes_and_git_log_numstat
  else
    #TODO Handle this
    echo "repository does not exist!" 1>&2
    fetch_git_repository
  fi
}

#Not safe to run this method parallel from the same directory, since the $numstat_file is touched, written to and deleted.
#TODO: Figure out a way to remove the $numstat_file logic.
print_hashes_and_git_log_numstat ()
{
  numstat_file=git-commit-formatted.out #temporary gather git-diff-tree output
  cd $chosen_repository
  git fetch 1>&2

#for each commit in the git history
  for commit in `git log --pretty=format:'%H' --topo-order --all --no-color --no-renames --no-merges --skip=$NUMBER_OF_COMMITS_TO_SKIP`
  do
    touch $numstat_file
    git --no-pager diff-tree $commit --pretty=format:'[%ci] author_name="%an" author_mail="%ae" commit_hash="%H" parrent_hash="%P" tree_hash="%T"' --numstat | sed '/^$/d' | awk -F \t -v FIRST_LINE=1 -v REPO="$GIT_REPO" '{if (FIRST_LINE==1) {FIRST_LINE=0;COMMIT_INFO=$0} else {print COMMIT_INFO" insertions=\""$1"\" deletions=\""$2"\" path=\""$3"\" file_type=\"---/"$3"---\" repository=\""REPO"\""}}' | perl -pe 's|---.*/(.+?)---|---\.\1---|' | perl -pe 's|---.*\.(.+?)---|\1|' |  tee $numstat_file

    if [ ! -s $numstat_file ]; then #if there was no numstat output, just print the commit_info
      git --no-pager show $commit --pretty=format:'[%ci] author_name="%an" author_mail="%ae" commit_hash="%H" parrent_hash="%P" tree_hash="%T"' --quiet
      echo ;
    fi
    rm $numstat_file #clean up
  done
}

fetch_git_repository ()
{
  error_output=err.out
  touch $error_output
  mkdir -p $GIT_REPOS_HOME
  git clone --mirror $GIT_REPO $chosen_repository &> $error_output
  if [ ! -s $error_output ]; then #if there are no errors from git clone.
    print_hashes_and_git_log_numstat # try again
  else
    cat $error_output 1>&2
  fi
  rm $error_output
}

main