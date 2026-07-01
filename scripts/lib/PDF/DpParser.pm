package PDF::DpParser;

use strict;
use Exporter;
use PDF::Parser::Accueol;
use PDF::Parser::AMS_BKET;
use PDF::Parser::Asc;
use PDF::Parser::ASM;
use PDF::Parser::AUTOV;
use PDF::Parser::AWW;
use PDF::Parser::BK_LEHS;
use PDF::Parser::BKET_HP;
use PDF::Parser::COC;
use PDF::Parser::COFC_GBLWFR_JP_xls;
use PDF::Parser::COFC_xls;
use PDF::Parser::COFC_xlsx;
use PDF::Parser::CZ;
use PDF::Parser::CZ2Weh;
use PDF::Parser::Douyee;
use PDF::Parser::Dts_2k_xls;
use PDF::Parser::Eagle;
use PDF::Parser::ET_BKET;
use PDF::Parser::HP_ET_CSV;
use PDF::Parser::HP_ET;
use PDF::Parser::HP_JAZZ_ET;
use PDF::Parser::ICOS_xls;
use PDF::Parser::ISO;
use PDF::Parser::ITCLCR;
use PDF::Parser::Itec;
use PDF::Parser::ItecSum;
use PDF::Parser::Juno_Data_xls;
use PDF::Parser::Juno_Sum_csv;
use PDF::Parser::Juno_Sum_xls;
use PDF::Parser::KeySightCsv;
use PDF::Parser::Klarf;
use PDF::Parser::MavPT_TXT;
use PDF::Parser::MavPT;
use PDF::Parser::MiniKlarf;
use PDF::Parser::NAM;
use PDF::Parser::NJRC;
use PDF::Parser::MavPT;
use PDF::Parser::MiniKlarf;
use PDF::Parser::NAM;
use PDF::Parser::NJRC;
use PDF::Parser::powertech_xls;
use PDF::Parser::powertech_xlsx_sum;
use PDF::Parser::PT_TXT;
use PDF::Parser::RH_CSV;
use PDF::Parser::RH_MT;
use PDF::Parser::RS75;
use PDF::Parser::SEPM;
use PDF::Parser::Shiba;
use PDF::Parser::Sic_xls;
use PDF::Parser::SiCBurnIn;
use PDF::Parser::SicEcofA;
use PDF::Parser::SINF;
use PDF::Parser::SLET_HP;
use PDF::Parser::SPM_LOG2;
use PDF::Parser::SRM;
use PDF::Parser::statec_log_cpft;
use PDF::Parser::statec_log2;
use PDF::Parser::statec_sum;
use PDF::Parser::Stdf;
use PDF::Parser::Stdf::Generic;
use PDF::Parser::Sz;
use PDF::Parser::TESEC_CSV_SORT;
use PDF::Parser::TESEC_CSV;
use PDF::Parser::Tesec_Ksm;
#use PDF::Parser::TESEC;
use PDF::Parser::Tmt;
use PDF::Parser::TMTLSR;
use PDF::Parser::TMTSPD;
use PDF::Parser::TongHui_CSV;
use PDF::Parser::WAT;
our @ISA=qw/Exporter/;
our @EXPORT=qw/new_nam_parser new_sepm_parser new_eagle_parser new_statec_log2_parser/;

sub new_nam_parser{ return PDF::Parser::NAM->new(@_); }
sub new_sepm_parser{ return PDF::Parser::SEPM->new(@_); }
sub new_eagle_parser{ return PDF::Parser::Eagle->new(@_); }
sub new_statec_log2_parser{ return PDF::Parser::statec_log2->new(@_); }

1;

__END__;