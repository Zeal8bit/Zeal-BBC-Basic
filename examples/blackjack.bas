   10 REM ****************
   20 REM     Blackjack
   30 REM  By Duncan Fumi
   40 REM ****************
   50 REM NC100/200 Version : 1995
   60 REM Downloaded from Tim's Amstrad NC User's Site
   70 REM http://www.ncus.org.uk
   80 REM Originally from the Amstrad Notepad Users' Web
   90 PROCinit
  100 PROCGetdeck
  110 PROCPlay
  120 PROCGoodbye
  130 END
  140 :
  150 DEFPROCinit
  160 CLS
  170 PRINT"Duncan's card table, enjoy!"
  180 crap=RND(-TIME):REM Seed random number generator.
  190 DIM cardval%(51)
  200 DIM cardsuit$(51)
  210 DIM cardname$(51)
  220 DIM cardvalue%(51)
  230 DIM playedcards%(5,10):REM max of five cards per player
  240 DIM numofcards%(10):REM number of cards played
  250 DIM playname$(10):REM Name of players
  260 DIM score%(10):REM Player's exiting score
  270 numcard%=51
  280 quit%=0
  290 ENDPROC
  300 DEFPROCGetdeck
  310 REM Number for cards:eg. 102. First 1 suit. Last 2,value.
  320 REM Deck begins with 52 cards. cards taken from the top and
  330 REM numcard% is decremented accordingly. it is set to 51 upon
  340 REM shuffling the deck.
  350 PRINT"Making up deck, please wait...."
  360 FOR T=0TO51
  370   READ cardno%
  380   suit%=INT(cardno%/100)
  390   number%=cardno% MOD 100
  400   cardvalue%(T)=cardno%
  410   IF suit%=1 THEN cardsuit$(T)="Hearts"
  420   IF suit%=2 THEN cardsuit$(T)="Diamonds"
  430   IF suit%=3 THEN cardsuit$(T)="Spades"
  440   IF suit%=4 THEN cardsuit$(T)="Clubs"
  450   IF number%=2 THEN cardname$(T)="a 2":cardval%(T)=2
  460   IF number%=3 THEN cardname$(T)="a 3":cardval%(T)=3
  470   IF number%=4 THEN cardname$(T)="a 4":cardval%(T)=4
  480   IF number%=5 THEN cardname$(T)="a 5":cardval%(T)=5
  490   IF number%=6 THEN cardname$(T)="a 6":cardval%(T)=6
  500   IF number%=7 THEN cardname$(T)="a 7":cardval%(T)=7
  510   IF number%=8 THEN cardname$(T)="a 8":cardval%(T)=8
  520   IF number%=9 THEN cardname$(T)="a 9":cardval%(T)=9
  530   IF number%=10 THEN cardname$(T)="a 10":cardval%(T)=10
  540   IF number%=11 THEN cardname$(T)="a Jack":cardval%(T)=10
  550   IF number%=12 THEN cardname$(T)="a Queen":cardval%(T)=10
  560   IF number%=13 THEN cardname$(T)="a King":cardval%(T)=10
  570   IF number%=14 THEN cardname$(T)="an Ace":cardval%(T)=11
  580 NEXT T
  590 CLS
  600 ENDPROC
  610 :
  620 DEFPROCShuffle
  630 REM Shuffles cards by moving cards to random positions.
  640 PRINT"Shuffling....."
  650 FOR c1=0TO51
  660   REPEAT
  670     c2=RND(numcard%)-1
  680   UNTIL c2<>c1
  690   value1%=cardvalue%(c1)
  700   suit1$=cardsuit$(c1)
  710   name1$=cardname$(c1)
  720   val1%=cardval%(c1)
  730   cardvalue%(c1)=cardvalue%(c2)
  740   cardsuit$(c1)=cardsuit$(c2)
  750   cardname$(c1)=cardname$(c2)
  760   cardval%(c1)=cardval%(c2)
  770   cardvalue%(c2)=value1%
  780   cardsuit$(c2)=suit1$
  790   cardname$(c2)=name1$
  800   cardval%(c2)=val1%
  810 NEXT c1
  820 numcard%=51
  830 CLS
  840 ENDPROC
  850 :
  860 DEFPROCPlay
  870 quit%=0
  880 REPEAT
  890   CLS
  900   PRINT"You are now ready to play, make your choice"
  910   PRINT"1) Blackjack (simple version)"
  920   PRINT"2) Quit to basic"
  930   choice$=GET$
  940   IF choice$="1" THEN PROCBlackjack
  950   IF choice$="2" THEN quit%=1 ELSE quit%=0
  960 UNTIL quit%=1
  970 ENDPROC
  980 DEFPROCBlackjack
  990 CLS
 1000 PROCShuffle
 1010 PROCBlackinit
 1020 PROCBlackfirst
 1030 FOR player%=1TOnumplayer%
 1040   PROCBlackplay
 1050 NEXT player%
 1060 PROCwhoone
 1070 ENDPROC
 1080 DEFPROCBlackinit
 1090 REM Subroutine to initialise variables and get player details.
 1100 REPEAT
 1110   INPUT"Number of players(1>10):"playnum$
 1120   numplayer%=VAL(playnum$)
 1130 UNTIL numplayer%>1ANDnumplayer%<11
 1140 FOR getname%=1TOnumplayer%
 1150   PRINT"Name of player ";getname%;:INPUT":"playname$(getname%)
 1160   numofcards%(getname%)=0
 1170 NEXT getname%
 1180 ENDPROC
 1190 DEFPROCBlackfirst
 1200 REM Subroutine to deal out the first two cards to all players.
 1210 FOR card%=1TO2
 1220   FOR player%=1TOnumplayer%
 1230     playedcards%(card%,player%)=numcard%
 1240     numcard%=numcard%-1
 1250     numofcards%(player%)=numofcards%(player%)+1
 1260   NEXT player%
 1270 NEXT card%
 1280 ENDPROC
 1290 DEFPROCBlackplay
 1300 CLS
 1310 PRINT"Player number ";player%;",";playname$(player%);" Press a key.."
 1320 crap=GET
 1330 stick%=0
 1340 REPEAT
 1350   CLS
 1360   PRINT"Player number ";player%;",";playname$(player%)
 1370   PROCShowcards
 1380   PRINT"Do you want to 1-Twist, 2-Stick or 3-Change ace value.";
 1390   choice1$=GET$
 1400   IF choice1$="1" AND value%<22 THEN PROCTwist
 1410   IF choice1$="2" THEN stick%=1
 1420   IF choice1$="3" THEN PROCChangeace
 1430 UNTIL stick%=1
 1440 PROCgetscore
 1450 CLS
 1460 ENDPROC
 1470 DEFPROCChangeace
 1480 CLS
 1490 FOR card%=1 TO numofcards%(player%)
 1500   dekpos%=playedcards%(card%,player%)
 1510   isace%=cardvalue%(dekpos%)MOD100
 1520   IF isace%=14THEN PROCChangeit
 1530 NEXT card%
 1540 ENDPROC
 1550 DEFPROCChangeit
 1560 PRINT"Card number ";card%;" is an ace, currently worth ";cardval%(dekpos%)
 1570 PRINT"Change it (y/n)?"
 1580 IF GET$="Y" THEN PROCChange
 1590 ENDPROC
 1600 DEFPROCChange
 1610 temp%=cardval%(dekpos%)
 1620 IF temp%=11 THEN cardval%(dekpos%)=1
 1630 IF temp%=1 THEN cardval%(dekpos%)=11
 1640 ENDPROC
 1650 DEFPROCShowcards
 1660 value%=0
 1670 PRINT"You have:"
 1680 FOR card%=1TOnumofcards%(player%)
 1690   deckno%=playedcards%(card%,player%)
 1700   PRINT cardname$(deckno%);" of ";cardsuit$(deckno%)
 1710   value%=value%+cardval%(deckno%)
 1720 NEXT card% 
 1730 PRINT"With total value:";value%
 1740 IF value%>21 THEN PROCBust
 1750 ENDPROC
 1760 DEFPROCBust
 1770 PRINT"You are bust. Change the value of an ace or end your turn."
 1780 ENDPROC
 1790 DEFPROCTwist
 1800 IF numofcards%(player%)<5 THEN PROCAddacard ELSE PROCfiverror
 1810 ENDPROC
 1820 DEFPROCfiverror
 1830 PRINT"You cannot have more than five cards, press enter to continue...."
 1840 crap=GET
 1850 ENDPROC
 1860 DEFPROCAddacard
 1870 numofcards%(player%)=numofcards%(player%)+1
 1880 playedcards%(numofcards%(player%),player%)=numcard%
 1890 numcard%=numcard%-1
 1900 ENDPROC
 1910 DEFPROCgetscore
 1920 score%(player%)=value%
 1930 ENDPROC
 1940 DEFPROCwhoonez 
 1950 FOR scores%=1 TO numplayer%
 1960   PRINT playname$(scores%);" got a total score of ";score%(scores%)
 1970   PRINT "using ";numofcards%(scores%);" press enter too continue..."
 1980   crap=GET
 1990 NEXT scores%
 2000 ENDPROC
 2010 DEFPROCtest
 2020 FOR deck%=0TO51
 2030   PRINT cardname$(deck%);" of ";cardsuit$(deck%)
 2040   a=GET
 2050 NEXT deck%
 2060 ENDPROC
 2070 DEFPROCebuf
 2080 REPEAT
 2090   a=INKEY(1)
 2100 UNTIL a=-1
 2110 ENDPROC
 2120 DEFPROCGoodbye
 2130 PRINT"See you later, have a nice day........."
 2140 ENDPROC
 2150 :
 2160 DATA 102, 103, 104, 105, 106, 107, 108, 109, 110, 111
 2170 DATA 112, 113, 114, 202, 203, 204, 205, 206, 207, 208
 2180 DATA 209, 210, 211, 212, 213, 214, 302, 303, 304, 305
 2190 DATA 306, 307, 308, 309, 310, 311, 312, 313, 314, 402
 2200 DATA 403, 404, 405, 406, 407, 408, 409, 410, 411, 412
 2210 DATA 413, 414
 2220 REM Data for cards