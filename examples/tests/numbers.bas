10 Total$=""
20 PRINT "Type your number or Enter to finish"
30 REPEAT
40   Key$=GET$
50   IF Key$ < "0" OR Key$ > "9" THEN GOTO 80
60   Total$=Total$+Key$
70   PRINT Key$;
80 UNTIL ASC(Key$) = 10
90 PRINT: PRINT "You entered: ";VAL(Total$)
