#!/bin/bash

# add users to docker group
# Usage: ./add-users-to-docker.sh <user1> <user2> <user3> ...
# If no user is provided, will add all users to docker group

# check if user is root
if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

# get userlist from /home
if [ "$#" -eq 0 ]; then
    userlist=$(ls /home)
else
    userlist="$@"
fi

# do we have docker group?
if ! grep -q docker /etc/group
then
    echo "docker group does not exist"
    echo "create it now"

    # create docker group
    groupadd docker
fi

# add users to docker group
for user in $userlist;
do
    # check if user exists
    if id "$user" >/dev/null 2>&1
    then
        echo "add user $user to docker group"
        usermod -aG docker "$user"
    else
        echo "$user does not exist"
    fi
done

echo "OK: users added to docker group"
