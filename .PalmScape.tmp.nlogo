extensions [ gis vid palette ]

globals [
  roads-dataset
  farms-dataset
  cities-dataset
  boundaries-dataset
  revenue
  cost
  profit
  max-palmOil
  optimal-patches
  ticks-per-year
  load-unload-time
]

breed [ city-labels city-label ]

turtles-own [
  currentTruckCapacity
  speed
  health
  transportState  ; 0 - heading out, 1 - picking up ; 2 - returning; 3 - dropping off
  firstRound
  homeDistance
  distanceTurtle?
  visitedOptimal?
]

patches-own [
  road?
  farm?
  plant?
  palmOil
  farmCapital
  currentPlantCapacity
  traversable
  trackDensity
  plantDistance
  contractDistance
  degradation
  contract?
  newFarm?
  growthFactor
  baseMapColor
  developed
]

to setup
  clear-all
  setup-gis
  setup-patches
  compute-manhattan-distances
  assign-contracts
  compute-contract-manhattan-distances
  setup-turtles
  setup-time
  reset-ticks
  if vid:recorder-status = "recording" [ vid:record-interface ]
end

to go
;  rest-farms
  find-optimal
  regenerate-farms
  grow-palm-oil
  head-out
  pick-up-loads
  head-home
  drop-off-loads
  sell-oil
  expand-farm
  maintain-farms
  liquidate-farm
  color-farms
  color-roads
  color-plants
  buy-trucks
  maintain-trucks
  trucks-age
  trucks-breakdown
  calculate-profit
  tick
  if vid:recorder-status = "recording" [ vid:record-interface ]
end

to setup-time
;  let average-trip-distance sum [ plantDistance ] of patches with [ contract? = true ] / count patches with [ contract? = true ]
  let average-trip-distance 25
  let trips-per-month 1
  let pickup-factor 1.25
  let months-per-year 12
  set ticks-per-year average-trip-distance * trips-per-month * pickup-factor * months-per-year
  set load-unload-time average-trip-distance / 3
end

to setup-gis
  set boundaries-dataset gis:load-dataset "C:/Users/user/Downloads/KEN_adm_shp/KEN_adm0.shp"
  set roads-dataset gis:load-dataset "C:/Users/user/Downloads/ke_major-roads/ke_major-roads.shp"
  set farms-dataset gis:load-dataset "C:/Users/user/Downloads/ke_agriculture/ke_agriculture.shp"
  set cities-dataset gis:load-dataset "C:/Users/user/Downloads/ke_major-towns/ke_major_cities.shp"
  gis:set-world-envelope (gis:envelope-union-of (gis:envelope-of boundaries-dataset)
                                                (gis:envelope-of roads-dataset)
                                                (gis:envelope-of farms-dataset)
                                                (gis:envelope-of cities-dataset))
  ; satellite
  ; use world imagery basemap in ArcGIS with extent set to country boundaries
  import-pcolors "C:/Users/user/Dropbox/Oxford/DPhil/NetLogo/Kenya_satellite2.jpg"
  ask patches [
    set baseMapColor pcolor
  ]
  ; boundaries
  gis:set-drawing-color white
  gis:draw boundaries-dataset 5.0
  ; roads
  ask patches gis:intersecting roads-dataset [
    set pcolor 8
    set road? true
    set developed 1
  ]
  ; farms
  ask patches with [ road? = 0 ] gis:intersecting farms-dataset [
    set pcolor 57
    set farm? true
    set traversable 1
    set trackDensity 0
    set farmCapital 1 + random-float 3
    set plantDistance 999999999
    set contractDistance 999999999
    set developed 1
  ]
  ; cities
  ask city-labels [ die ]
  foreach gis:feature-list-of cities-dataset [ [vector-feature] ->
    gis:set-drawing-color black
    gis:fill vector-feature 5.0
    let location gis:location-of (first (first (gis:vertex-lists-of vector-feature)))
    if not empty? location
    [ create-city-labels 1
      [ set xcor item 0 location
        set ycor item 1 location
        set size 0
        set label gis:property-value vector-feature "TOWN_NAME"
        set label-color black
      ]
    ]
  ]
end

to create-roads
  ask patches with [ road? = true ] [
    set traversable 1
    set trackDensity 0
    set plantDistance 999999999
    set contractDistance 999999999
    set developed 1
  ]
end

to create-farms
  let potentialSites patches with [ traversable = 0 ]
  let nextToRoad potentialSites with [ any? neighbors4 with [ road? = true ] ]
  ask n-of number-of-farms nextToRoad [
    set pcolor 57
    set farm? true
    set traversable 1
    set trackDensity 0
    set farmCapital 1 + random-float 3
    set plantDistance 999999999
    set contractDistance 999999999
    set developed 1
  ]
