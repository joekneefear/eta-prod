#
# FSC Perl STDF Libraries
#
# Confidential Property of Fairchild Semiconductor Corperation
# (c) Copyright Fairchild Semiconductor Corperation, 1999
# All rights reserved
#
# MODIFICATION HISTORY:
#
# DATE       WHO             DESCRIPTION
# __________ ______________  __________________________________________________
# 01-03-2001 Steve Frampton  Original.  Contact Information:
#                            (207) 273-3364
#                            sframpto@fairchildsemi.com,
#                            sframpto@midcoast.com
# 03-28-2001 Steve Frampton  Changed TEST_FLG to '0000010' per Andrew
# 04-09-2010 Scott Boothby   Added support for site-specific bin and test records.
#
# Copied from stdfPL_202.spec and downgraded to 1.4 stdf specifcation
# based on old 1.4 hard copy documentation from NSC.
#
# It is noted that a number of records are missing from the 1.4 standard.
# Comments have been added to indicate which are missing.
#
# STDF V3+ specification file read by stdf_gen to generate stdf code
# and data structures.
#
# This file was created for documentation purposes only.  It has not been
# tested.
#
# The WMR record in STDFPL.pl is specific to STDF+ 202 and above.
# STDFPL.pl may be used for a performance enhancements, so long
# as WMR support is not needed, otherwise, include only the gdrPL.pl
#
# example: ?
#
# 
# {
# package out ;   # use either namespace in or out
# use Carp ;
# if ( !eval(&::generate_all('stdfPL_104.spec')))  # generate code and evaluate
#   { confess $@ ; }      # if it failed to evaluate, print errors and exit.
# require 'gdrPL.pl' ;    # gdr routines
# }
#
# Be careful if editing this file.  It is very easy to break stdf_gen
# see stdf_gen -h, or stdf_gen.pm source code for details.
#
BGD	Bin Group Definition Record
REC_LEN	U*2	0
REC_TYP	U*1	1
REC_SUB	U*1	225
BIN_TYPE	C*1	''
PAD_BYTE	B*1	'00000000'
BIN_CNT	U*2	32768
BIN_NUM	${$bgd}{bin_cnt} x U*2	()
BIN_NAME	${$bgd}{bin_cnt} x C*n	()
GRP_NAME	C*n	''
GRP_TYPE	C*n	''

# BPD	Begin Pattern Definition Record
# BPS	Begin Program Section Record
# DTR	Datalog Text Record
#
EFDR	Enhanced Functional Test Description
REC_LEN	U*2	0
REC_TYP	U*1	10
REC_SUB	U*1	225
TEST_NUM	U*4	0
DESC_FLG	B*1	'00000000'
OPT_FLAG	B*1	'00000000'
SBIN_NUM	U*2	32768
HBIN_NUM	U*2	32768
VCC	R*4	-999
VEE	R*4	-999
FREQ	R*4	-999
TEMP	R*4	-273
TEST_NAM	C*n	''
SEQ_NAME	C*n	''
TCONDS	C*n	''
SBIN_NAM	C*n	''
HBIN_NAM	C*n	''
TEST_TXT	C*n	''

EFTR	Enhanced Functional Test Record
REC_LEN	U*2	0
REC_TYP	U*1	15
REC_SUB	U*1	200
TEST_NUM	U*4	0
HEAD_NUM	U*1	255
SITE_NUM	U*1	255
TEST_FLG	B*1	'00000010'
DESC_FLG	B*1	'00000000'
OPT_FLAG	B*1	'11111111'
TIME_SET	U*1	0
VECT_ADR	U*4	0
CYCL_CNT	U*4	0
REPT_CNT	U*2	0
PCP_ADDR	U*2	0
NUM_FAIL	U*4	0
PAT_NUM	U*2	32768
FAIL_PIN	B*n	''
VECT_DAT	B*n	''
DEV_DAT	B*n	''
RPIN_MAP	B*n	''
TEST_NAM	C*n	''
SEQ_NAM	C*n	''
TEST_TXT	C*n	''
PAT_NAME	C*n	''

