"""
SYNOPSIS

DESCRIPTION
    Wmap class

AUTHOR
    junifferallan.garcia@onsemi.com

CHANGES
    2024-Sept-3 - jgarcia - initial

LICENSE
    (C) onsemi 2024 All rights reserved.
"""

from dataclasses import dataclass, field
from lib.Data.Base import Base
from lib.Log import Log
# from lib.Util import Util
import math

@dataclass
class Wmap:
    stats: dict = field(default_factory=dict)
    center_x: int = None
    center_y: int = None
    id: int = None
    status: str = None
    product: str = None
    wf_units: str = None
    wf_size: float = None
    flat_type: str = None
    flat: str = None
    die_width: float = None
    die_height: float = None
    center_x_coord: float = None
    center_y_coord: float = None
    positive_x: str = None
    positive_y: str = None
    reticle_rows: int = None
    reticle_cols: int = None
    reticle_row_offset: int = None
    reticle_col_offset: int = None
    confirmed: bool = None
    device_count: int = None
    confirm_time: str = None
    comments: str = None
    insert_time: str = None
    input_file: str = None
    cfg_id: int = None
    location: str = None
    ref_die_x: int = None
    ref_die_y: int = None
    ref_die_init_dt: str = None
    wmc_device: str = None
    error_message: str = None

    def calculate_center_die(self):
        minX = self.stats['minX']
        minY = self.stats['minY']
        maxX = self.stats['maxX']
        maxY = self.stats['maxY']
        Log.INFO(f"DIE Range Column: {minX} -- {maxX} Rows: {minY} -- {maxY}")
        Log.INFO(f"DIE Size Width={self.die_width} Height={self.die_height}")
        
        numX = maxX - minX + 1
        numY = maxY - minY + 1
        diamX = numX * self.die_width
        diamY = numY * self.die_height
        
        # Calculate diameter and radius based on flat type
        radius = diamX / 2.0 if self.flat in ['B', 'T'] else diamY / 2.0
        
        distanceX = radius
        distanceY = radius
        centerX = math.ceil(numX / 2.0)
        centerY = math.ceil(numY / 2.0)
        
        # Adjust center based on flat type
        if self.flat_type == 'F':
            if self.flat == 'T':
                distanceY = diamY - radius
            elif self.flat == 'L':  # Changed to elif for clarity
                distanceX = diamX - radius
            # Log wafersize information
            Log.INFO(f"FLAT = {self.flat}, diamX = {diamX}, diamY = {diamY}, radius = {radius} wafersize = {self.wf_size} {self.wf_units}")
            centerX = math.ceil(distanceX / self.die_width)
            centerY = math.ceil(distanceY / self.die_height)
        
        if (numX % 2 == 0) and self.positive_x == 'R':
            centerX += 1
        if (numY % 2 == 0) and self.positive_y == 'U':
            centerY += 1
        
        # Log final center positions
        Log.INFO(f"relative center X = {centerX} Y = {centerY}")
        Log.INFO(f"absolute center X = {minX + centerX - 1} Y = {minY + centerY - 1}")
        
        # Update center positions
        self.center_x = minX + centerX - 1
        self.center_y = minY + centerY - 1