end

to create-plants
  let potentialSites patches with [ road? = 0 ]
  let nextToRoad potentialSites with [ any? neighbors4 with [ road? = true ] ]
  ask n-of number-of-plants nextToRoad [
    set pcolor 18
    set plant? true
    set farm? 0
    set currentPlantCapacity 0
    set traversable 1
    set trackDensity 0
    set plantDistance 0
    set contractDistance 999999999
    set developed 1
  ]
end

to setup-patches
  create-roads
;  create-farms
  create-plants
end

to compute-manhattan-distances
  ask patches with [ plant? = true and traversable = 1 ] [
    sprout 1 [
      set distanceTurtle? true
      set homeDistance 0
    ]
  ]
  repeat 10000 [ compute-manhattan-distance-one-step ]
end

to compute-manhattan-distance-one-step
  ask turtles with [ distanceTurtle? = true ] [
    set plantDistance homeDistance
    let nextDistance homeDistance + 1
    let patchesToVisit neighbors4 with [ traversable = 1 and nextDistance < plantDistance ]
    ask patchesToVisit [
      if not any? turtles-here [
        sprout 1 [
          set distanceTurtle? true
          set homeDistance nextDistance
          set hidden? true
        ]
      ]
    ]
    die
  ]
end

to assign-contracts
  let proportion-farms round ( 0.05 * count patches with [ farm? = true ] )
  ask n-of proportion-farms patches with [ farm? = true and plantDistance < 999999999 ] [
    set contract? true
    if contract? = true [ set plabel "C" ]
  ]
end

to compute-contract-manhattan-distances
  ask patches with [ contract? = true and traversable = 1 ] [
    sprout 1 [
      set distanceTurtle? true
      set homeDistance 0
    ]
  ]
  repeat 10000 [ compute-contract-manhattan-distance-one-step ]
end

to compute-contract-manhattan-distance-one-step
  ask turtles with [ distanceTurtle? = true ] [
    set contractDistance homeDistance
    let nextDistance homeDistance + 1
    let patchesToVisit neighbors4 with [ traversable = 1 and nextDistance < contractDistance ]
    ask patchesToVisit [
      if not any? turtles-here with [ distanceTurtle? = true ] [
        sprout 1 [
          set distanceTurtle? true
          set homeDistance nextDistance
          set hidden? true
        ]
      ]
    ]
    die
  ]
end

to setup-turtles
  set-default-shape turtles "car"
;  start with one truck
  ask patches with [ plant? = true ] [
    sprout 1 [
      set color blue
      set heading 0
      set speed 1
      set health 100
      set transportState 0
      set firstRound 1
      set distanceTurtle? false
    ]
  ]
end

to head-out
  ask turtles with [ distanceTurtle? = false and transportState = 0 ] [
    if any? neighbors4 with [ traversable = 1 ] [
      let p min-one-of neighbors4 with [ traversable = 1 ] [ contractDistance ]
      let p-min [ contractDistance ] of p
      if p-min < contractDistance [
        face p
        move-to p
      ]
    ]
    if contractDistance = 0 [
      ;    show "head-out-optimal"
      set transportState transportState + 1
    ]
]
end

to head-home
  ask turtles with [ distanceTurtle? = false and transportState = 2 ] [
    if any? neighbors4 with [ traversable = 1 ] [
      let p min-one-of neighbors4 with [ traversable = 1 ] [ plantDistance ]
      face p
      move-to p
    ]
    if plant? = true [
      ;show "head-home"
      set transportState transportState + 1
    ]
  ]
end

to grow-palm-oil
  let tickInYear ticks mod ticks-per-year
  let ticks-per-month ticks-per-year / 12
  let start-growing-season ticks-per-month * 5
  let end-growing-season ticks-per-month * 9
  ask patches with [ farm? = true ] [
    ifelse tickInYear > start-growing-season and tickInYear < end-growing-season [
      set growthFactor growth-rate
    ] [
      set growthFactor 0 - growth-rate
    ]
  ]
  ask patches with [ farm? = true ] [
;    palm oil grows on farms at certain rate
    set palmOil palmOil + growthFactor
    ifelse palmOil - degradation > 0 [
      set palmOil palmOil - degradation
    ] [
      set palmOil 0
    ]
  ]
end