EMIR	Enhanced Master Information Record
REC_LEN	U*2	0
REC_TYP	U*1	1
REC_SUB	U*1	200
CPU_TYPE	U*1	1
STDF_VER	U*1	104
MODE_COD	C*1	0
STAT_NUM	U*1	255
TEST_COD	C*3	'   '
RTST_COD	C*1	' '
PROT_COD	C*1	' '
CMOD_COD	C*1	' '
SETUP_T	U*4	0
START_T	U*4	0
TEMP	R*4	-273
SSUM_CNT	I*4	0
SSWB_CNT	I*4	0
SHWB_CNT	I*4	0
SSYN_CNT	I*4	0
SHIS_CNT	I*4	0
WSUM_CNT	I*4	0
WSWB_CNT	I*4	0
WHWB_CNT	I*4	0
WSYN_CNT	I*4	0
WHIS_CNT	I*4	0
PSUM_CNT	I*4	0
PRES_CNT	I*4	0
FRES_CNT	I*4	0
PSYN_CNT	I*4	0
PHIS_CNT	I*4	0
LOT_ID	C*n	''
PART_TYP	C*n	''
JOB_NAM	C*n	''
OPER_NAM	C*n	''
NODE_NAM	C*n	''
TSTR_TYP	C*n	''
EXEC_TYP	C*n	''
SUPR_NAM	C*n	''
HAND_ID	C*n	''
SBLOT_ID	C*n	''
JOB_REV	C*n	''
PROC_ID	C*n	''
PRB_CARD	C*n	''
OPER_ID	C*n	''
SPEC_NAM	C*n	''
SPEC_REV	C*n	''
LOAD_BRD	C*n	''
DEVICE	C*n	''
LOT_STRT	C*n	''
LOT_TYPE	C*n	''
DES_REV	C*n	''
FAMILY	C*n	''
GROUP	C*n	''
INT_LEV	C*n	''
PKG_ID	C*n	''
PKG_TYPE	C*n	''
CUSTOMER	C*n	''
DRAWING	C*n	''
FACILITY	C*n	''

# EPD Record	End Pattern Definition Record
#
EPDR	Enhanced Parametric Test Description Record
REC_LEN	U*2	0
REC_TYP	U*1	10
REC_SUB	U*1	200
TEST_NUM	U*4	0
DESC_FLG	B*1	'00000000'
OPT_FLG	B*1	'00011111'
RES_SCAL	I*1	0
UNITS	C*7	'       '
RES_LDIG	U*1	0
RES_RDIG	U*1	0
LLM_SCAL	I*1	0
HLM_SCAL	I*1	0
LLM_LDIG	U*1	0
LLM_RDIG	U*1	0
HLM_LDIG	U*1	0
HLM_RDIG	U*1	0
LO_LIMIT	R*4	-$::FLT_MAX
HI_LIMIT	R*4	$::FLT_MAX
LO_CENSR	R*4	-$::FLT_MAX
HI_CENSR	R*4	$::FLT_MAX
PIN_1	I*2	-1
PIN_2	I*2	-1
PIN_3	I*2	-1
SBIN_NUM	U*2	32768
HBIN_NUM	U*2	32768
VCC	R*4	-999
VEE	R*4	-999
TEMP	R*4	-273
FREQ	R*4	-999
PARMTYP	C*1	' '
TEST_NAM	C*n	''
SEQ_NAME	C*n	''
TCONDS	C*n	''
SBIN_NAM	C*n	''
HBIN_NAM	C*n	''
TEST_TXT	C*n	''

