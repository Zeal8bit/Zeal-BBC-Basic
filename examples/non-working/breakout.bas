10 REM ***************
20 REM    Breakout!
30 REM   By Mark Ray
40 REM ***************
50 REM NC100 Version
60 REM Downloaded from Tim's Amstrad NC User's Site
70 REM http://www.ncus.org.uk
80 REM Originally from the Amstrad Notepad Users' Web
90 REPEAT
100   CLS:PRINT SPC(36);"BREAKOUT"''SPC(32);"Q - Up  A - Down";'''SPC(26);
110   INPUT "Difficulty (1=Hard 5=Easy)";DIFF
120   X=RND(-TIME):DY=1:BY=4:CLS
130   FOR T=0TO7:FOR C=0TO15STEP15
140       PRINTTAB(40+C,T);STRING$(5,CHR$(219));STRING$(5,CHR$(175));STRING$(5,CHR$(221));
150     NEXT:PRINT STRING$(5,CHR$(219));:NEXT
160   BS=3:REPEAT:DX=4:X=90:Y=1:PROCball(X,Y)
170     REPEAT:PRINTTAB(9,BY);STRING$(DIFF,CHR$(219));
180       PT=POINT(X+DX,Y+DY):DX=DX+2*DX*(PT=1)
190       DY=-DY*(PT=0)+DY*(PT=-1)-DY*RND(6-DIFF)*(PT=1)/ABS(DY)
200       PROCball(X,Y):IFPT=1ANDX>90 THEN VDU 31,FNcx,FNcy,32,32
210       X=X+DX:Y=Y+DY:PROCball(X,Y):K$=INKEY$(0)
220       IF K$<>"" THEN PRINTTAB(9,BY);STRING$(DIFF," ");
230       BY=BY-(K$="A")+(K$="Q"):BY=BY-(BY<0)+(BY>7)
240     UNTIL X<0 OR X>450
250     BS=BS-1:UNTIL BS=0 OR X>450
260   VDU30:IF X<450 THEN PRINT "Game Over." ELSE PRINT "Break Out!"
270   PRINT '"Another Go(Y/N)?":K$=GET$:UNTIL K$="N"
280 CHAIN"AUTO"
290 DEFFNcx=X DIV6
300 DEFFNcy=7-((Y+DY-1)DIV8)
310 DEFPROCball(X,Y)
320 MOVE X,Y-2:PLOT 98,2,4:ENDPROC