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
# 03-20-2000 Steve Frampton  $max_tp_len increased to 12 for edb schema rev
# 06-07-2000 Steve Frampton  Added $edb_seq_name_len, $edb_tconds_len,
#                            $edb_test_txt_len
#                            to support epdr
# 01-18-2001 Steve Frampton  Added fix_test_nam routine
# 01-18-2001 steve Frampton  Added fix_bin_nam routine
# 01-29-2001 steve Frampton  fix_test_nam and fix_bin_nam were reporting
#                            changes when '_' existed in input.
#                            No longer logs with '_'.
# 01-29-2001 steve Frampton  Moved some edb record length fields
#                            from sessed.pl (SLED).
# 28-Sep-12  Scott Boothby   Length changes:
#                             - lot to 25 from 11.              
#                             - parameter_name to 60 from 21.
#                             - bin_name to 60 from 21.
#                             - test_plan to 35 from 20.
#                             - probe_card and load_board to 25 from 8
#                             - wafer ID/num to 25 from 5.                
#

#
# Definitions dependent on EDB Schema
#

$edb_lot_id_len = 25 ;   # lot.lot
$edb_spec_nam_len = 35 ; # test_plan.test_plan

$max_tp_len = 12 ;        # test_plan.test_plan_rev
$max_edb_tp_len = 4 ;    # Fixed number of digits available right of decimal
                         # of test_plan_rev when resolver is used
$edb_spec_rev_len = $max_tp_len - $max_edb_tp_len ;  # What is available for test program, assuming resolver is used
$edb_part_typ_len = 25 ; # product.product - This overflow cores edb
$edb_test_nam_len = 60 ; # parameter.parameter_name
$edb_bin_nam_len = 60 ;  # bin.bin_name
$edb_seq_name_len = 12 ; # test_plan_detail.seq_name
$edb_tconds_len = 20 ;   # environment.test_conditions
$edb_test_txt_len = 80 ; # test_plan_detail.descripton

#
# moved here from SLED
#

#
# EDB field lengths as mapped to STDF fields.
# Used to format input text fields, as well as data format/validation
# Also defined as javascript variables
#
#   STDF                  EDB
$emir_oper_nam_l=12;   # session_summary.operator, badge number is used
$emir_customer_l=24;   # lot.customer
$emir_device_l=15 ;      # product.device
$emir_part_typ_l=25 ;  # product.product
$emir_pkg_type_l=12;   # product.package_type
$emir_des_rev_l=4;     # product.design_rev
$emir_family_l=12;     # product.family, needs to also populate emir_group
$emir_lot_id_l=25;     # lot.lot.  
$wir_wafer_id_l=25;    # wafer_summary.wafer_num.  Small Int
$emir_node_nam_l=12;   # entity.entity
$emir_tstr_typ_l=12;   # entity.entity_type
$emir_stat_num_l=3 ;   # session_summary.station_number
$emir_temp_l=4;        # 4 to be compatible with spec_nam convention
                       # environment.temperature.  Sybase real
$epdr_tconds_l=3;      # 3 to be compatible with spec_nam convention
                       # EDB is 20.  environment.test_conditions.  load for PDC,
$epdr_freq_l=12;       # environment.frequency. Sybase real
$epdr_parmtyp_l=1;     # test_plan_detail.test_type.  Limited by stdf
$emir_spec_nam_l=35;   # testplan.test_plan
$emir_spec_rev_l=7;    # testplan.test_plan_rev 
                       # Must be less than 12
                       # 6 user, 1 decimal, 4 system, 1 extra 
$edb_spec_rev_l=4;     # edb portion of $emir_spec_rev_l
$emir_load_brd_l=25;    # session_summary.load_board
$emir_prb_card_l=25;    # session_summary.probe_card


sub fix_test_nam
{
my $test_num=shift ;
my $test_nam=shift ;
my $log_bad_chars = shift ;
my $log_trunc_bin_tests = shift ;
my $compress = 1 ;  # compress all _ characters after conversion

$test_nam =~ s/^\s+//;
$test_nam =~ s/\s+$//;

my $tmp_nam = $test_nam ;

#if ($test_nam =~ s/[\[\_\@\#\$\%\^\&\*\(\)\{\}\[\]\|\?\/\\\!\~\`\<\>\:\"\,\=\s]/_/g )
if ($test_nam =~ s/[\[\@\#\$\%\^\&\*\(\)\{\}\[\]\|\?\/\\\!\~\`\<\>\:\"\,\=\s]/_/g )
  {
  wlog($log_bad_chars, "Invalid characters:  test_nam=$tmp_nam was changed to $test_nam, test_num=$test_num\n") ;
  }

if ($compress)
  {
  $test_nam =~ s/([_])[_]+/$1/g ;  # compress multiple _ to a single _
  }

#
# Length is critical in EDB, so we check it
#
if ( length($test_nam) > $edb_test_nam_len)
  {
  wlog($log_trunc_bin_tests, "test_nam length > edb max of $edb_test_nam_len, truncating, test_num=$test_num\n") ;
  $test_nam = substr($test_nam,0,$edb_test_nam_len) ;
  }
return($test_nam) ;
}

sub fix_bin_nam
{
my $test_num=shift ;
my $test_nam=shift ;
my $log_bad_chars = shift ;
my $log_trunc_bin_tests = shift ;
my $compress = 1 ;  # compress all _ characters after conversion

$test_nam =~ s/^\s+//;
$test_nam =~ s/\s+$//;

my $tmp_nam = $test_nam ; 

#if ($test_nam =~ s/[\[\_\@\#\$\%\^\&\*\(\)\{\}\[\]\|\?\/\\\!\~\`\<\>\:\"\,\=\s]/_/g )
if ($test_nam =~ s/[\[\@\#\$\%\^\&\*\(\)\{\}\[\]\|\?\/\\\!\~\`\<\>\:\"\,\=\s]/_/g )
  {
  wlog($log_bad_chars, "Invalid characters:  bin_nam=$tmp_nam was changed to $test_nam, bin_num=$test_num\n") ;
  }
if ($compress)
  {
  $test_nam =~ s/([_])[_]+/$1/g ;  # compress multiple _ to a single _
  }
#
# Length is critical in EDB, so we check it
#
if ( length($test_nam) > $edb_test_nam_len)
  {
  wlog($log_trunc_bin_tests, "bin_nam length > edb max of $edb_bin_nam_len, truncating, bin_num=$test_num\n") ;
  $test_nam = substr($test_nam,0,$edb_bin_nam_len) ;
  }
return($test_nam) ;
}

return(1) ;