EPRR	Enhanced Part Results Record
REC_LEN	U*2	0
REC_TYP	U*1	5
REC_SUB	U*1	200
HEAD_NUM	U*1	255
SITE_NUM	U*1	255
NUM_TEST	U*2	0
HARD_BIN	U*2	65535
SOFT_BIN	U*2	65535
PART_FLG	B*1	'00000000'
RTST_FLG	B*1	'00000000'
X_COORD	I*2	-32768
Y_COORD	I*2	-32768
HBIN_NAM	C*n	''
SBIN_NAM	C*n	''
PART_ID	C*n	''
PART_TXT	C*n	''
PART_FIX	C*n	''

# EPS	End Program Section Record
#
EWCR	Enhanced Wafer Configuration Record
REC_LEN	U*2	0
REC_TYP	U*1	2
REC_SUB	U*1	210
WAFR_SIZ	R*4	0
DIE_HT	R*4	0
DIE_WID	R*4	0
WF_UNITS	U*1	0
WF_FLAT	C*1	' '
CENTER_X	I*2	-32768
CENTER_Y	I*2	-32768
POS_X	C*1	' '
POS_Y	C*1	' '
START_X	I*2	-32768
START_Y	I*2	-32768
ROW_CNT	I*2	0
COL_CNT	I*2	0
ORIGIN	I*1	-1
PRAXIS	I*1	-1
REFPT1_X	I*2	-32768
REFPT1_Y	I*2	-32768
REFPT2_X	I*2	-32768
REFPT2_Y	I*2	-32768
REFPT3_X	I*2	-32768
REFPT3_Y	I*2	-32768
REFPT4_X	I*2	-32768
REFPT4_Y	I*2	-32768

FAR	File Attributes Record
REC_LEN	U*2	0
REC_TYP	U*1	0
REC_SUB	U*1	10
CPU_TYPE	U*1	1
STDF_VER	U*1	104

GDR	Generic Data Record
REC_LEN	U*2	0
REC_TYP	U*1	50
REC_SUB	U*1	10
FLD_CNT	U*2	0
# V*n is only implemented within the gdr pack and unpack
GEN_DATA	V*n	[]

HBR	Hardware Bin Record
REC_LEN	U*2	0
REC_TYP	U*1	1
REC_SUB	U*1	40
HBIN_NUM	U*2	0
HBIN_CNT	U*4	0
HBIN_NAM	C*n	''

LTR	Lot Traceability Record
REC_LEN	U*2	0
REC_TYP	U*1	1
REC_SUB	U*1	205
LOT_ID	C*n	''
LOT_STRT	C*n	''
PLANT	C*n	''

MRR	Master Results Record
REC_LEN	U*2	0
REC_TYP	U*1	1
REC_SUB	U*1	20
FINISH_T	U*4	0
PART_CNT	U*4	0
RTST_CNT	I*4	-1
ABRT_CNT	I*4	-1
GOOD_CNT	I*4	-1
FUNC_CNT	I*4	-1
DISP_COD	C*1	' '
USR_DESC	C*n	''
EXC_DESC	C*n	''

# PAT	Pattern Definition Record
#
# PDDR	Parametric Test Delta Description Record
#
PIR	Part Information Record
REC_LEN	U*2	0
REC_TYP	U*1	5
REC_SUB	U*1	10
HEAD_NUM	U*1	255
SITE_NUM	U*1	255
X_COORD	I*2	-32768
Y_COORD	I*2	-32768
PART_ID	C*n	''

# PMR	Pin Map Record
#
# PTGH	Part Test Group Histogram Record
#
# PTGS	Part Test Group Synopsis Record
#
PTR	Parametric Test Result Record
REC_LEN	U*2	0
REC_TYP	U*1	15
REC_SUB	U*1	10
TEST_NUM	U*4	0
HEAD_NUM	U*1	255
SITE_NUM	U*1	255
TEST_FLG	B*1	'00000010'
PARM_FLG	B*1	'00000000'
RESULT	R*4	0
OPT_FLAG	B*1	'11111111'
RES_SCAL	I*1	0
RES_LDIG	U*1	0
RES_RDIG	U*1	0
DESC_FLG	B*1	'00000000'
UNITS	C*7	'       '
LLM_SCAL	I*1	0
HLM_SCAL	I*1	0
LLM_LDIG	U*1	0
LLM_RDIG	U*1	0
HLM_LDIG	U*1	0
HLM_RDIG	U*1	0
LO_LIMIT	R*4	-$::FLT_MAX
HI_LIMIT	R*4	$::FLT_MAX
TEST_NAM	C*n	''
SEQ_NAME	C*n	''
TEST_TXT	C*n	''

