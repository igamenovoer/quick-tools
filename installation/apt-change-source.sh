#/bin/bash

# this script accepts the repository name as an argument
# the name can be one of the following:
# tuna, aliyun, 163, ustc, cn
# if the name is not one of the above, or not given, raise error
# if the name is given, replace the sources.list with the corresponding one
if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <tuna|aliyun|163|ustc|cn>"
  exit 1
fi

# am I root?
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

# set the APT_SOURCE_FILE to the first argument
APT_SOURCE_FILE=$1

# apt source file, it can be /etc/apt/sources.list or /etc/apt/sources.list.d/ubuntu.sources
# see which file exists, check /etc/apt/sources.list.d/ubuntu.sources first
CURRENT_APT_SOURCE=/etc/apt/sources.list
if [ -f /etc/apt/sources.list.d/ubuntu.sources ]; then
  echo "/etc/apt/sources.list.d/ubuntu.sources exists"
  CURRENT_APT_SOURCE="/etc/apt/sources.list.d/ubuntu.sources"
fi

# if you want to use proxy in shell, just use ENV in your dockerfile

# if APT_SOURCE_FILE is set, use it to replace /etc/apt/sources.list
if [ -n "$APT_SOURCE_FILE" ]; then
  echo "Using $APT_SOURCE_FILE as /etc/apt/sources.list"

  # backup the original sources.list
  cp "$CURRENT_APT_SOURCE" "$CURRENT_APT_SOURCE.bak"

  # check for special values
  # if APT_SOURCE_FILE is 'tuna', use tuna mirrors
  # replace archive.ubuntu.com with mirrors.tuna.tsinghua.edu.cn
  if [ "$APT_SOURCE_FILE" = "tuna" ]; then
    echo "Using tuna mirrors"

    # replace normal sources and security sources
    sed -i 's/archive.ubuntu.com/mirrors.tuna.tsinghua.edu.cn/g' $CURRENT_APT_SOURCE
    sed -i 's/security.ubuntu.com/mirrors.tuna.tsinghua.edu.cn/g' $CURRENT_APT_SOURCE
    sed -i 's/ports.ubuntu.com/mirrors.tuna.tsinghua.edu.cn/g' $CURRENT_APT_SOURCE
    
  # if APT_SOURCE_FILE is 'aliyun', use aliyun mirrors
  # replace archive.ubuntu.com with mirrors.aliyun.com
  elif [ "$APT_SOURCE_FILE" = "aliyun" ]; then
    echo "Using aliyun mirrors"

    # replace normal sources and security sources
    sed -i 's/archive.ubuntu.com/mirrors.aliyun.com/g' $CURRENT_APT_SOURCE
    sed -i 's/security.ubuntu.com/mirrors.aliyun.com/g' $CURRENT_APT_SOURCE
    sed -i 's/ports.ubuntu.com/mirrors.aliyun.com/g' $CURRENT_APT_SOURCE

  # if APT_SOURCE_FILE is '163', use 163 mirrors
  # replace archive.ubuntu.com with mirrors.163.com
  elif [ "$APT_SOURCE_FILE" = "163" ]; then
    echo "Using 163 mirrors"

    # replace normal sources and security sources
    sed -i 's/archive.ubuntu.com/mirrors.163.com/g' $CURRENT_APT_SOURCE
    sed -i 's/security.ubuntu.com/mirrors.163.com/g' $CURRENT_APT_SOURCE
    sed -i 's/ports.ubuntu.com/mirrors.163.com/g' $CURRENT_APT_SOURCE

  # if APT_SOURCE_FILE is 'ustc', use ustc mirrors
  # replace archive.ubuntu.com with mirrors.ustc.edu.cn
  elif [ "$APT_SOURCE_FILE" = "ustc" ]; then
    echo "Using ustc mirrors"

    # replace normal sources and security sources
    sed -i 's/archive.ubuntu.com/mirrors.ustc.edu.cn/g' $CURRENT_APT_SOURCE
    sed -i 's/security.ubuntu.com/mirrors.ustc.edu.cn/g' $CURRENT_APT_SOURCE
    sed -i 's/ports.ubuntu.com/mirrors.ustc.edu.cn/g' $CURRENT_APT_SOURCE
  
  # if APT_SOURCE_FILE is 'cn', use cn mirrors
  # replace archive.ubuntu.com with cn.archive.ubuntu.com
  elif [ "$APT_SOURCE_FILE" = "cn" ]; then
    echo "Using cn mirrors"

    # replace normal sources and security sources
    sed -i 's/archive.ubuntu.com/cn.archive.ubuntu.com/g' $CURRENT_APT_SOURCE
    sed -i 's/security.ubuntu.com/cn.archive.ubuntu.com/g' $CURRENT_APT_SOURCE
    sed -i 's/ports.ubuntu.com/cn.ports.ubuntu.com/g' $CURRENT_APT_SOURCE
  fi

  # display contents of /etc/apt/sources.list
  cat $CURRENT_APT_SOURCE
fi