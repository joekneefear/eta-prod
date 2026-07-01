"""
SYNOPSIS
    Klarf 1.8 Parser (Industry Standard Refined)

DESCRIPTION
    KLA reference file (Klarf file) parser for version 1.8.
    Follows a hierarchical parsing pattern using a stack to handle nested Record blocks.
    Preserves data relationship (e.g., Lot -> Wafer -> Defect).

AUTHOR
    jgarcia

CHANGES
    2026-Feb-16 - initial
    2026-Feb-16 - hierarchical (stack-based) refactor for industry standards
"""

import re
import gzip
from lib.Log import Log

class Klarf18:
    def __init__(self):
        self.data = {}

    def parse(self, file_path):
        """
        Parses a Klarf 1.8 file and returns a nested dictionary of extracted data.
        """
        try:
            content = self._read_file(file_path)
            # Remove comments (/* ... */) if any
            content = re.sub(r'/\*.*?\*/', '', content, flags=re.DOTALL)

            # Tokenize the content
            # Order matters: Quoted strings first, then keywords, then braces, then everything else
            token_pattern = r'"(?:[^"\\]|\\.)*"|Record|Field|List|[{}";]|[^\s{}";]+'
            tokens = re.findall(token_pattern, content)
            
            # Clean tokens: remove leading/trailing quotes from the whole token if it's a quoted string
            tokens = [t.strip('"') if t.startswith('"') and t.endswith('"') else t for t in tokens]
            
            stack = [self.data]
            current_context = self.data
            
            i = 0
            while i < len(tokens):
                token = tokens[i]
                
                if token == 'Record':
                    rec_name = tokens[i+1]
                    rec_val = tokens[i+2]
                    i += 3
                    
                    # Create new record context
                    new_rec = {"_val": rec_val, "_type": rec_name}
                    
                    # Store as both direct key and in a list for nested discovery
                    if rec_name in current_context:
                        if not isinstance(current_context[rec_name], list):
                            current_context[rec_name] = [current_context[rec_name]]
                        current_context[rec_name].append(new_rec)
                    else:
                        current_context[rec_name] = new_rec
                    
                    # Also keep a general records list for deep search
                    if "_records" not in current_context:
                        current_context["_records"] = []
                    current_context["_records"].append(new_rec)

                    if i < len(tokens) and tokens[i] == '{':
                        stack.append(new_rec)
                        current_context = new_rec
                        i += 1
                        
                elif token == 'Field':
                    field_name = tokens[i+1]
                    i += 3
                    if i < len(tokens) and tokens[i] == '{':
                        i += 1
                        val_start = i
                        brace_count = 1
                        while brace_count > 0 and i < len(tokens):
                            if tokens[i] == '{': brace_count += 1
                            elif tokens[i] == '}': brace_count -= 1
                            i += 1
                        
                        value_block = " ".join(tokens[val_start:i-1])
                        current_context[field_name] = self._parse_value_block(value_block)
                    else:
                        current_context[field_name] = tokens[i]
                        i += 1
                        
                elif token == '}':
                    if len(stack) > 1:
                        stack.pop()
                        current_context = stack[-1]
                    i += 1
                else:
                    i += 1

            return self.data

        except Exception as e:
            Log.ERROR(f"Error parsing Klarf 1.8 file {file_path}: {e}")
            raise

    def _read_file(self, file_path):
        if file_path.endswith('.gz'):
            with gzip.open(file_path, 'rt', encoding='utf-8', errors='ignore') as f:
                return f.read()
        else:
            with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
                return f.read()

    def _parse_value_block(self, block_str):
        """
        Parses the content inside a Field brace { ... }
        """
        # Split by whitespace but respect quotes
        vals = re.findall(r'"(?:[^"\\]|\\.)*"|[^\s,]+', block_str)
        return [v.strip('"') for v in vals]
