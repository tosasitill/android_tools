#!/bin/bash

# SPDX-License-Identifier: GPL-3.0-or-later
#
# Copyright (C) 2019 Shivam Kumar Jha <jha.shivam3@gmail.com>
#
# Helper functions

SECONDS=0

# Store project path
PROJECT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." >/dev/null && pwd )"

# Common stuff
source $PROJECT_DIR/helpers/common_script.sh

# Exit if no arguements
if [ -z "$1" ] ; then
    echo -e "Supply OTA file(s) as arguement!"
    exit 1
fi

# Password
if [ "$EUID" -ne 0 ] && [ -z "$user_password" ]; then
    read -p "Enter user password: " user_password
fi

for var in "$@"; do
    # Variables
    if [[ "$var" == *"http"* ]]; then
        URL="$var"
        dlrom
    else
        URL=$( realpath "$var" )
    fi
    [[ ! -e ${URL} ]] && echo "Error! File $URL does not exist." && break
    FILE=${URL##*/}
    EXTENSION=${URL##*.}
    UNZIP_DIR=${FILE/.$EXTENSION/}
    PARTITIONS="boot init_boot"
    [[ -d $PROJECT_DIR/dumps/$UNZIP_DIR/ ]] && rm -rf $PROJECT_DIR/dumps/$UNZIP_DIR/

    if [ -d "$var" ] ; then
        echo -e "Copying images"
        cp -a "$var" $PROJECT_DIR/dumps/${UNZIP_DIR}
    else
        # Firmware extractor
        if [[ "$VERBOSE" = "n" ]]; then
            echo -e "Creating sparse images"
            bash $PROJECT_DIR/tools/Firmware_extractor/extractor.sh ${URL} $PROJECT_DIR/dumps/${UNZIP_DIR} > /dev/null 2>&1
        else
            bash $PROJECT_DIR/tools/Firmware_extractor/extractor.sh ${URL} $PROJECT_DIR/dumps/${UNZIP_DIR}
        fi
    fi
    [[ ! -e $PROJECT_DIR/dumps/${UNZIP_DIR}/system.img ]] && echo "No system.img found. Exiting" && break
    # mounting
    for file in $PARTITIONS; do
        if [ -e "$PROJECT_DIR/dumps/${UNZIP_DIR}/$file.img" ]; then
            DIR_NAME=$(echo $file | cut -d . -f1)
            echo -e "Mounting & copying ${DIR_NAME}"
            mkdir -p $PROJECT_DIR/dumps/${UNZIP_DIR}/$DIR_NAME $PROJECT_DIR/dumps/$UNZIP_DIR/tempmount
            # mount & permissions
            echo $user_password | sudo -S mount -o loop "$PROJECT_DIR/dumps/${UNZIP_DIR}/$file.img" "$PROJECT_DIR/dumps/${UNZIP_DIR}/tempmount" > /dev/null 2>&1
            echo $user_password | sudo -S chown -R $USER:$USER "$PROJECT_DIR/dumps/${UNZIP_DIR}/tempmount" > /dev/null 2>&1
            echo $user_password | sudo -S chmod -R u+rwX "$PROJECT_DIR/dumps/${UNZIP_DIR}/tempmount" > /dev/null 2>&1
            # copy to dump
            cp -a $PROJECT_DIR/dumps/${UNZIP_DIR}/tempmount/* $PROJECT_DIR/dumps/$UNZIP_DIR/$DIR_NAME > /dev/null 2>&1
            # unmount
            echo $user_password | sudo -S umount -l "$PROJECT_DIR/dumps/${UNZIP_DIR}/tempmount" > /dev/null 2>&1
            # if empty partitions dump, try with 7z
            if [[ -z "$(ls -A $PROJECT_DIR/dumps/$UNZIP_DIR/$DIR_NAME)" ]]; then
                7z x $PROJECT_DIR/dumps/${UNZIP_DIR}/$file.img -y -o$PROJECT_DIR/dumps/${UNZIP_DIR}/$file/ 2>/dev/null >> $PROJECT_DIR/dumps/${UNZIP_DIR}/zip.log || {
                    rm -rf $PROJECT_DIR/dumps/${UNZIP_DIR}/$file/* 2>/dev/null >> $PROJECT_DIR/dumps/${UNZIP_DIR}/zip.log
                    $PROJECT_DIR/tools/Firmware_extractor/tools/Linux/bin/fsck.erofs --extract=$PROJECT_DIR/dumps/${UNZIP_DIR}/$file $PROJECT_DIR/dumps/${UNZIP_DIR}/$file.img 2>/dev/null >> $PROJECT_DIR/dumps/${UNZIP_DIR}/zip.log2>/dev/null >> $PROJECT_DIR/dumps/${UNZIP_DIR}/zip.log
                }
            fi
            # cleanup
            rm -rf $PROJECT_DIR/dumps/${UNZIP_DIR}/$file.img $PROJECT_DIR/dumps/${UNZIP_DIR}/zip.log $PROJECT_DIR/dumps/$UNZIP_DIR/tempmount > /dev/null 2>&1
        fi
    done
done
