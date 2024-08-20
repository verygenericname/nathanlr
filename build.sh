#!/bin/sh

set -e
rm -rf build | true
echo "Building IPA"
xcodebuild clean build -scheme nathanlr -configuration Release -derivedDataPath build/DerivedData CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED="NO"
echo "done building"
cd build/DerivedData/Build/Products/Release-iphoneos
rm -rf Payload
rm -rf FUCK.tipa
mkdir Payload
mv nathanlr.app Payload
ldid -S../../../../../usprebooter/usprebooter.entitlements Payload/nathanlr.app/nathanlr -Ipisshill.usprebooter
../../../../../macbins/ct_bypass -i Payload/nathanlr.app/nathanlr -o Payload/nathanlr.app/nathanlr -r
../../../../../macbins/ct_bypass -i Payload/nathanlr.app/libxpf.dylib -o Payload/nathanlr.app/libxpf.dylib -r
cp ../../../../../bins/* Payload/nathanlr.app/
zip -vr nathanlr.tipa Payload/ -x "*.DS_Store"
rm -rf Payload
cd ../../../../../
scp -i/Users/nathan/Downloads/ssh-key-2024-05-25.key build/DerivedData/Build/Products/Release-iphoneos/nathanlr.tipa root@nathan4s.lol:/var/www/nathan4s.lol/html/nathanlr/nathanlr.tipa
open build/DerivedData/Build/Products/Release-iphoneos
