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
# 11-02-1999 Steve Frampton  Original.  Contact Information:
#                            (207) 273-3364
#                            sframpto@fairchildsemi.com,
#                            sframpto@midcoast.com
# 02-11-2000 Steve Frampton  Enabled Array Fields
#                            Gave PCR.PART_CNT a default
# 05-18-2000 Steve Frampton  Changed all HI_LIMIT, LO_LIMIT to
#                            $FLT_MAX, -$FLT_MAX
# 03-28-2001 Steve Frampton  Changed TEST_FLG to '0000010' per Andrew
# 04-22-2006 Steve Frampton  Changed any occurances of () to [], representing
# the initialization value of arrays.  Also changed array counts to be 0...Exception: wmr record was not changed.
#
#
# STDF V4 specification file read by stdf_gen to generate stdf code
# and data structures.
# 
# Based on Teradyne STDF V4 Standard
#
# Be careful if editing this file.  It is very easy to break stdf_gen
# see stdf_gen -h, or stdf_gen.pm source code for details.
#
FAR	File Attributes Record
REC_LEN	U*2	0
REC_TYP	U*1	0
REC_SUB	U*1	10
CPU_TYPE	U*1	1
STDF_VER	U*1	4

ATR	Audit Trail Record
REC_LEN	U*2	0
REC_TYP	U*1	0
REC_SUB	U*1	20
MOD_TIM	U*4	0
CMD_LINE	C*n	''

MIR	Master Information Record
REC_LEN	U*2	0
REC_TYP	U*1	1
REC_SUB	U*1	10
SETUP_T	U*4	0
START_T	U*4	0
STAT_NUM	U*1	0
MODE_COD	C*1	' '
RTST_COD	C*1	' '
PROT_COD	C*1	' '
BURN_TIM	U*2	65535
CMOD_COD	C*1	' '
LOT_ID	C*n	''
PART_TYP	C*n	''
NODE_NAM	C*n	''
TSTR_TYP	C*n	''
JOB_NAM	C*n	''
JOB_REV	C*n	''
SBLOT_ID	C*n	''
OPER_NAM	C*n	''
EXEC_TYP	C*n	''
EXEC_VER	C*n	''
TEST_COD	C*n	''
TST_TEMP	C*n	''
USER_TXT	C*n	''
AUX_FILE	C*n	''
PKG_TYP	C*n	''
FAMILY_ID	C*n	''
DATE_COD	C*n	''
FACIL_ID	C*n	''
FLOOR_ID	C*n	''
PROC_ID	C*n	''
OPER_FRQ	C*n	''
SPEC_NAM	C*n	''
SPEC_VER	C*n	''
FLOW_ID	C*n	''
SETUP_ID	C*n	''
DSGN_REV	C*n	''
ENG_ID	C*n	''
ROM_COD	C*n	''
SERL_NUM	C*n	''
SUPR_NAM	C*n	''


MRR	Master Results Record
REC_LEN	U*2	0
REC_TYP	U*1	1
REC_SUB	U*1	20
FINISH_T	U*4	0
DISP_COD	C*1	' '
USER_DESC	C*n	''
EXC_DESC	C*n	''


PCR	Part Count Record
REC_LEN	U*2	0
REC_TYP	U*1	1
REC_SUB	U*1	30
HEAD_NUM	U*1	255
SITE_NUM	U*1	0
# Specification actually does not have a default for PART_CNT
PART_CNT	U*4	4294967295
RTST_CNT	U*4	4294967295
ABRT_CNT	U*4	4294967295
GOOD_CNT	U*4	4294967295
FUNC_CNT	U*4	4294967295

HBR	Hardware Bin Record
REC_LEN	U*2	0
REC_TYP	U*1	1
REC_SUB	U*1	40
HEAD_NUM	U*1	255
SITE_NUM	U*1	0
HBIN_NUM	U*2	0
HBIN_CNT	U*4	0
HBIN_PF	C*1	' '
HBIN_NAM	C*n	''

SBR	Software Bin Record
REC_LEN	U*2	0
REC_TYP	U*1	1
REC_SUB	U*1	50
HEAD_NUM	U*1	255
SITE_NUM	U*1	0
SBIN_NUM	U*2	0
SBIN_CNT	U*4	0
SBIN_PF	C*1	' '
SBIN_NAM	C*n	''

PMR	Pin Map	Record
REC_LEN	U*2	0
REC_TYP	U*1	1
REC_SUB	U*1	60
PMR_INDX	U*2	0
CHAN_TYP	U*2	0
CHAN_NAM	C*n	''
PHY_NAM	C*n	''
LOG_NAM	C*n	''
HEAD_NUM	U*1	1
SITE_NUM	U*1	1

