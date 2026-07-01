package sepi_const;

use constant EXPORT_WMAP_NO_TAG 	=> 0; # No TAG, backwards compatible. Default value.
use constant EXPORT_WMAP_TAG_FIRST	=> 1; # First probed wafermap of this wafer
use constant EXPORT_WMAP_TAG_LAST	=> 2; # Last probed wafermap of this wafer
use constant EXPORT_WMAP_TAG		=> 3; # Provide a TAG string yourself

use constant EXPORT_MAPTYPE_SE 			=>  0;
use constant EXPORT_MAPTYPE_ARRAY		=>  1;
use constant EXPORT_MAPTYPE_ASCII 		=>  2;
use constant EXPORT_MAPTYPE_XY 			=>  3;
use constant EXPORT_MAPTYPE_MICREL 		=>  4;
use constant EXPORT_MAPTYPE_SNI 		=>  7;
use constant EXPORT_MAPTYPE_CARSEM 		=>  9;
use constant EXPORT_MAPTYPE_TRIAGE 		=> 10;
use constant EXPORT_MAPTYPE_CHIPPAC 		=> 16;
use constant EXPORT_MAPTYPE_LEXMARK 		=> 17;
use constant EXPORT_MAPTYPE_CSV 		=> 18;
use constant EXPORT_MAPTYPE_ECN 		=> 19;
use constant EXPORT_MAPTYPE_ECN_R 		=> 20;
use constant EXPORT_MAPTYPE_SIMPLIFIED_INF 	=> 21;

use constant SEPI_SVR_HOST			=> 'mentwsaic4';
use constant SEPI_SVR_PORT			=> '8080';
use constant SEPI_SVR_PATH			=> 'SEPI/SEPIConvertWaferMap';
use constant SEPI_SVR_TIMEOUT			=> '120';
use constant SEPI_SITE_LOCATION			=> 'MESORT';

1;
