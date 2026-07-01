import sys
import os
import unittest
from unittest.mock import patch, MagicMock

# Add scripts/py to sys.path
sys.path.append(os.path.join(os.path.dirname(__file__), '..'))

import klarf_18_enricher
from lib.WS.RefdbAPIClient import RefdbAPIClient

class TestBKRetry(unittest.TestCase):
    @patch('klarf_18_enricher.RefdbAPIClient')
    @patch('klarf_18_enricher.Util')
    @patch('klarf_18_enricher.Log')
    @patch('klarf_18_enricher.Writer')
    def test_bk_retry_logic(self, mock_writer, mock_log, mock_util, mock_refdb_class):
        # 1. Setup Mocks
        mock_refdb_client = mock_refdb_class.return_id()
        mock_refdb_class.return_value = mock_refdb_client
        
        # Simulate ws_url loading
        mock_util.load_yaml.return_value = {
            'refdb': {
                'prod': {
                    'on_lot': 'http://test-ws/api/onlot'
                }
            }
        }
        mock_util.configure_ws_urls.return_value = {'onlot': 'http://test-ws/api/onlot'}
        mock_util.process_command_line_args.return_value = {
            'infile': 'tests/test_bk_lot.klarf',
            'out': 'output/',
            'ws_source': 'prod',
            'ws_url': 'some_config.yaml',
            'site': 'BK_SICA88_Rework'
        }
        
        # 2. Mock API Responses
        # First call returns NO_DATA
        # Second call (retry) returns valid data
        mock_refdb_client.get_metadata.side_effect = [
            {'status': 'NO_DATA'},
            {
                'status': 'MES',
                'lot': 'KG46Z1PA',
                'sourceLot': 'KG46Z1PX',
                'product': 'CR1299XXXXA-WDX',
                'fab': 'KRG:BUCHEON 6IN FE (BSG)'
            }
        ]
        
        # 3. Simulate Klarf content
        with patch('builtins.open', unittest.mock.mock_open(read_data='FileRecord 1.8; LotRecord "KG46Z1PA" { FabID "BK"; }')):
            with patch('os.path.exists', return_value=True):
                # We need to mock the parser too to return what we expect
                mock_parser = MagicMock()
                mock_parser.parse.return_value = {
                    'LotRecord': {'_val': 'KG46Z1PA', '_type': 'LotRecord'},
                    'FabID': ['BK']
                }
                with patch('klarf_18_enricher.Klarf18', return_value=mock_parser):
                    # 4. Run main() logic partially or just trigger the relevant part
                    # To keep it simple, let's just run main() and see if it hits the retry
                    try:
                        sys.argv = ['klarf_18_enricher.py', 'tests/test_bk_lot.klarf', '--out', 'output/', '--site', 'BK_SICA88_Rework', '--ws_url', 'url.yaml', '--ws_source', 'prod']
                        klarf_18_enricher.main()
                    except SystemExit:
                        pass # Util.dp_exit calls sys.exit
                    
        # 5. Assertions
        # Verify get_metadata was called twice
        self.assertEqual(mock_refdb_client.get_metadata.call_count, 2)
        
        # Verify first call URL
        first_call_url = mock_refdb_client.get_metadata.call_args_list[0][0][0]
        self.assertEqual(first_call_url, 'http://test-ws/api/onlot/KG46Z1PA')
        
        # Verify second call URL (with ?site=BK)
        second_call_url = mock_refdb_client.get_metadata.call_args_list[1][0][0]
        self.assertIn('?site=BK', second_call_url)
        
        print("Verification SUCCESS: Retry logic triggered correctly.")

if __name__ == '__main__':
    unittest.main()
