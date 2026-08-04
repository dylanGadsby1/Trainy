import json

with open("/Users/dylangadsby/.gemini/antigravity/brain/89822dba-9aa5-4e4a-9373-4942009a808e/.system_generated/steps/738/content.md", "r") as f:
    lines = f.readlines()

in_paths = False
for line in lines:
    if line.startswith('paths:'):
        in_paths = True
        continue
    if in_paths:
        if line.startswith('  /') and not line.startswith('    '):
            print(line.strip())
        elif line.startswith('components:'):
            break
