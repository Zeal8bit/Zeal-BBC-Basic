    1 REM *********************************************
    2 REM              Neptunes' Caverns
    3 REM Programmed by Steve Rodgers and Marcus Milton
    4 REM  Adapted from BBC version by Timothy Surtell
    5 REM *********************************************
    6 REM NC200 Version
    7 REM Downloaded from Tim's NC Users' Site
    8 REM http://www.ncus.org.uk
   40 PROCinitialise
   50 REPEAT
   60   PROCinput
   70   PROCsort
   80 UNTIL wf=TRUE OR lf=TRUE
   90 PROCend
  100 END
  110 REM ***Input***
  120 DEF PROCinput
  130 vb$="":no$=""
  140 PRINTSTRING$(80,"-"):INPUT"What do you do next ? "r$
  150 IF r$="" GOTO140
  160 FORI=1 TO LEN(r$)
  170   IF MID$(r$,I,1)=" " vb$=LEFT$(r$,3):no$=MID$(r$,I+1,3):I=LEN(r$)
  180 NEXT
  190 IF vb$="GO " OR vb$="MOV" vb$="GO":ENDPROC
  200 IF no$<>"" ENDPROC
  210 r$=LEFT$(r$,3)
  220 IF r$="NOR" OR r$="SOU" OR r$="EAS" OR r$="WES" vb$="GO":no$=r$:ENDPROC
  230 IF r$="HEL" OR r$="INV" OR r$="LOO" no$="DOO":vb$=r$:ENDPROC
  240 PRINT"I don't understand that!"
  250 GOTO140
  260 REM ***Sort***
  270 DEF PROCsort
  280 vb=0:no=0:FORI=1 TO vv
  290   IF vb$=LEFT$(vb$(I),3) vb=I:I=vv
  300 NEXT
  310 FORI=1 TO nn
  320   IF no$=no$(I) no=I:I=nn
  330 NEXT
  340 IF no=0 OR vb=0 PRINT"I don't understand that!":ENDPROC
  350 ON vb GOTO360,410,410,500,500,620,620,700,750,870,870,940,1000,1050,1100
  360 REM ***Go***
  370 IF no>4 PRINT"Go where ?":ENDPROC
  380 IF ex(cp,no)=0 PRINT"There is no exit that way!":ENDPROC
  390 IF cp=16 AND (no=1 OR no=4) AND ff=FALSE lf=TRUE:ENDPROC
  400 cp=ex(cp,no):GOTO1100
  410 REM ***Get***
  420 IF no=6 AND cp=13 PRINT"It's too heavy!":ENDPROC
  430 IF no<8 PRINT"Don't be silly!":ENDPROC
  440 IF ob(no-7)=99 AND no$<>"HAN" PRINT"You've already got it!":ENDPROC
  450 FORI=7 TO 10
  460   IF ob(I)=cp AND no=14 no=I+7:hc=hc+1:I=10
  470 NEXT
  480 IF ob(no-7)=cp PRINT"O.K":ob(no-7)=99:in=in+1:ENDPROC
  490 PRINT"It isn't here!":ENDPROC
  500 REM ***Drop***
  510 IF cp=3 AND ob(1)=99 AND vb$="THR" PRINT"The knife slams hard into the door.  You cannot remove it.":lo$(3)=lo$(3)+"  A knife is wedged into the door.":ob(1)=0:in=in-1:ENDPROC
  520 IF cp=9 AND ob(1)=99 AND vb$="THR" PRINT"The knife slams hard into the door.  You cannot remove it.":lo$(9)=lo$(9)+"  A knife is wedged into the door.":ob(1)=0:in=in-1:ENDPROC
  530 IF cp=20 AND ob(1)=99 AND vb$="THR" AND ex(20,4)=0 PRINT"The knife hits the octopus.  He only gets more angry.":lf=TRUE:ENDPROC
  540 IF no<8 PRINT"Don't be silly!":ENDPROC
  550 FORI=7 TO 10
  560   IF ob(I)=99 AND no=14 no=I+7:hc=hc-1:I=10
  570 NEXT
  580 IF ob(no-7)<>99 PRINT"You haven't got it!":ENDPROC
  590 PRINT"O.K":ob(no-7)=cp:in=in-1
  600 IF cp=19 AND no=13 wf=TRUE
  610 ENDPROC
  620 REM ***Cut***
  630 IF ob(1)<>99 PRINT"You've nothing sharp enough!":ENDPROC
  640 IF no<>11 PRINT"You can't cut that!":ENDPROC
  650 IF cp<>5 PRINT"You can't do that!":ENDPROC
  660 IF cf=TRUE PRINT"You've already done that!":ENDPROC
  670 PRINT"The seaweed falls away to reveal an open window."
  680 ob(4)=5:ex(5,2)=11:cf=TRUE
  690 lo$(5)=LEFT$(lo$(5),58)+"an open window in it.":ENDPROC
  700 REM ***Wear***
  710 IF ff=TRUE AND no$="FLI" PRINT"You've already got them on!":ENDPROC
  720 IF ob(2)=99 AND no$="FLI" ff=TRUE:ob(2)=0:PRINT"They fit nicely!":ENDPROC
  730 IF no=14 AND hc>0 PRINT"That's really silly!":ENDPROC
  740 PRINT"You can't wear that!":ENDPROC
  750 REM ***Give***
  760 IF cp=10 AND no=11 GOTO800
  770 IF cp=7 AND no=12 GOTO830
  780 IF cp=20 PRINT"That won't do any good!":ENDPROC
  790 PRINT"Nothing here want's it!":ENDPROC
  800 IF ob(4)<>99 PRINT"You haven't got it!":ENDPROC
  810 ob(4)=0:ob(3)=10
  820 PRINT"They crowd around you and something glints in the corner.":ENDPROC
  830 IF ob(5)<>99 PRINT"You haven't got it!":ENDPROC
  840 ob(5)=0:ex(7,2)=13
  850 PRINT"The fish snatches a bone and retires to a corner."
  860 lo$(7)="You are in a low cavern.  A dog fish is in a corner gnawing on a thigh bone.":ENDPROC
  870 REM ***Unlock***
  880 IF ob(3)<>99 PRINT"You haven't got a key!":ENDPROC
  890 IF no=5 AND (cp=3 OR cp=9) PRINT"There isn't even a keyhole!":ENDPROC
  900 IF cp<>13 OR no<>6 PRINT"You can't do that!":ENDPROC
  910 IF uf=TRUE PRINT"It's already unlocked!":ENDPROC
  920 uf=TRUE:ob(7)=13:PRINT"The key turns easily."
  930 lo$(13)="You are in a room that has a large open chest in the middle.":ENDPROC
  940 REM ***Use***
  950 IF cp<>20 OR no<>14 PRINT"You can't do that here!":ENDPROC
  960 IF hc<4 PRINT"You haven't got enough pairs!":ENDPROC
  970 PRINT"The octopus can't move.  He isn't amused!"
  980 FORI=7 TO 10:ob(I)=0:NEXT
  990 hc=0:ex(20,4)=19:lo$(20)=LEFT$(lo$(20),57)+"A manacled octopus sitssulking.":ENDPROC
 1000 REM ***Inventory***
 1010 PRINT"You are carrying :-"'
 1020 IF in=0 PRINT"Nothing!":ENDPROC
 1030 FORI=1 TO 10:IF ob(I)=99 PRINT"A ";ob$(I)
 1040 NEXT:ENDPROC
 1050 REM ***Help***
 1060 PRINT"These are the words you may use :-"'
 1070 PRINT"NORTH SOUTH EAST WEST MOVE ";:FORI=1 TO 7:PRINT;vb$(I);" ";:NEXT:PRINT:FORI=8 TO vv:PRINT;vb$(I);" ";:NEXT
 1080 PRINT'"(You need only type the first 3 letters)"
 1090 ENDPROC
 1100 REM ***Look***
 1110 PRINT'lo$(cp):IF cp=22 lf=TRUE:ENDPROC
 1120 FORI=1 TO 10
 1130   IF I=5 AND cp=15 GOTO1150
 1140   IF ob(I)=cp PRINT"A ";ob$(I);" is here."
 1150 NEXT
 1160 PRINT'"Exits : ";
 1170 IF ex(cp,1)>0 PRINT"North ";
 1180 IF ex(cp,2)>0 PRINT"South ";
 1190 IF ex(cp,3)>0 PRINT"East ";
 1200 IF ex(cp,4)>0 PRINT"West ";
 1210 PRINT':ENDPROC
 1220 REM ***Initialise***
 1230 DEF PROCinitialise
 1240 CLS:PRINTTAB(23,0)CHR$19"N e p t u n e ' s    C a v e r n s"CHR$20TAB(2,2)"Programmed by Steve Rodgers and Marcus Milton.   Adapted by Timothy Surtell."
 1250 PRINT'"Press any key to start.  Type HELP for assistance at any time..."
 1260 nn=14:vv=15:cp=3:in=1:hc=0:wf=FALSE:lf=FALSE:uf=FALSE:ff=FALSE:cf=FALSE
 1270 DIMlo$(24),ex(24,4),no$(nn),vb$(vv),ob$(10),ob(10)
 1280 FORI=1 TO 24
 1290   IF I=17 OR I=18 OR I=23 OR I=24 lo$(I)=lo$(12):GOTO1310
 1300   READd$:lo$(I)=d$
 1310 NEXT
 1320 FORI=1 TO 24:FORJ=1 TO 4:READex(I,J):NEXT:NEXT
 1330 FORI=1 TO 10:READob$(I),ob(I):NEXT
 1340 FORI=1 TO nn:READno$(I):NEXT
 1350 FORI=1 TO vv:READvb$(I):NEXT
 1360 G=GET:CLS:PRINT"The story so far..."
 1370 PRINT'"You have found the magic plug that belongs at the bottom of the sea, and you"'"decide to replace it at all costs before the water drains away.  With your"'"scuba gear you dive into the ocean and begin your adventure..."
 1380 PRINTSTRING$(80,"-")
 1390 GOTO1100:REM Look
 1400 REM ***End***
 1410 DEF PROCend
 1420 IF cp=22 PRINT"With one swift bite, the shark bites off your head."''TAB(30)"T H E   E N D"':END
 1430 IF cp=20 PRINT"The octopus picks you up and strangles you to death."''TAB(30)"T H E   E N D"':END
 1440 IF cp=16 PRINT"The spines on the sea-urchins are very poisonous! You die a horrible death!     Next time take precautions!"''TAB(30)"T H E   E N D"':END
 1450 PRINT"With a thunk the plug drops into the hole and the swirling waters grow still.   CONGRATULATIONS!!!  You saved the seas!"''TAB(30)"T H E   E N D"':END
 1460 REM ***Descriptions***
 1470 DATA "You are on the seabed.  The way west is blocked by a high coral reef."
 1480 DATA "You are on the seabed.  To the south a wall towers above you."
 1490 DATA "You are in front of a wooden door set into a barnacled wall.  You can see no    handle."
 1500 DATA "You are on the seabed.  To the south a barnacled wall towers above you."
 1510 DATA "You are on the seabed.  To the south a barnacled wall has a square patch of     seaweed growing on it."
 1520 DATA "You are on the seabed.  To the south is a barnacled wall.  A cliff blocks the   way."
 1530 DATA "You are in a long, low cavern.  At the far end a large dog-like fish is swimmingaround."
 1540 DATA "You are in a brightly lit chamber.  The walls, floor and ceiling all glow in theshimmering light."
 1550 DATA "You are in a dimmly lit cavern with a huge door at the far end.  You can see no handle."
 1560 DATA "You are in a room full of hungry sea-horses!  They nuzzle your hand in a        friendly manner."
 1570 DATA "You are in a small square room.  The north wall has a small window in it,       though which you can see the seabed."
 1580 DATA "You are in an aMAZEingly square room.  The walls, floor and ceiling are all     square, as are all the exits."
 1590 DATA "You are in a tiny room that is almost totally occupied by a chest, inscribed    with the initials 'D.J'."
 1600 DATA "You are in a cold, murky room.  Grey mud swirls around you and you feel a slightcurrent to the east."
 1610 DATA "You are in a gloomy and errie place.  All around you are the bones of long dead explorers."
 1620 DATA "You are in a square room.  The south exit has the words 'DO NOT ENTER' above it.The north and west doorways are crawling with sea-urchins."
 1630 DATA "You are in a circular room with a very strong current that swirls around the    room and down a hole in the floor."
 1640 DATA "You are in a corridor with a strong current going west.  Your way is blocked by the arms of a huge rainbow coloured octopus."
 1650 DATA "You are in a shipwreaked captains cabin.  You feel the flow of water to the     west."
 1660 DATA "You see a rush of swirling water and face the jaws of a great white shark."
 1670 REM ***Exits***
 1680 DATA0,0,2,0,0,0,3,1,0,0,4,2,0,0,5,3
 1690 DATA0,0,6,4,0,0,0,5,0,0,8,0,0,14,0,7
 1700 DATA0,15,0,0,0,16,0,0,5,17,12,0,0,18,12,11
 1710 DATA7,0,0,0,8,0,15,0,9,21,16,14,10,22,17,15
 1720 DATA11,23,18,16,12,24,18,17,0,0,20,0,0,0,21,0
 1730 DATA15,0,0,20,16,0,0,0,17,23,24,0,18,24,24,23
 1740 REM ***Objects***
 1750 DATA "KNIFE",2
 1760 DATA "PAIR OF FLIPPERS",6
 1770 DATA "KEY",0
 1780 DATA "CLUMP OF SEAWEED",0
 1790 DATA "MOULDY OLD BONE",15
 1800 DATA "MAGIC PLUG",99
 1810 DATA "YELLOW PAIR OF HANDCUFFS",0
 1820 DATA "GREEN PAIR OF HANDCUFFS",9
 1830 DATA "RED PAIR OF HANDCUFFS",17
 1840 DATA "BLUE PAIR OF HANDCUFFS",11
 1850 REM ***Nouns***
 1860 DATA "NOR","SOU","EAS","WES","DOO","CHE","WIN","KNI","FLI","KEY","SEA","BON","PLU","HAN"
 1870 REM ***Verbs***
 1880 DATA "GO","TAKE","GET","DROP","THROW","CUT","CHOP","WEAR","GIVE","UNLOCK","OPEN","USE","INVENTORY","HELP","LOOK"