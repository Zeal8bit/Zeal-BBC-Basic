   10 REM *************
   20 REM  Block  Game
   30 REM  By Mark Ray
   40 REM *************
   50 REM NC100 Version
   60 REM Downloaded from Tim's Amstrad NC User's Site
   70 REM http://www.ncus.org.uk
   80 REM Originally from the Amstrad Notepad Users' Web
   90 CLS:PRINTSPC(35);"BLOCK GAME"''SPC(28);"Left:F   Down:V  Right:G"
  100 PRINT'''SPC(29);"Press any key to start";GET
  110 TDL=50:SC=0:A=RND(-TIME):CLS
  120 REPEAT:TYPE=RND(15):X=39:Y=0:FIN=FALSE:PROCdisp(X,Y)
  130   REPEAT:K$=INKEY$(TDL):PY=Y-(INSTR("FG",K$)):PROCeras(X,Y):PX=X+(K$="F")-(K$="G"):IF FNok2go2(PX,Y) THEN X=PX
  140     IF FNok2go2(X,PY) THEN Y=PY ELSE FIN=TRUE
  150     PROCdisp(X,Y):UNTIL FIN:CHK=0
  160   FORL=1TO7:CHK=CHK+FNcheck(L):NEXT
  170   TDL=TDL*0.9:SC=CHK:PRINT TAB(0,0);"Score:";SC
  180 UNTIL FNcheck(0):CHK=GET:CHAIN"AUTO"
  190 DEF FNcheck(L):LOCAL C:C=0
  200 FOR XC=31TO49:C=C-FNpt(XC,L):NEXT:=C
  210 DEFFNok2go2(X,Y):LOCAL OK:OK=TRUE
  220 FOR XC=0TO1:FOR YC=0TO1
  230     IFFNpt(XC+X,YC+Y) AND FNblk(XC,YC) THEN OK=FALSE
  240   NEXT:NEXT:=OK
  250 DEF PROCdisp(X,Y)
  260 FOR XC=0TO1:FOR YC=0TO1
  270     IFFNblk(XC,YC) THEN VDU 31,X+XC,Y+YC,219
  280   NEXT:NEXT:ENDPROC
  290 DEF PROCeras(X,Y)
  300 VDU 14:PROCdisp(X,Y):VDU 15:ENDPROC
  310 DEF FNpt(X,Y):=(POINT((6*X)+3,(8*(7-Y))+4)<>0)
  320 DEF FNblk(X,Y):=(TYPE AND(2^(Y*2+X)))