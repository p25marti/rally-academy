# Venue catalogue

Practice spots on the surveyed maps, by **surface you drive on** and kind of place, measured
in-game by `tools/ingame/catalog.py` (data: [venue-catalog.json](venue-catalog.json); this page
is generated, don't edit it). For drills that let you pick a surface, and for finding venues
([VENUES](VENUES.md)). The surface family is what the car's wheels reported at the spot
(start and middle of a road section); "fits" is a venue fit test on that surface
(open: B05's 50 m circle or A01's 30 m; straights: B01/A05 braking; corners and hills: the
game's AI at 35–45 km/h). Open ground is listed only when clear in at least six of eight
directions (trees and walls further than 20 m).

| Map | Surveyed | Spots | Notes |
| --- | --- | --- | --- |
| `automation_test_track` | 2026-10-17 (0.39.4) | 138 | stock |
| `rally_forest` | 2026-10-16 (0.39.4) | 67 | community map: needs installing |
| `utah` | 2026-10-16 (0.39.4) | 127 | stock |
| `west_coast_usa` | 2026-10-16 (0.39.4) | 150 | stock |

## What's available

Maps with at least one usable spot, per surface and kind:

| Surface | Open ground | Straights | Corners | Hairpins | Hills | Crests |
| --- | --- | --- | --- | --- | --- | --- |
| tarmac | `automation_test_track`, `utah`, `west_coast_usa` | `automation_test_track`, `rally_forest`, `utah`, `west_coast_usa` | `automation_test_track`, `rally_forest`, `utah`, `west_coast_usa` | `automation_test_track`, `utah`, `west_coast_usa` | `automation_test_track`, `rally_forest`, `utah`, `west_coast_usa` | `automation_test_track`, `rally_forest`, `utah`, `west_coast_usa` |
| gravel | `utah` | `utah` | `utah`, `west_coast_usa` | `utah`, `west_coast_usa` | `utah`, `west_coast_usa` | `utah`, `west_coast_usa` |
| dirt | `automation_test_track`, `rally_forest`, `utah`, `west_coast_usa` | `automation_test_track`, `rally_forest`, `utah` | `automation_test_track`, `rally_forest`, `utah`, `west_coast_usa` | `automation_test_track`, `west_coast_usa` | `automation_test_track`, `rally_forest`, `utah` | `automation_test_track`, `rally_forest`, `utah` |
| sand | – | – | – | `automation_test_track` | – | `utah` |
| mud | `automation_test_track` | – | – | – | – | `rally_forest` |
| grass | `automation_test_track`, `rally_forest`, `utah` | – | – | – | – | – |
| snow | `automation_test_track` | – | – | – | – | – |
| rock | – | – | – | – | `utah` | `utah` |
| mixed | `utah` | `utah` | `automation_test_track`, `west_coast_usa` | – | `automation_test_track` | `utah` |

## Tarmac

### Open ground

| Map | Where | What | Fit test | Go there |
| --- | --- | --- | --- | --- |
| `automation_test_track` | (344, 680) | 96 x 176 m | B05: no (Hit something at 17 km/h (damage +140); Left the road: 3 wheels on DIRT_DUSTY at) | `--at=344.0,680.0,132.2,0.0,1.0` |
| `utah` | (-264, -888) | 624 x 192 m | B05: no (Hit something at 18 km/h (damage +1281); Left the road: 3 wheels on GRAVEL at 14) | `--at=-264.0,-888.0,131.1,0.0,1.0` |
| `utah` | (816, -171) | road node 17 m wide m | B05: no (Hit something at 19 km/h (damage +1085); Left the road: 3 wheels on DIRT_DUSTY a) | `--at=816.41,-170.8,144.3,0.0,1.0` |
| `west_coast_usa` | (-7, 616) | 224 x 320 m | B05: no (Hit something at 18 km/h (damage +4585)) | `--at=-7.0,616.0,74.7,0.0,1.0` |
| `west_coast_usa` | (-887, 328) | 288 x 320 m | B05: no (Hit something at 1 km/h (damage +60); Left the road: 4 wheels on GRASS at 0 km/h) | `--at=-887.0,328.0,157.4,0.0,1.0` |
| `west_coast_usa` | (-172, 495) | road node 17 m wide m |  | `--at=-172.21,495.45,74.84,0.0,1.0` |

### Straights

| Map | Where | What | Fit test | Go there |
| --- | --- | --- | --- | --- |
| `automation_test_track` | (-23, -413) | 751 m long, 10 m wide, -0.3% | **B01 fits** | `--at=-23.19,-412.8,122.83,-0.9822,0.1878` |
| `automation_test_track` | (369, 361) | 592 m long, 12.2 m wide, -5.4% | **B01 fits** | `--at=368.53,360.55,144.04,-1.0,-0.0006` |
| `rally_forest` | (8, -371) | 90 m long, 9 m wide, +0.2% | **A05 fits** | `--at=7.77,-371.45,-0.24,0.9917,-0.1287` |
| `utah` | (1031, -1160) | 1998 m long, 7.6 m wide, +0.0% | **B01 fits** | `--at=1031.42,-1159.89,149.74,-1.0,-0.0001` |
| `utah` | (-816, -905) | 343 m long, 7.3 m wide, -0.4% | **B01 fits** | `--at=-815.86,-904.64,135.54,0.9999,0.0129` |
| `west_coast_usa` | (175, 858) | 794 m long, 5.7 m wide, -0.3% | **B01 fits** | `--at=175.02,857.66,102.27,-0.1925,0.9813` |
| `west_coast_usa` | (153, 920) | 727 m long, 4.7 m wide, -0.6% | **B01 fits** | `--at=153.11,919.67,103.69,-0.189,0.982` |
| `automation_test_track` | (235, 853) | 484 m long, 5.6 m wide, +0.6% |  | `--at=235.2,852.55,257.72,-0.998,-0.0637` |
| `automation_test_track` | (525, -312) | 346 m long, 9 m wide, +0.4% |  | `--at=525.22,-311.9,120.39,0.9562,-0.2927` |
| `automation_test_track` | (-526, -208) | 299 m long, 12.2 m wide, +0.6% |  | `--at=-526.39,-208.16,117.02,1.0,-0.0035` |
| `automation_test_track` | (-246, -255) | 287 m long, 11 m wide, -0.9% |  | `--at=-246.13,-255.45,118.98,-1.0,0.0001` |
| `automation_test_track` | (525, 773) | 274 m long, 7 m wide, +0.0% |  | `--at=524.8,772.76,257.72,-0.9589,0.2838` |
| `automation_test_track` | (-15, 806) | 268 m long, 4 m wide, -0.7% |  | `--at=-14.74,806.4,134.25,0.9997,0.0257` |
| `automation_test_track` | (139, 26) | 265 m long, 12.5 m wide, -0.9% |  | `--at=138.57,26.42,123.28,-0.782,0.6233` |
| `automation_test_track` | (334, 179) | 251 m long, 12.3 m wide, -1.1% |  | `--at=334.44,179.1,134.24,1.0,-0.0001` |
| `automation_test_track` | (-687, 14) | 245 m long, 12.5 m wide, -2.5% |  | `--at=-686.64,13.96,116.15,0.6357,0.772` |
| `automation_test_track` | (-449, 58) | 243 m long, 5.8 m wide, -0.0% |  | `--at=-449.06,58.15,117.25,-0.9218,-0.3876` |
| `automation_test_track` | (-295, 464) | 238 m long, 6.7 m wide, -1.3% |  | `--at=-294.58,463.61,137.7,0.9924,0.1233` |
| `automation_test_track` | (186, 687) | 209 m long, 5 m wide, +0.0% |  | `--at=186.3,686.81,134.55,-0.9982,-0.0594` |
| `automation_test_track` | (-613, -245) | 193 m long, 9.8 m wide, +0.2% |  | `--at=-613.05,-244.86,117.52,-0.9829,0.1839` |
| `automation_test_track` | (-462, 433) | 170 m long, 7.1 m wide, -4.9% |  | `--at=-462.28,432.72,146.13,0.981,0.1941` |
| `automation_test_track` | (-148, 330) | 159 m long, 8.8 m wide, -7.3% |  | `--at=-147.62,330.27,121.02,-0.9996,0.0293` |
| `automation_test_track` | (-368, -126) | 156 m long, 6.9 m wide, -0.1% |  | `--at=-367.56,-126.08,117.62,0.9978,0.0664` |
| `utah` | (-179, -915) | 320 m long, 7.2 m wide, +2.3% |  | `--at=-179.44,-914.67,132.87,0.9954,-0.0955` |
| `utah` | (-303, -395) | 253 m long, 7.3 m wide, +1.7% |  | `--at=-303.27,-394.68,133.71,0.7993,0.601` |
| `utah` | (654, -420) | 239 m long, 4.4 m wide, +0.3% |  | `--at=653.75,-420.47,143.02,0.7418,0.6706` |
| `utah` | (50, -927) | 235 m long, 7.6 m wide, -3.7% |  | `--at=50.17,-927.44,141.56,-0.9935,0.1136` |
| `utah` | (1220, -728) | 234 m long, 7.2 m wide, +0.1% |  | `--at=1220.15,-727.53,148.3,-0.001,-1.0` |
| `utah` | (644, 784) | 227 m long, 4.3 m wide, +7.2% |  | `--at=643.84,784.04,174.98,-0.6627,-0.7489` |
| `utah` | (-615, -645) | 215 m long, 7.4 m wide, -9.8% |  | `--at=-614.7,-645.3,161.6,0.4016,-0.9158` |
| `utah` | (579, -844) | 200 m long, 7.5 m wide, +2.9% |  | `--at=579.26,-843.99,141.24,0.7784,0.6278` |
| `utah` | (597, 946) | 187 m long, 4.5 m wide, +4.1% |  | `--at=596.58,945.79,257.48,-0.9998,-0.0178` |
| `utah` | (-313, -908) | 170 m long, 7.8 m wide, +1.2% |  | `--at=-313.34,-907.7,132.11,-0.9998,-0.0198` |
| `utah` | (753, 132) | 140 m long, 7.5 m wide, -4.1% |  | `--at=753.32,131.54,146.84,0.115,0.9934` |
| `utah` | (-770, -61) | 136 m long, 7.3 m wide, -2.6% |  | `--at=-769.6,-60.7,296.88,-0.8963,0.4434` |
| `west_coast_usa` | (-263, 137) | 678 m long, 14.2 m wide, -1.2% |  | `--at=-262.55,137.12,111.94,-0.7022,-0.712` |
| `west_coast_usa` | (287, 198) | 617 m long, 4.5 m wide, +0.0% |  | `--at=287.34,198.49,119.38,-0.8112,-0.5847` |
| `west_coast_usa` | (-207, -171) | 616 m long, 4.5 m wide, -0.0% |  | `--at=-207.32,-170.52,119.4,0.8084,0.5886` |
| `west_coast_usa` | (685, 639) | 530 m long, 11 m wide, -1.5% |  | `--at=684.64,638.55,127.48,-0.6856,-0.728` |
| `west_coast_usa` | (-42, 339) | 454 m long, 12.8 m wide, +0.1% |  | `--at=-41.95,338.56,115.61,0.787,0.6169` |
| `west_coast_usa` | (465, 693) | 414 m long, 15 m wide, +0.0% |  | `--at=465.34,692.89,117.22,-0.8018,-0.5976` |
| `west_coast_usa` | (986, -779) | 333 m long, 7.6 m wide, -2.6% |  | `--at=985.62,-778.92,156.77,-0.9264,-0.3766` |
| `west_coast_usa` | (1159, -703) | 331 m long, 7.3 m wide, -2.5% |  | `--at=1159.24,-703.03,161.37,-0.9344,-0.3564` |
| `west_coast_usa` | (-483, -140) | 319 m long, 14.2 m wide, -0.4% |  | `--at=-483.32,-139.64,107.79,-0.6888,-0.7249` |
| `west_coast_usa` | (261, -315) | 313 m long, 7.9 m wide, -5.4% |  | `--at=260.85,-315.19,144.72,-0.9933,0.1153` |
| `west_coast_usa` | (339, -251) | 312 m long, 14.5 m wide, +1.0% |  | `--at=338.66,-251.25,143.68,0.9999,-0.0151` |
| `west_coast_usa` | (590, 435) | 297 m long, 4 m wide, -0.0% |  | `--at=590.21,434.6,119.41,-0.8113,-0.5846` |
| `west_coast_usa` | (-1381, -981) | 290 m long, 7 m wide, +0.0% |  | `--at=-1380.57,-980.94,104.36,0.6825,0.7309` |
| `west_coast_usa` | (-500, 2020) | 286 m long, 6.3 m wide, -1.5% |  | `--at=-499.98,2019.97,78.89,0.9598,-0.2807` |
| `west_coast_usa` | (-436, 52) | 284 m long, 4 m wide, -0.5% |  | `--at=-436.19,51.86,91.7,0.7324,0.6809` |
| `west_coast_usa` | (-218, 203) | 266 m long, 7 m wide, +0.6% |  | `--at=-217.88,203.21,113,-0.7531,-0.6579` |
| `west_coast_usa` | (-437, 1782) | 265 m long, 3.2 m wide, -1.8% |  | `--at=-437,1782.32,79.4,0.93,-0.3675` |
| `west_coast_usa` | (101, 42) | 250 m long, 4 m wide, +0.0% |  | `--at=100.53,41.69,119.36,0.811,0.585` |

### Corners

| Map | Where | What | Fit test | Go there |
| --- | --- | --- | --- | --- |
| `automation_test_track` | (-151, 288) | 147° left, r 21.1 m, constant, 11.8 m wide | **D05 fits** | `--at=-150.88,287.62,120.92,0.9841,0.1776` |
| `utah` | (-728, -253) | 148° right, r 16.2 m, decreasing, 7.3 m wide | **D05 fits** | `--at=-728.29,-253.42,226.69,0.9375,0.348` |
| `utah` | (-833, 752) | 128° left, r 23.4 m, constant, 4.5 m wide | **D05 fits** | `--at=-832.88,752.3,265.44,-0.9682,0.2504` |
| `west_coast_usa` | (877, -642) | 150° right, r 22.9 m, constant, 8 m wide | **D05 fits** | `--at=876.78,-642.01,168.19,0.0761,-0.9971` |
| `west_coast_usa` | (-715, -112) | 149° right, r 9 m, decreasing, 4 m wide | **D05 fits** | `--at=-715.39,-112.24,100.45,0.3745,0.9272` |
| `automation_test_track` | (-345, 796) | 144° left, r 32.4 m, constant, 7.5 m wide | D05: no (Left the road: 3 wheels on SNOW at 40 km/h) | `--at=-345.22,795.99,270.81,-0.3602,0.9329` |
| `automation_test_track` | (-427, 702) | 140° right, r 20.7 m, constant, 7.3 m wide |  | `--at=-426.81,702.24,244.06,0.4857,0.8741` |
| `automation_test_track` | (27, 505) | 137° left, r 18.1 m, increasing, 5 m wide |  | `--at=26.97,504.58,134.55,0.8417,0.54` |
| `automation_test_track` | (-701, 472) | 132° right, r 17.3 m, decreasing, 7.5 m wide |  | `--at=-700.53,472.12,176.3,-0.7657,0.6433` |
| `automation_test_track` | (-269, -60) | 121° left, r 24.9 m, constant, 7 m wide |  | `--at=-268.71,-59.77,117.19,0.4358,-0.9` |
| `automation_test_track` | (374, 483) | 118° left, r 14.6 m, decreasing, 12.5 m wide |  | `--at=374.03,482.57,144.87,-0.8348,-0.5506` |
| `automation_test_track` | (-241, -213) | 108° left, r 9.9 m, constant, 12.5 m wide |  | `--at=-240.53,-213.43,118.68,0.9997,0.0252` |
| `automation_test_track` | (-430, -125) | 106° right, r 12.6 m, increasing, 7 m wide |  | `--at=-429.92,-125.05,118.24,0.4241,-0.9056` |
| `automation_test_track` | (-410, 45) | 104° left, r 19.8 m, constant, 7 m wide |  | `--at=-410.23,44.69,119.2,-0.9996,0.0266` |
| `automation_test_track` | (249, 50) | 98° right, r 44 m, constant, 12.5 m wide |  | `--at=248.7,50.48,134.88,-0.1929,-0.9812` |
| `automation_test_track` | (313, -33) | 92° left, r 9.6 m, increasing, 5 m wide |  | `--at=313.02,-33.31,134.05,0.999,-0.0456` |
| `automation_test_track` | (216, 249) | 92° right, r 16.2 m, increasing, 9 m wide |  | `--at=215.64,248.61,135.65,0.2184,0.9759` |
| `automation_test_track` | (415, 48) | 89° right, r 12.1 m, decreasing, 7.3 m wide |  | `--at=414.6,47.99,134.09,-0.014,-0.9999` |
| `automation_test_track` | (-693, -105) | 89° right, r 20.8 m, increasing, 7 m wide |  | `--at=-692.66,-105.39,118.32,0.079,0.9969` |
| `automation_test_track` | (394, 297) | 88° left, r 15.4 m, decreasing, 9 m wide |  | `--at=393.75,296.73,144.37,0.9996,-0.0279` |
| `automation_test_track` | (-157, -256) | 87° right, r 9.3 m, constant, 5 m wide |  | `--at=-156.6,-255.5,119.77,0.0134,0.9999` |
| `automation_test_track` | (505, -23) | 86° right, r 23.6 m, decreasing, 10 m wide |  | `--at=504.54,-23.02,134.05,-0.9998,0.0212` |
| `automation_test_track` | (-608, -143) | 86° right, r 19.3 m, increasing, 7 m wide |  | `--at=-607.88,-143.44,117.93,-0.078,-0.997` |
| `automation_test_track` | (-99, -236) | 83° right, r 10.9 m, decreasing, 5 m wide |  | `--at=-99.28,-236.11,120.49,0.9983,-0.0575` |
| `automation_test_track` | (100, -344) | 83° right, r 13 m, increasing, 5 m wide |  | `--at=99.87,-344.37,123.09,0.9987,-0.0505` |
| `automation_test_track` | (-437, 737) | 83° right, r 30.1 m, constant, 7.5 m wide |  | `--at=-437.04,736.59,266.36,-0.0601,-0.9982` |
| `automation_test_track` | (-591, -52) | 82° right, r 20.3 m, increasing, 7 m wide |  | `--at=-590.67,-51.87,118.55,0.7829,0.6222` |
| `automation_test_track` | (-245, -274) | 81° left, r 9.3 m, constant, 5 m wide |  | `--at=-245.11,-273.64,118.48,0.0382,-0.9993` |
| `automation_test_track` | (506, 443) | 80° right, r 21.2 m, decreasing, 8 m wide |  | `--at=505.85,443.08,144.71,-0.0599,-0.9982` |
| `automation_test_track` | (332, 208) | 80° left, r 14.6 m, constant, 6 m wide |  | `--at=332.49,207.75,134.14,-0.1448,0.9895` |
| `automation_test_track` | (-554, 397) | 79° left, r 20.6 m, increasing, 7.1 m wide |  | `--at=-554.4,397.24,145.65,-0.2193,0.9757` |
| `automation_test_track` | (434, 263) | 78° left, r 8.6 m, decreasing, 5 m wide |  | `--at=433.65,262.95,133.69,-0.9999,-0.0152` |
| `automation_test_track` | (-223, 255) | 77° right, r 21.7 m, decreasing, 9.9 m wide |  | `--at=-222.6,255.38,118.38,0.1411,0.99` |
| `rally_forest` | (237, -363) | 100° right, r 14.5 m, increasing, 5 m wide | D05: no (Left the road: 3 wheels on GRASS at 13 km/h) | `--at=236.53,-362.98,-0.24,0.0519,0.9987` |
| `rally_forest` | (-273, -387) | 58° right, r 28.6 m, decreasing, 5 m wide |  | `--at=-273.32,-386.69,-8.03,-0.6721,-0.7405` |
| `utah` | (845, 875) | 123° right, r 21.9 m, constant, 4.9 m wide |  | `--at=844.93,874.93,196.65,0.996,0.0892` |
| `utah` | (-927, -287) | 116° left, r 27.2 m, increasing, 7.5 m wide |  | `--at=-926.82,-287.08,262.71,-0.9214,-0.3886` |
| `utah` | (-816, -87) | 113° left, r 14.8 m, constant, 4.7 m wide |  | `--at=-815.98,-87,296.62,-0.6473,-0.7622` |
| `utah` | (157, 697) | 110° right, r 20.6 m, increasing, 4.6 m wide |  | `--at=157.41,697.02,261.2,0.3566,-0.9343` |
| `utah` | (-401, -576) | 102° left, r 11.9 m, constant, 4.6 m wide |  | `--at=-401.12,-575.68,129.48,-0.2875,-0.9578` |
| `utah` | (-684, 399) | 102° left, r 23.6 m, constant, 4.6 m wide |  | `--at=-684.2,398.63,298.63,-0.9943,0.1065` |
| `utah` | (-639, 878) | 100° left, r 16.5 m, increasing, 4.5 m wide |  | `--at=-638.7,877.77,271.26,-0.9886,0.1509` |
| `utah` | (-366, -857) | 96° right, r 16.1 m, constant, 7.3 m wide |  | `--at=-366.47,-857.04,132.79,0.9861,0.1664` |
| `utah` | (929, 669) | 90° right, r 16.2 m, decreasing, 5.3 m wide |  | `--at=929.33,669.44,217.24,0.7749,-0.6321` |
| `utah` | (-769, -109) | 90° left, r 10.1 m, decreasing, 4.9 m wide |  | `--at=-768.96,-108.7,296.22,0.7772,0.6292` |
| `utah` | (225, 921) | 90° left, r 36.6 m, constant, 4.6 m wide |  | `--at=225.35,920.65,265.14,-0.9953,-0.0972` |
| `utah` | (199, 816) | 89° right, r 17 m, decreasing, 4.6 m wide |  | `--at=198.88,815.98,265.11,0.4379,-0.899` |
| `utah` | (938, 617) | 87° left, r 11.1 m, increasing, 4.7 m wide |  | `--at=938.37,617.18,225.61,0.9848,-0.1737` |
| `utah` | (-810, -139) | 86° left, r 17.2 m, constant, 4.7 m wide |  | `--at=-810.07,-139.31,296.62,0.9695,-0.2451` |
| `utah` | (-199, 921) | 84° left, r 28.7 m, constant, 4.4 m wide |  | `--at=-199.03,920.52,268.97,-0.9641,-0.2655` |
| `utah` | (99, 660) | 84° right, r 16.8 m, increasing, 4.6 m wide |  | `--at=98.73,660.49,261.06,-0.9651,0.2621` |
| `utah` | (-745, -33) | 77° right, r 19.8 m, decreasing, 7.4 m wide |  | `--at=-744.99,-33.37,297.22,0.2222,-0.975` |
| `utah` | (953, 728) | 65° right, r 13.3 m, decreasing, 5.3 m wide |  | `--at=953.17,727.87,236.05,-0.9963,0.0862` |
| `west_coast_usa` | (-886, 605) | 149° right, r 9.6 m, increasing, 4.2 m wide |  | `--at=-885.83,604.7,123.28,-0.9955,0.0949` |
| `west_coast_usa` | (-16, -912) | 148° right, r 29.6 m, constant, 5.5 m wide |  | `--at=-16.3,-911.6,125.68,0.6612,-0.7502` |
| `west_coast_usa` | (802, 371) | 148° left, r 33 m, decreasing, 11.1 m wide |  | `--at=802.45,370.68,154.68,0.0169,0.9999` |
| `west_coast_usa` | (229, 680) | 146° left, r 22.4 m, decreasing, 6.8 m wide |  | `--at=228.95,679.6,100.25,0.5956,-0.8033` |
| `west_coast_usa` | (144, -118) | 146° left, r 20.3 m, decreasing, 7.3 m wide |  | `--at=144.01,-118.47,130.63,-0.9766,-0.215` |
| `west_coast_usa` | (-877, 2005) | 140° right, r 20.4 m, constant, 6.5 m wide |  | `--at=-877.32,2004.92,82.21,-0.9523,0.3051` |
| `west_coast_usa` | (-886, 577) | 140° left, r 10.9 m, increasing, 4.2 m wide |  | `--at=-885.91,577.4,128.82,0.8283,0.5602` |
| `west_coast_usa` | (-78, -188) | 140° right, r 19 m, decreasing, 7.5 m wide |  | `--at=-77.61,-187.71,119.4,-0.0766,-0.9971` |
| `west_coast_usa` | (-899, -872) | 139° right, r 24.7 m, decreasing, 8 m wide |  | `--at=-899.25,-872.25,124.99,0.8189,-0.5739` |
| `west_coast_usa` | (-382, -922) | 137° right, r 28.4 m, constant, 8 m wide |  | `--at=-381.89,-921.63,139.62,0.2354,-0.9719` |
| `west_coast_usa` | (661, 1713) | 134° left, r 8.5 m, decreasing, 3.2 m wide |  | `--at=661.11,1712.59,74.66,-0.0398,0.9992` |
| `west_coast_usa` | (-120, 133) | 134° left, r 42.3 m, constant, 4 m wide |  | `--at=-119.67,133.3,83.28,0.2608,-0.9654` |
| `west_coast_usa` | (-1377, -921) | 131° right, r 15.4 m, constant, 3 m wide |  | `--at=-1377.41,-921.33,96.83,-0.232,-0.9727` |
| `west_coast_usa` | (422, -310) | 131° left, r 20.2 m, decreasing, 6 m wide |  | `--at=422.18,-310.16,152.55,-0.6704,0.742` |
| `west_coast_usa` | (197, -826) | 130° right, r 23.9 m, constant, 8 m wide |  | `--at=196.65,-825.88,142.73,-0.9931,-0.1177` |
| `west_coast_usa` | (744, -649) | 128° right, r 29.4 m, constant, 8 m wide |  | `--at=744.38,-648.94,192.44,0.6251,-0.7805` |
| `west_coast_usa` | (-93, -443) | 126° left, r 16 m, increasing, 9.5 m wide |  | `--at=-92.78,-443.4,124.32,-0.4072,0.9133` |
| `west_coast_usa` | (711, 159) | 125° right, r 23.1 m, constant, 11.1 m wide |  | `--at=710.76,158.75,148.42,-0.114,-0.9935` |
| `west_coast_usa` | (-442, 158) | 124° left, r 9.7 m, increasing, 4 m wide |  | `--at=-442.12,157.77,100.13,-0.3086,-0.9512` |
| `west_coast_usa` | (41, -63) | 121° right, r 13.7 m, increasing, 7.5 m wide |  | `--at=41.08,-62.94,119.4,0.5332,-0.846` |
| `west_coast_usa` | (120, 782) | 118° right, r 23.6 m, decreasing, 2.8 m wide |  | `--at=120.49,781.5,101.02,0.6799,0.7333` |
| `west_coast_usa` | (-652, -88) | 117° left, r 13.7 m, decreasing, 4 m wide |  | `--at=-652.2,-88.03,100.56,0.2104,0.9776` |
| `west_coast_usa` | (916, -235) | 113° right, r 38.6 m, constant, 4 m wide |  | `--at=916.23,-235.35,147.41,0.903,0.4296` |
| `west_coast_usa` | (-5, 28) | 112° right, r 26.4 m, constant, 11.1 m wide |  | `--at=-4.56,28,119.41,0.3952,0.9186` |
| `west_coast_usa` | (-699, 2005) | 112° left, r 15.7 m, increasing, 6.5 m wide |  | `--at=-698.71,2004.78,80.42,0.2173,0.9761` |
| `west_coast_usa` | (70, -831) | 112° right, r 34.7 m, increasing, 4.9 m wide |  | `--at=69.64,-830.78,128.15,-0.1062,-0.9943` |

### Hairpins

| Map | Where | What | Fit test | Go there |
| --- | --- | --- | --- | --- |
| `automation_test_track` | (111, 172) | 360° left, r 29.7 m, hairpin, 5 m wide | **C04 fits** | `--at=111.18,172.49,128.7,0.9949,0.1009` |
| `automation_test_track` | (-715, 413) | 213° right, r 16.4 m, hairpin, 7.3 m wide | **C04 fits** | `--at=-714.9,413,159.9,-0.9966,-0.0819` |
| `utah` | (776, -144) | 228° left, r 8.2 m, hairpin, 6 m wide | **C04 fits** | `--at=776.42,-143.52,144.3,-0.9467,-0.3222` |
| `west_coast_usa` | (406, -122) | 343° right, r 26.3 m, hairpin, 9 m wide | **C04 fits** | `--at=406.28,-122.48,145.01,-0.9634,0.2681` |
| `west_coast_usa` | (-1088, 2004) | 213° right, r 16.8 m, hairpin, 6.5 m wide | **C04 fits** | `--at=-1088.02,2003.75,77.56,-0.9577,-0.2877` |
| `automation_test_track` | (917, -457) | 204° left, r 14.5 m, hairpin, 5.9 m wide |  | `--at=916.61,-456.73,122.08,0.6464,-0.763` |
| `automation_test_track` | (-316, 617) | 199° left, r 12.8 m, hairpin, 7.2 m wide |  | `--at=-315.83,617.29,216.18,0.9763,-0.2165` |
| `automation_test_track` | (-598, 453) | 192° left, r 14 m, hairpin, 7.3 m wide |  | `--at=-597.64,453.38,168.31,0.9885,0.1509` |
| `automation_test_track` | (-512, 699) | 175° left, r 17.8 m, hairpin, 7.5 m wide |  | `--at=-512.26,699.24,261.51,-0.9998,-0.0179` |
| `automation_test_track` | (-414, -14) | 173° right, r 12.5 m, hairpin, 7 m wide |  | `--at=-413.68,-13.95,117.79,-0.6404,0.768` |
| `automation_test_track` | (-550, -103) | 172° left, r 17.2 m, hairpin, 7 m wide |  | `--at=-549.5,-103.35,114.87,0.2193,0.9757` |
| `automation_test_track` | (-547, -176) | 168° right, r 12.6 m, hairpin, 7 m wide |  | `--at=-547.28,-176.11,116.54,-0.9949,-0.1013` |
| `automation_test_track` | (-376, -127) | 167° left, r 12.6 m, hairpin, 6.7 m wide |  | `--at=-376.3,-127.24,117.53,-0.9825,-0.1861` |
| `automation_test_track` | (-56, 182) | 163° left, r 33 m, hairpin, 12.5 m wide |  | `--at=-56.48,182.08,121.05,-0.8154,0.5789` |
| `automation_test_track` | (571, 442) | 156° right, r 34.3 m, hairpin, 12.6 m wide |  | `--at=571.45,442.4,145.26,0.9976,-0.0695` |
| `west_coast_usa` | (-1244, -796) | 203° left, r 18.9 m, hairpin, 3 m wide |  | `--at=-1244.06,-795.66,96.85,0.9474,0.3201` |
| `west_coast_usa` | (196, -155) | 201° left, r 14.2 m, hairpin, 7.3 m wide |  | `--at=196.31,-154.91,135.29,0.4868,-0.8735` |
| `west_coast_usa` | (750, -552) | 192° left, r 15.4 m, hairpin, 8 m wide |  | `--at=750.42,-551.61,175.1,0.3479,0.9375` |
| `west_coast_usa` | (494, -597) | 187° right, r 20.7 m, hairpin, 8 m wide |  | `--at=493.87,-596.74,177.74,0.3588,0.9334` |
| `west_coast_usa` | (-579, -276) | 186° left, r 37.1 m, hairpin, 4.6 m wide |  | `--at=-579.2,-275.68,104.9,-0.1886,-0.982` |
| `west_coast_usa` | (-1016, 1976) | 185° left, r 16.4 m, hairpin, 6.5 m wide |  | `--at=-1016.33,1976.4,85.47,0.9822,-0.1879` |
| `west_coast_usa` | (365, -340) | 180° right, r 15.4 m, hairpin, 3.5 m wide |  | `--at=365.08,-339.66,148.53,0.0079,-1.0` |
| `west_coast_usa` | (-608, 1956) | 178° left, r 10.2 m, hairpin, 6.5 m wide |  | `--at=-607.97,1955.95,80.42,0.9808,-0.1948` |
| `west_coast_usa` | (581, 1892) | 175° right, r 9.3 m, hairpin, 4.5 m wide |  | `--at=581.47,1891.51,74.8,0.0553,-0.9985` |
| `west_coast_usa` | (-850, -630) | 173° right, r 8.7 m, hairpin, 4 m wide |  | `--at=-849.96,-629.7,104.52,-0.6772,0.7358` |
| `west_coast_usa` | (-247, -225) | 167° right, r 10.1 m, hairpin, 7.8 m wide |  | `--at=-247.24,-225.48,118.86,-0.4374,0.8992` |
| `west_coast_usa` | (-946, -934) | 165° left, r 20.7 m, hairpin, 8 m wide |  | `--at=-946.44,-933.84,134.7,-0.9659,-0.259` |

### Hills

| Map | Where | What | Fit test | Go there |
| --- | --- | --- | --- | --- |
| `automation_test_track` | (-289, -123) | -23.0% over 62 m, 6.9 m wide | **D06 fits** | `--at=-288.55,-122.64,132.08,0.9995,0.0319` |
| `utah` | (-696, 399) | -21.3% over 147 m, 4.2 m wide | **D06 fits** | `--at=-695.74,399.34,298.05,-0.9871,-0.1601` |
| `utah` | (962, 749) | +17.4% over 141 m, 4.4 m wide | **D06 fits** | `--at=961.67,748.91,237.01,-0.3314,0.9435` |
| `west_coast_usa` | (-698, 107) | -23.3% over 62 m, 11 m wide | **D06 fits** | `--at=-697.66,107.26,118.26,0.7075,-0.7067` |
| `west_coast_usa` | (-920, 655) | +22.2% over 89 m, 11 m wide | **D06 fits** | `--at=-920.35,655.17,112.06,0.0,-1.0` |
| `automation_test_track` | (508, 778) | -21.4% over 517 m, 4 m wide | D06: no (the AI didn't get through the section at 35 km/h) | `--at=507.61,778.27,245.14,-0.9691,0.2468` |
| `automation_test_track` | (-368, -126) | +18.3% over 79 m, 6.9 m wide |  | `--at=-367.56,-126.08,117.62,0.9978,0.0664` |
| `automation_test_track` | (246, 35) | -14.5% over 64 m, 12.5 m wide |  | `--at=245.68,35.12,134.11,-0.4199,-0.9076` |
| `automation_test_track` | (-715, 516) | +13.0% over 113 m, 7.2 m wide |  | `--at=-714.91,516.28,180.02,0.9052,0.425` |
| `automation_test_track` | (-300, 644) | +12.0% over 83 m, 7.2 m wide |  | `--at=-299.71,643.69,220.33,-0.994,0.1091` |
| `automation_test_track` | (-223, 807) | +11.6% over 84 m, 7.1 m wide |  | `--at=-223.16,806.96,257.97,-0.9939,-0.1103` |
| `automation_test_track` | (-148, 330) | -11.0% over 86 m, 9.3 m wide |  | `--at=-147.62,330.27,121.02,-0.9996,0.0293` |
| `automation_test_track` | (-362, 628) | +9.7% over 88 m, 7.2 m wide |  | `--at=-361.63,627.72,211.15,0.9992,0.0409` |
| `automation_test_track` | (-585, 419) | +9.6% over 173 m, 7.4 m wide |  | `--at=-584.99,419,147.44,-0.9971,-0.0765` |
| `rally_forest` | (237, -363) | -8.8% over 88 m, 5 m wide | D06: no (Left the road: 3 wheels on GRASS at 13 km/h) | `--at=236.53,-362.98,-0.24,0.0519,0.9987` |
| `utah` | (595, 727) | +16.8% over 86 m, 4.3 m wide |  | `--at=595.06,726.75,177.78,-0.6719,-0.7406` |
| `utah` | (855, 765) | +14.6% over 177 m, 4.9 m wide |  | `--at=855.14,764.68,198.93,0.2741,-0.9617` |
| `west_coast_usa` | (-639, 492) | -21.5% over 117 m, 14 m wide |  | `--at=-639.42,492.5,116.01,0.7074,0.7068` |
| `west_coast_usa` | (-951, 152) | -21.3% over 89 m, 11 m wide |  | `--at=-951.35,152.08,156.82,0.7076,-0.7067` |
| `west_coast_usa` | (-784, 195) | +21.1% over 98 m, 8.6 m wide |  | `--at=-784.16,194.52,138.7,-0.7322,0.6811` |
| `west_coast_usa` | (-818, 19) | +20.5% over 99 m, 11 m wide |  | `--at=-818.36,19,117.53,-0.6953,0.7187` |
| `west_coast_usa` | (-920, 555) | +20.5% over 101 m, 11 m wide |  | `--at=-920.05,554.88,131.96,-0.0155,-0.9999` |
| `west_coast_usa` | (-669, 289) | -20.2% over 82 m, 11 m wide |  | `--at=-668.87,288.86,129.01,0.7064,-0.7078` |
| `west_coast_usa` | (-601, 617) | +19.4% over 104 m, 5.9 m wide |  | `--at=-600.82,617.02,91.45,-0.7037,-0.7105` |
| `west_coast_usa` | (-920, 784) | -18.8% over 88 m, 11 m wide |  | `--at=-920.27,784.35,91.23,0.0013,1.0` |
| `west_coast_usa` | (-295, 527) | +17.3% over 73 m, 15 m wide |  | `--at=-294.58,527.16,75.31,-0.7081,-0.7061` |
| `west_coast_usa` | (-769, 545) | +17.3% over 90 m, 11 m wide |  | `--at=-768.78,544.57,123.74,-0.0013,-1.0` |
| `west_coast_usa` | (-744, 363) | -16.3% over 82 m, 11.4 m wide |  | `--at=-743.64,363.44,142.54,0.7055,-0.7087` |
| `west_coast_usa` | (-539, 157) | +16.0% over 70 m, 10 m wide |  | `--at=-539.45,157.38,100.32,-0.5833,0.8123` |

### Crests

| Map | Where | What | Fit test | Go there |
| --- | --- | --- | --- | --- |
| `automation_test_track` | (-762, 230) | 54 m over the top, 7 m wide | **E05 fits** | `--at=-761.87,230.38,131.98,0.6211,0.7837` |
| `automation_test_track` | (-295, -158) | 27 m over the top, 6 m wide | **E05 fits** | `--at=-295.12,-158.44,123.43,0.9887,-0.1501` |
| `utah` | (-370, 854) | 52 m over the top, 4.5 m wide | **E05 fits** | `--at=-369.85,854.02,270.27,0.9376,-0.3476` |
| `west_coast_usa` | (-159, 377) | 12 m over the top, 4 m wide | **E05 fits** | `--at=-159.3,376.92,90.14,0.3752,0.9269` |
| `west_coast_usa` | (-762, 725) | 11 m over the top, 3 m wide | **E05 fits** | `--at=-762.12,725.37,94.83,0.9277,-0.3733` |
| `automation_test_track` | (-409, -20) | 54 m over the top, 7 m wide |  | `--at=-409.1,-20.02,117.45,-0.6023,0.7983` |
| `automation_test_track` | (-223, 48) | 26 m over the top, 7.5 m wide |  | `--at=-223.48,47.97,117.31,-0.1564,-0.9877` |
| `automation_test_track` | (-297, -123) | 19 m over the top, 6.9 m wide |  | `--at=-297.21,-122.96,131.19,0.9993,0.0369` |
| `automation_test_track` | (-139, 73) | 52 m over the top, 11.7 m wide |  | `--at=-138.67,72.64,122.7,0.1931,-0.9812` |
| `automation_test_track` | (-131, 291) | 54 m over the top, 11.8 m wide |  | `--at=-131.26,291.16,121.06,0.455,0.8905` |
| `automation_test_track` | (-547, -176) | 45 m over the top, 7 m wide |  | `--at=-547.28,-176.11,116.54,-0.9949,-0.1013` |
| `automation_test_track` | (-548, -92) | 39 m over the top, 7 m wide |  | `--at=-547.91,-92.18,114.84,-0.2413,0.9705` |
| `rally_forest` | (407, -112) | 58 m over the top, 5 m wide | E05: no (start spot isn't clear: the game moved the car 5.5 m when placing it; the AI did) | `--at=407.05,-111.51,-4.41,0.2109,-0.9775` |
| `west_coast_usa` | (-125, 328) | 47 m over the top, 4 m wide |  | `--at=-124.74,327.62,103.67,0.7539,0.657` |

## Gravel

### Open ground

| Map | Where | What | Fit test | Go there |
| --- | --- | --- | --- | --- |
| `utah` | (-632, 216) | 528 x 704 m | B05: no (Hit something at 63 km/h (damage +8358); Rolled over at 26 km/h; Left the road: ) | `--at=-632.0,216.0,298.3,0.0,1.0` |
| `utah` | (-104, 424) | 544 x 480 m | B05: no (Hit something at 14 km/h (damage +57); Left the road: 4 wheels on DIRT_DUSTY at ) | `--at=-104.0,424.0,240.0,0.0,1.0` |

### Straights

| Map | Where | What | Fit test | Go there |
| --- | --- | --- | --- | --- |
| `utah` | (512, 150) | 198 m long, 4.5 m wide, +14.2% | B01: no (needed 235 m but the drill allows 150 m; Hit something at 38 km/h (damage +107);) | `--at=512.16,150.39,145.11,-0.3733,0.9277` |
| `utah` | (335, 743) | 192 m long, 4.8 m wide, +11.1% | B01: no (needed 213 m but the drill allows 150 m) | `--at=335.48,743.18,182.2,0.8734,0.4871` |
| `utah` | (-123, -282) | 192 m long, 5.3 m wide, -1.4% |  | `--at=-122.9,-281.56,136.35,-0.8066,-0.591` |

### Corners

| Map | Where | What | Fit test | Go there |
| --- | --- | --- | --- | --- |
| `utah` | (-411, -635) | our venue `utah-ngrc-stages` | **D05 fits** | `--at=-410.97,-635.14,121.06,-0.9271,0.3529` |
| `utah` | (780, -369) | 146° left, r 23.2 m, increasing, 5.1 m wide | **D05 fits** | `--at=780.33,-369.31,127.74,0.6384,-0.7697` |
| `west_coast_usa` | (-851, -71) | 148° right, r 19.2 m, decreasing, 8 m wide | **D05 fits** | `--at=-851.45,-70.65,113.61,0.9991,0.0421` |
| `west_coast_usa` | (765, -808) | 146° left, r 10.7 m, constant, 8 m wide | **D05 fits** | `--at=765.1,-808.2,159.07,0.7907,0.6122` |
| `utah` | (-511, 405) | 141° left, r 15.3 m, constant, 4.9 m wide |  | `--at=-511.42,405.48,261.32,-0.5262,-0.8504` |
| `utah` | (-371, -617) | 92° right, r 14.6 m, decreasing, 6 m wide |  | `--at=-371.16,-616.55,127.28,-0.1545,-0.988` |
| `utah` | (147, -167) | 91° right, r 11.6 m, constant, 5.2 m wide |  | `--at=147.34,-166.76,139.04,0.1103,-0.9939` |
| `utah` | (114, 37) | 90° right, r 10.1 m, decreasing, 4.5 m wide |  | `--at=114.16,37.26,171.99,0.9583,-0.2856` |
| `utah` | (907, 557) | 88° right, r 18.4 m, decreasing, 2.9 m wide |  | `--at=906.61,557.07,217.99,-0.364,0.9314` |
| `utah` | (-805, 335) | 83° left, r 8.4 m, increasing, 5.2 m wide |  | `--at=-805.22,334.77,250.16,0.9922,0.1249` |
| `utah` | (169, 440) | 80° right, r 8.5 m, increasing, 4.9 m wide |  | `--at=169.09,439.62,174.77,0.8828,-0.4698` |
| `utah` | (922, -107) | 79° left, r 17.6 m, decreasing, 2.3 m wide |  | `--at=921.84,-106.93,195.79,0.6219,0.7831` |
| `utah` | (-346, 350) | 78° left, r 19.4 m, increasing, 4.7 m wide |  | `--at=-345.71,350.3,269.05,0.4395,-0.8982` |
| `utah` | (-129, 276) | 78° left, r 33.9 m, constant, 5.9 m wide |  | `--at=-129.04,276.41,238.87,0.9794,0.202` |
| `utah` | (-440, -746) | 77° left, r 17.3 m, decreasing, 5.1 m wide |  | `--at=-439.74,-745.62,104.33,0.7204,0.6935` |
| `utah` | (-843, -886) | 74° right, r 13.2 m, constant, 5.9 m wide |  | `--at=-843.21,-885.81,130.12,0.9989,-0.0469` |
| `utah` | (-395, 394) | 72° right, r 23.3 m, constant, 4.9 m wide |  | `--at=-395.38,394.19,265.44,0.9809,0.1945` |
| `utah` | (523, -452) | 70° right, r 16.7 m, increasing, 5.2 m wide |  | `--at=523.47,-451.94,136.48,0.9114,-0.4116` |
| `west_coast_usa` | (161, 207) | 145° left, r 19.4 m, constant, 8 m wide |  | `--at=160.76,206.92,116.55,0.3721,0.9282` |
| `west_coast_usa` | (534, 542) | 138° left, r 19.5 m, increasing, 8.1 m wide |  | `--at=533.66,541.71,125.79,0.5165,0.8563` |
| `west_coast_usa` | (151, 301) | 124° left, r 32.4 m, constant, 8 m wide |  | `--at=150.93,301.35,129.77,-0.209,-0.9779` |
| `west_coast_usa` | (552, -893) | 118° left, r 16.4 m, decreasing, 7 m wide |  | `--at=551.56,-892.69,153,0.8039,0.5948` |

### Hairpins

| Map | Where | What | Fit test | Go there |
| --- | --- | --- | --- | --- |
| `utah` | (19, -102) | 181° right, r 14.7 m, hairpin, 5.6 m wide | **C04 fits** | `--at=18.65,-101.65,146.57,-0.8923,-0.4515` |
| `utah` | (-161, 522) | 172° right, r 25.2 m, hairpin, 4.1 m wide | **C04 fits** | `--at=-160.51,522.34,242.46,-0.2641,0.9645` |
| `west_coast_usa` | (-66, -491) | 177° left, r 10.4 m, hairpin, 4 m wide | **C04 fits** | `--at=-66.41,-490.7,125.99,0.5668,-0.8239` |
| `west_coast_usa` | (291, -789) | 170° right, r 12.2 m, hairpin, 6 m wide | **C04 fits** | `--at=291.46,-789.26,152.19,-0.9982,0.0601` |
| `utah` | (-893, -823) | 158° left, r 10 m, hairpin, 5.9 m wide |  | `--at=-893.03,-822.94,103.13,-0.9845,0.1755` |
| `west_coast_usa` | (1, 142) | 166° left, r 16.5 m, hairpin, 8.1 m wide |  | `--at=0.97,142.14,125.82,-0.7455,-0.6665` |
| `west_coast_usa` | (310, -813) | 164° left, r 9.5 m, hairpin, 6 m wide |  | `--at=310.46,-812.61,149.05,0.9864,0.1642` |

### Hills

| Map | Where | What | Fit test | Go there |
| --- | --- | --- | --- | --- |
| `west_coast_usa` | (-576, -820) | +26.1% over 86 m, 6 m wide | **D06 fits** | `--at=-576.44,-820.4,148.99,0.9789,0.2043` |
| `west_coast_usa` | (-467, -855) | -24.1% over 67 m, 6 m wide | **D06 fits** | `--at=-467.26,-855.38,171.99,0.8564,-0.5163` |
| `utah` | (-60, 742) | +44.8% over 172 m, 2.7 m wide | D06: no (the AI didn't get through the section at 35 km/h; Hit something at 18 km/h (dama) | `--at=-59.76,742.19,190.24,0.7836,0.6213` |
| `utah` | (504, 173) | +35.1% over 78 m, 4.7 m wide | D06: no (the AI didn't get through the section at 35 km/h) | `--at=503.69,172.54,145.72,-0.3455,0.9384` |
| `utah` | (-906, -821) | +20.5% over 154 m, 5.9 m wide |  | `--at=-906.44,-820.55,103.75,-0.999,0.0453` |
| `utah` | (252, -834) | -20.3% over 82 m, 5.4 m wide |  | `--at=252.46,-834.47,132.41,-0.9694,-0.2455` |
| `utah` | (492, -691) | +20.2% over 78 m, 4.7 m wide |  | `--at=491.78,-690.95,122.6,-0.4041,-0.9147` |
| `utah` | (-273, 352) | -19.5% over 127 m, 4 m wide |  | `--at=-272.55,352.13,264.29,0.9893,-0.1462` |
| `utah` | (-452, -646) | -18.1% over 60 m, 5.9 m wide |  | `--at=-451.86,-646.31,117.86,-0.3939,-0.9191` |
| `utah` | (649, 658) | -17.6% over 188 m, 4.6 m wide |  | `--at=648.97,657.63,184.43,0.9693,0.2459` |
| `utah` | (885, -178) | +15.9% over 124 m, 2.8 m wide |  | `--at=885.49,-178.34,150.32,0.2534,-0.9674` |
| `utah` | (570, 839) | -15.7% over 139 m, 5 m wide |  | `--at=570.38,839.14,204.15,0.9922,0.125` |
| `utah` | (-22, -111) | +15.1% over 82 m, 5.1 m wide |  | `--at=-21.59,-111.2,147.65,-0.9694,0.2456` |
| `utah` | (930, 127) | +15.0% over 172 m, 2.7 m wide |  | `--at=930.35,126.71,200.27,0.0152,0.9999` |
| `utah` | (373, 763) | +14.6% over 156 m, 4.8 m wide |  | `--at=373.07,762.64,181.25,0.9007,0.4345` |
| `west_coast_usa` | (214, 838) | -20.6% over 136 m, 4.8 m wide |  | `--at=213.99,838.42,101.27,0.6973,0.7168` |
| `west_coast_usa` | (-425, -952) | -20.5% over 62 m, 6 m wide |  | `--at=-424.87,-952.04,151.36,0.9454,0.3259` |
| `west_coast_usa` | (-613, -823) | +18.5% over 82 m, 6 m wide |  | `--at=-612.81,-822.62,145.11,-0.885,-0.4656` |
| `west_coast_usa` | (236, 670) | +17.8% over 63 m, 8 m wide |  | `--at=236.35,669.62,100.33,0.7595,-0.6505` |

### Crests

| Map | Where | What | Fit test | Go there |
| --- | --- | --- | --- | --- |
| `utah` | (309, -831) | 41 m over the top, 5.4 m wide | **E05 fits** | `--at=309.27,-831.07,132.01,-0.9992,0.0408` |
| `utah` | (723, -583) | 31 m over the top, 5.9 m wide | **E05 fits** | `--at=722.66,-582.77,125.39,0.5263,0.8503` |
| `west_coast_usa` | (-851, -71) | 47 m over the top, 8 m wide | **E05 fits** | `--at=-851.45,-70.65,113.61,0.9991,0.0421` |
| `west_coast_usa` | (-512, -843) | 56 m over the top, 6 m wide | **E05 fits** | `--at=-512.44,-842.51,169.12,0.9537,-0.3007` |
| `utah` | (283, 414) | 34 m over the top, 5 m wide |  | `--at=283.05,413.98,178.58,-0.4009,-0.9161` |
| `utah` | (495, 196) | 59 m over the top, 4.7 m wide |  | `--at=494.97,196.34,150.48,-0.3423,0.9396` |
| `utah` | (-98, -788) | 28 m over the top, 4.5 m wide |  | `--at=-97.53,-787.75,113.32,-0.9999,-0.0107` |
| `west_coast_usa` | (-457, -915) | 38 m over the top, 6 m wide |  | `--at=-456.83,-915.48,155.79,0.9319,0.3628` |
| `west_coast_usa` | (-926, -260) | 52 m over the top, 4 m wide |  | `--at=-925.56,-260.5,103.37,0.5943,0.8043` |
| `west_coast_usa` | (267, 655) | 55 m over the top, 8.1 m wide |  | `--at=267.19,654.9,106.93,0.9898,0.1428` |
| `west_coast_usa` | (294, 664) | 27 m over the top, 8.1 m wide |  | `--at=293.57,664.04,111.54,0.6719,0.7407` |
| `west_coast_usa` | (240, 955) | 46 m over the top, 5 m wide |  | `--at=240.42,954.78,71.51,-0.9412,0.3378` |
| `west_coast_usa` | (-645, -905) | 18 m over the top, 6 m wide |  | `--at=-645.47,-904.83,169.23,0.8415,0.5403` |
| `west_coast_usa` | (310, 845) | 43 m over the top, 8 m wide |  | `--at=309.79,844.67,115.84,0.8356,-0.5493` |
| `west_coast_usa` | (291, -789) | 48 m over the top, 6 m wide |  | `--at=291.46,-789.26,152.19,-0.9982,0.0601` |
| `west_coast_usa` | (265, -783) | 21 m over the top, 6 m wide |  | `--at=264.92,-783.43,154.53,-0.5281,0.8492` |
| `west_coast_usa` | (306, -754) | 37 m over the top, 6 m wide |  | `--at=306.1,-753.86,153.35,0.9975,0.0709` |
| `west_coast_usa` | (171, 770) | 33 m over the top, 3 m wide |  | `--at=171.22,769.64,101.84,-0.996,0.0891` |
| `west_coast_usa` | (357, 851) | 45 m over the top, 8 m wide |  | `--at=356.76,851.49,127.23,0.9558,0.2941` |
| `west_coast_usa` | (82, 933) | 45 m over the top, 5 m wide |  | `--at=81.91,932.75,77.13,-0.1578,0.9875` |
| `west_coast_usa` | (679, -955) | 47 m over the top, 6 m wide |  | `--at=679.07,-954.6,161.28,0.9667,0.2557` |
| `west_coast_usa` | (239, 909) | 44 m over the top, 5 m wide |  | `--at=238.62,909.4,72.59,-0.6122,-0.7907` |

## Dirt

### Open ground

| Map | Where | What | Fit test | Go there |
| --- | --- | --- | --- | --- |
| `rally_forest` | (112, -9) | 576 x 256 m | **B05 fits** | `--at=112.0,-9.0,4.2,0.0,1.0` |
| `utah` | (968, 8) | 160 x 1680 m | **B05 fits** | `--at=968.0,8.0,235.1,0.0,1.0` |
| `utah` | (504, -952) | 1440 x 352 m | **B05 fits** | `--at=504.0,-952.0,161.6,0.0,1.0` |
| `west_coast_usa` | (337, 96) | our venue `bmp-dirt-arena` | **B05 fits** | `--at=337.07,96.09,127.26,-0.7051,-0.7046` |
| `west_coast_usa` | (265, 40) | our venue `bmp-dirt-circle` | **B05 fits** | `--at=265.0,40.05,127.3,0.7076,0.7067` |
| `automation_test_track` | (-920, 424) | 224 x 128 m | B05: no (Left the road: 3 wheels on GRASS at 13 km/h) | `--at=-920.0,424.0,163.3,0.0,1.0` |
| `automation_test_track` | (728, 648) | 160 x 48 m | B05: no (Hit something at 17 km/h (damage +1376)) | `--at=728.0,648.0,206.2,0.0,1.0` |
| `rally_forest` | (480, -313) | 112 x 128 m |  | `--at=480.0,-313.0,-3.5,0.0,1.0` |
| `utah` | (-56, 24) | 624 x 400 m |  | `--at=-56.0,24.0,173.8,0.0,1.0` |
| `utah` | (-584, -424) | 352 x 448 m |  | `--at=-584.0,-424.0,167.6,0.0,1.0` |
| `utah` | (360, 408) | 432 x 400 m |  | `--at=360.0,408.0,177.1,0.0,1.0` |
| `utah` | (328, -856) | 416 x 256 m |  | `--at=328.0,-856.0,131.7,0.0,1.0` |
| `utah` | (-968, -456) | 160 x 320 m |  | `--at=-968.0,-456.0,297.1,0.0,1.0` |
| `utah` | (-744, -1000) | 592 x 96 m |  | `--at=-744.0,-1000.0,162.4,0.0,1.0` |
| `utah` | (632, 280) | 192 x 192 m |  | `--at=632.0,280.0,145.1,0.0,1.0` |
| `utah` | (-984, -72) | 96 x 256 m |  | `--at=-984.0,-72.0,288.9,0.0,1.0` |
| `utah` | (744, 776) | 208 x 128 m |  | `--at=744.0,776.0,173.5,0.0,1.0` |
| `west_coast_usa` | (313, 504) | 176 x 176 m |  | `--at=313.0,504.0,130.9,0.0,1.0` |

### Straights

| Map | Where | What | Fit test | Go there |
| --- | --- | --- | --- | --- |
| `automation_test_track` | (-534, -346) | 634 m long, 5 m wide, +0.3% | **B01 fits** | `--at=-534.27,-346.11,121.3,0.9799,-0.1993` |
| `automation_test_track` | (-685, -309) | 155 m long, 5 m wide, +0.4% | **B01 fits** | `--at=-684.98,-309.07,120.65,0.9663,-0.2573` |
| `rally_forest` | (307, 462) | 127 m long, 5 m wide, -4.7% | **A05 fits** | `--at=307.2,461.83,5.94,0.4055,-0.9141` |
| `rally_forest` | (19, -62) | 104 m long, 5 m wide, -1.9% |  | `--at=19.19,-62.06,1.78,-0.937,0.3494` |
| `rally_forest` | (347, 82) | 87 m long, 5 m wide, +2.8% |  | `--at=346.6,81.83,-2.69,0.0612,0.9981` |
| `utah` | (-855, 282) | 180 m long, 5.4 m wide, -0.4% | B01: no (needed 237 m but the drill allows 150 m; Hit something at 47 km/h (damage +64)) | `--at=-855.1,282.11,236.36,-0.0605,0.9982` |
| `utah` | (318, 668) | 136 m long, 3 m wide, +1.5% | A05: no (Hit something at 33 km/h (damage +2091)) | `--at=318.23,667.58,165.14,-0.4977,-0.8674` |

### Corners

| Map | Where | What | Fit test | Go there |
| --- | --- | --- | --- | --- |
| `automation_test_track` | (221, 68) | 129° right, r 21.2 m, constant, 5 m wide | **D05 fits** | `--at=220.55,67.68,130.2,-0.058,-0.9983` |
| `automation_test_track` | (795, -301) | 100° right, r 15.7 m, increasing, 6 m wide | **D05 fits** | `--at=795.3,-300.81,133.66,0.0723,-0.9974` |
| `rally_forest` | (224, 292) | 140° right, r 12.3 m, decreasing, 5 m wide | **D05 fits** | `--at=223.7,291.99,0.58,0.3343,0.9425` |
| `utah` | (-18, 708) | 94° left, r 8.7 m, decreasing, 5.6 m wide | **D05 fits** | `--at=-17.99,707.76,186.6,-0.7141,0.7001` |
| `west_coast_usa` | (345, 163) | 149° right, r 38.6 m, constant, 12.1 m wide | **D05 fits** | `--at=344.6,162.61,127.48,0.8665,0.4992` |
| `west_coast_usa` | (641, 49) | 140° left, r 27.9 m, constant, 10 m wide | **D05 fits** | `--at=641.09,48.63,154.35,-0.6227,0.7825` |
| `automation_test_track` | (-460, 185) | 99° right, r 16.4 m, constant, 7.8 m wide |  | `--at=-460.24,185.41,112.74,0.0829,-0.9966` |
| `automation_test_track` | (-422, 162) | 95° left, r 10.6 m, decreasing, 4.8 m wide |  | `--at=-422.05,161.96,125.67,0.4431,-0.8964` |
| `automation_test_track` | (284, 468) | 92° left, r 29.1 m, constant, 6.9 m wide |  | `--at=283.62,468.2,135.4,-0.5063,-0.8624` |
| `automation_test_track` | (76, -467) | 90° left, r 29.9 m, constant, 5 m wide |  | `--at=75.68,-466.75,123.09,0.9908,-0.1354` |
| `automation_test_track` | (735, 344) | 88° left, r 15.7 m, increasing, 5 m wide |  | `--at=734.99,343.62,140.98,0.6831,0.7303` |
| `automation_test_track` | (-382, 229) | 88° left, r 12.7 m, increasing, 6.3 m wide |  | `--at=-381.74,229.39,130,-0.9801,-0.1984` |
| `automation_test_track` | (58, -198) | 85° left, r 9.9 m, increasing, 4 m wide |  | `--at=58.17,-197.79,119.67,0.5948,0.8039` |
| `automation_test_track` | (-332, 85) | 81° left, r 27 m, constant, 8 m wide |  | `--at=-332.01,85.02,114.4,0.9976,-0.0689` |
| `rally_forest` | (164, 474) | 133° left, r 13.8 m, constant, 5 m wide |  | `--at=164.3,474.28,5.19,0.2097,-0.9778` |
| `rally_forest` | (-103, 40) | 123° left, r 9.5 m, decreasing, 5 m wide |  | `--at=-102.67,39.65,-1.69,-0.8017,0.5977` |
| `rally_forest` | (-327, -374) | 116° left, r 9.6 m, constant, 5 m wide |  | `--at=-326.9,-374.15,-3.54,0.8518,0.5238` |
| `rally_forest` | (178, 142) | 100° left, r 12.2 m, decreasing, 5 m wide |  | `--at=178.31,141.88,-0.03,0.0355,0.9994` |
| `rally_forest` | (165, 172) | 95° right, r 21.9 m, decreasing, 5 m wide |  | `--at=164.7,172.35,-1.89,-0.9906,-0.1369` |
| `rally_forest` | (414, 311) | 91° right, r 16.9 m, decreasing, 5 m wide |  | `--at=413.63,311.05,-2.15,0.8154,-0.5789` |
| `rally_forest` | (415, -10) | 89° left, r 25.3 m, constant, 5 m wide |  | `--at=415.23,-9.75,1.65,0.3205,0.9472` |
| `rally_forest` | (-401, 180) | 88° left, r 19.1 m, decreasing, 5 m wide |  | `--at=-401.39,180.3,-2.28,0.2889,-0.9573` |
| `rally_forest` | (-4, 137) | 84° left, r 18.4 m, increasing, 5 m wide |  | `--at=-4.36,137.18,-2.64,-0.9653,0.2612` |
| `rally_forest` | (-48, 329) | 82° left, r 11.7 m, increasing, 5 m wide |  | `--at=-48.19,329.47,1.99,0.7644,-0.6447` |
| `rally_forest` | (179, 105) | 80° right, r 20.9 m, constant, 5 m wide |  | `--at=179.17,105.35,2.79,-0.3729,-0.9279` |
| `rally_forest` | (-330, -281) | 79° right, r 15.7 m, constant, 5 m wide |  | `--at=-329.51,-281.29,1.97,-0.0859,0.9963` |
| `rally_forest` | (-90, -100) | 79° right, r 15.3 m, constant, 5 m wide |  | `--at=-90.43,-99.77,1.97,0.9755,0.2201` |
| `rally_forest` | (296, -288) | 72° right, r 22 m, constant, 5 m wide |  | `--at=296.03,-287.55,-7.75,0.9897,0.1435` |
| `rally_forest` | (-158, -136) | 71° right, r 13.1 m, decreasing, 5 m wide |  | `--at=-157.64,-135.66,1.97,0.2533,0.9674` |
| `rally_forest` | (-191, -216) | 70° left, r 14.1 m, increasing, 5 m wide |  | `--at=-190.6,-215.99,1.97,0.9348,0.3551` |
| `rally_forest` | (115, 103) | 68° left, r 16.7 m, decreasing, 5 m wide |  | `--at=115.32,102.98,4.47,-0.4963,0.8681` |
| `rally_forest` | (-297, -17) | 68° left, r 15.3 m, constant, 5 m wide |  | `--at=-297.08,-17.18,1.97,0.5795,0.815` |
| `rally_forest` | (212, -266) | 67° right, r 18.4 m, increasing, 5 m wide |  | `--at=211.81,-265.93,-7.25,-0.9948,0.1019` |
| `rally_forest` | (-297, 48) | 67° left, r 30.6 m, constant, 5 m wide |  | `--at=-297.12,47.87,1.97,-0.0676,0.9977` |
| `rally_forest` | (374, 51) | 64° right, r 25.4 m, decreasing, 5 m wide |  | `--at=373.56,51.37,0.17,-0.9371,0.3491` |
| `rally_forest` | (188, 262) | 64° left, r 21.2 m, constant, 5 m wide |  | `--at=187.85,262.36,0.44,0.9749,0.2226` |
| `rally_forest` | (311, -266) | 64° right, r 8.6 m, decreasing, 5 m wide |  | `--at=311.19,-265.61,-8.31,-1.0,0.0075` |
| `rally_forest` | (273, 492) | 62° right, r 15 m, constant, 5 m wide |  | `--at=272.6,492.21,2.95,0.9727,0.2322` |
| `rally_forest` | (-313, -344) | 57° right, r 12.8 m, decreasing, 5 m wide |  | `--at=-312.71,-343.65,-0.15,-0.8407,0.5415` |
| `rally_forest` | (250, 79) | 56° right, r 17 m, decreasing, 5 m wide |  | `--at=249.83,78.79,6.11,0.4278,-0.9039` |
| `rally_forest` | (129, 226) | 56° right, r 24.2 m, increasing, 5 m wide |  | `--at=128.8,226.21,-0.1,0.3014,0.9535` |
| `utah` | (860, 394) | 114° right, r 26.9 m, constant, 2.9 m wide | D05: no (Left the road: 3 wheels on GRAVEL at 32 km/h) | `--at=859.82,393.51,223.92,-0.2205,0.9754` |
| `utah` | (179, 480) | 81° left, r 9.3 m, increasing, 4.3 m wide |  | `--at=179.11,480.25,169.94,-0.9589,0.2837` |
| `west_coast_usa` | (751, 218) | 140° right, r 17.6 m, increasing, 10 m wide |  | `--at=750.71,218.19,155.62,0.3466,0.938` |
| `west_coast_usa` | (-999, -499) | 118° left, r 29 m, increasing, 4 m wide |  | `--at=-998.93,-499.24,99.99,0.0223,-0.9998` |
| `west_coast_usa` | (595, -648) | 116° left, r 14.4 m, constant, 8 m wide |  | `--at=595.08,-648.29,203.83,-0.293,-0.9561` |

### Hairpins

| Map | Where | What | Fit test | Go there |
| --- | --- | --- | --- | --- |
| `automation_test_track` | (-527, 104) | 241° left, r 17.8 m, hairpin, 8 m wide | **C04 fits** | `--at=-526.52,103.72,113.87,-0.5806,0.8142` |
| `automation_test_track` | (679, 667) | 190° left, r 11.4 m, hairpin, 6 m wide | **C04 fits** | `--at=679.42,666.91,205.89,-0.9415,-0.3369` |
| `west_coast_usa` | (-569, 312) | 188° left, r 8.5 m, hairpin, 4 m wide | **C04 fits** | `--at=-568.9,312.36,104.38,-0.6902,0.7236` |
| `automation_test_track` | (797, 698) | 181° right, r 11.6 m, hairpin, 5.6 m wide |  | `--at=796.55,697.83,221.07,0.9961,0.0877` |
| `automation_test_track` | (-515, 159) | 178° left, r 11.7 m, hairpin, 6.6 m wide |  | `--at=-514.54,158.52,112.98,-0.9975,-0.0711` |
| `automation_test_track` | (914, 377) | 161° right, r 11.3 m, hairpin, 5.3 m wide |  | `--at=913.64,377.14,161.18,-0.2639,-0.9646` |
| `automation_test_track` | (-467, 135) | 158° right, r 14 m, hairpin, 7.3 m wide |  | `--at=-467.26,135.13,112.94,0.9999,-0.0159` |
| `west_coast_usa` | (-486, -644) | 202° right, r 13.1 m, hairpin, 8 m wide | C04: no (Left the road: 4 wheels on GRAVEL at 27 km/h) | `--at=-485.72,-643.61,145.24,0.9961,-0.0877` |

### Hills

| Map | Where | What | Fit test | Go there |
| --- | --- | --- | --- | --- |
| `automation_test_track` | (-316, 146) | -17.7% over 83 m, 5.1 m wide | **D06 fits** | `--at=-315.73,146.28,130.32,-0.4079,-0.913` |
| `automation_test_track` | (653, 716) | -17.4% over 122 m, 5.7 m wide | **D06 fits** | `--at=653.39,716.4,243.22,0.996,-0.0896` |
| `rally_forest` | (225, -16) | -10.7% over 64 m, 5 m wide | **D06 fits** | `--at=225.31,-16.26,5.62,-0.7879,-0.6158` |
| `utah` | (-522, 259) | -21.7% over 83 m, 2.7 m wide | **D06 fits** | `--at=-521.53,258.67,281.99,0.9591,-0.2829` |
| `automation_test_track` | (845, 466) | -14.5% over 84 m, 6.3 m wide |  | `--at=845.09,465.91,157.58,-0.8906,0.4549` |
| `automation_test_track` | (831, 644) | -13.1% over 336 m, 5 m wide |  | `--at=831.17,644.18,204.05,0.8953,-0.4455` |
| `automation_test_track` | (-259, 215) | -12.6% over 175 m, 6.1 m wide |  | `--at=-259.25,214.59,130.18,-0.4239,0.9057` |
| `automation_test_track` | (-305, 86) | +11.7% over 130 m, 7 m wide |  | `--at=-304.98,86.46,115.4,0.9228,0.3853` |
| `automation_test_track` | (819, 676) | -11.4% over 116 m, 5.6 m wide |  | `--at=819.06,676,220.23,-0.7938,-0.6082` |
| `automation_test_track` | (312, 511) | +10.5% over 97 m, 6.6 m wide |  | `--at=312.32,510.82,135.28,0.3539,0.9353` |
| `automation_test_track` | (878, -400) | +9.4% over 72 m, 6 m wide |  | `--at=878.41,-400.48,125.61,-0.4687,0.8833` |
| `rally_forest` | (278, 269) | -10.1% over 63 m, 5 m wide |  | `--at=278.1,269.45,1.63,0.6865,-0.7271` |
| `utah` | (-917, -147) | -21.3% over 142 m, 2.6 m wide | D06: no (Hit something at 33 km/h (damage +87)) | `--at=-917.09,-147.4,275.47,0.5895,0.8077` |

### Crests

| Map | Where | What | Fit test | Go there |
| --- | --- | --- | --- | --- |
| `automation_test_track` | (939, -472) | 34 m over the top, 5.9 m wide | **E05 fits** | `--at=939.43,-472.5,122.69,0.9293,0.3693` |
| `automation_test_track` | (-322, 156) | 19 m over the top, 6 m wide | **E05 fits** | `--at=-322.12,155.92,129.99,0.8794,-0.4761` |
| `rally_forest` | (349, 114) | 50 m over the top, 5 m wide | **E05 fits** | `--at=348.57,113.96,-0.35,0.0332,0.9994` |
| `utah` | (194, 488) | 42 m over the top, 4.3 m wide | **E05 fits** | `--at=193.86,487.69,168.82,-0.8522,-0.5232` |
| `automation_test_track` | (-413, 206) | 28 m over the top, 4.5 m wide |  | `--at=-412.73,206.36,125.41,0.1504,-0.9886` |
| `automation_test_track` | (785, 28) | 54 m over the top, 6 m wide |  | `--at=785.15,27.5,135.56,0.7636,0.6457` |
| `automation_test_track` | (-383, 192) | 27 m over the top, 6.2 m wide |  | `--at=-383.39,192.03,129.99,-0.2429,0.97` |
| `automation_test_track` | (-261, 180) | 53 m over the top, 7 m wide |  | `--at=-260.63,180.14,127.62,0.4354,0.9002` |
| `automation_test_track` | (-464, 203) | 54 m over the top, 7.8 m wide |  | `--at=-464.23,202.87,111.54,0.2228,-0.9749` |
| `automation_test_track` | (-459, 176) | 26 m over the top, 7.8 m wide |  | `--at=-459.47,176.15,113.17,-0.1268,-0.9919` |
| `rally_forest` | (-50, 57) | 57 m over the top, 5 m wide |  | `--at=-49.66,56.84,0.29,0.174,-0.9847` |
| `rally_forest` | (21, -46) | 58 m over the top, 5 m wide |  | `--at=20.7,-45.89,0.52,0.4719,-0.8817` |
| `rally_forest` | (-111, 46) | 60 m over the top, 5 m wide |  | `--at=-111.04,45.89,-1.45,-0.9623,0.2719` |
| `rally_forest` | (-131, 20) | 17 m over the top, 5 m wide |  | `--at=-131.47,20.01,-1.16,-0.5225,-0.8526` |
| `rally_forest` | (-283, -94) | 46 m over the top, 5 m wide |  | `--at=-283.16,-94.29,-9.5,-0.8959,-0.4442` |
| `rally_forest` | (-311, -109) | 16 m over the top, 5 m wide |  | `--at=-310.59,-108.51,-7.46,-0.9303,-0.3667` |
| `rally_forest` | (-295, -68) | 32 m over the top, 5 m wide |  | `--at=-295.22,-67.8,-5.94,0.5549,0.8319` |
| `rally_forest` | (-326, -87) | 42 m over the top, 5 m wide |  | `--at=-326.39,-87.2,-3.9,-0.6235,-0.7818` |
| `rally_forest` | (-346, -110) | 11 m over the top, 5 m wide |  | `--at=-346.28,-110.08,-0.25,-0.9979,-0.0648` |
| `rally_forest` | (-390, 126) | 43 m over the top, 5 m wide |  | `--at=-390.25,125.79,1.91,-0.6568,0.754` |
| `rally_forest` | (-275, 407) | 54 m over the top, 5 m wide |  | `--at=-274.76,407.03,5.01,0.8086,0.5884` |
| `rally_forest` | (-63, 343) | 36 m over the top, 5 m wide |  | `--at=-62.91,342.89,1.47,0.7507,-0.6606` |
| `utah` | (-830, 545) | 50 m over the top, 2.8 m wide | E05: no (Hit something at 26 km/h (damage +1557)) | `--at=-830.4,544.72,232.19,0.6165,0.7873` |
| `utah` | (927, -75) | 30 m over the top, 2.3 m wide |  | `--at=927.24,-75.08,199.67,-0.485,0.8745` |
| `utah` | (925, 509) | 19 m over the top, 3.1 m wide |  | `--at=924.65,508.88,221.55,0.0479,0.9989` |
| `utah` | (-614, 297) | 56 m over the top, 1.3 m wide |  | `--at=-614.43,297.35,286.08,-0.9211,0.3893` |
| `utah` | (-638, 312) | 28 m over the top, 1.3 m wide |  | `--at=-638.03,311.74,289.5,-0.5832,0.8123` |
| `utah` | (-649, 334) | 3 m over the top, 1.3 m wide |  | `--at=-648.74,334.37,294.59,-0.073,0.9973` |

## Sand

### Hairpins

| Map | Where | What | Fit test | Go there |
| --- | --- | --- | --- | --- |
| `automation_test_track` | (-321, 196) | 151° left, r 10.4 m, hairpin, 8.9 m wide | **C04 fits** | `--at=-321.26,196.42,129.99,0.9934,0.1149` |

### Crests

| Map | Where | What | Fit test | Go there |
| --- | --- | --- | --- | --- |
| `utah` | (927, -101) | 57 m over the top, 2.3 m wide | E05: no (Left the road: 3 wheels on DIRT_DUSTY at 3 km/h) | `--at=926.78,-100.71,197.56,0.5113,0.8594` |

## Mud

### Open ground

| Map | Where | What | Fit test | Go there |
| --- | --- | --- | --- | --- |
| `automation_test_track` | (168, 520) | 336 x 400 m | B05: no (start spot isn't clear: the game moved the car 1.3 m when placing it) | `--at=168.0,520.0,108.0,0.0,1.0` |
| `automation_test_track` | (168, 856) | 448 x 256 m | B05: no (start spot isn't clear: the game moved the car 1.2 m when placing it) | `--at=168.0,856.0,124.0,0.0,1.0` |
| `automation_test_track` | (40, -24) | 256 x 304 m |  | `--at=40.0,-24.0,104.0,0.0,1.0` |
| `automation_test_track` | (-104, 632) | 112 x 416 m |  | `--at=-104.0,632.0,107.4,0.0,1.0` |
| `automation_test_track` | (280, 728) | 64 x 96 m |  | `--at=280.0,728.0,112.0,0.0,1.0` |

### Crests

| Map | Where | What | Fit test | Go there |
| --- | --- | --- | --- | --- |
| `rally_forest` | (391, -273) | 40 m over the top, 5 m wide | E05: no (start spot isn't clear: the game moved the car 1.0 m when placing it; the AI did) | `--at=390.59,-272.74,-12.7,-0.6938,-0.7201` |

## Grass

### Open ground

| Map | Where | What | Fit test | Go there |
| --- | --- | --- | --- | --- |
| `automation_test_track` | (136, -664) | 832 x 352 m | B05: no (Left the road: 3 wheels on GRAVEL at 14 km/h) | `--at=136.0,-664.0,117.6,0.0,1.0` |
| `automation_test_track` | (680, -568) | 160 x 64 m | B05: no (Hit something at 17 km/h (damage +55); Left the road: 3 wheels on DIRT at 22 km/) | `--at=680.0,-568.0,120.8,0.0,1.0` |
| `rally_forest` | (240, 231) | 160 x 192 m | B05: no (Hit something at 19 km/h (damage +255); Left the road: 3 wheels on DIRT at 17 km) | `--at=240.0,231.0,4.4,0.0,1.0` |
| `utah` | (-424, 920) | 1920 x 608 m | B05: no (Hit something at 54 km/h (damage +3388); Rolled over at 23 km/h; Left the road: ) | `--at=-424.0,920.0,298.2,0.0,1.0` |

## Snow

### Open ground

| Map | Where | What | Fit test | Go there |
| --- | --- | --- | --- | --- |
| `automation_test_track` | (-568, 888) | snowfield ~176 x 224 m | B05: no (Hit something at 13 km/h (damage +56); Left the road: 3 wheels on GRASS at 4 km/) | `--at=-568,888,264.0,1.0,0.0` |
| `automation_test_track` | (-540, 930) | snowfield ~176 x 224 m | B05: no (Hit something at 14 km/h (damage +55)) | `--at=-540,930,266.0,0.0,1.0` |

## Rock

### Hills

| Map | Where | What | Fit test | Go there |
| --- | --- | --- | --- | --- |
| `utah` | (919, -158) | +15.3% over 71 m, 2.9 m wide | D06: no (the AI didn't get through the section at 35 km/h) | `--at=919.43,-157.9,188.02,-0.2066,0.9784` |

### Crests

| Map | Where | What | Fit test | Go there |
| --- | --- | --- | --- | --- |
| `utah` | (919, 475) | 54 m over the top, 3.1 m wide | E05: no (Left the road: 3 wheels on GRAVEL at 18 km/h) | `--at=918.74,474.67,219.61,0.0232,0.9997` |

## Mixed

### Open ground

| Map | Where | What | Fit test | Go there |
| --- | --- | --- | --- | --- |
| `utah` | (280, -312) | 1312 x 1136 m |  | `--at=280.0,-312.0,135.7,0.0,1.0` |
| `utah` | (-424, -744) | 304 x 176 m |  | `--at=-424.0,-744.0,104.5,0.0,1.0` |

### Straights

| Map | Where | What | Fit test | Go there |
| --- | --- | --- | --- | --- |
| `utah` | (-320, -555) | 238 m long, 8.4 m wide, +1.7% |  | `--at=-320.17,-554.85,129.66,0.9868,-0.1618` |

### Corners

| Map | Where | What | Fit test | Go there |
| --- | --- | --- | --- | --- |
| `automation_test_track` | (-270, 761) | 142° right, r 24.1 m, increasing, 7.3 m wide |  | `--at=-270.45,760.55,267.1,-0.3666,-0.9304` |
| `west_coast_usa` | (-510, -663) | 130° left, r 9.8 m, decreasing, 8 m wide |  | `--at=-510.32,-662.89,159.93,-0.3876,0.9218` |

### Hills

| Map | Where | What | Fit test | Go there |
| --- | --- | --- | --- | --- |
| `automation_test_track` | (-535, 667) | -12.6% over 236 m, 7.3 m wide |  | `--at=-535.1,667.11,260.03,0.7519,-0.6593` |

### Crests

| Map | Where | What | Fit test | Go there |
| --- | --- | --- | --- | --- |
| `utah` | (169, 481) | 15 m over the top, 4.4 m wide |  | `--at=169.13,481.23,171.38,-0.9818,-0.1897` |
| `utah` | (914, -244) | 58 m over the top, 1.4 m wide |  | `--at=913.74,-243.6,182.83,0.4803,0.8771` |
| `utah` | (921, -205) | 18 m over the top, 1.4 m wide |  | `--at=921.38,-205.39,187.72,0.0467,0.9989` |
| `utah` | (864, 363) | 44 m over the top, 3.6 m wide |  | `--at=864.09,363.24,223.43,-0.0266,0.9996` |
