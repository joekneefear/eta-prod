/*
** MODIFICATION HISTORY:
**
** Date        Who            Comment
** ----------- -------------- ------------------
** 25-Nov-2020 S. Boothby     Created.
*/
DECLARE v_col_exists NUMBER;
BEGIN
  SELECT COUNT(*) into v_col_exists FROM user_tab_cols WHERE column_name = 'GLOBAL_WAFER_ID' AND table_name = 'ON_SLICE';

  IF (v_col_exists = 0) THEN
     EXECUTE IMMEDIATE 'ALTER TABLE REFDB.ON_SLICE
     ADD 
     (
         "GLOBAL_WAFER_ID" VARCHAR2(32 BYTE),
         "SLICE_ORDER"     INTEGER
     )';
     EXECUTE IMMEDIATE 'UPDATE REFDB.ON_SLICE SET GLOBAL_WAFER_ID = SLICE WHERE GLOBAL_WAFER_ID IS NULL';
     EXECUTE IMMEDIATE 'COMMIT';
     EXECUTE IMMEDIATE 'CREATE INDEX "REFDB"."REFDB_ON_GLOBAL_WAFER_ID" ON "REFDB"."ON_SLICE" ("GLOBAL_WAFER_ID") TABLESPACE "DP_INDX"'; 
  ELSE
     DBMS_OUTPUT.PUT_LINE('Columns aready exist');
  END IF;
END;
/
