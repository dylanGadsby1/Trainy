import urllib.request
import json

url = "https://data.rtt.io/api/gb-nr/location?code=EUS&filterTo=MAN&detailed=true&timeWindow=1439"
req = urllib.request.Request(url)
# Read token from RTTService.swift manually or use the one we can get:
# Actually we can just run one of the existing python scripts.
