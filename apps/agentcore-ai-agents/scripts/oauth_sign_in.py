"""Sign in on a Cognito hosted UI (managed login version 1) for an AgentCore Identity consent link, as a user
would in the browser, and print the session_id that AgentCore appends to the return URL. For the terminal tests.

Usage: uv run --no-project --with requests oauth_sign_in.py AUTHORIZATION_URL USERNAME PASSWORD
"""
import html
import re
import sys
from urllib.parse import parse_qs, urljoin, urlparse

import requests

url, username, password = sys.argv[1:4]
session = requests.Session()
page = session.get(url, timeout=30)
form = re.search(r'<form[^>]*action="([^"]*)"[^>]*>(.*?)</form>', page.text, re.S)
if not form:
    sys.exit(f"no sign-in form at {urlparse(page.url).netloc}")
fields = dict(re.findall(r'<input[^>]*name="([^"]+)"[^>]*value="([^"]*)"', form.group(2)))
fields.update(username=username, password=password, signInSubmitButton="Sign in")
# Follow the redirects (Cognito -> AgentCore callback -> return URL) without loading the return page itself
response = session.post(urljoin(page.url, html.unescape(form.group(1))), data=fields, timeout=30, allow_redirects=False)
for _ in range(10):
    location = response.headers.get("Location")
    if not location:
        break
    location = urljoin(response.url, location)
    found = parse_qs(urlparse(location).query).get("session_id")
    if found:
        print(found[0])
        sys.exit(0)
    response = session.get(location, timeout=30, allow_redirects=False)
sys.exit(f"no session_id in the redirects (last status {response.status_code})")
