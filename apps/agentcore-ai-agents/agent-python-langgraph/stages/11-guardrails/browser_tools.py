import logging
import os

import boto3
from bedrock_agentcore.tools.browser_client import browser_session
from playwright.async_api import async_playwright
from langchain_core.tools import tool

import artifacts
# >> Import the guardrail check for web pages
import guardrail
# <<

log = logging.getLogger(__name__)
REGION = os.environ.get("AWS_REGION") or boto3.session.Session().region_name


async def open_page(url, action):
    with browser_session(REGION) as client:
        ws_url, headers = client.generate_ws_headers()
        async with async_playwright() as playwright:
            browser = await playwright.chromium.connect_over_cdp(ws_url, headers=headers)
            try:
                context = browser.contexts[0] if browser.contexts else await browser.new_context()
                page = context.pages[0] if context.pages else await context.new_page()
                log.info("Navigating to: %s", url)
                await page.goto(url, wait_until="domcontentloaded", timeout=60000)
                return await action(page)
            finally:
                await browser.close()


@tool(parse_docstring=True)
async def browse_url(url: str) -> str:
    """Browse a web page and extract its text content. Returns the page title and body text. Use this to read and extract data from websites.

    Args:
        url: The URL to open
    """
    async def read(page):
        text = await page.inner_text("body")
        # >> Check the page text with the guardrail before the model reads it
        return guardrail.check_content(f"Title: {await page.title()}\n\n{text[:20000]}")
        # <<

    return await open_page(url, read)


@tool(parse_docstring=True)
async def take_screenshot(url: str) -> str:
    """Take a screenshot of a web page for the user to see. Does NOT return page content to you. Use browse_url to extract data first, then take_screenshot for visual evidence.

    Args:
        url: The URL to capture
    """
    async def capture(page):
        png = await page.screenshot()
        artifacts.store("screenshot.png", png, "image/png")
        log.info("Screenshot taken: %d bytes", len(png))
        return "Screenshot taken. It is shown to the user below your answer."

    return await open_page(url, capture)
