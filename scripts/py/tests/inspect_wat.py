
import os
path = r'c:\Users\fg8n8x\Desktop\eta\eta_1_15\eta_master\RGAAK2000.WAT'
print(f"Checking file: {path}")
if not os.path.exists(path):
    print("File does not exist!")
else:
    with open(path, 'r', encoding='latin-1') as f:
        lines = f.readlines()
        print(f"Total lines: {len(lines)}")
        for i in [5, 7]: # Lines 6 and 8 (0-indexed)
            if i < len(lines):
                line = lines[i]
                print(f"Line {i+1}: '{line.rstrip()}'")
                print("Indices:")
                for idx, char in enumerate(line[:60]):
                    print(f"{idx:2}: '{char}'", end=" | ")
                    if (idx + 1) % 5 == 0:
                        print()
                print("\n" + "-"*50)
            else:
                print(f"Line {i+1} out of range!")