to pick-up-loads
  ask turtles with [ distanceTurtle? = false and transportState = 1 ] [
;    trucks below capacity pick up plam oil
    let pick-up-amount ( max-truck-capacity / load-unload-time )
    let oldCapacity currentTruckCapacity
    if currentTruckCapacity < max-truck-capacity and palmOil > pick-up-amount and contract? = true [
      let remainingTruckCapacity max-truck-capacity - currentTruckCapacity
      let toPickUp min list remainingTruckCapacity pick-up-amount
      set currentTruckCapacity currentTruckCapacity + toPickUp
      set palmOil palmOil - toPickUp
      set farmCapital farmCapital + toPickUp
      set degradation degradation + degradation-rate
    ]
    if currentTruckCapacity = oldCapacity [
      set transportState transportState - 1
    ]
    if currentTruckCapacity >= max-truck-capacity [
      set color magenta
;      show "pick-up-loads"
      set transportState transportState + 1
    ]
  ]
end

to drop-off-loads
  let drop-off-amount ( max-truck-capacity / load-unload-time )
  ask turtles with [ distanceTurtle? = false and transportState = 3 ] [
;    trucks at full capacity drop off loads at plants
    if currentTruckCapacity > 0 and transportState = 3 and plant? = true [
;      palm oil in trucks processed and converted to revenue
      let remaining min list currentTruckCapacity drop-off-amount
      if currentPlantCapacity + remaining <= max-plant-capacity [
        set currentTruckCapacity currentTruckCapacity - remaining
        set currentPlantCapacity currentPlantCapacity + remaining
      ]
      if currentTruckCapacity = 0 [
        set transportState 0
        set color blue
      ]
    ]
  ]
end

to find-optimal
  set max-palmOil max [ palmOil ] of patches with [ contract? = true ]
  set optimal-patches patches with [ ( palmOil >= optimal-proportion * max-palmOil ) and ( contract? = true ) ]
  ask turtles with [ distanceTurtle? = false ] [
    if contractDistance = 0 and visitedOptimal? = 0 [
      set visitedOptimal? true
    ]
  ]
  if count turtles with [ distanceTurtle? = false and visitedOptimal? = true ] = count turtles with [ distanceTurtle? = false ]
  [
    ask patches with [ traversable = 1 ] [
      set contractDistance 999999999
    ]
    ask turtles with [ distanceTurtle? = false ] [
      set visitedOptimal? 0
    ]
    ask optimal-patches [
      sprout 1 [
        set distanceTurtle? true
        set homeDistance 0
        set hidden? true
      ]
    ]
    repeat 10000 [ compute-contract-manhattan-distance-one-step ]
  ]
end

to sell-oil
  ask one-of patches with [ plant? = true ] [
    if currentPlantCapacity >= max-truck-capacity [
      set currentPlantCapacity currentPlantCapacity - max-truck-capacity
      set revenue revenue + max-truck-capacity
    ]
  ]
end

to expand-farm
  ask patches with [ farm? = true ] [
;    farms with enough capital expand to adjacent road (where trucks can pick up)
    if farmCapital >= 5 and any? neighbors4 with [ developed = 0 ] [
      set farmCapital farmCapital - 5
      ask one-of neighbors4 with [ developed = 0 ] [
        set pcolor 57
        set farm? true
        set newFarm? true
        set farmCapital 1 + random-float 3
        set traversable 1
        set developed 1
        set trackDensity 0
        let p random-float 1
        ifelse p > 0.1 [ set contract? true ] [ set contract? false ]
        if contract? [ set plabel "C" ]
        if any? neighbors4 with [ traversable = 1 ] [
          set plantDistance [ plantDistance ] of min-one-of neighbors4 with [ traversable = 1 ] [ plantDistance ] + 1
        ]
      ]
    ]
  ]
end

to liquidate-farm
  ask patches with [ farm? = true ] [
    if farmCapital < 0 [
      set farm? false
      set farmCapital 0
      set newFarm? 0
      set palmOil 0
      set pcolor 35
      set contract? 0
      set plabel ""
      set developed 0
    ]
  ]
end

to maintain-farms
  ask patches with [ farm? = true ] [
    set farmCapital farmCapital - farm-maintenance-cost
  ]
end

to color-farms
  let light-green-netlogo extract-rgb 57
  let dark-green-netlogo extract-rgb 53
  ask patches with [ farm? = true ] [
    set pcolor palette:scale-gradient ( list light-green-netlogo dark-green-netlogo ) palmOil 0 1000
  ]
end

to color-roads
  let light-gray-netlogo extract-rgb 8
  let dark-gray-netlogo extract-rgb 4
  ask patches with [ road? = true ] [
    set pcolor palette:scale-gradient ( list light-gray-netlogo dark-gray-netlogo ) trackDensity 0 10
  ]
