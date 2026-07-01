#!/usr/bin/env python3
"""
E142 Module Trace Extraction Manager
Supports: cron automation, manual runs, historical date extraction

AUTHOR
  junifferallan.garcia@onsemi.com

CHANGES
    2026-Mar-06 - initial implementation

"""

import os
import sys
import subprocess
import argparse
import yaml
import json
import logging
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List, Optional, Tuple
import re

class E142ExtractionManager:
    """Manages E142 extraction across multiple facilities and modes"""
    
    def __init__(self, config_file: Optional[str] = None):
        # Default config location relative to this script
        if config_file is None:
            script_dir = Path(__file__).parent
            config_file = str(script_dir / 'resources' / 'e142_extraction_config.yaml')
        
        self.config_file = config_file
        self.config = self._load_config()
        
        # Get Perl script path from config
        script_dir = self.config['paths']['script_dir']
        self.script_path = self._resolve_path(f"{script_dir}/getSnowflakeE142ModuleTrace.pl")
        
    def _load_config(self) -> Dict:
        """Load and parse configuration file"""
        config_path = Path(self.config_file)
        if not config_path.exists():
            raise FileNotFoundError(f"Config file not found: {self.config_file}")
        
        with open(config_path, 'r') as f:
            config = yaml.safe_load(f)
        
        # Expand environment variables in paths
        config = self._expand_env_vars(config)
        return config
    
    def _expand_env_vars(self, obj):
        """Recursively expand environment variables in config"""
        if isinstance(obj, dict):
            return {k: self._expand_env_vars(v) for k, v in obj.items()}
        elif isinstance(obj, list):
            return [self._expand_env_vars(item) for item in obj]
        elif isinstance(obj, str):
            return os.path.expandvars(obj)
        return obj
    
    def _resolve_path(self, path: str) -> str:
        """Resolve path with environment variables"""
        return os.path.expandvars(path)

    def _atomic_write_text(self, path: str, content: str):
        target = Path(path)
        target.parent.mkdir(parents=True, exist_ok=True)
        temp_path = str(target) + ".tmp"
        try:
            with open(temp_path, 'w', encoding='utf-8') as f:
                f.write(content)
                f.flush()
                os.fsync(f.fileno())
            os.replace(temp_path, str(target))
        except Exception:
            if Path(temp_path).exists():
                Path(temp_path).unlink()
            raise
    
    def setup_logging(self, facility: str, stage: str, mode: str = 'cron') -> Path:
        """Setup logging for extraction run"""
        log_dir = Path(self._resolve_path(self.config['paths']['log_dir']))
        log_dir.mkdir(parents=True, exist_ok=True)
        
        timestamp = datetime.now().strftime('%Y-%m-%d_%H:%M:%S')
        log_file = log_dir / f"getSnowflakeE142ModuleTrace.{facility}.{stage}.{timestamp}.log"
        
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler(log_file),
                logging.StreamHandler(sys.stdout)
            ]
        )
        
        return log_file
    
    def validate_environment(self) -> bool:
        """Validate required environment variables"""
        required_vars = ['SNOW_USER', 'SNOW_PASS']
        missing = [var for var in required_vars if not os.getenv(var)]
        
        if missing:
            logging.error(f"Missing environment variables: {', '.join(missing)}")
            return False
        
        return True
    
    def get_facility_config(self, facility: str) -> Optional[Dict]:
        """Get configuration for a specific facility"""
        return self.config['facilities'].get(facility)
    
    def list_facilities(self) -> List[str]:
        """List all configured facilities"""
        return list(self.config['facilities'].keys())
    
    def build_command(self, facility: str, stage: str, 
                     modfile: Optional[str] = None,
                     start_date: Optional[str] = None,
                     end_date: Optional[str] = None,
                     max_hours: Optional[int] = None,
                     out_trace: Optional[str] = None) -> Tuple[List[str], str, str]:
        """Build Perl command for extraction"""
        
        fac_config = self.get_facility_config(facility)
        if not fac_config:
            raise ValueError(f"Unknown facility: {facility}")
        
        stage_config = fac_config['stages'].get(stage)
        if not stage_config:
            raise ValueError(f"Unknown stage: {stage} for facility: {facility}")
        
        defaults = self.config['defaults']
        
        # Determine modfile
        if modfile:
            modfile_path = modfile
        elif start_date:
            # Create temporary modfile for historical extraction
            modfile_path = f"/tmp/modfile_{facility}_{stage}_{start_date.replace('-', '')}.txt"
        else:
            # Use configured modfile for cron mode
            modfile_path = stage_config['modfile']
        
        # Build log file path
        timestamp = datetime.now().strftime('%Y-%m-%d_%H:%M:%S')
        log_dir = self._resolve_path(self.config['paths']['log_dir'])
        logfile = f"{log_dir}/getSnowflakeE142ModuleTrace.{facility}.{stage}.{timestamp}.log"
        
        # Get Perl interpreter from config (default: perl_db)
        perl_interpreter = self.config['paths'].get('perl_interpreter', 'perl_db')
        
        # Determine output trace directory
        output_trace = out_trace or fac_config.get('out_trace')
        if not output_trace:
            raise ValueError(f"Output trace directory not defined for facility: {facility}")

        # Build command
        cmd = [
            perl_interpreter, self.script_path,
            '--source_odbc', defaults['source_odbc'],
            '--source_warehouse', defaults['source_warehouse'],
            '--source_schema', defaults['source_schema'],
            '--view_name', fac_config['view_name'],
            '--flow', fac_config['flow'],
            '--stage', stage,
            '--modfile', modfile_path,
            '--max_hours', str(max_hours or defaults['max_hours']),
            '--out_trace', output_trace,
            '--logfile', logfile,
            '--pipeline_name', f"E142_{facility}_{fac_config['flow']}_{stage}",
        ]
        
        # Add optional parameters
        if defaults.get('get_product'):
            cmd.append('--get_product')
        
        if defaults.get('prod_not_regexp'):
            cmd.extend(['--prod_not_regexp', defaults['prod_not_regexp']])
        
        if defaults.get('benchmark_log'):
            benchmark_log = self._resolve_path(defaults['benchmark_log'])
            cmd.extend(['--benchmark_log', benchmark_log])
        
        if defaults.get('benchmark_db_dsn'):
            cmd.extend(['--benchmark_db_dsn', defaults['benchmark_db_dsn']])
            if defaults.get('benchmark_db_user'):
                cmd.append('--benchmark_db_user')
        
        return cmd, modfile_path, logfile
    
    def create_modfile(self, path: str, timestamp: str):
        """Create modfile with timestamp"""
        self._atomic_write_text(path, f"{timestamp}\n")
        logging.debug(f"Created modfile: {path} with timestamp: {timestamp}")
    
    def run_extraction(self, facility: str, stage: str,
                      modfile: Optional[str] = None,
                      start_date: Optional[str] = None,
                      max_hours: Optional[int] = None,
                      out_trace: Optional[str] = None) -> Tuple[bool, str]:
        """Run extraction for a facility/stage"""
        
        logging.info(f"{'='*60}")
        logging.info(f"Extraction: {facility} - {stage}")
        logging.info(f"{'='*60}")
        
        try:
            cmd, modfile_path, logfile = self.build_command(
                facility, stage, modfile, start_date, None, max_hours, out_trace
            )
            
            # Create modfile if start_date provided
            if start_date and not modfile:
                self.create_modfile(modfile_path, f"{start_date} 00:00:00")
            
            logging.info(f"Command: {' '.join(cmd)}")
            
            # Set up environment for Perl script
            # Add scripts/lib to PERL5LIB so FindBin::libs or use lib can find PDF modules
            env = os.environ.copy()
            script_dir = self.config['paths']['script_dir']
            perl_lib = self._resolve_path(f"{script_dir}/lib")
            
            # Add to PERL5LIB (append to existing if present)
            if 'PERL5LIB' in env:
                env['PERL5LIB'] = f"{perl_lib}:{env['PERL5LIB']}"
            else:
                env['PERL5LIB'] = perl_lib
            
            logging.debug(f"PERL5LIB set to: {env['PERL5LIB']}")
            
            # Run extraction
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=7200,  # 2 hour timeout
                env=env  # Pass modified environment
            )
            
            if result.returncode == 0:
                logging.info(f"✓ SUCCESS: {facility} - {stage}")
                return True, logfile
            else:
                logging.error(f"✗ FAILED: {facility} - {stage} (exit: {result.returncode})")
                if result.stderr:
                    logging.error(f"Error: {result.stderr[:500]}")
                return False, logfile
                
        except subprocess.TimeoutExpired:
            logging.error(f"✗ TIMEOUT: {facility} - {stage}")
            return False, logfile
        except Exception as e:
            logging.error(f"✗ EXCEPTION: {facility} - {stage} - {e}")
            return False, logfile
        finally:
            # Cleanup temporary modfile
            # if start_date and not modfile and Path(modfile_path).exists():
            #     Path(modfile_path).unlink()
            pass
    
    def run_cron_mode(self, facility: str, stage: str):
        """Run in cron mode (uses configured modfile)"""
        log_file = self.setup_logging(facility, stage, 'cron')
        logging.info(f"Running in CRON mode - Log: {log_file}")
        
        if not self.validate_environment():
            sys.exit(1)
        
        success, _ = self.run_extraction(facility, stage)
        sys.exit(0 if success else 1)
    
    def run_manual_mode(self, facility: str, stage: str, 
                       modfile: Optional[str] = None,
                       max_hours: Optional[int] = None,
                       out_trace: Optional[str] = None):
        """Run in manual mode (custom modfile or default)"""
        log_file = self.setup_logging(facility, stage, 'manual')
        logging.info(f"Running in MANUAL mode - Log: {log_file}")
        
        if not self.validate_environment():
            sys.exit(1)
        
        success, _ = self.run_extraction(facility, stage, modfile, None, max_hours, out_trace)
        sys.exit(0 if success else 1)
    
    def run_historical_mode(self, facility: str, stage: str,
                           start_date: str, end_date: str,
                           max_hours: int = 24,
                           out_trace: Optional[str] = None):
        """Run historical extraction for date range"""
        log_file = self.setup_logging(facility, stage, 'historical')
        logging.info(f"Running in HISTORICAL mode - Log: {log_file}")
        logging.info(f"Date range: {start_date} to {end_date}")
        
        if not self.validate_environment():
            sys.exit(1)
        
        # Parse dates
        try:
            start = datetime.strptime(start_date, '%Y-%m-%d')
            end = datetime.strptime(end_date, '%Y-%m-%d')
        except ValueError as e:
            logging.error(f"Invalid date format: {e}")
            sys.exit(1)
        
        # Generate date range
        dates = []
        current = start
        while current <= end:
            dates.append(current)
            current += timedelta(days=1)
        
        total_days = len(dates)
        logging.info(f"Processing {total_days} days")
        
        # Run extractions
        results = []
        success_count = 0
        fail_count = 0
        
        for i, date in enumerate(dates, 1):
            date_str = date.strftime('%Y-%m-%d')
            logging.info(f"\n[{i}/{total_days}] Processing: {date_str}")
            
            success, logfile = self.run_extraction(
                facility, stage, None, date_str, max_hours, out_trace
            )
            
            results.append({
                'date': date_str,
                'success': success,
                'logfile': logfile
            })
            
            if success:
                success_count += 1
            else:
                fail_count += 1
        
        # Summary
        logging.info(f"\n{'='*60}")
        logging.info(f"Historical Extraction Complete")
        logging.info(f"{'='*60}")
        logging.info(f"Total days: {total_days}")
        logging.info(f"Success: {success_count}")
        logging.info(f"Failed: {fail_count}")
        
        if fail_count > 0:
            logging.warning("\nFailed dates:")
            for r in results:
                if not r['success']:
                    logging.warning(f"  - {r['date']}")
        
        sys.exit(0 if fail_count == 0 else 1)
    
    def run_all_facilities(self, stage: Optional[str] = None):
        """Run extraction for all configured facilities"""
        facilities = self.list_facilities()
        
        logging.info(f"Running extraction for all facilities: {', '.join(facilities)}")
        
        results = []
        for facility in facilities:
            fac_config = self.get_facility_config(facility)
            stages = [stage] if stage else list(fac_config['stages'].keys())
            
            for stg in stages:
                if fac_config['stages'][stg].get('enabled', True):
                    success, logfile = self.run_extraction(facility, stg)
                    results.append({
                        'facility': facility,
                        'stage': stg,
                        'success': success,
                        'logfile': logfile
                    })
        
        # Summary
        success_count = sum(1 for r in results if r['success'])
        fail_count = len(results) - success_count
        
        logging.info(f"\n{'='*60}")
        logging.info(f"All Facilities Complete")
        logging.info(f"Total runs: {len(results)}")
        logging.info(f"Success: {success_count}")
        logging.info(f"Failed: {fail_count}")
        
        sys.exit(0 if fail_count == 0 else 1)
    
    def generate_crontab(self, output_file: Optional[str] = None):
        """Generate crontab entries from configuration"""
        lines = []
        lines.append("# E142 Extraction Cron Jobs")
        lines.append("# Generated: " + datetime.now().strftime('%Y-%m-%d %H:%M:%S'))
        lines.append("")
        
        script_path = Path(__file__).absolute()
        
        for facility, fac_config in self.config['facilities'].items():
            lines.append(f"# {fac_config['facility_name']}")
            
            for stage, stage_config in fac_config['stages'].items():
                if not stage_config.get('enabled', True):
                    continue
                
                schedule = stage_config.get('cron_schedule', '0 * * * *')
                
                cmd = (
                    f"{schedule} "
                    f". $HOME/.bashrc; "
                    f"python3 {script_path} cron "
                    f"--facility {facility} --stage {stage} "
                    f"> /dev/null 2>&1"
                )
                
                lines.append(cmd)
            
            lines.append("")
        
        crontab_content = '\n'.join(lines)
        
        if output_file:
            self._atomic_write_text(output_file, crontab_content)
            print(f"Crontab written to: {output_file}")
        else:
            print(crontab_content)
        
        return crontab_content


