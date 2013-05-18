SOLR=~/Downloads/solr-4.3.0

javac -cp "$SOLR/dist/solr-solrj-4.3.0.jar" MakeData.java

java -cp "$SOLR/dist/solr-solrj-4.3.0.jar:$SOLR/dist/solrj-lib/*:." MakeData
