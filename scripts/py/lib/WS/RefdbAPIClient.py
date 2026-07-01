import requests
import json
import pybreaker
from requests.adapters import HTTPAdapter
from requests.packages.urllib3.util.retry import Retry
from lib.Log import Log

class RefdbAPIClient:
    def __init__(self, retries=5, backoff_factor=0.5, status_forcelist=(500, 502, 504), session=None):
        self.session = session or requests.Session()
        retry = Retry(
            total=retries,
            backoff_factor=backoff_factor,
            status_forcelist=status_forcelist,
        )
        adapter = HTTPAdapter(max_retries=retry)
        self.session.mount('http://', adapter)
        self.session.mount('https://', adapter)
        Log.INFO("Session initialized with retry and adapter settings")
        # print(f"Session initialized with retry and adapter settings")
        
        # Initialize the circuit breaker as an attribute
        self.circuit_breaker = pybreaker.CircuitBreaker(fail_max=5, reset_timeout=20)
        
        # Apply the circuit breaker decorator to the get_metadata method
        self.get_metadata = self.circuit_breaker(self.get_metadata)
    
    def get_metadata(self, url, default_metadata=None, timeout=5.0):
        if default_metadata is None:
            default_metadata = {}  # or any other default value you prefer

        try:
            response = self.session.get(url, timeout=timeout)
            response.raise_for_status()
            data = response.json()
            if isinstance(data, list) and len(data) > 0:
                Log.INFO("Response data is a list, using first element")
                data = data[0]

            if isinstance(data, dict) and data:
                return data
            else:
                Log.INFO("Response data is not a dictionary or is empty, returning default metadata")
                return default_metadata
        except requests.exceptions.HTTPError as errh:
            Log.ERROR(f"HTTP Error: {errh}")
        except requests.exceptions.ConnectionError as errc:
            Log.ERROR(f"Error Connecting: {errc}")
        except requests.exceptions.Timeout as errt:
            Log.ERROR(f"Timeout Error: {errt}")
        except requests.exceptions.RequestException as err:
            Log.ERROR(f"Something went wrong: {err}")
        return default_metadata
