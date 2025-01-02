   10 REM *****************
   20 REM Light Cycle Racer
   30 REM    By Mark Ray
   40 REM *****************
   50 REM NC100 Version
   60 REM Downloaded from Tim's Amstrad NC Users' Site
   70 REM http://www.ncus.org.uk
   80 REM Originally from the Amstrad Notepad Users' Web
   90 ON ERROR CLOSE#0:REPORT:PRINT " at ";ERL:END
  100 CLS:PRINT SPC(32);"LIGHT CYCLE RACER"
  110 PRINT''SPC(24);"Read printed sheet before playing.";GET
  120 REPEAT:CLS:INPUT LINE "Name of Racetrack";N$:IF LEN(N$) THEN F$=N$
  130   F=OPENIN(F$):REPEAT:INPUT#F,X$:PRINT CHR$(11);X$:UNTIL EOF#F:CLOSE#F
  140   T=TIME:MOVE 0,0:X=0:Y=0:DX=1:DY=1:NX=0:NY=0
  150   REPEAT:X=NX:Y=NY:DRAW X,Y:K$=INKEY$(10)
  160     DX=DX+(K$="Z")-(K$="X"):DY=DY+(K$="/")-(K$="'"):NX=X+DX:NY=Y+DY
  170     HIT=POINT(NX,NY):DONE=(X<7)AND(Y>57):UNTIL HIT
  180   VDU30:IF DONE PRINT "Time:";(TIME-T)DIV96;"s."
  190   K=GET:UNTILK=32