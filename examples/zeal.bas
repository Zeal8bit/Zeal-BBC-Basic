  1 CLS
  5 FG=5:BG=143:HL1=13:HL2=11
  6 PRINT "BBC BASIC (Z80) Version 3.00"
  7 PRINT "(C) Copyright R.T.Russell 1987"
  8 PRINT "Modified for Zeal 8-bit Computer"
 10 PRINT
 15 COLOR FG: COLOR BG
 20 PRINT "  .----------------.  "
 30 PRINT " | ";: COLOR HL2: PRINT ".--------------.";: COLOR FG: PRINT " | "
 40 PRINT " | ";: COLOR HL2: PRINT "|  ";: COLOR HL1: PRINT " ________ ";: COLOR HL2: PRINT "  |";: COLOR FG: PRINT " | "
 50 PRINT " | ";: COLOR HL2: PRINT "|  ";: COLOR HL1: PRINT "|  __   _|";: COLOR HL2: PRINT "  |";: COLOR FG: PRINT " | "
 60 PRINT " | ";: COLOR HL2: PRINT "|  ";: COLOR HL1: PRINT "|_/  / /  ";: COLOR HL2: PRINT "  |";: COLOR FG: PRINT " | "
 70 PRINT " | ";: COLOR HL2: PRINT "|  ";: COLOR HL1: PRINT "   .'.' _ ";: COLOR HL2: PRINT "  |";: COLOR FG: PRINT " | "
 80 PRINT " | ";: COLOR HL2: PRINT "|  ";: COLOR HL1: PRINT " _/ /__/ |";: COLOR HL2: PRINT "  |";: COLOR FG: PRINT " | "
 90 PRINT " | ";: COLOR HL2: PRINT "|  ";: COLOR HL1: PRINT "|________|";: COLOR HL2: PRINT "  |";: COLOR FG: PRINT " | "
100 PRINT " | ";: COLOR HL2: PRINT "|              |";: COLOR FG: PRINT " | "
110 PRINT " | ";: COLOR HL2: PRINT "'--------------'";: COLOR FG: PRINT " | "
120 PRINT "  '----------------'  "
130 PRINT
200 COLOUR 15: COLOUR 128: REM Reset colors