# RTR	Data Fields
#
SBR	Software Bin Record
REC_LEN	U*2	0
REC_TYP	U*1	1
REC_SUB	U*1	50
SBIN_NUM	U*2	0
SBIN_CNT	U*4	0
SBIN_NAM	C*n	''

SCR	Site-Specific Part Count Record
REC_LEN	U*2	0
REC_TYP	U*1	25
REC_SUB	U*1	40
HEAD_NUM	U*1	0
SITE_NUM	U*1	0
PART_CNT	U*4	0
RTST_CNT	I*4	-1
ABRT_CNT	I*4	-1
GOOD_CNT	I*4	-1
FUNC_CNT	I*4	-1
FINISH_T	U*4	0

SHB	Site-Specific Hardware Bin Record
REC_LEN	U*2	0
REC_TYP	U*1	25
REC_SUB	U*1	10
HEAD_NUM	U*1	0
SITE_NUM	U*1	0
HBIN_NUM	U*2	0
HBIN_CNT	U*4	0
HBIN_NAM	C*n	''

SSB	Site-Specific Software Bin Record
REC_LEN	U*2	0
REC_TYP	U*1	25
REC_SUB	U*1	20
HEAD_NUM	U*1	0
SITE_NUM	U*1	0
SBIN_NUM	U*2	0
SBIN_CNT	U*4	0
SBIN_NAM	C*n	''

STS	Site-Specific Synopsis Record
REC_LEN	U*2	0
REC_TYP	U*1	25
REC_SUB	U*1	30
HEAD_NUM	U*1	0
SITE_NUM	U*1	0
TEST_NUM	U*4	0
EXEC_CNT	I*4	-1
FAIL_CNT	I*4	-1
ALRM_CNT	I*4	-1
OPT_FLAG	B*1	'00000000'
PAD_BYTE	B*1	'00000000'
TEST_MIN	R*4	0
TEST_MAX	R*4	0
TST_MEAN	R*4	0
TST_SDEV	R*4	0
TST_SUMS	R*4	0
TST_SQRS	R*4	0
TEST_NAM	C*n	''
SEQ_NAME	C*n	''
TEST_LBL	C*n	''

TGD	Test Group Record
REC_LEN	U*2	0
REC_TYP	U*1	1
REC_SUB	U*1	220
TEST_CNT	U*2	0
TEST_NUM	${$tgd}{test_cnt} x U*4	()
GRP_NAME	C*n	''

# TGH	Test Group Historgram Record
#
TGS	Test Group Synopsis Record
REC_LEN	U*2	0
REC_TYP	U*1	200
REC_SUB	U*1	10
EXEC_CNT	I*4	-1
FAIL_CNT	I*4	-1
ALRM_CNT	I*4	-1
OPT_FLAG	B*1	'00001111'
PAD_BYTE	B*1	'00000000'
TEST_MIN	R*4	0
TEST_MAX	R*4	0
TST_MEAN	R*4	0
TST_SDEV	R*4	0
TST_SUMS	R*4	0
TST_SQRS	R*4	0
GRP_NAME	C*n	''

THR	Test Histogram Record
REC_LEN	U*2	0
REC_TYP	U*1	10
REC_SUB	U*1	205
TEST_NUM	U*4	0
OPT_FLAG	B*1	'00111111'
PAD_BYTE	B*1	'00000000'
PERC_03	R*4	0
PERC_10	R*4	0
PERC_20	R*4	0
PERC_50	R*4	0
PERC_80	R*4	0
PERC_90	R*4	0
PERC_97	R*4	0
TEST_NAM	C*n	''
SEQ_NAME	C*n	''

