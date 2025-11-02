#!/bin/bash

# require root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

# add users to group
# Usage: ./add-users-to-group.sh <group> <user1> <user2> <user3> ...

# get userlist
if [ "$#" -lt 2 ]; then
    # echo "Usage: $0 <group> <user1> <user2> <user3> ..."
    echo "Usage: $0 <group> <user1> <user2> <user3> ..."
    exit 1
else
    group=$1
    userlist="${@:2}"
fi

# make sure all users are valid
for user in $userlist
do
    if ! id -u $user &>/dev/null
    then
        echo "User $user does not exist"
        exit 1
    fi
done

# if the group does not exist, exit
if ! grep -q $group /etc/group
then
    echo "Group $group does not exist"
    exit 1
fi

# remove duplicate
userlist=$(echo $userlist | tr ' ' '\n' | uniq)

# sort userlist by username
userlist=$(echo $userlist | tr ' ' '\n' | sort)

# add users to group
for user in $userlist
do
    echo "Adding $user to $group"
    usermod -aG $group $user
done

echo "Done"