PGR	Pin Group Record
REC_LEN	U*2	0
REC_TYP	U*1	1
REC_SUB	U*1	62
GRP_INDX	U*2	0
GRP_NAM	C*n	''
INDX_CNT	U*2	0
PMR_INDX	${$pgr}{indx_cnt} x U*2	[]

PLR	Pin List Record
REC_LEN	U*2	0
REC_TYP	U*1	1
REC_SUB	U*1	63
GRP_CNT	U*2	0
GRP_INDX	${$plr}{grp_cnt} x U*2	[]
GRP_MODE	${$plr}{grp_cnt} x U*2	[]
GRP_RADX	${$plr}{grp_cnt} x U*1	[]
PGM_CHAR	${$plr}{grp_cnt} x C*n	[]
RTN_CHAR	${$plr}{grp_cnt} x C*n	[]
PGM_CHAL	${$plr}{grp_cnt} x C*n	[]
RTN_CHAL	${$plr}{grp_cnt} x C*n	[]

RDR	Retest Data Record
REC_LEN	U*2	0
REC_TYP	U*1	1
REC_SUB	U*1	70
NUM_BINS	U*2	0
RTST_BIN	${$rdr}{num_bins} x U*2	[]

SDR	Site Description Record
REC_LEN	U*2	0
REC_TYP	U*1	1
REC_SUB	U*1	80
HEAD_NUM	U*1	0
SITE_GRP	U*1	0
SITE_CNT	U*1	0
SITE_NUM	${$sdr}{site_cnt} x U*1	[]
HAND_TYP	C*n	''
HAND_ID	C*n	''
CARD_TYP	C*n	''
CARD_ID	C*n	''
LOAD_TYP	C*n	''
LOAD_ID	C*n	''
DIB_TYP	C*n	''
DIB_ID	C*n	''
CABL_TYP	C*n	''
CABL_ID	C*n	''
CONT_TYP	C*n	''
CONT_ID	C*n	''
LASR_TYP	C*n	''
LASR_ID	C*n	''
EXTR_TYP	C*n	''
EXTR_ID	C*n	''

WIR	Wafer Information Record
REC_LEN	U*2	0
REC_TYP	U*1	2
REC_SUB	U*1	10
HEAD_NUM	U*1	0
SITE_GRP	U*1	255
START_T	U*4	0
WAFER_ID	C*n	''

WRR	Wafer	Results	Record
REC_LEN	U*2	0
REC_TYP	U*1	2
REC_SUB	U*1	20
HEAD_NUM	U*1	0
SITE_GRP	U*1	255
FINISH_T	U*4	0
PART_CNT	U*4	0
RTST_CNT	U*4	4294967295
ABRT_CNT	U*4	4294967295
GOOD_CNT	U*4	4294967295
FUNC_CNT	U*4	4294967295
WAFER_ID	C*n	''
FABWF_ID	C*n	''
FRAME_ID	C*n	''
MASK_ID	C*n	''
USR_DESC	C*n	''
EXC_DESC	C*n	''

WCR	Wafer Configuration Record
REC_LEN	U*2	0
REC_TYP	U*1	2
REC_SUB	U*1	30
WAFR_SIZ	R*4	0
DIE_HT	R*4	0
DIE_WID	R*4	0
WF_UNITS	U*1	0
WF_FLAT	C*1	' '
CENTER_X	I*2	-32768
CENTER_Y	I*2	-32768
POS_X	C*1	' '
POS_Y	C*1	' '

PIR	Part Information Record
REC_LEN	U*2	0
REC_TYP	U*1	5
REC_SUB	U*1	10
HEAD_NUM	U*1	0
SITE_NUM	U*1	0

PRR	Part Results Record
REC_LEN	U*2	0
REC_TYP	U*1	5
REC_SUB	U*1	20
HEAD_NUM	U*1	0
SITE_NUM	U*1	0
PART_FLG	B*1	'00000000'
NUM_TEST	U*2	0
HARD_BIN	U*2	0
SOFT_BIN	U*2	0
X_COORD	I*2	0
Y_COORD	I*2	0
TEST_T	U*4	0
PART_ID	C*n	''
PART_TXT	C*n	''
PART_FIX	B*n	''

TSR	Test Synopsis Record
REC_LEN	U*2	0
REC_TYP	U*1	10
REC_SUB	U*1	30
HEAD_NUM	U*1	255
SITE_NUM	U*1	0
TEST_TYP	C*1	' '
TEST_NUM	U*4	0
EXEC_CNT	U*4	4294967295
FAIL_CNT	U*4	4294967295
ALRM_CNT	U*4	4294967295
TEST_NAM	C*n	''
SEQ_NAME	C*n	''
TEST_LBL	C*n	''
OPT_FLAG	B*1	'00000000'
TEST_TIM	R*4	0
TEST_MIN	R*4	0
TEST_MAX	R*4	0
TST_SUMS	R*4	0
TST_SQRS	R*4	0

