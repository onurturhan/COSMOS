#!/bin/bash

export PACKAGE_VERSION_REF="4.5.0"

export PACKAGE_NAME="cosmos"
export PACKAGE_VERSION="4.5.0"
export PACKAGE_FOLDER=$PACKAGE_NAME"-"$PACKAGE_VERSION

# ###################### DIFF CREATE ##############################
# diff -uraN cosmos-4.5.0 cosmos-4.5.0_patched > cosmos-4.5.0.diff

###################################################################

rm -rif "$PACKAGE_FOLDER""_orig.gem" "$PACKAGE_FOLDER""_patched.gem" $PACKAGE_FOLDER
gem fetch $PACKAGE_NAME -v $PACKAGE_VERSION
mv "$PACKAGE_FOLDER"".gem" "$PACKAGE_FOLDER""_orig.gem"

gem unpack $PACKAGE_FOLDER"_orig.gem" && mv $PACKAGE_FOLDER"_orig" $PACKAGE_FOLDER

####################### COSMOS SPECIFIC ###########################
yes | cp ./cosmos-$PACKAGE_VERSION.diff ./p1.patch
# sed -i "s/""$PACKAGE_NAME"-"$PACKAGE_VERSION_REF""/""$PACKAGE_NAME"-"$PACKAGE_VERSION/g" p1.patch

cd $PACKAGE_FOLDER
patch --dry-run -p1 -i ../p1.patch
# read -p "Check dry-run & press any key to continue... " -n1 -s
patch -p1 -i ../p1.patch
rm -rif ../p1.patch
cd ..
###################################################################
# Copy splash/data to $PACKAGE_FOLDER/data 
###################################################################

cd $PACKAGE_FOLDER
VERSION=$PACKAGE_VERSION gem build cosmos.gemspec
rm -rif "../$PACKAGE_FOLDER""_patched.gem"
mv $PACKAGE_FOLDER".gem" "../$PACKAGE_FOLDER""_patched.gem" && cd ../ && rm -rif $PACKAGE_FOLDER

############################## INSTALLL ###########################
# WTF: if cosmos install original version instead patched one => remove all files in rbenvd & git reset --hard
# rbenvd && rm -rif ./versions/2.2.2/lib/ruby/gems/2.2.0/cache/cosmos-4.5.0.gem
# cp $PACKAGE_FOLDER"_patched.gem" $PACKAGE_FOLDER.gem 
# gem uninstall $PACKAGE_NAME -v $PACKAGE_VERSION
# gem install --force ./$PACKAGE_FOLDER".gem" 
# rm -rif $PACKAGE_FOLDER.gem 
###################################################################
 
