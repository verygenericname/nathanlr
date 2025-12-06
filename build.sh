#!/bin/sh

set -e
rm -rf build | true
echo "Building IPA"
xcodebuild clean build -scheme NathanLR -configuration Release -derivedDataPath build/DerivedData CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED="NO"
echo "done building"
cd build/DerivedData/Build/Products/Release-iphoneos
rm -rf Payload
rm -rf nathanlr.tipa
mkdir Payload
mv NathanLR.app Payload
codesign -f -s - Payload/NathanLR.app/NathanLR --entitlements ../../../../../usprebooter/usprebooter.entitlements --identifier com.nathan.nathanlr
cp ../../../../../bins/* Payload/NathanLR.app/
zip -vr nathanlr.tipa Payload/ -x "*.DS_Store"
rm -rf Payload
cd ../../../../../
open build/DerivedData/Build/Products/Release-iphoneos