end

to color-plants
  let light-red-netlogo extract-rgb 18
  let dark-red-netlogo extract-rgb 14
  ask patches with [ plant? = true ] [
    set pcolor palette:scale-gradient ( list light-red-netlogo dark-red-netlogo ) currentPlantCapacity 0 max-plant-capacity
  ]
end

to buy-trucks
  let numTrucks count turtles with [ distanceTurtle? = false ]
  ask one-of patches with [ plant? = true ] [
;    company buys trucks if profits exceed threshold
    if profit > truck-cost and currentPlantCapacity <= 0.75 * max-plant-capacity and numTrucks < max-trucks [
;      wait 2
      sprout 1 [
        set color blue
        set health 100
        set transportState 0
        set firstRound 0
;        new trucks move at random speed
        set speed random-float 1
;        new trucks randomly move east or west
        ifelse random 1 > 0.5 [ set heading 90 ] [ set heading 270 ]
        set distanceTurtle? false
      ]
;      company accounts for truck costs on balance sheet
      set cost cost + truck-cost
    ]
  ]
end

to maintain-trucks
  let maintenance maintenance-cost
  let numTrucks count turtles with [ distanceTurtle? = false ]
  if profit > numTrucks * maintenance [
    ask turtles with [ distanceTurtle? = false ] [
      if health < 100 [
        set health health + maintenance
      ]
    ]
    set cost cost + numTrucks * maintenance
  ]
end

to trucks-age
  ask turtles with [ distanceTurtle? = false ] [
    set health health - 0.02
  ]
end

to trucks-breakdown
  ask turtles with [ distanceTurtle? = false ] [
    if health < 10 [ die ]
  ]
end

to calculate-profit
  set profit ( revenue - cost )
end

to start-recorder
  carefully [ vid:start-recorder ] [ user-message error-message ]
end

to reset-recorder
  let message (word
    "If you reset the recorder, the current recording will be lost."
    "Are you sure you want to reset the recorder?")
  if vid:recorder-status = "inactive" or user-yes-or-no? message [
    vid:reset-recorder
  ]
end

to save-recording
  if vid:recorder-status = "inactive" [
    user-message "The recorder is inactive. There is nothing to save."
    stop
  ]
  ; prompt user for movie location
  user-message (word
    "Choose a name for your movie file (the "
    ".mp4 extension will be automatically added).")
  let path user-new-file
  if not is-string? path [ stop ]  ; stop if user canceled
  ; export the movie
  carefully [
    vid:save-recording path
    user-message (word "Exported movie to " path ".")
  ] [
    user-message error-message
  ]
end

to rest-farms
    ifelse rest-quadrant = "top right" [
      ask patches with [ pxcor > 0 and pycor > 0 ] [
        set traversable 0
      ]
      reset-plant-distance-farms-rest
    ] [
      reset-plant-distance-no-farm-rest
      ifelse rest-quadrant = "top left" [
        ask patches with [ pxcor < 0 and pycor > 0 ] [
          set traversable 0
        ]
        reset-plant-distance-farms-rest
      ] [
        reset-plant-distance-no-farm-rest
        ifelse rest-quadrant = "bottom right" [
          ask patches with [ pxcor > 0 and pycor < 0 ] [
            set traversable 0
          ]
          reset-plant-distance-farms-rest
        ] [
          reset-plant-distance-no-farm-rest
          ifelse rest-quadrant = "bottom left" [
            ask patches with [ pxcor < 0 and pycor < 0 ] [
              set traversable 0
            ]
            reset-plant-distance-farms-rest
          ] [
            reset-plant-distance-no-farm-rest
          ]
        ]
      ]
    ]
end

to reset-plant-distance-farms-rest
  ask patches with [ farm? = true or road? = true ] [
    set plantDistance 999999999
  ]
  ask patches with [ plant? = true ] [
    set plantDistance 0
  ]
  compute-manhattan-distances
end

to reset-plant-distance-no-farm-rest
  ask patches with [ farm? = true or road? = true or plant? = true ] [
    set traversable 1
  ]
  ask patches with [ farm? = true or road? = true ] [
    set plantDistance 999999999
  ]
  ask patches with [ plant? = true ] [
    set plantDistance 0
  ]
  compute-manhattan-distances
end

to regenerate-farms
  ask patches with [ farm? = true ] [
    ifelse degradation - regeneration-rate > 0 [
      set degradation degradation - regeneration-rate
    ] [
      set degradation 0
    ]
  ]
