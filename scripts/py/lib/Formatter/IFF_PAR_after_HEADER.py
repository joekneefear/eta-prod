"""
SYNOPSIS

DESCRIPTION
    IFF

AUTHOR
    junifferallan.garcia@onsemi.com

CHANGES
    2023-Oct-12 - jgarcia - initial
    2024-Jul-17 - jgarcia - added write_jnd_lot_metadata, write_dict_to_file, save_dataframe_to_csv, format_and_export and format_value functions
    2025-Mar-07 - jgarcia - updated to adhere Base class settings and intention
    2025-Mar-07 - jgarcia - refactored to be similar to Perl version
    2025-Aug-07 - jgarcia - added build_outfilename function to apped wafer number(s) in the filename.

LICENSE
    (C) onsemi 2023 All rights reserved.
"""

from os.path import basename
import re
from lib.Util import Util
from lib.Data import Base
from lib.Log import Log
from lib.Writer import Writer
from lib.Data.Limit import Limit
import numbers
import pandas as pd
import os
import csv


class IFF(Base):
    ATTRIBUTES = [
        "writer", "model", "defect"
    ]
    ARRAY_ATTRIBUTES = ["test_items", "data_items", "bin_items", "rel_items", "index_items"]

    def __init__(self, args=None):
        """
        Initializes an IFF object.

        Args:
            args (dict, optional): A dictionary of attributes to initialize the object with.
        """
        args = args or {}  # Ensure args is a dictionary
        super().__init__(args)

        # Initialize predefined attributes with defaults
        for attr in self.ATTRIBUTES:
            setattr(self, attr, args.get(attr, None))  # Use None if missing

        # Initialize list attributes using a helper function
        self.initialize_list_attributes()

        # Preserve original defaults to avoid altering output format/content
        if not self.test_items:
            self.test_items = ['number', 'name', 'units']
        if not self.bin_items:
            self.bin_items = ['number', 'name', 'PF', 'count']
        if not self.data_items:
            self.data_items = ['x', 'y', 'site', 'partid', 'touchdown_num', 'soft_bin', 'hard_bin', 'org_x', 'org_y']
        if not self.rel_items:
            self.rel_items = ['qpnumber', 'devchar', 'lotchar', 'strname', 'strduration', 'atetemp', 'datalogtype']
        if not self.index_items:
            self.index_items = ['index1', 'index2', 'index3', 'index4', 'index5']

    def initialize_list_attributes(self):
        """Helper function to initialize list attributes."""
        self._arrays = {}
        for attr in self.ARRAY_ATTRIBUTES:
            self._arrays[attr] = []

    @property
    def test_items(self):
        return self._arrays["test_items"]

    @test_items.setter
    def test_items(self, value):
        self._arrays["test_items"] = value

    @property
    def data_items(self):
        return self._arrays["data_items"]

    @data_items.setter
    def data_items(self, value):
        self._arrays["data_items"] = value

    @property
    def bin_items(self):
        return self._arrays["bin_items"]

    @bin_items.setter
    def bin_items(self, value):
        self._arrays["bin_items"] = value

    @property
    def rel_items(self):
        return self._arrays["rel_items"]

    @rel_items.setter
    def rel_items(self, value):
        self._arrays["rel_items"] = value

    @property
    def index_items(self):
        return self._arrays["index_items"]

    @index_items.setter
    def index_items(self, value):
        self._arrays["index_items"] = value

    # Compatibility aliases with original attribute naming
    @property
    def testItems(self):
        return self.test_items

    @testItems.setter
    def testItems(self, value):
        self.test_items = value

    @property
    def dataItems(self):
        return self.data_items

    @dataItems.setter
    def dataItems(self, value):
        self.data_items = value

    @property
    def binItems(self):
        return self.bin_items

    @binItems.setter
    def binItems(self, value):
        self.bin_items = value

    @property
    def relItems(self):
        return self.rel_items

    @relItems.setter
    def relItems(self, value):
        self.rel_items = value

    @property
    def indexItems(self):
        return self.index_items

    @indexItems.setter
    def indexItems(self, value):
        self.index_items = value

    def array(self):
        """
        Returns a list of array-like attributes.

        Returns:
            list: A list of attribute names.
        """
        # Keep original naming expected by legacy config/base flows
        return ['testItems', 'dataItems', 'binItems', 'relItems', 'indexItems']

    def list(self):
        """
        Defines attributes that should be included in the string representation.

        Returns:
            list: A list of attribute names.
        """
        return self.ATTRIBUTES

    def _format_bin_line(self, bin_obj):
        """Formats a single line for bin data."""
        line = []
        if 'number' in self.bin_items:
            line.append(Util.rep_na(bin_obj.number))
        if 'name' in self.bin_items:
            line.append(bin_obj.name.strip() if bin_obj.name else f"BIN_{str(bin_obj.number).zfill(3)}")
        if 'bindesc' in self.bin_items:
            line.append(Util.rep_na(bin_obj.bindesc.strip()) if bin_obj.bindesc else f"BIN_{str(bin_obj.number).zfill(3)}")
        if 'PF' in self.bin_items:
            line.append(Util.rep_na(bin_obj.PF))
        if 'count' in self.bin_items:
            line.append(Util.rep_na(bin_obj.count))
        
        # Convert all elements to string to avoid TypeError during join
        line = [str(item) for item in line]
        return ",".join(line)

    def bins_to_string(self, bins):
        """
        Converts a list of bin objects to a string.

        Args:
            bins (list): A list of bin objects.

        Returns:
            str: A string representation of the bin data.
        """
        strings = [self._format_bin_line(bin_obj) for bin_obj in bins]
        return "\n".join(strings) + "\n"

    def header_to_string(self, metadata):
        """
        Converts header metadata to a string.

        Args:
            metadata: The metadata object.

        Returns:
            str: A string representation of the header metadata.
        """
        data_source = self.model.dataSource
        string = ""
        for key in metadata.list():
            value = getattr(metadata, key)
            value = Util.rep_na(value)
            string += f"{key}={value}\n"
        return string

    def tests_to_string(self, tests):
        """
        Converts a list of test objects to a string.

        Args:
            tests (list): A list of test objects.

        Returns:
            str: A string representation of the test data.
        """
        strings = []
        for test in tests:
            line = [getattr(test, item, None) for item in self.test_items]
            line = [str(Util.rep_na(element)) for element in line]
            strings.append(",".join(line))
        strings = [str(element) for element in strings]
        return "\n".join(strings) + "\n"

    def _format_die_line(self, die):
        """Formats a single line for die data."""
        line = []
        if 'x' in self.data_items:
            line.append(f"DIE_X={Util.rep_na(die.x)}")
        if 'y' in self.data_items:
            line.append(f"DIE_Y={Util.rep_na(die.y)}")
        if 'org_x' in self.data_items:
            line.append(f"ORG_X={Util.rep_na(die.org_x)}")
        if 'org_y' in self.data_items:
            line.append(f"ORG_Y={Util.rep_na(die.org_y)}")
        if 'site' in self.data_items:
            line.append(f"SITE={Util.rep_na(die.site)}")
        if 'partid' in self.data_items:
            line.append(f"PARTID={Util.rep_na(die.partid)}")
        if 'touchdown_num' in self.data_items:
            line.append(f"TOUCHDOWN_NUM={Util.rep_na(die.touchdown_num)}")
        if 'ecid' in self.data_items:
            line.append(f"ECID={Util.rep_na(die.ecid)}")
        if 'hard_bin' in self.data_items:
            line.append(f"HARD_BIN={Util.rep_na(die.hard_bin)}")
        if 'soft_bin' in self.data_items:
            line.append(f"SOFT_BIN={Util.rep_na(die.soft_bin)}")
        if 'bindesc' in self.data_items:
            line.append(f"BINDESC={Util.rep_na(die.bindesc)}")    
        if 'readtime' in self.data_items:
            line.append(f"READTIME={Util.rep_na(die.readtime)}")
        if 'runtime' in self.data_items:
            line.append(f"RUNTIME={Util.rep_na(die.runtime)}")
        die_result = getattr(die, 'result', [])
        line.append(",".join(str(Util.rep_na(v)) for v in die_result))
        return "\n".join(line)

    def dies_to_string(self, dies):
        """
        Converts a list of die objects to a string.

        Args:
            dies (list): A list of die objects.

        Returns:
            str: A string representation of the die data.
        """
        strings = [self._format_die_line(die) for die in dies if not (die.inked or die.notest)]
        return "\n".join(strings) + "\n"

    def build_outfilename(self, orig_basename, wafer_number):
        base, ext = os.path.splitext(orig_basename)
        parts = base.split('_')
        if len(parts) < 2:
            new_base = f"{base}_{wafer_number}"
        else:
            # new_base = '_'join(parts[:-1]) + [wafer_number, parts[-1]]
            new_base = '_'.join(parts[:-1] + [wafer_number, parts[-1]])
        return new_base + ext
        
    def print_par(self):
        """
        Formats and writes PAR data to a file, grouping wafers by START_TIME.
        For single lot: PAR section is printed once after header from model.tests.
        """
        wr = self.writer
        model = self.model
        outfilename = wr.basename
        group = {}
        model_tests = getattr(model, "tests", None)
        model_tests_string = self.tests_to_string(model_tests) if model_tests else None

        metadata = model.header if getattr(model, "header", None) else getattr(model, "metadata", None)
        if not metadata:
            Util.dp_exit(1, pplogger=wr.pplogger, error="Header/metadata is missing in model")

        Log.INFO(f"Starting print_par for LOT: {metadata.LOT}, Filename: {outfilename}")

        # Group wafers by START_TIME
        for wafer in model.wafers:
            key = wafer.START_TIME
            group.setdefault(key, []).append(wafer)

        # Process each group of wafers
        for wafers in group.values():
            # Update model header with first wafer's start and end times
            first_wafer = wafers[0]
            if first_wafer.START_TIME:
                metadata.START_TIME = first_wafer.START_TIME
            if first_wafer.END_TIME:
                metadata.END_TIME = first_wafer.END_TIME

            # Determine the output filename
            if getattr(first_wafer, "key", None):
                wr.basename = f"{outfilename}_{first_wafer.key}"
            else:
                try:
                    wafer_number = int(first_wafer.number)
                    if wafer_number > 0:
                        wr.basename = f"{outfilename}_{wafer_number}"
                except (TypeError, ValueError):
                    Log.WARN(f"Invalid wafer number: {first_wafer.number}")

            # Open the output file
            try:
                wr.open()
                Log.INFO(f"Opened output file: {wr.outfile()}")
            except Exception as e:
                Log.ERROR(f"Failed to open output file: {wr.outfile()}, Error: {e}")
                continue  # Skip to the next group of wafers

            # Write data to the file
            try:
                # Write header and wmap first
                wr.put(f"<HEADER>\n{self.header_to_string(metadata)}</HEADER>\n")
                if model.wmap:
                    wr.put(f"<WMAP>\n{model.wmap.to_string()}</WMAP>\n")
                
                # Write PAR section once for the entire lot (after header, before wafers)
                if model_tests_string:
                    wr.put(f"<PAR>\n{model_tests_string}</PAR>\n")

                # Write wafer data
                for wafer in wafers:
                    wafer_id = f"{metadata.LOT.upper()}_{wafer.number}"
                    wafer_rels = getattr(wafer, "rels", None)
                    model_rels = getattr(model, "rels", None)
                    wafer_custindexes = getattr(wafer, "custindexes", None)
                    model_custindexes = getattr(model, "custindexes", None)
                    wr.put("<WAFER>\n")
                    if wafer.name:
                        wr.put(f"WAFER_ID={wafer.name}\n")
                    else:
                        wr.put(f"WAFER_ID={wafer_id}\n")
                    wr.put(f"WAFER_NUMBER={wafer.number}\n")
                    wr.put("</WAFER>\n")

                    if wafer.bins:
                        wr.put(f"<BIN>\n{self.bins_to_string(wafer.bins)}</BIN>\n")
                    if wafer.sbins:
                        wr.put(f"<SBIN>\n{self.bins_to_string(wafer.sbins)}</SBIN>\n")
                    if wafer.hbins:
                        wr.put(f"<HBIN>\n{self.bins_to_string(wafer.hbins)}</HBIN>\n")
                    if model.sbins:
                        wr.put(f"<SBIN>\n{self.bins_to_string(model.sbins)}</SBIN>\n")
                    if model.hbins:
                        wr.put(f"<HBIN>\n{self.bins_to_string(model.hbins)}</HBIN>\n")
                    if wafer_rels:
                        wr.put(f"<REL>\n{self.rels_to_string(wafer_rels)}</REL>\n")
                    if model_rels:
                        wr.put(f"<REL>\n{self.rels_to_string(model_rels)}</REL>\n")
                    if wafer_custindexes:
                        wr.put(f"<CUSTOM_INDEXES>\n{self.custindexes_to_string(wafer_custindexes)}</CUSTOM_INDEXES>\n")
                    if model_custindexes:
                        wr.put(f"<CUSTOM_INDEXES>\n{self.custindexes_to_string(model_custindexes)}</CUSTOM_INDEXES>\n")
                    wr.put(f"<DATA>\n{self.dies_to_string(wafer.dies)}</DATA>\n")

                    generate_stat = any(die.min for die in wafer.dies)
                    if generate_stat:
                        try:
                            wr.put(f"<STAT>\n{self.stat_to_string(wafer.dies)}</STAT>\n")
                        except AttributeError as e:
                            Log.ERROR(f"Error calling stat_to_string for wafer {wafer.number}: {e}")

                    generate_model_stat = any(die.min for die in model.dies)
                    if generate_model_stat:
                        try:
                            wr.put(f"<STAT>\n{self.stat_to_string(model.dies)}</STAT>\n")
                        except AttributeError as e:
                            Log.ERROR(f"Error calling stat_to_string for model dies: {e}")

            except Exception as e:
                Log.ERROR(f"Error writing data to file: {wr.outfile()}, Error: {e}")
                Util.dp_exit(1, pplogger=wr.pplogger, error=f"Error writing data to file: {wr.outfile()}, Error: {e}")

            # Close the output file
            finally:
                try:
                    wr.close()
                    Log.INFO(f"Closed output file: {wr.outfile()}")
                except Exception as e:
                    Log.ERROR(f"Failed to close output file: {wr.outfile()}, Error: {e}")

        Log.INFO("Finished print_par")
    
    def print_par_per_wafer_number(self):
        """
        Formats and writes PAR data to a file per wafer.
        For each wafer: PAR section is printed right after header from wafer.tests or model.tests.
        """
        wr = self.writer
        model = self.model
        outfilename = wr.basename
        group = {}
        model_tests = getattr(model, "tests", None)
        model_tests_string = self.tests_to_string(model_tests) if model_tests else None

        metadata = model.header if getattr(model, "header", None) else getattr(model, "metadata", None)
        if not metadata:
            Util.dp_exit(1, pplogger=wr.pplogger, error="Header/metadata is missing in model")

        Log.INFO(f"Starting print_par for LOT: {metadata.LOT}, Filename: {outfilename}")

        # Group wafers by START_TIME
        for wafer in model.wafers:
            key = wafer.START_TIME
            group.setdefault(key, []).append(wafer)

        # Process each group of wafers
        for start_time, wafers in group.items():
            for wafer in wafers:
                wafer_number = str(wafer.number).zfill(2)

                # Update model header with wafer's start and end times
                if wafer.START_TIME:
                    metadata.START_TIME = wafer.START_TIME
                if wafer.END_TIME:
                    metadata.END_TIME = wafer.END_TIME

                # Determine the output filename
                wr.basename = f"{outfilename}_{wafer_number}"

                # Open the output file
                try:
                    wr.open()
                    Log.INFO(f"Opened output file: {wr.outfile()}")
                except Exception as e:
                    Log.ERROR(f"Failed to open output file: {wr.outfile()}, Error: {e}")
                    continue  # Skip to the next wafer

                # Write data to the file
                try:
                    # Write header and wmap first
                    wr.put(f"<HEADER>\n{self.header_to_string(metadata)}</HEADER>\n")
                    if model.wmap:
                        wr.put(f"<WMAP>\n{model.wmap.to_string()}</WMAP>\n")
                    
                    # Write PAR section per wafer (after header, before wafer sections)
                    wafer_tests = getattr(wafer, "tests", None)
                    if wafer_tests:
                        wr.put(f"<PAR>\n{self.tests_to_string(wafer_tests)}</PAR>\n")
                    elif model_tests_string:
                        wr.put(f"<PAR>\n{model_tests_string}</PAR>\n")

                    # Write wafer data
                    wafer_id = f"{metadata.LOT.upper()}_{wafer_number}"
                    wafer_rels = getattr(wafer, "rels", None)
                    model_rels = getattr(model, "rels", None)
                    wafer_custindexes = getattr(wafer, "custindexes", None)
                    model_custindexes = getattr(model, "custindexes", None)
                    wr.put("<WAFER>\n")
                    if wafer.name:
                        wr.put(f"WAFER_ID={wafer.name}\n")
                    else:
                        wr.put(f"WAFER_ID={wafer_id}\n")
                    wr.put(f"WAFER_NUMBER={wafer_number}\n")
                    wr.put("</WAFER>\n")

                    if wafer.bins:
                        wr.put(f"<BIN>\n{self.bins_to_string(wafer.bins)}</BIN>\n")
                    if wafer.sbins:
                        wr.put(f"<SBIN>\n{self.bins_to_string(wafer.sbins)}</SBIN>\n")
                    if wafer.hbins:
                        wr.put(f"<HBIN>\n{self.bins_to_string(wafer.hbins)}</HBIN>\n")
                    if model.sbins:
                        wr.put(f"<SBIN>\n{self.bins_to_string(model.sbins)}</SBIN>\n")
                    if model.hbins:
                        wr.put(f"<HBIN>\n{self.bins_to_string(model.hbins)}</HBIN>\n")
                    if wafer_rels:
                        wr.put(f"<REL>\n{self.rels_to_string(wafer_rels)}</REL>\n")
                    if model_rels:
                        wr.put(f"<REL>\n{self.rels_to_string(model_rels)}</REL>\n")
                    if wafer_custindexes:
                        wr.put(f"<CUSTOM_INDEXES>\n{self.custindexes_to_string(wafer_custindexes)}</CUSTOM_INDEXES>\n")
                    if model_custindexes:
                        wr.put(f"<CUSTOM_INDEXES>\n{self.custindexes_to_string(model_custindexes)}</CUSTOM_INDEXES>\n")
                    wr.put(f"<DATA>\n{self.dies_to_string(wafer.dies)}</DATA>\n")

                    generate_stat = any(die.min for die in wafer.dies)
                    if generate_stat:
                        try:
                            wr.put(f"<STAT>\n{self.stat_to_string(wafer.dies)}</STAT>\n")
                        except AttributeError as e:
                            Log.ERROR(f"Error calling stat_to_string for wafer {wafer.number}: {e}")

                    generate_model_stat = any(die.min for die in model.dies)
                    if generate_model_stat:
                        try:
                            wr.put(f"<STAT>\n{self.stat_to_string(model.dies)}</STAT>\n")
                        except AttributeError as e:
                            Log.ERROR(f"Error calling stat_to_string for model dies: {e}")

                except Exception as e:
                    Log.ERROR(f"Error writing data to file: {wr.outfile()}, Error: {e}")
                    Util.dp_exit(1, pplogger=wr.pplogger, error=f"Error writing data to file: {wr.outfile()}, Error: {e}")

                # Close the output file
                finally:
                    try:
                        wr.close()
                        Log.INFO(f"Closed output file: {wr.outfile()}")
                    except Exception as e:
                        Log.ERROR(f"Failed to close output file: {wr.outfile()}, Error: {e}")

        Log.INFO("Finished print_par_per_wafer_number")


    def write_dict_line_list(self, add_new_line=True):
        """
        Writes dictionary data to a file, where each entry is a list of lines.
        """
        wr = self.writer
        model = self.model
        outfilename = wr.basename
        file_data = model.misc

        for route, addr in file_data.items():
            if route and not any(route.lower().startswith(prefix) for prefix in ["header", "flag", "sample_test_plan_coordinates", "sample_test_plan_count"]):
                fname = f"{outfilename}_{route}"
                wr.basename = fname
                try:
                    wr.open()
                    for line_data in addr:
                        wr.put(str(line_data) + ("\n" if add_new_line else ""))
                    wr.put("\n")
                except Exception as e:
                    Log.ERROR(f"Error writing route {route} to file: {wr.outfile()}, Error: {e}")
                finally:
                    wr.close()

    def write_dict_line_list_klarf12(self, add_new_line=True):
        """
        Writes dictionary data to a file in Klarf12 format, where each entry is a list of lines.
        This function is similar to write_dict_line_list but may have specific formatting requirements for Klarf12.
        """
        # The implementation is identical to write_dict_line_list, consider refactoring if differences arise
        self.write_dict_line_list(add_new_line)

    def write_jnd_lot_metadata(self):
        """
        Writes JND lot metadata to a file, sorting and de-duplicating the data.
        """
        wr = self.writer
        model = self.model
        file_data = model.misc

        def get_sort_key(line):
            fields = line.split(",")
            try:
                return (fields[6], int(fields[17]))
            except (ValueError, IndexError):
                return ("", 0)

        for route, addr in file_data.items():
            if route and not any(route.lower().startswith(prefix) for prefix in ["header", "flag", "sample_test_plan_coordinates", "sample_test_plan_count"]):
                fname = f"{route}"
                wr.basename = fname
                full_path = wr.outfile()
                lines = []

                if os.path.exists(full_path):
                    try:
                        with open(full_path, 'r') as f:
                            lines = [line.strip() for line in f]
                    except Exception as e:
                        Log.ERROR(f"Error reading existing file {full_path}: {e}")

                combined_data = lines + addr
                sorted_unique_data = sorted(set(combined_data), key=get_sort_key)

                try:
                    wr.open()
                    first_line = True
                    for line in sorted_unique_data:
                        if not first_line:
                            wr.put("\n")
                        wr.put(str(line))
                        first_line = False
                except Exception as e:
                    Log.ERROR(f"Error writing to file {full_path}: {e}")
                finally:
                    wr.close()

    def write_dict_to_file(self, version, add_new_line=True):
        """
        Writes dictionary data to a file in a specific format based on the version.
        """
        wr = self.writer
        model = self.model
        outfilename = wr.basename
        try:
            file_data = model.misc[version]
        except KeyError:
            raise KeyError(f"Dictionary doesn't contain version={version} data")

        fname = f"{outfilename}"
        wr.basename = fname
        try:
            wr.open()
            self.format_and_export(file_data, wr)
            wr.put("EndOfFile;")
            if add_new_line:
                wr.put("\n")
        except Exception as e:
            Log.ERROR(f"Error writing version {version} to file: {wr.outfile()}, Error: {e}")
        finally:
            wr.close()

    def save_dataframe_to_csv(self):
        """
        Saves a list of pandas DataFrames to a CSV file.
        """
        wr = self.writer
        model = self.model
        df_list = model.misc
        outfile = wr.outfile()
        tempfile_path = outfile + ".tmp"

        # Start from a clean temp file to avoid appending stale data.
        if os.path.exists(tempfile_path):
            os.remove(tempfile_path)

        wrote_any = False
        for idx, df in enumerate(df_list):
            if isinstance(df, pd.DataFrame):
                df.to_csv(tempfile_path, mode='a', index=False, header=True)
                with open(tempfile_path, 'a') as file:
                    file.write('\n')
                wrote_any = True
            else:
                Log.WARN(f"Warning: Item {idx} is not a DataFrame (type: {type(df)})")

        if not wrote_any:
            # Preserve old behavior of producing an output artifact even with no valid DataFrame rows.
            open(tempfile_path, 'w').close()

        # Ensure dataframe bytes are durable before publish/compress.
        wr.fsync_file(tempfile_path)

        wr.openedfile = outfile
        wr.tempfile = tempfile_path

        # Keep Writer.close() ordering semantics: fork first, then gzip/rename.
        if wr.forkdir:
            wr.fork()

        if wr.gzipIFF and not Util.is_gzipped(wr.openedfile):
            wr.compress_to_gzip_iff()
        else:
            if os.path.exists(wr.tempfile):
                wr.atomic_replace(wr.tempfile, wr.openedfile)
                Log.INFO(f"renamed temp struct {wr.tempfile} -> {wr.openedfile}")

    def format_and_export(self, data_dict, wr):
        """
        Formats and exports data to a file in Klarf v1.2 format.
        """
        for key, val in data_dict.items():
            try:
                if key.endswith("OnelineList"):
                    key = key.replace("OnelineList", "List")
                    s = f"{key} {' '.join(self.format_value(v) for v in val)};\n"
                    wr.put(s)
                elif key.endswith("ShortList"):
                    key = key.replace("ShortList", "List")
                    s = f"{key}\n {' '.join(self.format_value(v) for v in val)};\n"
                    wr.put(s)
                elif key.endswith("List"):
                    columns_info = val["Columns"]
                    rows = val["Data"]
                    key_spec = "DefectRecordSpec" if key == "DefectList" else key.replace("List", "Spec")
                    s = f"{key_spec} {len(columns_info)} {' '.join(str(col['Column']) for col in columns_info)};\n"
                    wr.put(s)
                    s = f"{key} \n"
                    s += "".join(f" {' '.join(str(v) for v in row)}\n" for row in rows)
                    s += ";\n"
                    wr.put(s)
                else:
                    if key.lower() == "metadata":
                        s = f"{val};\n"
                    else:
                        s = f"{key} {' '.join(str(v) for v in val)};\n"
                    wr.put(s)
            except Exception as e:
                Log.ERROR(f"Error formatting and exporting key {key}: {e}")

    def format_value(self, value):
        """
        Formats a single value for output.
        """
        if value is None:
            return "None"
        if isinstance(value, float):
            s = f"{value:.10E}"
            mantissa, exponent = s.split("E")
            exponent_sign = exponent[0]
            expanded_exponent = f"{int(exponent[1:]):03}"
            return mantissa + "E" + exponent_sign + expanded_exponent
        return str(value)
    
    def print_limit(self):
        wr = self.writer
        limit = self.model.limit
        outfile = limit.limit_file
        
        # Set the basename attribute directly
        wr.basename = outfile
        wr.ext = 'limit'
        wr.noWMap = 0
        wr.open()
        wr.put(f"<HEADER>\n{limit.to_string()}\n</HEADER>\n")
        wr.put(f"<LIMIT>\n{self.limit_to_string()}</LIMIT>\n")
        
        if limit.conditionNames:
            wr.put("<CONDITION>\n")
            wr.put(",".join(limit.conditionNames) + "\n")
            wr.put(self.limit_to_string_with_conditions())
            wr.put("</CONDITION>\n")
        
        wr.close()
     
    def limit_to_string(self):
        limit = self.model.limit
        tests = limit.tests
        # Log.INFO(f"tests in limit={tests}")
        result = []

        # Check if limit.testItems exists and is not empty
        if not hasattr(limit, 'tests') or not limit.tests:
            # Log.INFO("limit.tests is not defined or is empty!")
            Log.WARN("limit.tests is not defined or is empty!")
            return ""
        
        # Print the contents of limit.testItems
        # Log.INFO(f"limit.testItems: {limit.testItems}")

        if not tests:
            # Log.INFO("The tests list is empty!")
            Log.WARN("The tests list is empty!")
            return ""

        for test in tests:
            # print("Processing a test...")  # Debug print to indicate a test is being processed
            if not test:  # Check if the test is empty
                # Log.WARN("Empty test found!")  # Print a message if the test is empty
                print("Empty test found!")  # Print a message if the test is empty
                continue

            line = []
            for item in limit.testItems:
                # print(f"Processing item: {item}")  # Debug print to indicate an item is being processed
                # Log.INFO(f"===========test=====")
                value = getattr(test, item)  # Access the attribute of the Test instance
                # Log.INFO(f"Item: {item}, Value: {value}")  # Debug print
                line.append(Util.rep_na(value))
            line.append(Util.rep_na(getattr(test, 'LPL', "")))
            line.append(Util.rep_na(getattr(test, 'HPL', "")))
            line.append(Util.rep_na(getattr(test, 'LSL', "")))
            line.append(Util.rep_na(getattr(test, 'HSL', "")))
            line.append(Util.rep_na(getattr(test, 'LOL', "")))
            line.append(Util.rep_na(getattr(test, 'HOL', "")))
            line.append(Util.rep_na(getattr(test, 'LWL', "")))
            line.append(Util.rep_na(getattr(test, 'HWL', "")))
            # Convert all elements in line to strings before joining
            line = [str(element) for element in line]
            result.append(",".join(line))
        return "\n".join(result) + "\n"
   
    def limit_to_string_with_conditions(self):
        """
        Converts limit data with conditions to a string.
        """
        limit = self.model.limit
        tests = limit.tests
        strings = []
        for test in tests:
            line = [Util.rep_na(getattr(test, item, None)) for item in limit.testItems]
            line.extend([Util.rep_na(cond) for cond in getattr(test, 'conditions', [])])
            # Convert all elements to string to avoid TypeError during join
            line = [str(element) for element in line]
            strings.append(",".join(line))
        return "\n".join(strings) + "\n"