def main():
    parser = argparse.ArgumentParser(
        description='E142 Extraction Manager',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Execution Modes:

1. CRON Mode (automated, uses configured modfile):
   python e142_extraction_manager.py cron --facility VN5 --stage WAFER

2. MANUAL Mode (one-time run with custom or default modfile):
   python e142_extraction_manager.py manual --facility VN5 --stage WAFER
   python e142_extraction_manager.py manual --facility VN5 --stage WAFER --modfile /path/to/modfile.txt
   python e142_extraction_manager.py manual --facility VN5 --stage WAFER --max-hours 48

3. HISTORICAL Mode (date range extraction):
   python e142_extraction_manager.py historical --facility VN5 --stage WAFER \\
     --start-date 2026-02-10 --end-date 2026-02-20
   
   python e142_extraction_manager.py historical --facility VN5 --stage WAFER \\
     --start-date 2026-02-10 --end-date 2026-02-20 --max-hours 24

4. ALL Facilities:
   python e142_extraction_manager.py all --stage WAFER

5. Generate Crontab:
   python e142_extraction_manager.py generate-cron
   python e142_extraction_manager.py generate-cron --output crontab.txt

6. List Facilities:
   python e142_extraction_manager.py list

Examples:
  # Cron job for VN5 WAFER
  python e142_extraction_manager.py cron --facility VN5 --stage WAFER
  
  # Manual run for MY1 TEST
  python e142_extraction_manager.py manual --facility MY1 --stage TEST
  
  # Historical extraction for Feb 10-20
  python e142_extraction_manager.py historical --facility VN5 --stage WAFER \\
    --start-date 2026-02-10 --end-date 2026-02-20
  
  # Run all facilities for WAFER stage
  python e142_extraction_manager.py all --stage WAFER
        """
    )
    
    parser.add_argument('--config', 
                       help='Configuration file path (default: script_dir/resources/e142_extraction_config.yaml)')
    
    subparsers = parser.add_subparsers(dest='mode', help='Execution mode')
    
    # Cron mode
    cron_parser = subparsers.add_parser('cron', help='Run in cron mode')
    cron_parser.add_argument('--facility', required=True, help='Facility code')
    cron_parser.add_argument('--stage', required=True, help='Stage')
    
    # Manual mode
    manual_parser = subparsers.add_parser('manual', help='Run in manual mode')
    manual_parser.add_argument('--facility', required=True, help='Facility code')
    manual_parser.add_argument('--stage', required=True, help='Stage')
    manual_parser.add_argument('--modfile', help='Custom modfile path')
    manual_parser.add_argument('--max-hours', type=int, help='Max hours')
    manual_parser.add_argument('--out-trace', help='Custom output trace directory')
    
    # Historical mode
    hist_parser = subparsers.add_parser('historical', help='Run historical extraction')
    hist_parser.add_argument('--facility', required=True, help='Facility code')
    hist_parser.add_argument('--stage', required=True, help='Stage')
    hist_parser.add_argument('--start-date', required=True, help='Start date (YYYY-MM-DD)')
    hist_parser.add_argument('--end-date', required=True, help='End date (YYYY-MM-DD)')
    hist_parser.add_argument('--max-hours', type=int, default=24, help='Max hours per day')
    hist_parser.add_argument('--out-trace', help='Custom output trace directory')
    
    # All facilities mode
    all_parser = subparsers.add_parser('all', help='Run all facilities')
    all_parser.add_argument('--stage', help='Specific stage (optional)')
    
    # Generate crontab
    cron_gen_parser = subparsers.add_parser('generate-cron', help='Generate crontab')
    cron_gen_parser.add_argument('--output', help='Output file (default: stdout)')
    
    # List facilities
    subparsers.add_parser('list', help='List configured facilities')
    
    args = parser.parse_args()
    
    if not args.mode:
        parser.print_help()
        sys.exit(1)
    
    # Initialize manager
    try:
        manager = E142ExtractionManager(args.config)
    except Exception as e:
        print(f"Error loading configuration: {e}")
        sys.exit(1)
    
    # Execute based on mode
    if args.mode == 'cron':
        manager.run_cron_mode(args.facility, args.stage)
    
    elif args.mode == 'manual':
        manager.run_manual_mode(args.facility, args.stage, args.modfile, args.max_hours, args.out_trace)
    
    elif args.mode == 'historical':
        manager.run_historical_mode(
            args.facility, args.stage,
            args.start_date, args.end_date,
            args.max_hours,
            args.out_trace
        )
    
    elif args.mode == 'all':
        manager.run_all_facilities(args.stage)
    
    elif args.mode == 'generate-cron':
        manager.generate_crontab(args.output)
    
    elif args.mode == 'list':
        facilities = manager.list_facilities()
        print("Configured Facilities:")
        for fac in facilities:
            config = manager.get_facility_config(fac)
            print(f"  {fac}: {config['facility_name']} ({config['flow']})")
            for stage in config['stages'].keys():
                enabled = config['stages'][stage].get('enabled', True)
                status = "✓" if enabled else "✗"
                print(f"    {status} {stage}")

if __name__ == '__main__':
    main()
