#!/bin/bash

echo "Testing add"
./test.sh add32
cp *.vmh ./../bluesim/
cd ..
timeout 60 make run.bluesim
cd ./_unused

echo "Testing and"
./test.sh and32
cp *.vmh ./../bluesim/
cd ..
timeout 60 make run.bluesim
cd ./_unused

echo "Testing or"
./test.sh or32
cp *.vmh ./../bluesim/
cd ..
timeout 60 make run.bluesim
cd ./_unused

echo "Testing sub"
./test.sh sub32
cp *.vmh ./../bluesim/
cd ..
timeout 60 make run.bluesim
cd ./_unused

echo "Testing xor" 
./test.sh xor32
cp *.vmh ./../bluesim/
cd ..
timeout 60 make run.bluesim
cd ./_unused

echo "Testing hello"
./test.sh hello32
cp *.vmh ./../bluesim/
cd ..
timeout 60 make run.bluesim
cd ./_unused

echo "Testing mul"
./test.sh mul32
cp *.vmh ./../bluesim/
cd ..
timeout 60 make run.bluesim
cd ./_unused

echo "Testing reverse"
./test.sh reverse32
cp *.vmh ./../bluesim/
cd ..
timeout 60 make run.bluesim
cd ./_unused

echo "Testing thelie"
./test.sh thelie32
cp *.vmh ./../bluesim/
cd ..
timeout 60 make run.bluesim
cd ./_unused

echo "Testing thuemorse"
./test.sh thuemorse32
cp *.vmh ./../bluesim/
cd ..
timeout 60 make run.bluesim
cd ./_unused

echo "Testing matmul"
./test.sh matmul32
cp *.vmh ./../bluesim/
cd ..
timeout 60 make run.bluesim
cd ./_unused

