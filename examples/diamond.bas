   10 REM *********************
   20 REM Return of the diamond
   30 REM *********************
   40 REM NC100/200
   50 REM Downloaded from Tim's NC Users' Site
   60 REM http://www.ncus.org.uk
   70 PROCset_up
   80 PROCtitle
   90 PROClook
  100 REPEAT
  110   REPEAT
  120     INPUT"What now",c$
  130     IF LEN(c$)=0THENPRINT"Eh?"
  140   UNTIL LEN(c$)>0
  150   PRINTSTRING$(39,"-")
  160   PROCanalise
  170   PROCtime_passing
  180 UNTILdead OR won
  190 PROCfinish
  200 RUN
  210 DEFPROCset_up
  220 DIM place$(9)
  230 FOR I=1TO9
  240   READ place$(I)
  250 NEXT
  260 DATA in a hut,in a garden
  270 DATA in a shrubbery,on a path
  280 DATA on a lane,in a forest
  290 DATA at a dead end,at diamond castle
  300 DATA in a dark passage
  310 DIM newpos(9,4)
  320 FOR I=1TO9
  330   FOR J=1TO4
  340     READ newpos(I,J)
  350   NEXT
  360 NEXT
  370 DATA 0,2,0,0,0,0,5,1,0,0,6,0
  380 DATA 0,5,7,0,2,6,0,4,3,0,9,5
  390 DATA 4,0,0,0,0,9,0,0,6,0,0,8
  400 DIM item$(6),itemname$(6),itempos(6)
  410 FORI=1TO6
  420   READitem$(I),itemname$(I),itempos(I)
  430 NEXT
  440 DATA a lamp,LAMP,5
  450 DATA the great diamond,DIAMOND,7
  460 DATA a sharp knife,KNIFE,3
  470 DATA a hammer,HAMMER,1
  480 DATA a mean looking gremlin,GREMLIN,4
  490 DATA a nasty little pixie,PIXIE,9
  500 DIMcom$(7)
  510 FOR I=1TO7
  520   READ com$(I)
  530 NEXT
  540 DATA GET,TAKE,ON,LIGHT,OFF,DROP,KILL
  550 DIM direct$(4)
  560 FORI=1TO4
  570   READdirect$(I)
  580 NEXT
  590 DATANorth,East,South,West
  600 DIM bright$(2)
  610 bright$(0)="( It's off )"
  620 bright$(1)="( It's shining dimly )"
  630 bright$(2)="( It's shining brightly )"
  640 on=FALSE
  650 reallit=2.9
  660 lit=2
  670 position=1
  680 dead=FALSE
  690 won=FALSE
  700 moves=0
  710 score=30
  720 carried=0
  730 ENDPROC
  740 DEF PROCtitle
  750 CLS:PRINT"RETURN OF THE DIAMOND"
  760 ENDPROC
  770 DEF PROClook
  780 IF(position=6 OR position=9)AND(NOT on OR (itempos(1)<>position AND itempos(1)<>0)) THEN PRINT"It is pitch dark.":ENDPROC
  790 PRINT'"You are ";place$(position)'
  800 PRINT"Exits : ";
  810 FORI=1TO4
  820   IF newpos(position,I)>0 THEN PRINT direct$(I);":";
  830 NEXT
  840 PRINT''"You can see :";
  850 printed=FALSE
  860 FOR I=1TO6
  870   IF itempos(I)=position THEN PRINTitem$(I):printed=TRUE
  880   IF itempos(I)=position AND I=1 AND NOT on THEN PRINT bright$(0)
  890   IF itempos(I)=position AND I=1 AND on THEN PRINT bright$(lit)
  900 NEXT
  910 IF NOT printed THEN PRINT"nothing."
  920 ENDPROC
  930 DEFPROCanalise
  940 IF LEN(c$)=1 THEN IF INSTR("NESW",c$)>0 THEN PROCmove:ENDPROC
  950 IF c$="LOOK" THEN PROClook:ENDPROC
  960 IF LEFT$(c$,3)="INV" THEN PROCinventory:ENDPROC
  970 IF c$="SCORE"THENPRINT"Your score is ";score;".":ENDPROC
  980 IF c$="MOVES"THENPRINT"Moves made : ";moves:ENDPROC
  990 PROCother_commands
 1000 ENDPROC
 1010 DEF PROCtime_passing
 1020 score=score-1
 1030 moves=moves+1
 1040 dimmed=FALSE
 1050 IF on THEN reallit=reallit-0.1:dimmed=TRUE
 1060 lit=INT(reallit)
 1070 IF dimmed AND lit=0 THEN PRINT"Your lamp just went out.":on=FALSE
 1080 won=(position=8 AND itempos(2)=8)
 1090 ENDPROC
 1100 DEF PROCmove
 1110 dir=INSTR("NESW",c$)
 1120 IF newpos(position,dir)=0 THEN PRINT"You can't move in that direction.":ENDPROC
 1130 IF (position=6 OR position=9) AND(NOT on OR(itempos(1)<>position AND itempos(1)<>0)) THEN PRINT"You have fallen into a snake pit!":dead=TRUE:ENDPROC
 1140 position=newpos(position,dir)
 1150 PROClook
 1160 ENDPROC
 1170 DEF PROCinventory
 1180 PRINT''"You are carrying :"
 1190 printed=FALSE
 1200 FORI=1TO6
 1210   IFitempos(I)=0THEN PRINT item$(I):printed=TRUE
 1220   IFitempos(I)=0 AND I=1 AND NOT on THEN PRINTbright$(0)
 1230   IFitempos(I)=0 AND I=1 AND on THEN PRINTbright$(lit)
 1240 NEXT
 1250 IF NOT printed THEN PRINT"nothing."
 1260 ENDPROC
 1270 DEF PROCother_commands
 1280 comno=FNcommand
 1290 thingno=FNthing
 1300 IF comno=0 OR thingno=0 THENPRINT"Sorry, I don't understand.":ENDPROC
 1310 ON comno GOTO 1320,1320,1330,1330,1340,1350,1360
 1320 PROCtake:ENDPROC
 1330 PROClight:ENDPROC
 1340 PROCoff:ENDPROC
 1350 PROCdrop:ENDPROC
 1360 PROCkill:ENDPROC
 1370 ENDPROC
 1380 DEF FNcommand
 1390 no=0:I=0
 1400 REPEAT
 1410   I=I+1
 1420   IF LEFT$(c$,LEN(com$(I)))=com$(I) THEN no=I
 1430 UNTIL no>0 OR I=7
 1440 =no
 1450 DEF FNthing
 1460 no=0:I=0
 1470 REPEAT
 1480   I=I+1
 1490   IF RIGHT$(c$,LEN(itemname$(I)))=itemname$(I) THEN no=I
 1500 UNTIL no>0 OR I=6
 1510 =no
 1520 DEF PROCtake
 1530 IF itempos(thingno)<>position THEN PRINT"I don't see that here.":ENDPROC
 1540 IF thingno=5 OR thingno=6 THEN PRINT"You'll be lucky!":ENDPROC
 1550 IF carried=3 THEN PRINT"You can't carry any more.":ENDPROC
 1560 itempos(thingno)=0
 1570 PRINT"O.K."
 1580 carried=carried+1
 1590 ENDPROC
 1600 DEF PROClight
 1610 IF itempos(thingno)<>0 THEN PRINT"I would if you had it.":ENDPROC
 1620 IF thingno<>1 THEN PRINT"You're joking!":ENDPROC
 1630 IF on THEN PRINT"It's already on.":ENDPROC
 1640 IF lit=0 THEN PRINT"It won't relight.":ENDPROC
 1650 PRINT"O.K."
 1660 on=TRUE
 1670 ENDPROC
 1680 DEF PROCoff
 1690 IF itempos(thingno)<>0 THEN PRINT"You're not carrying that.":ENDPROC
 1700 IF thingno<>1 THEN PRINT"You're joking!":ENDPROC
 1710 IF NOT on THEN PRINT"It's already off.":ENDPROC
 1720 PRINT"O.K." 
 1730 on=FALSE
 1740 ENDPROC
 1750 DEF PROCdrop
 1760 IF itempos(thingno)<>0 THEN PRINT"But you haven't got that.":ENDPROC
 1770 itempos(thingno)=position
 1780 PRINT"O.K."
 1790 carried=carried-1
 1800 ENDPROC
 1810 DEF PROCkill
 1820 IF itempos(thingno)<>position THEN PRINT"I don't see that here.":ENDPROC
 1830 IF thingno=5 THEN PROCkill_gremlin:ENDPROC
 1840 IF thingno=6 THEN PROCkill_pixie:ENDPROC
 1850 PRINT"You're joking!"
 1860 ENDPROC
 1870 DEF PROCkill_gremlin
 1880 IF itempos(3)=0 THEN PRINT"You slash your knife at the gremlin and kill it easily.":itempos(5)=-1:score=score+10:ENDPROC
 1890 IF itempos(4)=0 THEN PRINT"You throw your hammer at the gremlin,but it catches it and throws it back.":ENDPROC
 1900 PRINT"You fight the gremlin bare handed,but only succeed in getting killed."
 1910 dead=TRUE
 1920 ENDPROC
 1930 DEF PROCkill_pixie
 1940 IF itempos(4)=0 THEN PRINT"You throw your hammer at the pixie......A hit!":itempos(6)=-1:score=score+10:ENDPROC
 1950 IF itempos(3)=0 THEN PRINT"You slash your knife at the pixie but it dodges.":ENDPROC
 1960 PRINT"You fight the pixie bare handed but    it is stronger than you thought. You get killed."
 1970 dead=TRUE
 1980 ENDPROC
 1990 DEF PROCfinish
 2000 PRINT''
 2010 IF won THEN PRINT"    Congratulations!!!    You won!!!"
 2020 IF dead THEN PRINT"    Bad luck!!!    You lost!!!":score=0
 2030 PRINT''"   You took ";moves;" moves,"
 2040 PRINT"   and your final score was ";score;"."
 2050 PRINT"   Press SPACE to play again."
 2060 REPEAT UNTIL GET$=" "