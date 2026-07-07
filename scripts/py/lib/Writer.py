"""
SYNOPSIS

DESCRIPTION
    Writer

AUTHOR
    junifferallan.garcia@onsemi.com

CHANGES
    2023-Sep-06 - jgarcia - initial
    2023-Sep-14 - jgarcia - add replaced forSBox attribute to forced_sandbox
    2023-Oct-23 - jgarcia - updated outfile method to only append file ext to the basename if basename not ends with ext 
    2025-Aug-07 - jgarcia - timestamp in filename made optinal depending on the Writer initialization, defualt to True

LICENSE
    (C) onsemi 2023 All rights reserved.
"""

import os
import shutil
import gzip
import tempfile
from pathlib import Path
from datetime import datetime
from lib.Util import Util
from lib.Log import Log
import re
from datetime import datetime
from typing import Optional
import pandas as pd


class Writer:
    ATTRIBUTES = [
        'outdir', 'basename', 'ext', 'noMeta', 'noWMap', 'wmapIsEmpty',
        'forced_sandbox', 'FH', 'openedfile', 'tempfile', 'forkedfile', 'forkdir', 'qde',
        'gzipIFF', 'pplogger' 
    ]

    REQUIRED_ATTRIBUTES = ['outdir']

    def __init__(self, use_timestamp_in_filename=True, site=None, script_name=None, **kwargs):
        """
        use_timestamp_in_filename: bool - If True, append timestamp to basename. Defaults to True for backward compatibility.
        site: Optional[str] - Optionally used for site-specific filename rules.
        script_name: Optional[str] - Optionally used for script-specific filename rules.
        """
        self.use_timestamp_in_filename = use_timestamp_in_filename
        self.site = site
        self.script_name = script_name
        self.validate_attributes(kwargs)
        for attr in self.ATTRIBUTES:
            setattr(self, attr, kwargs.get(attr, None))
        self.set_timestamp_to_basename()

 
    def validate_attributes(self, kwargs):
        """
        validate required attributes
        """
        for attr in self.REQUIRED_ATTRIBUTES:
            if attr not in kwargs or kwargs[attr] is None:
                #raise ValueError(f"'{attr}' is a required field and must have a value.")
                Util.dp_exit(1, f"'{attr}' is a required field and must have a value.")
    
    def should_apply_timestamp(self):
        """
        Returns True if timestamp should be applied to basename, according to use_timestamp_in_filename and optional site/script_name rules.
        """
        skip_sites = set() 
        skip_scripts = set() 
        if self.site and self.site in skip_sites:
            return False
        if self.script_name and self.script_name in skip_scripts:
            return False
        return self.use_timestamp_in_filename
    
    def set_timestamp_to_basename(self):
        """
        Append timestamp to basename if should_apply_timestamp() returns True.
        Timestamp is added between basename and extension, regardless of dots in basename.
        """
        if self.basename is not None and self.ext is not None and self.should_apply_timestamp():
            date_time = Util.get_logging_time()
            # Simply append timestamp to basename without parsing it
            self.basename = f'{self.basename}_{date_time}'
                
    def outfile(self):
        if self.basename is None or self.ext is None:
            Log.ERROR(f"outfile basename or extension is not defined")
            Util.dp_exit(1, "outfile basename or extension is not defined")

        if self.noWMap:
            if not self.ext.endswith('_nc'):
                self.ext += '_nc'

        if self.noMeta or self.wmapIsEmpty or self.forced_sandbox:
            outdir = os.path.join(self.outdir, "SANDBOX")
            self.set_output_directory_to_pplogger(outdir)
            Log.INFO(f"to SANDBOX schema")
        elif self.qde:
            outdir = os.path.join(self.outdir, "QDE")
            self.set_output_directory_to_pplogger(outdir)
            Log.INFO(f"to QDE schema")
        else:
            outdir = os.path.join(self.outdir, "PRODUCTION")
            self.set_output_directory_to_pplogger(outdir)
            Log.INFO(f"to PRODUCTION schema")
            if self.ext.endswith('lot'):
                outdir = self.outdir

        if not os.path.exists(outdir):
            os.makedirs(outdir)

        # Check if self.ext is not already in self.basename
        if self.ext not in self.basename:
            filename = f"{self.basename}.{self.ext}"
        else:
            filename = self.basename
            
        # Remove '.gz' or '.zip' from the extension in the filename
        filename = filename.replace('.gz', '')

        return os.path.join(outdir, filename)

    def get_fork_file(self):
        if self.basename is None or self.ext is None:
            Log.ERROR(f"forkfile basename or extension is not defined")
            Util.dpExit(1,"forkfile basename or extension is not defined")

        if self.noMeta or self.wmapIsEmpty or self.forced_sandbox:
            fork_directory = os.path.join(self.forkdir, "SANDBOX")
        elif self.qde:
            fork_directory = os.path.join(self.forkdir, "QDE")
        else:
            fork_directory = os.path.join(self.forkdir, "PRODUCTION")

        if not os.path.exists(fork_directory):
            os.makedirs(fork_directory)

        return os.path.join(fork_directory, f"{self.basename}.{self.ext}")

    def open(self):
        outfile = self.outfile()
        self.tempfile = outfile + ".tmp"
        self.FH = open(self.tempfile, "w")
        Log.INFO(f"outfile={self.tempfile} (will be renamed to {outfile})")
        self.openedfile = outfile

    def _path_exists(self, path):
        """Safely check path existence (handles None and non-path types)."""
        return isinstance(path, (str, bytes, os.PathLike)) and os.path.exists(path)

    def fsync_file(self, path):
        """Durably flush file contents to disk."""
        if not self._path_exists(path):
            return
        with open(path, 'rb') as f_sync:
            os.fsync(f_sync.fileno())

    def _fsync_dir(self, target_path):
        """Best-effort fsync for parent directory after atomic rename/replace."""
        directory = os.path.dirname(target_path) or '.'
        try:
            dir_fd = os.open(directory, os.O_RDONLY)
            try:
                os.fsync(dir_fd)
            finally:
                os.close(dir_fd)
        except Exception:
            # Best effort only (platform/filesystem dependent)
            pass

    def atomic_replace(self, src, dst):
        """Atomically replace dst with src and fsync parent dir (best effort)."""
        os.replace(src, dst)
        self._fsync_dir(dst)

    def put(self, data):
        if hasattr(self, 'FH'):
            if isinstance(data, pd.DataFrame):
                df_str = data.to_string()
                self.FH.write(df_str)
            else:
                self.FH.write(data)
        else:
            #raise ValueError("File not opened")
            Util.dp_exit(1, "file not found")

    def close(self):
        if hasattr(self, 'FH'):
            self.FH.flush()
            os.fsync(self.FH.fileno())
            self.FH.close()
            
            if self.forkdir:
                self.fork()
                
            if self.gzipIFF and not Util.is_gzipped(self.openedfile):
                self.compress_to_gzip_iff()
            else:
                if self._path_exists(getattr(self, 'tempfile', None)):
                    self.atomic_replace(self.tempfile, self.openedfile)
                    Log.INFO(f"renamed temp struct {self.tempfile} -> {self.openedfile}")
        else:
            #raise ValueError("File not opened")
            Util.dp_exit(1, "File not opened")

    def cancel(self):
        if hasattr(self, 'FH'):
            self.FH.close()
            if self._path_exists(getattr(self, 'tempfile', None)):
                os.remove(self.tempfile)
                Log.INFO(f"tempfile removed: {self.tempfile}")
            elif self._path_exists(getattr(self, 'openedfile', None)):
                os.remove(self.openedfile)
                Log.INFO(f"outfile removed: {self.openedfile}")
        else:
            #raise ValueError("File not opened")
            Util.dp_exit(1, "File not opened")
   
    def fork(self):
        if hasattr(self, 'openedfile'):
            source_file = self.tempfile if self._path_exists(getattr(self, 'tempfile', None)) else self.openedfile
            forkfile = self.get_fork_file()
            temp_forkfile = forkfile + ".tmp"
            with open(source_file, 'rb') as f_in, open(temp_forkfile, 'wb') as f_out:
                shutil.copyfileobj(f_in, f_out)
                f_out.flush()
                os.fsync(f_out.fileno())

            final_gz = forkfile + ".gz"
            final_dir = os.path.dirname(final_gz) or '.'
            fd, temp_gz = tempfile.mkstemp(prefix='.tmp_', suffix='.gz.tmp', dir=final_dir)
            os.close(fd)
            try:
                with open(source_file, 'rb') as f_in:
                    with open(temp_gz, 'wb') as raw_out:
                        # filename='' prevents the temp path from being embedded in the gzip header;
                        # decompressors (incl. Windows) then use the .gz file's own name as the output.
                        with gzip.GzipFile(filename='', mode='wb', fileobj=raw_out) as f_out:
                            shutil.copyfileobj(f_in, f_out)
                # fsync AFTER close so gzip footer (CRC32+size) is written first
                with open(temp_gz, 'rb') as f_sync:
                    os.fsync(f_sync.fileno())
                self.atomic_replace(temp_gz, final_gz)
                temp_gz = None
            finally:
                if temp_gz and os.path.exists(temp_gz):
                    os.remove(temp_gz)

            self.atomic_replace(temp_forkfile, forkfile)
            self.forkedfile = forkfile

    def compress_to_gzip_iff(self):
        """Compress the file with gzip if it's not already compressed."""
        source_file = self.tempfile if self._path_exists(getattr(self, 'tempfile', None)) else self.openedfile
        if not Util.is_gzipped(self.openedfile):
            output_filename = self.openedfile + '.gz' if not self.openedfile.endswith('.gz') else self.openedfile
            output_dir = os.path.dirname(output_filename) or '.'
            fd, temp_output = tempfile.mkstemp(prefix='.tmp_', suffix='.gz.tmp', dir=output_dir)
            os.close(fd)
            Log.INFO(f"compressing file={source_file} to local temp={temp_output}.")
            try:
                with open(source_file, 'rb') as f_in:
                    with open(temp_output, 'wb') as raw_out:
                        # filename='' prevents the temp path from being embedded in the gzip header;
                        # decompressors (incl. Windows) then use the .gz file's own name as the output.
                        with gzip.GzipFile(filename='', mode='wb', fileobj=raw_out) as f_out:
                            shutil.copyfileobj(f_in, f_out)
                # fsync AFTER close so gzip footer (CRC32+size) is written first
                with open(temp_output, 'rb') as f_sync:
                    os.fsync(f_sync.fileno())
                self.atomic_replace(temp_output, output_filename)
                temp_output = None
                Log.INFO(f"compressed to {output_filename}.")
                # Remove the uncompressed temp file
                Log.INFO(f"removed original uncompressed file={source_file}.")
                os.remove(source_file)
            finally:
                if temp_output and os.path.exists(temp_output):
                    os.remove(temp_output)
    
    def set_output_directory_to_pplogger(self, outdir):
        if outdir != "" and self.pplogger:
            self.pplogger.set_out_dir(outdir)

    
