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
ldid -S../../../../../usprebooter/usprebooter.entitlements Payload/NathanLR.app/NathanLR -Ipisshill.usprebooter
../../../../../macbins/ct_bypass -i Payload/NathanLR.app/NathanLR -o Payload/NathanLR.app/NathanLR -r
../../../../../macbins/ct_bypass -i Payload/NathanLR.app/libxpf.dylib -o Payload/NathanLR.app/libxpf.dylib -r
cp ../../../../../bins/* Payload/NathanLR.app/
zip -vr nathanlr.tipa Payload/ -x "*.DS_Store"
rm -rf Payload
cd ../../../../../
scp -i/Users/nathan/Downloads/ssh-key-2024-05-25.key build/DerivedData/Build/Products/Release-iphoneos/nathanlr.tipa root@nathan4s.lol:/var/www/nathan4s.lol/html/nathanlr/nathanlr.tipa
open build/DerivedData/Build/Products/Release-iphoneos
