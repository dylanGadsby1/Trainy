import os

file_path = "/Users/dylangadsby/Trainy/Trainy/ContentView.swift"

with open(file_path, "r") as f:
    lines = f.readlines()

start_idx = -1
end_idx = -1

for i, line in enumerate(lines):
    if "// MARK: - Congestion Card (Card A)" in line:
        start_idx = i
    if "// MARK: - Arrival Context Card" in line:
        end_idx = i
        break

if start_idx != -1 and end_idx != -1:
    del lines[start_idx:end_idx]

with open(file_path, "w") as f:
    f.writelines(lines)
