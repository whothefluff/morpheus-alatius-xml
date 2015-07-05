cd stemlib/Latin
rm stemsrc/nom.irreg
rm stemsrc/vbs.irreg
export PATH=$PATH:../../bin
MORPHLIB=.. make
cd ../..
