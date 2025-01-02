   10 REM ***********************
   20 REM The Crystal of Nebumeth
   30 REM      By Ian Larkin
   40 REM ***********************
   50 REM NC100/200 Version : 01/02
   60 REM Downloaded from Tim's Amstrad NC Users' Site
   70 REM http:\\www.ncus.org.uk
   80 :
   90 PROCinit
  100 PRINT "You are "L$(R)"."'
  110 IF R=4 OR R=5 THEN PRINT "A ferry boat is moored here. An elfish ferryman sits inside it reading a 'Barry Plotter' book."'
  120 T=0:FOR N=1 TO 13:IF R(N)=R T=N
  130 NEXT:IF T=0 GOTO 160
  140 PRINT "You can see ";:FOR N=1 TO 13:IF R(N)=R PRINT O$(N);:IF N<T PRINT ", ";
  150 NEXT:PRINT"."'
  160 IF F(15)=1 PRINT "A bus conductor stands here, looking around sheepishly."'
  170 IF F(R)=0 AND F$(R)<>"1" PRINT F$(R)'
  180 IF R=21 AND F(15)=1 AND F(21)=0 PRINT "The lightning is discharged harmlessly by the conductor."'
  190 IF R=21 AND F(15)=0 AND F(21)=0 PRINT "You get fried. Oh dear.":PROCagain
  200 IF R=8 AND F(R)=0 F(R)=1:L$(8)=L$(8)+". A fallen tree blocks the way east"
  210 PRINT "Exits: ";
  220 IF E(R,1)>0 PRINT"North ";
  230 IF E(R,2)>0 PRINT"South ";
  240 IF E(R,3)>0 PRINT"East ";
  250 IF E(R,4)>0 PRINT"West ";
  260 IF R=4 OR R=5 THEN PRINT "In";
  270 PRINT'
  280 INPUT "What now? "I$
  290 IF LEFT$(I$,3)="GO " THEN I$=RIGHT$(I$,LEN(I$)-3)
  300 IF I$="IN" GOTO 480
  310 V=INSTR("NSEW",I$): IF V>0 GOTO 400
  320 V=INSTR(V$,LEFT$(I$+"  ",3)):IF V=0 THEN PRINT "I don't understand you.":GOTO 280
  330 IF V=1 OR V=4 OR V=7 OR V=10 THEN I$=LEFT$(I$,1):GOTO 310
  340 IF R=9 PRINT "You are attacked and killed by a swamp monster. Oh dear.":PROCagain
  350 V=(V-1)/3-3
  360 N=INSTR(I$," "):IF N>0 N$=RIGHT$(I$,LEN(I$)-N):N$=LEFT$(N$,3) ELSE N$=""
  370 IF N$>"" GOTO 390
  380 IF V=1 OR V=2 OR V=10 OR V=20 OR V=24 GOTO 390 ELSE PRINT "That verb needs a noun.":GOTO 280
  390 ON V GOTO 530,100,540,540,600,630,680,830,920,1020,1060,1100,1200,1260,1310,1310,1360,1410,1440,1500,1530,1580,1580,1620
  400 IF (R=4 AND V=3) OR (R=5 AND V=4) THEN PRINT "You try to swim across the river but are attacked by geese and killed. Oh dear."':PROCagain
  410 IF R=19 AND F(19)=0 AND V=3 PRINT "The Hellhound chews you into very small pieces. Oh dear."':PROCagain
  420 IF R=20 AND F(20)=0 AND V=3 PRINT "The dragon blasts you with its fiery breath, reducing you to a pile of ash.     Oh dear."':PROCagain
  430 IF R<>9 GOTO 460
  440 IF EVAL(MID$(Q$,SW,1))<>V PRINT "You take a wrong turn and sink into the swamp. Oh dear.":PROCagain
  450 SW=SW+1:IF SW=5 R=10:SW=1:GOTO 100
  460 IF E(R,V)>0 THEN R=E(R,V):PRINT:GOTO 100
  470 PRINT "You can't go that way.":GOTO 280
  480 IF R<>4 AND R<>5 GOTO 470
  490 IF C=0 THEN PRINT "The ferryman turns you away as you have no money.":GOTO 280
  500 C=C-1:PRINT "The ferryman welcomes you aboard, rows across to the opposite bank of the river and takes a groat from you for his trouble."
  510 IF R=4 R=5:PRINT:GOTO 100
  520 R=4:PRINT:GOTO 100
  530 PRINT "Words I know: Go, North, South, East, West, In, Take, Get, Drop, Throw, Examine,Read, Give, Dig, Ring, Open, Fill, Empty, Cut, Chop, Buy, Eat, Drink, Wait,     Wave, Hit, Smash, Inventory, Look.":GOTO 280
  540 V=INSTR(K$,N$):IF V=0 THEN PRINT "You can't take that.":GOTO 280
  550 V=(V+2)/3:IF R(V)=0 THEN PRINT "You've already got it.":GOTO 280
  560 IF R(V)<>R THEN PRINT "You can't see that.":GOTO 280
  570 IF CA=4 PRINT "You can't carry any more.":GOTO 280
  580 IF V=13 AND F(21)=0 PRINT "Sarumort won't let you have it.":GOTO 280
  590 R(V)=0:CA=CA+1:PRINT "Okay.":GOTO 280
  600 V=INSTR(K$,N$):IF V=0 PRINT "You can't drop that.":GOTO 280
  610 V=(V+2)/3:IF R(V)<>0 THEN PRINT "You don't have it.":GOTO 280
  620 CA=CA-1:R(V)=R:PRINT "Okay.":GOTO 280
  630 V=INSTR(K$,N$):IF V=0 PRINT "You can't throw that.":GOTO 280
  640 V=(V+2)/3:IF R(V)>0 PRINT "You don't have it.":GOTO 280
  650 IF V=2 AND R=20 AND F(20)=0 F(20)=1:R(2)=99:CA=CA-1:PRINT "The wet blanket lands on the dragon's head, putting out its fire and covering   its eyes. It blunders off, banging into walls.":GOTO 280
  660 IF (R=20 AND F(20)=0) OR (R=19 AND F(19)=0) PRINT "You're only making it angry...":R(V)=R:CA=CA-1:GOTO 280
  670 GOTO 620
  680 V=INSTR(K$,N$):IF V=0 GOTO 710
  690 V=(V+2)/3:IF R(V)=0 OR R(V)=R THEN PRINT D$(V):GOTO 280
  700 PRINT "You can't see that.":GOTO 280
  710 V=INSTR(S$,N$):IF V=0 PRINT "Examine what?":GOTO 280
  720 V=(V+2)/3:IF V=7 AND R=8 PRINT "I think it's what's left of Unlucky Unwin..."
  730 IF V=7 AND R=8 AND GR=0 GR=1:C=C+1:PRINT "You've found a groat!":GOTO 280
  740 IF V=7 AND R=8 GOTO 280
  750 IF V=12 AND F(15)=1 PRINT "He wears a uniform with a lightning bolt logo on it.":GOTO 280
  760 IF V=12 GOTO 700
  770 IF S(V)<>R GOTO 700
  780 IF F(R)<>0 GOTO 700
  790 IF V=1 PRINT "It has a wicked gleam in its eye." ELSE IF V=2 PRINT "She's fallen on hard times." ELSE IF V=3 PRINT "Phwoar!"
  800 IF V=10 PRINT "It has razor-sharp teeth." ELSE IF V=11 PRINT "Fire licks around its snout."
  810 IF V>3 AND V<10 PRINT "Nothing special."
  820 GOTO 280
  830 IF INSTR("SIGQUONOT",N$)=0 PRINT "You can't read that.":GOTO 280
  840 IF N$="NOT" AND R<>3 PRINT "What note?":GOTO 280
  850 IF N$="NOT" PRINT "You've already read it.":GOTO 280
  860 IF N$="QUO" AND R<>12 PRINT "You can't see that.":GOTO 280
  870 IF N$="QUO" PRINT "'Wait here awhile, weary traveller, and think on the future (if you have one).'":GOTO 280
  880 IF R=18 PRINT "Okay, so I lied when I said 'Not far now!'":GOTO 280
  890 IF R=10 PRINT "Not far now!":GOTO 280
  900 IF R=3 OR R=19 PRINT "You've already read it.":GOTO 280
  910 PRINT "You can't see a sign.":GOTO 280
  920 IF INSTR("MONGROALMCAS",N$)=0 GOTO 960
  930 IF C=0 THEN PRINT "You have no money to give.":GOTO 280
  940 IF R=13 PRINT "Try 'BUY' instead.":GOTO 280
  950 IF R=6 AND F(6)=0 C=C-1:F(6)=1:PRINT "You give the old woman a groat. 'Thank you dear. A word to the wise: if you everget lost, remember the names of the old kings - ";X$;" - initially speaking, of course!' She walks away.":GOTO 280
  960 V=INSTR(K$,N$):IF V=0 PRINT "You can't give that.":GOTO 280
  970 V=(V+2)/3:IF R(V)<>0 PRINT "You don't have it.":GOTO 280
  980 IF R=4 AND F(4)=0 AND V=7 THEN F(4)=1:R(7)=99:CA=CA-1:PRINT "The poodle snatches the pie from you and runs off.":GOTO 280
  990 IF R=14 AND F$(14)<>"1" AND R(10)=0 F$(14)="1":R(10)=99:R(11)=0:PRINT "The witch takes the hat. 'Why thank you, young elf. Here, have some sweets.' Thewitch gives you some sweets and goes back inside.":GOTO 280
 1000 IF R=19 AND F(19)=0 AND R(11)=0 R(11)=99:CA=CA-1:F(19)=1:PRINT "The Hellhound wolfs down the magical sweets. Moments later its teeth fall out.  It runs off, whimpering.":GOTO 280
 1010 PRINT "No one here wants that.":GOTO 280
 1020 IF R(5)>0 THEN PRINT "You have nothing to dig with.":GOTO 280
 1030 IF R<>4 THEN PRINT "It's no use digging here.":GOTO 280
 1040 IF F(4)=0 THEN PRINT "The poodle savages you to death. Oh dear.":PROCagain
 1050 PRINT "You've unearthed a box!":R(8)=4:GOTO 280
 1060 IF N$<>"BEL" PRINT "You can't ring that!":GOTO 280
 1070 IF R<>14 PRINT "What bell?":GOTO 280
 1080 IF F$(14)<>"1" THEN PRINT "You've already done that.":GOTO 280
 1090 F$(14)="A witch stands here, glaring at you.":PRINT "Ding! A witch comes out. 'Hello small child! Would you like some sweets? Step   into my oven, I mean house! Hang on, you're an elf! Can't stand elves. Well,    what do you want?":GOTO 280
 1100 IF R=2 AND N$="CUP" AND F(2)=0 THEN PRINT "Okay. You find a bucket.":F(2)=1:R(1)=2:GOTO 280
 1110 IF R=2 AND N$="CUP" THEN PRINT "It's already open.":GOTO 280
 1120 IF N$="BOX" AND R(8)>0 THEN PRINT "You don't have it.":GOTO 280
 1130 IF N$="BOX" AND R(9)<>99 THEN PRINT "It's already open":GOTO 280
 1140 IF N$="BOX" AND R(12)>0 THEN PRINT "It's locked.":GOTO 280
 1150 IF N$="BOX" PRINT "Okay. You find a wand.":R(9)=R:GOTO 280
 1160 IF N$<>"DOO" PRINT "You can't open that.":GOTO 280
 1170 IF R<>3 AND R<>14 THEN PRINT "What door?":GOTO 280
 1180 IF R=3 THEN PRINT "It's already open." ELSE PRINT "You can't."
 1190 GOTO 280
 1200 IF N$<>"BUC" PRINT "You can't fill that.":GOTO 280
 1210 IF R(1)>0 PRINT "You don't have it.":GOTO 280
 1220 IF FILL=1 PRINT "It's already full.":GOTO 280
 1230 IF R=2 PRINT "The taps don't work!":GOTO 280
 1240 IF R=4 OR R=5 FILL=1:O$(1)="a bucket full of water":PRINT "Okay. The bucket's full of river water.":GOTO 280
 1250 PRINT "There's no water here!":GOTO 280
 1260 IF N$<>"BUC" PRINT "You can't empty that.":GOTO 280
 1270 IF FILL=0 PRINT "But it's empty!":GOTO 280
 1280 FILL=0:O$(1)="an empty bucket":PRINT "Splash!"
 1290 IF R=2 AND F(2)=1 THEN F(2)=2:PRINT "You put out the fire on your bed.":R(2)=2:L$(2)=LEFT$(L$(2),121)
 1300 GOTO 280
 1310 IF R(3)>0 PRINT "You need a tool for the job.":GOTO 280
 1320 IF N$<>"TRE" PRINT "You can't cut that!":GOTO 280
 1330 IF R=8 AND F(8)=1 F(8)=2:E(8,3)=9:L$(8)=LEFT$(L$(8),115):PRINT "You chop up the fallen tree and clear the way east.":GOTO 280
 1340 IF R=7 OR R=8 THEN PRINT "You haven't got time to cut down trees.":GOTO 280
 1350 PRINT "There are no trees here.":GOTO 280
 1360 IF C=0 THEN PRINT "You haven't got any money.":GOTO 280
 1370 IF R<>13 THEN PRINT "There's nothing to buy here.":GOTO 280
 1380 IF INSTR("BEEPINDRI",N$)=0 THEN PRINT "Buy what?":GOTO 280
 1390 IF F(13)=1 THEN PRINT "'Sorry love, we've just run out of beer.'":GOTO 280
 1400 F(13)=1:R(6)=13:R(7)=13:C=C-1:PRINT "'There you go love. A pint of Demon's Brew and a free pie, seeing as it's you.' The bar elf winks at you and you give her a groat.":GOTO 280
 1410 IF N$<>"PIE" PRINT "You can't eat that!":GOTO 280
 1420 IF R(7)<>0 PRINT "You don't have it.":GOTO 280
 1430 PRINT "Yummy.":CA=CA-1:R(7)=99:GOTO 280
 1440 V=INSTR("WATBEE",N$):IF V=0 PRINT "You can't drink that!":GOTO 280
 1450 IF V=1 GOTO 1480
 1460 IF R(6)=0 THEN R(6)=99:CA=CA-1:PRINT "Thash luvverly... Hic!":GOTO 280
 1470 PRINT "You don't have any.":GOTO 280
 1480 IF R<>4 AND R<>5 THEN PRINT "There's no water here.":GOTO 280
 1490 PRINT "That's better.":GOTO 280
 1500 IF R=15 AND F(15)=0 F(15)=1:PRINT "A magical bus appears from nowhere and stops at the bus stop. The conductor getsoff and the bus disappears.":GOTO 280
 1510 IF WA=0 WA=1:R(10)=R:PRINT "You wait. There's a flash and a bang and Grandalf appears. 'What are you hangingaround for?! Get moving!' There is another flash and bang and Grandalf vanishes,leaving nothing but his hat.":GOTO 280
 1520 PRINT "You wait. There is a flash and a bang and Grandalf appears. 'I've had enough of your laziness!' He waves his wand and reduces you to a pile of ash. Oh dear.":PROCagain
 1530 IF N$<>"WAN" PRINT "You can't wave that!":GOTO 280
 1540 IF R(9)>0 PRINT "You don't have it.":GOTO 280
 1550 PRINT "Pretty sparks fly from the wand's tip."
 1560 IF R=21 AND F(21)=0 F(21)=1:PRINT "Sarumort explodes in a mass of stars. There is nothing left of him except a     nasty mark on the floor."
 1570 GOTO 280
 1580 IF R(4)>0 PRINT "You need the right tool for the job.":GOTO 280
 1590 IF N$<>"CRY" PRINT "Why should I do that?":GOTO 280
 1600 IF R(13)>0 PRINT "You don't have it!":GOTO 280
 1610 PRINT "The Crystal shatters into a million tiny pieces. Suddenly there is a flash and abang and Grandalf appears. 'Well done! Sarumort is defeated and the Crystal of  Nebumeth is destroyed. Excellent work! How about a nice cup of tea?'"':PROCagain
 1620 PRINT "You are carrying ";
 1630 FOR N=1 TO 13:IF R(N)=0 PRINT O$(N)", ";
 1640 NEXT:PRINT ;C;" groats.":GOTO 280
 1650 DEF PROCagain
 1660 INPUT "Do you want to play again? "I$
 1670 IF I$="N" THEN PRINT "Okay - bye!":END
 1680 IF I$="Y" THEN RUN
 1690 GOTO 1660
 1700 ENDPROC
 1710 DEF PROCinit
 1720 CLS:PRINT CHR$(17)"The Crystal of Nebumeth"CHR$(18)'
 1730 DIM L$(21),E(21,4),O$(13),R(13),D$(13),F$(21),F(21),KI$(4),S(12)
 1740 R=2:C=3:CA=0:WA=0:FILL=0:GR=0:SW=1
 1750 FOR N=1 TO 12:READ S(N):NEXT
 1760 FOR N=1 TO 4:READ KI$(N):NEXT
 1770 Q$="32141234432123411432214334214123":Q$=MID$(Q$,RND(8)*4-3,4)
 1780 FOR N=1 TO 3:X$=X$+KI$(EVAL(MID$(Q$,N,1)))+", ":NEXT:X$=X$+"and "+KI$(EVAL(RIGHT$(Q$,1)))
 1790 FOR N=1 TO 21:READ L$(N):NEXT
 1800 FOR N=1 TO 21:FOR M=1 TO 4:READ E(N,M):NEXT:NEXT
 1810 FOR N=1 TO 13:READ O$(N),R(N),D$(N):NEXT
 1820 FOR N=1 TO 21:READ F$(N):F(N)=0:NEXT
 1830 V$="NORSOUEASWESHELLOOGETTAKDROTHREXAREAGIVDIGRINOPEFILEMPCUTCHOBUYEATDRIWAIWAVHITSMAINV"
 1840 K$="BUCBLAAXEHAMSPABEEPIEBOXWANHATSWEKEYCRY"
 1850 S$="POOWOMELFFERCUPSINSKESIGQUOHELDRACON"
 1860 ENDPROC
 1870 DATA 4,6,13,5,2,2,8,18,12,19,20,15
 1880 DATA "Norbert","Smidge","Eggbreath","Wibblegurt"
 1890 DATA "in the woodcutter's cottage. It is, unsurprisingly, made of wood"
 1900 DATA "in your small, decrepit hovel. There is a cupboard and a sink, which    smells of rotting vegetables. There is also a bed, which is on fire"
 1910 DATA "outside a small cottage. A sign above the door reads 'Unlucky Unwin -   Woodcutter'. A handwritten note stuck to the door reads 'Gone to defeat Sarumort- back soon'"
 1920 DATA "on the far river bank. Thick brambles prevent you going any further"
 1930 DATA "on the edge of town. The River Elf lies to the west. (Elves are not veryimaginative when it comes to naming things)"
 1940 DATA "in the middle of Elverton Village. Lots of elves are going about their  daily business, namely avoiding an honest day's work. Elvy Forest lies to the   east"
 1950 DATA "in Elvy Forest. It is dark and scary, obviously"
 1960 DATA "deep in the forest. It is darker and scarier than you'd've thought      possible. A burnt skeleton lies on the moss"
 1970 DATA "in a swamp. It looks pretty treacherous - I hope you know where you're  going"
 1980 DATA "beyond the swamp - hurrah! A winding path leads east. There is a sign   here"
 1990 DATA "on a path"
 2000 DATA "in a quiet corner of the tavern. You can see a framed quotation on the  wall"
 2010 DATA "in the Dragon and Damsel tavern. It is dark and smoky and full of noisy,drunken elves. A busty blonde elf stands behind the bar polishing glasses"
 2020 DATA "outside a gingerbread house. It has a door made of marzipan, which is a pretty dumb idea. There is a bell attached to the door"
 2030 DATA "on a path. Strangely, there is a bus stop here","on a path","on a path"
 2040 DATA "at the end of the path. There is a sign here and a castle to the south"
 2050 DATA "outside Sarumort's castle. A sign on the gate reads 'No hawkers, tradersor circulars. PS - beware of the dragon'"
 2060 DATA "in a vast chamber decorated by someone with too much cash and too littletaste. Sarumort's throne room is to the east"
 2070 DATA "in Sarumort's chamber. Stone steps lead up to an ornate throne. Arcane  symbols cover the walls"
 2080 DATA 0,3,0,0,0,6,0,0,1,7,0,0,0,0,5,0,0,0,6,4,2,13,7,5,3,14,8,6
 2090 DATA 0,0,0,7,9,9,9,9,0,0,11,9,0,15,0,10,0,0,13,0,6,0,0,12,7,0,0,0
 2100 DATA 11,16,0,0,15,17,0,0,16,0,18,0,0,19,0,17,18,0,20,0,0,0,21,19,0,0,0,20
 2110 DATA "an empty bucket",99,"Made of zinc."
 2120 DATA "a blanket",99,"Sopping wet."
 2130 DATA "an axe",1,"Recently sharpened."
 2140 DATA "a hammer",1,"Good for hitting things."
 2150 DATA "a spade",1,"Covered in earth."
 2160 DATA "a pint of beer",99,"A dark and cloudy brew."
 2170 DATA "a pie",99,"Smells like horsemeat."
 2180 DATA "a box",99,"Very sturdy."
 2190 DATA "a wand",99,"Magic."
 2200 DATA "a hat",99,"A pointed hat, as worn by witches and wizards."
 2210 DATA "a bag of sweets",99,"Dr. Froggit's Magical Tooth-Rotters."
 2220 DATA "a key",6,"Small and golden."
 2230 DATA "the Crystal of Nebumeth",21,"Big and sparkly."
 2240 DATA "1","1","1","A white poodle is digging in the earth. It looks at you and barks.","1","A wizened old woman dressed in rags hobbles over to you. 'Alms for the poor,'   she cries, holding out a dirty hand."
 2250 DATA "1","A voice booms from the sky: 'Pathetic elf! You cannot hope to defeat me!' A boltof lightning strikes a nearby tree. It falls and blocks the way east. 'Drat,    missed you,' booms the voice.","1"
 2260 DATA "1","1","1","1","1","1","1","1","1"
 2270 DATA "A Hellhound stands here, growling menacingly.","A vast dragon almost fills the chamber, flames flickering around its mouth.","Sarumort raises his arm and a bolt of lightning fires at you."