TSR	Test Synopsis Record
REC_LEN	U*2	0
REC_TYP	U*1	10
REC_SUB	U*1	30
TEST_NUM	U*4	0
EXEC_CNT	I*4	-1
FAIL_CNT	I*4	-1
ALRM_CNT	I*4	-1
OPT_FLAG	B*1	'00111111'
PAD_BYTE	B*1	'00000000'
TEST_MIN	R*4	0
TEST_MAX	R*4	0
TST_MEAN	R*4	0
TST_SDEV	R*4	0
TST_SUMS	R*4	0
TST_SQRS	R*4	0
TEST_NAM	C*n	''
SEQ_NAME	C*n	''

WHBR	Wafer Hardware Bin Record
REC_LEN	U*2	0
REC_TYP	U*1	2
REC_SUB	U*1	200
HBIN_NUM	U*2	32768
HBIN_CNT	U*4	0
HBIN_NAM	C*n	''

WIR	Wafer Information Record
REC_LEN	U*2	0
REC_TYP	U*1	2
REC_SUB	U*1	10
HEAD_NUM	U*1	255
PAD_BYTE	B*1	'00000000'
START_T	U*4	0
WAFER_ID	C*n	''

# Note that this represents the STDF V 104-201 WMR Record
# This is implemented differently than the 202 and above
# WMR Record
WMR	Wafer Map Record
REC_LEN	U*2	0
REC_TYP	U*1	105
REC_SUB	U*1	200
DIE_CNT	I*2	-32768
DIE_BIN	${$wmr}{die_cnt} x U*1	()

WRR	Wafer Results Record
REC_LEN	U*2	0
REC_TYP	U*1	2
REC_SUB	U*1	20
FINISH_T	U*4	0
HEAD_NUM	U*1	255
PAD_BYTE	B*1	'00000000'
PART_CNT	U*4	0
RTST_CNT	I*4	-1
ABRT_CNT	I*4	-1
GOOD_CNT	I*4	-1
FUNC_CNT	I*4	-1
WAFER_ID	C*n	''
HAND_ID	C*n	''
PRB_CARD	C*n	''
USR_DESC	C*n	''
EXC_DESC	C*n	''

WSBR	Wafer Software Bin Record
REC_LEN	U*2	0
REC_TYP	U*1	2
REC_SUB	U*1	205
SBIN_NUM	U*2	32768
SBIN_CNT	U*4	0
SBIN_NAM	C*n	''

# WTGH	Wafer Test Group Histogram Record
#
# WTGS	Wafer Test Group Synopsis Record
#
WTHR	Wafer Test Histogram Record
REC_LEN	U*2	0
REC_TYP	U*1	10
REC_SUB	U*1	215
TEST_NUM	U*4	0
OPT_FLAG	B*1	'00111111'
PAD_BYTE	B*1	'00000000'
PERC_03	R*4	0
PERC_10	R*4	0
PERC_20	R*4	0
PERC_50	R*4	0
PERC_80	R*4	0
PERC_90	R*4	0
PERC_97	R*4	0
TEST_NAM	C*n	''
SEQ_NAME	C*n	''

# WTR	Wafer Traceability Record
#
WTSR	Wafer Test Synopsis Record
REC_LEN	U*2	0
REC_TYP	U*1	10
REC_SUB	U*1	210
TEST_NUM	U*4	0
EXEC_CNT	I*4	-1
FAIL_CNT	I*4	-1
ALRM_CNT	I*4	-1
OPT_FLAG	B*1	'01111111'
PAD_BYTE	B*1	'00000000'
TEST_MIN	R*4	0
TEST_MAX	R*4	0
TST_MEAN	R*4	0
TST_SDEV	R*4	0
TST_SUMS	R*4	0
TST_SQRS	R*4	0
TEST_NAM	C*n	''
SEQ_NAME	C*n	''