PTR	Parametric Test Record
REC_LEN	U*2	0
REC_TYP	U*1	15
REC_SUB	U*1	10
TEST_NUM	U*4	0
HEAD_NUM	U*1	255
SITE_NUM	U*1	0
TEST_FLG	B*1	'00000010'
PARM_FLG	B*1	'00000000'
RESULT	R*4	0
TEST_TXT	C*n	''
ALARM_ID	C*n	''
OPT_FLAG	B*1	'11111111'
RES_SCAL	I*1	0
LLM_SCAL	I*1	0
HLM_SCAL	I*1	0
LO_LIMIT	R*4	-$::FLT_MAX
HI_LIMIT	R*4	$::FLT_MAX
UNITS	C*n	''
C_RESFMT	C*n	''
C_LLMFMT	C*n	''
C_HLMFMT	C*n	''
LO_SPEC	R*4	-$::FLT_MAX
HI_SPEC	R*4	$::FLT_MAX

MPR	Multiple-Result Parametric Record
REC_LEN	U*2	0
REC_TYP	U*1	15
REC_SUB	U*1	15
TEST_NUM	U*4	0
HEAD_NUM	U*1	255
SITE_NUM	U*1	0
TEST_FLG	B*1	'00000010'
PARM_FLG	B*1	'00000000'
RTN_ICNT	U*2	0
RSLT_CNT	U*2	0
RTN_STAT	${$mpr}{rtn_icnt} x N*1	[]
RTN_RSLT	${$mpr}{rslt_cnt} x R*4	[]
TEST_TXT	C*n	''
ALARM_ID	C*n	''
OPT_FLAG	B*1	'00000000'
RES_SCAL	I*1	0
LLM_SCAL	I*1	0
HLM_SCAL	I*1	0
LO_LIMIT	R*4	0
HI_LIMIT	R*4	0
START_IN	R*4	0
INCR_IN	R*4	0
RTN_INDX	${$mpr}{rtn_icnt} x U*2	[]
UNITS	C*n	''
UNITS_IN	C*n	''
C_RESFMT	C*n	''
C_LLMFMT	C*n	''
C_HLMFMT	C*n	''
LO_SPEC	R*4	0
HI_SPEC	R*4	0

FTR	Functional Test Record
REC_LEN	U*2	0
REC_TYP	U*1	15
REC_SUB	U*1	20
TEST_NUM	U*4	0
HEAD_NUM	U*1	255
SITE_NUM	U*1	0
TEST_FLG	B*1	'00000010'
OPT_FLAG	B*1	'11111111'
CYCL_CNT	U*4	0
REL_VADR	U*4	0
REPT_CNT	U*4	0
NUM_FAIL	U*4	0
XFAIL_AD	I*4	0
YFAIL_AD	I*4	0
VECT_OFF	I*2	0
RTN_ICNT	U*2	0
PGM_ICNT	U*2	0
RTN_INDX	${$ftr}{rtn_icnt} x U*2	[]
RTN_STAT	${$ftr}{rtn_icnt} x N*1	[]
PGM_INDX	${$ftr}{pgm_icnt} x U*2	[]
PGM_STAT	${$ftr}{pgm_icnt} x N*1	[]
FAIL_PIN	D*n	''
VECT_NAM	C*n	''
TIME_SET	C*n	''
OP_CODE	C*n	''
TEST_TXT	C*n	''
ALARM_ID	C*n	''
PROG_TXT	C*n	''
RSLT_TXT	C*n	''
PATG_NUM	U*1	255
SPIN_MAP	D*n	''

BPS	Begin Program Section Record
REC_LEN	U*2	0
REC_TYP	U*1	20
REC_SUB	U*1	10
SEQ_NAME	C*n	''

EPS	End Program Section Record
REC_LEN	U*2	0
REC_TYP	U*1	20
REC_SUB	U*1	20
# There needs to be something here for a record.
# This should cause pack to pack nothing, because it is undefined
# The field UNDEFINED is not in the STDF V4 Standard
UNDEFINED	C*n	undef


GDR	Generic Data Record
REC_LEN	U*2	0
REC_TYP	U*1	50
REC_SUB	U*1	10
FLD_CNT	U*2	0
# V*n is only implemented within the gdr pack and unpack
GEN_DATA	V*n	[]

DTR	Datalog Text Record
REC_LEN	U*2	0
REC_TYP	U*1	50
REC_SUB	U*1	30
TEXT_DAT	C*n	''