end
@#$#@#$#@
GRAPHICS-WINDOW
3
628
2021
2647
-1
-1
10.0
1
24
1
1
1
0
0
0
1
-100
100
-100
100
1
1
1
ticks
30.0

BUTTON
120
374
183
407
NIL
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
0

BUTTON
119
335
182
368
NIL
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

MONITOR
11
332
103
377
NIL
revenue
17
1
11

MONITOR
10
388
104
433
NIL
cost
17
1
11

PLOT
9
10
209
160
profit over time
time
profit
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot profit"

SLIDER
240
53
417
86
growth-rate
growth-rate
0
50
20.1
0.1
1
NIL
HORIZONTAL

MONITOR
10
446
104
491
NIL
profit
17
1
11

MONITOR
9
502
104
547
number of trucks
count turtles with [ distanceTurtle? = false ]
0
1
11

SLIDER
232
198
405
231
truck-cost
truck-cost
1
10
5.0
1
1
NIL
HORIZONTAL

SLIDER
232
237
408
270
maintenance-cost
maintenance-cost
0
0.05
0.02
0.01
1
NIL
HORIZONTAL

PLOT
11
165
211
315
current capacity over time
time
current capacity
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot sum [ currentPlantCapacity ] of patches with [ plant? = true ]"

SLIDER
233
278
405
311
max-trucks
max-trucks
0
50
30.0
1
1
NIL
HORIZONTAL

SLIDER
1712
97
1885
130
number-of-farms
number-of-farms
0
2000
2000.0
25
1
NIL
HORIZONTAL

PLOT
442
238
643
388
farms over time
time
number of farms
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot count patches with [ farm? = true ]"

SLIDER
233
391
406
424
number-of-plants
number-of-plants
1
50
10.0
1
1
NIL
HORIZONTAL

TEXTBOX
244
11
394
29
PalmScape
11
0.0
1

TEXTBOX
242
32
392
50
---Farms---
11
0.0
1

TEXTBOX
235
180
385
198
---Trucks---
11
0.0
1

TEXTBOX
240
367
390
385
---Plants---
11
0.0
1

BUTTON
1918
114
2018
147
NIL
save-recording
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
1920
39
2018
72
NIL
start-recorder
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
1920
76
2018
110
NIL
reset-recorder
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
238
92
417
125
degradation-rate
degradation-rate
0
0.1
0.0
0.01
1
NIL
HORIZONTAL

CHOOSER
1713
42
1851
87
rest-quadrant
rest-quadrant
"none" "top right" "top left" "bottom right" "bottom left"
0

SLIDER
232
478
404
511
optimal-proportion
optimal-proportion
0
1
0.95
0.05
1
NIL
HORIZONTAL

SLIDER
235
134
414
167
regeneration-rate
regeneration-rate
0
0.01
0.0
0.001
1
NIL
HORIZONTAL

SLIDER
231
435
428
468
max-plant-capacity
max-plant-capacity
0
100000000
1.0E8
100
1
NIL
HORIZONTAL

BUTTON
231
323
367
356
eliminate-30-trucks
ask n-of 30 turtles with [ distanceTurtle? = false ] [ die ]
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

PLOT
439
61
639
211
growth rate over time
NIL
NIL
0.0
10.0
0.0
0.02
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot [ growthFactor ] of one-of patches with [ contract? = true ]"

SLIDER
237
531
426
564
farm-maintenance-cost
farm-maintenance-cost
0
0.01
0.001
0.001
1
NIL
HORIZONTAL

SLIDER
433
483
605
516
max-truck-capacity
max-truck-capacity
0
400
400.0
5
1
NIL
HORIZONTAL

@#$#@#$#@
## WHAT IS IT?

(a general understanding of what the model is trying to show or explain)

## HOW IT WORKS

(what rules the agents use to create the overall behavior of the model)

## HOW TO USE IT

(how to use the model, including a description of each of the items in the Interface tab)

## THINGS TO NOTICE

(suggested things for the user to notice while running the model)

## THINGS TO TRY

(suggested things for the user to try to do (move sliders, switches, etc.) with the model)

## EXTENDING THE MODEL

(suggested things to add or change in the Code tab to make the model more complicated, detailed, accurate, etc.)

## NETLOGO FEATURES

(interesting or unusual features of NetLogo that the model uses, particularly in the Code tab; or where workarounds were needed for missing features)

## RELATED MODELS

(models in the NetLogo Models Library and elsewhere which are of related interest)

## CREDITS AND REFERENCES

(a reference to the model's URL on the web if it has one, as well as any other necessary credits, citations, and links)
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.0
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
