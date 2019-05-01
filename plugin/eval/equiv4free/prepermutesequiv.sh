#!/bin/bash

# Once you have uncommented the extremely costly normalization in main.v, this script
# verifies the claim that it timed out in an hour trying to normalize it.
# Go grab a coffee or something.

if [ -e ../out ]
then
  rm -r ../out
else
  :
fi

if [ -e mainequiv2.v ]
then
  rm mainequiv2.v
else
  :
fi

mkdir ../out
mkdir ../out/inorder
mkdir ../out/postorder
mkdir ../out/preorder
mkdir ../out/search
mkdir ../out/equivalences
mkdir ../out/normalized

# Remake DEVOID case study code exactly once, to print terms
cd ..
make clean
make

# Copy the produced equivalences into the EFF code
for f in $(find out/equivalences/*.out); do
  name=$(basename "${f%.*}")
  line=$(grep -n "     : forall" $f | cut -d : -f 1)
  head -n $(($line-1)) $f > out/equivalences/$name-notyp.out
  dirname=$(echo $name | cut -d '-' -f 1)
  suffix=$(echo $name | cut -d '-' -f 2)
  defname=$dirname"'"
  sed -i "s/$defname =/Definition $defname :=/" out/equivalences/$name-notyp.out
  echo "." >> out/equivalences/$name-notyp.out
  term=$(cat out/equivalences/$name-notyp.out)

  # https://stackoverflow.com/questions/29613304/is-it-possible-to-escape-regex-metacharacters-reliably-with-sed
  IFS= read -d '' -r < <(sed -e ':a' -e '$!{N;ba' -e '}' -e 's/[&/\]/\\&/g; s/\n/\\&/g' <<<"$term")
  term=${REPLY%$'\n'}
  
  sed -i "s/(\* EQUIV $name \*)/$term/" equiv4free/mainequiv2.v
done

# Remake Univalent Parametricity case study code
cd equiv4free
make clean

echo "grab a coffee or a book; this will take an hour once you've uncommented the right line"
timeout 1h `time make equiv`

