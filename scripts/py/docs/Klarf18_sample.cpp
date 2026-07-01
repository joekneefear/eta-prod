Record FileRecord  "1.8"
{
  Record LotRecord "IT56261.1J"
  {
    Record WaferRecord "W_11"
    {
      Field DieOrigin 2 {0, 0}
      Field OrientationInstructions 1 {""}
      Field ProcessEquipmentState 7 {"NONE", "", "", "", "", "", ""}
      Field SampleCenterLocation 2 {100000000, 100000000}
      Field SlotNumber 1 {11}

      List DefectList
      {
        Columns 46 { int32 DEFECTID,  int32 XREL,  int32 YREL,  int32 XINDEX,  int32 YINDEX,  
        int32 XSIZE,  int32 YSIZE,  float DEFECTAREA,  int32 DSIZE,  int32 CLASSNUMBER,  
        int32 TEST,  int32 CLUSTERNUMBER,  int32 ROUGHBINNUMBER,  int32 FINEBINNUMBER,  int32 REVIEWSAMPLE,  
        int32 SAMPLEBINNUMBER,  float CONTRAST,  int32 CHANNELID,  int32 MANSEMCLASS,  int32 AUTOONSEMCLASS,  
        int32 MICROSIGCLASS,  int32 MACROSIGCLASS,  int32 ADDERFLAG,  int32 AUTOOFFSEMCLASS,  int32 AUTOOFFOPTADC,  
        int32 FACLASS,  int32 INTENSITY,  float KILLPROB,  int32 MACROSIGID,  int32 REGIONID,  
        int32 REPEATER,  int32 EVENTTYPE,  int32 EBRLINE,  ImageList IMAGEINFO,  
        int32 POLARITY,  float CRITICALAREA,  int32 MANOPTCLASS,  float PHI,  int32 DBCLASS,  
        int32 DBGROUP,  float DBCRITICALITYINDEX,  float CELLSIZE,  int32 CAREAREAGROUPCODE,  float PCI,  
        float LINECOMPLEXITY,  float DCIRANGE  }
        Data 5
        {
          1 103131000 118801000 0 0 1062000 1202000 1276520038400.0 1129830 
            0 1 0 200 0 0 0 0.0000 0 0 0 0 0 1 0 0 0 0 0.0000 0 0 0 0 0  N 
            0 0.0000 0 0.0 0 0 0.0000 0.000000 0 0.0000 0.0000 0.0000 ;
          2 95075000 57926000 0 0 0 0 0.0 200000000 0 1 0 200 0 0 0 0.0000 
            0 0 0 0 0 1 0 0 0 0 0.0000 0 0 0 0 0  N 0 0.0000 0 0.0 0 0 0.0000 
            0.000000 0 0.0000 0.0000 0.0000 ;
          3 187766000 70126000 0 0 0 0 0.0 288 0 1 0 0 0 0 0 0.0000 0 0 0 0 
            0 1 0 0 0 0 0.0000 0 0 0 0 0  N 0 0.0000 0 0.0 0 0 0.0000 0.000000 
            0 0.0000 0.0000 0.0000 ;
          4 96279000 195631000 0 0 0 0 0.0 167 0 1 0 0 0 0 0 0.0000 0 0 0 0 
            0 1 0 0 0 0 0.0000 0 0 0 0 0  N 0 0.0000 0 0.0 0 0 0.0000 0.000000 
            0 0.0000 0.0000 0.0000 ;
          5 5378000 82020000 0 0 0 0 0.0 163 0 1 0 0 0 0 0 0.0000 0 0 0 0 0 
            1 0 0 0 0 0.0000 0 0 0 0 0  N 0 0.0000 0 0.0 0 0 0.0000 0.000000 
            0 0.0000 0.0000 0.0000 ;
        }
      }
      Record TestRecord "1"
      {
        Field AreaPerTest 1 {2.8895900000e+16}
        Field InspectedAreaOrigin 2 {0, 0}
        Field InspectionTest 2 {1, "1" }

        List SampleTestPlanList
        {
          Columns 2 { int32 XINDEX, int32 YINDEX }
          Data 1
          {
            0 0 ;
          }
        }
      }
      Record SummaryRecord
      {

        List FullWaferSummaryList
        {
          Columns 1 { float INSPAREA  }
          Data 1
          {
            2.8895900000e+16   ;
          }
        }
        List TestSummaryList
        {
          Columns 11 { int32 TESTNO,  int32 NDEFECT,  float DEFDENSITY,  int32 NDIE,  int32 NDEFDIE,  
          float HAZEREGION,  float HAZEAVERAGE,  float HAZESTDDEV,  float HAZEMEDIAN,  float HAZEPEAK,  
          float AREAPERTEST  }
          Data 1
          {
            1  5  1.7300000414e-02  1  1  
              -1  -1  -1  -1  -1  2.8895900000e+16   ;
          }
        }
      }
    }
    Field DeviceID 1 {"W89XAXX"}
    Field DiePitch 2 {200000000, 200000000}
    Field FabID 1 {"ONSEMICZ2"}
    Field InspectionStationID 3 {"NONE", "SFSSP1", "DASP1C01"}
    Field OrientationMarkLocation 1 {0}
    Field RecipeID 3 {"W89XAXX", "12-08-2025", "04:40:00"}
    Field RecipeVersion 3 {"", "", ""}
    Field ResultTimestamp 2 {"12-08-2025", "04:41:19"}
    Field SampleOrientationMarkType 1 {"NOTCH"}
    Field SampleSize 2 {200000000, 0}
    Field SampleType 1 {"WAFER"}
    Field StepID 1 {"W89XAXX"}

    List ClassLookupList
    {
      Columns 3 { int32 CLASSNUMBER, string CLASSNAME, string CLASSCODE }
      Data 269
      {
         0 "UNCLASSIFIED" "";
         1 "UNDETERMINED" "";
         2 "NUISANCE" "";
         3 "PREVIOUS_LEVEL" "";
         4 "POINT_DEFECT" "";
         5 "SCRATCH" "";
         6 "DROP_ON_PARTICLE" "";
         7 "EMBEDD_PARTICLE" "";
         8 "FIBER" "";
         9 "EPI_SPIKE" "";
         10 "RESIDUAL_RESIST" "";
         11 "PHOTOETCH" "";
         12 "EMBEDD_ETCHBLOCK" "";
         13 "MISSING_TRENCH" "";
         14 "ETCH_POLYMER" "";
         15 "NOT_ETCHED_CONT" "";
         16 "RESIDUA_TRENCH" "";
         17 "MASKING_DEFECT" "";
         18 "LIQUIDE_CONTAMIN" "";
         19 "WATER_SPOT" "";
         20 "PITTING" "";
         21 "M2_DIAMOND" "";
         22 "BLUE_DOT_M1" "";
         23 "STRING_S" "";
         24 "CORROSION" "";
         25 "FLUORINE_DEFECT" "";
         26 "BPSG_DEF_IN_CONT" "";
         27 "HBR_DEF_TRENCH" "";
         28 "DEF_IN_TRENCH" "";
         29 "HOLE_IN_METAL" "";
         30 "TITAN_PARTICLES" "";
         31 "CRACK" "";
         32 "BLACK_DOT" "";
         33 "33" "";
         34 "34" "";
         35 "DEFECT_ON_OPEN_METAL" "";
         36 "36" "";
         37 "37" "";
         38 "38" "";
         39 "SEM_ANALYSIS" "";
         40 "MacroOverImg" "";
         41 "41" "";
         42 "42" "";
         43 "UNCLASS_ADC_W/O_IMG" "";
         44 "UNLABELED" "";
         45 "DOI" "";
         46 "REAL" "";
         47 "NUISANCEs" "";
         48 "48" "";
         49 "49" "";
         50 "DIE_SURFACE_DAMAGE" "";
         51 "51" "";
         52 "52" "";
         53 "53" "";
         54 "54" "";
         55 "DEF_SCAN_AREA" "";
         56 "DEF_ACTIVE_AREA" "";
         57 "DEF_SCAN_AREA(30um)" "";
         58 "58" "";
         59 "59" "";
         60 "VISUAL_KILLER_DEF" "";
         61 "61" "";
         62 "62" "";
         63 "63" "";
         64 "64" "";
         65 "65" "";
         66 "66" "";
         67 "67" "";
         68 "68" "";
         69 "69" "";
         70 "70" "";
         71 "71" "";
         72 "72" "";
         73 "73" "";
         74 "74" "";
         75 "75" "";
         76 "76" "";
         77 "77" "";
         78 "78" "";
         79 "79" "";
         80 "80" "";
         81 "81" "";
         82 "82" "";
         83 "83" "";
         84 "84" "";
         85 "85" "";
         86 "86" "";
         87 "87" "";
         88 "88" "";
         89 "89" "";
         90 "OVERLAY_OK" "";
         91 "OVERLAY_FAIL" "";
         92 "EDGE_CHIPPING_OK" "";
         93 "EDGE_CHIPPING_FAIL" "";
         94 "RETICLE_ ID_OK" "";
         95 "RETICLE_ ID_FAIL" "";
         96 "EBR_OK" "";
         97 "EBR_FAIL" "";
         98 "EBR_CENTER_OK" "";
         99 "EBR_CENTER_FAIL" "";
         100 "Scratch" "";
         101 "101" "";
         102 "102" "";
         103 "103" "";
         104 "104" "";
         105 "105" "";
         106 "106" "";
         107 "107" "";
         108 "108" "";
         109 "109" "";
         110 "TriangleCore" "";
         111 "Triangle" "";
         112 "112" "";
         113 "113" "";
         114 "114" "";
         115 "115" "";
         116 "116" "";
         117 "117" "";
         118 "118" "";
         119 "119" "";
         120 "120" "";
         121 "121" "";
         122 "122" "";
         123 "123" "";
         124 "124" "";
         125 "125" "";
         126 "126" "";
         127 "127" "";
         128 "128" "";
         129 "129" "";
         130 "SF" "";
         131 "131" "";
         132 "132" "";
         133 "133" "";
         134 "134" "";
         135 "135" "";
         136 "136" "";
         137 "137" "";
         138 "138" "";
         139 "139" "";
         140 "Downfall" "";
         141 "141" "";
         142 "142" "";
         143 "143" "";
         144 "144" "";
         145 "145" "";
         146 "146" "";
         147 "147" "";
         148 "148" "";
         149 "149" "";
         150 "CarrotCore" "";
         151 "Carrot" "";
         152 "152" "";
         153 "153" "";
         154 "154" "";
         155 "155" "";
         156 "156" "";
         157 "157" "";
         158 "158" "";
         159 "159" "";
         160 "ParticleTriangleCore" "";
         161 "ParticleTriangle" "";
         162 "162" "";
         163 "163" "";
         164 "164" "";
         165 "165" "";
         166 "166" "";
         167 "167" "";
         168 "168" "";
         169 "169" "";
         170 "PartialsS" "";
         171 "PartialsPL" "";
         172 "172" "";
         173 "173" "";
         174 "174" "";
         175 "175" "";
         176 "176" "";
         177 "177" "";
         178 "178" "";
         179 "179" "";
         180 "BPD" "";
         181 "181" "";
         182 "182" "";
         183 "183" "";
         184 "184" "";
         185 "185" "";
         186 "186" "";
         187 "187" "";
         188 "188" "";
         189 "189" "";
         190 "190" "";
         191 "191" "";
         192 "192" "";
         193 "193" "";
         194 "194" "";
         195 "195" "";
         196 "196" "";
         197 "197" "";
         198 "198" "";
         199 "199" "";
         200 "Particle" "";
         201 "201" "";
         202 "202" "";
         203 "203" "";
         204 "204" "";
         205 "205" "";
         206 "206" "";
         207 "207" "";
         208 "208" "";
         209 "209" "";
         210 "210" "";
         211 "211" "";
         212 "212" "";
         213 "213" "";
         214 "214" "";
         215 "215" "";
         216 "216" "";
         217 "217" "";
         218 "218" "";
         219 "219" "";
         220 "220" "";
         221 "221" "";
         222 "222" "";
         223 "223" "";
         224 "224" "";
         225 "225" "";
         226 "226" "";
         227 "227" "";
         228 "228" "";
         229 "229" "";
         230 "230" "";
         231 "231" "";
         232 "232" "";
         233 "233" "";
         234 "234" "";
         235 "235" "";
         236 "236" "";
         237 "237" "";
         238 "238" "";
         239 "239" "";
         240 "240" "";
         241 "241" "";
         242 "242" "";
         243 "243" "";
         244 "244" "";
         245 "245" "";
         246 "246" "";
         247 "247" "";
         248 "248" "";
         249 "249" "";
         250 "250" "";
         251 "251" "";
         252 "252" "";
         253 "253" "";
         254 "254" "";
         255 "255" "";
         256 "256" "";
         300 "Bar SF" "";
         450 "Misc Topo" "";
         500 "Etc." "";
         510 "Bump" "";
         520 "PitA" "";
         530 "PitB" "";
         540 "PitC" "";
         550 "Micropipe" "";
         600 "PL_White" "";
         610 "PL_Black" "";
         620 "InducedPL" "";
         999 "Unclassified" "";
      }
    }
  }
  Field FileTimestamp 2 {"12-08-2025", "04:57:03"}

}
EndOfFile;
