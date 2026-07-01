import csv
from lib.Log import Log
from lib.Util import Util

class SiCWlbiParser:
    def __init__(self, file_path):
        self.file_path = file_path

    def get_lotid_from_wlbi_csv(self):
        try:
            with open(self.file_path, 'r') as file:
                reader = csv.reader(file)
                for row in reader:
                    if row and row[0].startswith('strLotName'):
                        return row[1].strip()
        except FileNotFoundError:
            Log.ERROR(f"File {self.file_path} not found.")
            Util.dp_exit(1, f"File {self.file_path} not found.")
        except Exception as e:
            Log.ERROR(f"An error occurred: {e}")
            Util.dp_exit(1, f"An error occurred: {e}")
        return None

    def get_metadata_by_lot(self, lot, api_client, url):
        if not lot:
            raise ValueError("Invalid lot number provided")

        def check_lot(lot):
            """Attempt to retrieve and log metadata for a given lot ID."""
            try:
                on_lot_url = f"{url}/{lot}"
                lot_data = api_client.get_metadata(on_lot_url)
                Log.INFO(f"Metadata retrieved for lot: {lot}, status: {lot_data.get('status', 'unknown')}")
                return lot_data
            except Exception as e:
                Log.ERROR(f"Error retrieving metadata for lot {lot}: {str(e)}")
                return None

        # Check original lot ID first
        Log.INFO(f"Attempting to retrieve metadata for original lot: {lot}, first call")
        original_lot_data = check_lot(lot)
        if original_lot_data is not None and 'error' not in original_lot_data.get('status', '').lower():
            return original_lot_data

        # Handling special lot prefixes with potential modifications
        special_prefixes = {
            'M0': lambda x: [self.replace_third_char_with_zero(x)] if len(x) == 10 else [],
            'KG': lambda x: [x[:8]] if len(x) > 8 else [],
            'KH': lambda x: [x[:8]] if len(x) > 8 else [],
            'MKG': lambda x: [x[1:], x[1:][:8]] if len(x) > 1 else [],  # Drop 'M' and process the remainder, then try stripping to 8 chars
            'MKH': lambda x: [x[1:], x[1:][:8]] if len(x) > 1 else []   # Drop 'M' and process the remainder, then try stripping to 8 chars
        }

        # Check modified lot IDs based on special prefixes
        call_count = 1  # Initialize call count for original lot check
        for prefix, modify_func in special_prefixes.items():
            if lot.startswith(prefix):
                modifications = modify_func(lot)
                for modified_lot in modifications:
                    call_count += 1  # Increment call count for each modified lot check
                    Log.INFO(f"Attempting to retrieve metadata for modified lot ID: {modified_lot} (Call {call_count})")
                    modified_lot_data = check_lot(modified_lot)
                    if modified_lot_data is not None and 'error' not in modified_lot_data.get('status', '').lower():
                        return modified_lot_data
        Log.INFO(f"Lot ID {lot} does not match any special prefixes for modification.")
        Log.INFO(f'returned lot metadata is by original lot')
        # If all attempts fail, return the original lot data (which may contain an error)
        return original_lot_data

    def replace_third_char_with_zero(self, lot):
        """Replace the third character of the lot ID with '0'."""
        return lot[:2] + '0' + lot[3:]
