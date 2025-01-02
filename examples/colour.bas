10 CLS
20 FOR y=0 TO 15
25   COLOR y+128: REM Background
30   FOR x=0 TO 40
35     COLOR 15-y: REM Foreground
40     PRINT "*";
50   NEXT x
55   PRINT ""
60 NEXT y
70 COLOUR 15: COLOUR 128: REM Reset colors