5 PRINT "Type two characters..."
6 Key1$="": Key2$=""
10 REPEAT
15   Key1$=GET$
20   Key2$=GET$
30   IF Key2$<>"" PRINT "Key 1: ";Key1$
40 UNTIL Key2$<>""
50 PRINT "Key2: ";Key2$
100 PRINT "Complete."
