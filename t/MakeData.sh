VER=4.4.0
SOLR=~/Downloads/solr-$VER

javac -cp $SOLR/dist/solr-solrj-$VER.jar MakeData.java

java -cp $SOLR/dist/solr-solrj-$VER.jar:$SOLR/dist/solrj-lib/*:. MakeData
