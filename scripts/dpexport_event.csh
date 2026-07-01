#!/bin/csh 
#
# Delete a program from a specified schema
#
# MODIFICATION HISTORY
#
# WHEN      WHO WHAT
# --------- --- ------------------------------------------
# 11-Jun-15 SAB Initial version.
#
set isError = 0

if ($#argv < 1  || $#argv > 3) then
   set isError = 1
endif

if ( $isError ) then
   echo "USAGE: $0:t program-match-string schema-name [-test]"
   echo " " 

   exit(1)
endif

set program_match_str = "$1"
set schema_name = $2
if ( $#argv == 3 ) then
   set test = 1
else
   set test = 0
endif

set tmpScript = /tmp/$0:t.$$.sql

cat << eof  > ${tmpScript}
set HEADING ON;
set LINESIZE 2048;
set SERVEROUTPUT ON SIZE 1000000;

DECLARE RES_DROP_STR VARCHAR2(128);
        RES_TRUNC_STR VARCHAR2(128);
	DEF_DROP_STR VARCHAR2(128);
	DEF_TRUNC_STR VARCHAR2(128);
	DELETE_STR    VARCHAR2(128);

BEGIN
   FOR PG_REC IN (SELECT PG_KEY FROM ${schema_name}.PROGRAM WHERE PPID LIKE '$program_match_str')
   LOOP
      RES_TRUNC_STR:= 'TRUNCATE TABLE ${schema_name}.RES'||PG_REC.PG_KEY;
      RES_DROP_STR := 'DROP TABLE ${schema_name}.RES'||PG_REC.PG_KEY;
      DEF_TRUNC_STR:= 'TRUNCATE TABLE ${schema_name}.DEF'||PG_REC.PG_KEY;
      DEF_DROP_STR := 'DROP TABLE ${schema_name}.DEF'||PG_REC.PG_KEY;

eof
if ( $test == 1) then
cat << eof >> ${tmpScript}

      DBMS_OUTPUT.put_line(RES_TRUNC_STR);
      DBMS_OUTPUT.put_line(RES_DROP_STR);
      DBMS_OUTPUT.put_line(DEF_TRUNC_STR);
      DBMS_OUTPUT.put_line(DEF_DROP_STR);

eof
else
cat << eof >> ${tmpScript}

      BEGIN
      EXECUTE IMMEDIATE RES_TRUNC_STR;
      EXECUTE IMMEDIATE RES_DROP_STR;
      DBMS_OUTPUT.PUT_LINE('RES TABLES DROPPED');
      EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('RES TABLES NOT DROPPED');
      END;
      BEGIN
      EXECUTE IMMEDIATE DEF_TRUNC_STR;
      EXECUTE IMMEDIATE DEF_DROP_STR;
      DBMS_OUTPUT.PUT_LINE('DEF TABLES DROPPED');
      EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('DEF TABLES NOT DROPPED');
      END;
eof
endif
foreach table ( OP_LOG PROG2PROD SUM_COND PROG2STAGE PROGRAM_TABLES DP_ROLLBACK_STMTS CONDITION PROG2CUST PROG2LOT ARCHIVE_LOG \
PROG2FAM PROG_DATATYPE PROG2EQUIP PROG2TECH PAR2PARGRP EVENT_CONFIG PROG_REV TAG_LOG SITE2DIE EVENT_LOG \
PROG2SRCLOT META_IDX_DEF OP_META PROG2STEP LW_CLASS_LOG PROG2PROC PROG2PKG PROGRAM)
   set stmnt = "       DELETE_STR := 'DELETE FROM ${schema_name}.${table} WHERE PG_KEY = '||PG_REC.PG_KEY;"
   echo $stmnt >> ${tmpScript}
   if ( $test == 1 ) then
      echo "DBMS_OUTPUT.put_line(DELETE_STR);" >> ${tmpScript}
   else
cat << eof >> ${tmpScript}
BEGIN
EXECUTE IMMEDIATE DELETE_STR;
EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE(DELETE_STR||' EXECUTION FAILED');
END;
eof
   endif
end
cat << eof >> ${tmpScript}
   END LOOP;
END;
/
QUIT;

eof

sqlplus -s / @${tmpScript} 
#cat $tmpScript

/bin/rm ${tmpScript}

