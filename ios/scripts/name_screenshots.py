import json
import pathlib
import re
import shutil
import sys

root = pathlib.Path(sys.argv[1])
for test in json.loads((root / 'manifest.json').read_text()):
    for attachment in test.get('attachments', []):
        name = re.sub(r'_\d+_[0-9A-Fa-f-]{36}(?=\.png$)', '', attachment.get('suggestedHumanReadableName', ''))
        if name.endswith('.png'):
            shutil.copyfile(root / attachment['exportedFileName'], root / name)
