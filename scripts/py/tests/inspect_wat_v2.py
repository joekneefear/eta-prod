
path = r'c:\Users\fg8n8x\Desktop\eta\eta_1_15\eta_master\RGAAK2000.WAT'
out_path = 'inspect_output.txt'
with open(path, 'r', encoding='latin-1') as f:
    lines = f.readlines()
    with open(out_path, 'w') as out:
        for i in [5, 7]: # Lines 6 and 8
            line = lines[i]
            out.write(f"Line {i+1}: '{line.rstrip()}'\n")
            out.write("Indices:\n")
            for idx, char in enumerate(line[:100]):
                out.write(f"{idx:2}: '{char}' | ")
                if (idx + 1) % 5 == 0:
                    out.write("\n")
            out.write("\n" + "-"*50 + "\n")
print(f"Done. Results in {out_path}")
