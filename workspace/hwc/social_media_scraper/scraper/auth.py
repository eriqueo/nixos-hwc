"""Authentication handling for sites requiring login."""

from pathlib import Path

from playwright.sync_api import Page, TimeoutError as PlaywrightTimeoutError

from .config import get_auth_file_path
from .exceptions import AuthenticationError
from .logging_config import get_logger
from .models import SiteConfig


SECRETS_DIR = Path("/run/agenix")


def read_secret(secret_name: str) -> str | None:
    """
    Read a secret from agenix.

    Args:
        secret_name: Name of the secret (e.g., 'scraper-facebook-email')

    Returns:
        Secret value or None if not found
    """
    logger = get_logger()
    secret_path = SECRETS_DIR / secret_name

    if not secret_path.exists():
        logger.debug(f"Secret not found: {secret_path}")
        return None

    try:
        return secret_path.read_text().strip()
    except PermissionError:
        logger.warning(f"Permission denied reading secret: {secret_name}")
        logger.warning("Ensure your user is in the 'secrets' group")
        return None
    except Exception as e:
        logger.error(f"Error reading secret {secret_name}: {e}")
        return None


def perform_auto_login(page: Page, site_config: SiteConfig) -> bool:
    """
    Perform automatic login using stored credentials.

    Args:
        page: Playwright page instance
        site_config: Site configuration with login selectors

    Returns:
        True if login successful, False otherwise
    """
    logger = get_logger()

    if not site_config.login_url:
        logger.error("No login_url configured for auto-login")
        return False

    if not site_config.credential_email_secret or not site_config.credential_password_secret:
        logger.error("No credential secrets configured")
        return False

    # Read credentials from secrets
    email = read_secret(site_config.credential_email_secret)
    password = read_secret(site_config.credential_password_secret)

    if not email or not password:
        logger.error("Could not read credentials from secrets")
        logger.info("Run with --login for manual login instead")
        return False

    selectors = site_config.login_selectors
    if not selectors:
        logger.error("No login_selectors configured")
        return False

    logger.info(f"Performing auto-login to {site_config.name}")
    logger.info(f"Navigating to: {site_config.login_url}")

    try:
        # Navigate to login page
        page.goto(site_config.login_url, wait_until="networkidle")
        page.wait_for_timeout(2000)

        # Fill email
        email_selector = selectors.get("email_field")
        if email_selector:
            logger.debug(f"Filling email field: {email_selector}")
            page.fill(email_selector, email)
            page.wait_for_timeout(500)

        # Fill password
        password_selector = selectors.get("password_field")
        if password_selector:
            logger.debug(f"Filling password field: {password_selector}")
            page.fill(password_selector, password)
            page.wait_for_timeout(500)

        # Click submit
        submit_selector = selectors.get("submit_button")
        if submit_selector:
            logger.debug(f"Clicking submit: {submit_selector}")
            page.click(submit_selector)

        # Wait for navigation/login to complete
        logger.info("Waiting for login to complete...")
        page.wait_for_timeout(5000)

        # Check if login succeeded (basic check - not on login page anymore)
        current_url = page.url
        if "login" in current_url.lower():
            logger.warning("Still on login page - login may have failed")
            # Check for error messages
            error_el = page.query_selector('[role="alert"], .error, .login-error')
            if error_el:
                error_text = error_el.inner_text()
                logger.error(f"Login error: {error_text}")
            return False

        logger.info("Auto-login appears successful")
        return True

    except PlaywrightTimeoutError:
        logger.error("Timeout during auto-login")
        return False
    except Exception as e:
        logger.error(f"Auto-login failed: {e}")
        return False


def ensure_authenticated(
    page: Page,
    context,
    site_config: SiteConfig,
    auto_login: bool = True,
) -> bool:
    """
    Ensure user is authenticated for a site.

    Checks for saved auth state first, then attempts auto-login if enabled.

    Args:
        page: Playwright page instance
        context: Browser context (for saving state)
        site_config: Site configuration
        auto_login: Whether to attempt auto-login

    Returns:
        True if authenticated, False otherwise
    """
    logger = get_logger()
    auth_file = get_auth_file_path(site_config.name)

    # Check if we have saved auth
    if auth_file.exists():
        logger.info(f"Using saved authentication from {auth_file}")
        return True

    if not site_config.login_required:
        logger.debug(f"{site_config.name} does not require login")
        return True

    # Attempt auto-login
    if auto_login and site_config.credential_email_secret:
        success = perform_auto_login(page, site_config)
        if success:
            # Save auth state for future use
            logger.info(f"Saving authentication to {auth_file}")
            context.storage_state(path=str(auth_file))
            return True

    logger.warning(f"{site_config.name} requires login but no auth available")
    logger.info("Run with --login for manual login, or configure credentials")
    return False
