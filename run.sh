#!/bin/bash

# ############ DIFF CREATE 
# diff -uraN cosmos-4.4.2 cosmos-4.4.2_patched > cosmos-4.4.2.diff

export PACKAGE_VERSION_REF="4.4.2"

export PACKAGE_NAME="cosmos"
export PACKAGE_VERSION="4.4.2"
export PACKAGE_FOLDER=$PACKAGE_NAME"-"$PACKAGE_VERSION

rm -rif $PACKAGE_FOLDER".gem" $PACKAGE_FOLDER"_patched.gem" $PACKAGE_FOLDER

gem fetch $PACKAGE_NAME -v $PACKAGE_VERSION
gem unpack $PACKAGE_FOLDER".gem"

####################### COSMOS SPECIFIC #####################################

cp ./cosmos-$PACKAGE_VERSION.diff ./p1.patch
sed -i "s/""$PACKAGE_NAME"-"$PACKAGE_VERSION_REF""/""$PACKAGE_NAME"-"$PACKAGE_VERSION/g" p1.patch

cd $PACKAGE_FOLDER
patch --dry-run -p1 -i ../p1.patch
read -p "Check dry-run & press any key to continue... " -n1 -s
patch -p1 -i ../p1.patch

rm -rif ../p1.patch
cd ..

#############################################################################

cd $PACKAGE_FOLDER
VERSION=$PACKAGE_VERSION gem build cosmos.gemspec

gem uninstall $PACKAGE_NAME -v $PACKAGE_VERSION
gem install $PACKAGE_FOLDER".gem" --force

mv $PACKAGE_FOLDER".gem" ../$PACKAGE_FOLDER"_patched.gem" && cd ../ && rm -rif $PACKAGE_FOLDER $PACKAGE_FOLDER".gem"
 
