import importlib.util
import io
import os
import pathlib
import tempfile
import unittest
from email.message import EmailMessage, Message


MODULE_PATH = pathlib.Path(__file__).with_name("email-to-khal.py")
SPEC = importlib.util.spec_from_file_location("email_to_khal", MODULE_PATH)
email_to_khal = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(email_to_khal)


def public_resolver(*_args, **_kwargs):
    return [(2, 1, 6, "", ("8.8.8.8", 443))]


def private_resolver(*_args, **_kwargs):
    return [(2, 1, 6, "", ("127.0.0.1", 443))]


class FakeResponse(io.BytesIO):
    def __init__(self, body=b"image", content_type="image/jpeg", length=None):
        super().__init__(body)
        self.headers = Message()
        self.headers["Content-Type"] = content_type
        self.headers["Content-Length"] = str(len(body) if length is None else length)

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        self.close()


class FakeOpener:
    def __init__(self, response):
        self.response = response
        self.calls = []

    def open(self, request, timeout):
        self.calls.append((request, timeout))
        return self.response


class EmailToKhalTests(unittest.TestCase):
    def test_review_draft_is_private_and_parseable(self):
        event = {
            "title": "Parent conference",
            "date": "2026-09-24",
            "time": "09:00",
            "duration": "30m",
            "timezone": "local",
            "location": "School",
            "calendar": "family",
            "description": "Bring notes",
        }
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "proposal.event"
            email_to_khal.write_review_draft(path, event, "Original text")
            self.assertEqual(os.stat(path).st_mode & 0o777, 0o600)
            self.assertEqual(email_to_khal._parse_template(path.read_text())["title"], event["title"])

    def test_chamber_image_mail_yields_partial_offline_proposal(self):
        subject = (
            "Business Before Hours - Tami Majszak Farmers Insurance - "
            "Thursday, October 1, 2026"
        )
        message = EmailMessage()
        message["Subject"] = subject
        message.set_content(
            """
            <html><body>
              <a href="https://t.e2ma.net/click/a/b/c">
                <img src="https://cdn.example/flyer.jpg" width="608" height="787" alt="">
              </a>
              <a href="https://social.example/">
                <img src="https://cdn.example/social.jpg" width="48" height="48" alt="Facebook">
              </a>
            </body></html>
            """,
            subtype="html",
        )

        fields = email_to_khal.parse_structured_fields(
            email_to_khal.extract_html_text(message),
            message,
        )
        date = email_to_khal.parse_date_only(subject)

        self.assertEqual(date.strftime("%Y-%m-%d"), "2026-10-01")
        self.assertEqual(
            email_to_khal.clean_event_title(subject),
            "Business Before Hours - Tami Majszak Farmers Insurance",
        )
        self.assertEqual(fields["link_label"], "Event page (tracked flyer)")
        self.assertEqual(fields["link"], "https://t.e2ma.net/click/a/b/c")
        self.assertNotIn("location", fields)
        self.assertEqual(
            email_to_khal.extract_remote_flyer(message),
            "https://cdn.example/flyer.jpg",
        )

    def test_school_compact_range_is_preserved(self):
        text = "Back to School Night 5:30p-6:30p 9/17/26"
        fields = email_to_khal.parse_structured_fields(text)
        dt, _ = email_to_khal.parse_datetime(fields, text)

        self.assertEqual(dt.strftime("%Y-%m-%d %H:%M"), "2026-09-17 17:30")
        self.assertEqual(fields["duration_min"], 60)

    def test_ocr_range_and_address_are_extracted(self):
        text = """BUSINESS BEFORE HOURS
7:30AM - 8:30AM
Thursday, October 1, 2026
610 Boardwalk Ave., Ste. 103
Members: Included with Membership | Non-Members: $25
h Qzeman Area Chamber"""
        fields = email_to_khal.parse_structured_fields(text)
        fields["location"] = email_to_khal.extract_street_address(text)
        date = email_to_khal.parse_date_only(text)
        fields.setdefault("date_raw", date.strftime("%Y-%m-%d"))
        dt, _ = email_to_khal.parse_datetime(fields, text)

        self.assertEqual(dt.strftime("%Y-%m-%d %H:%M"), "2026-10-01 07:30")
        self.assertEqual(fields["duration_min"], 60)
        self.assertEqual(fields["location"], "610 Boardwalk Ave., Ste. 103")

    def test_price_and_ocr_noise_do_not_become_duration(self):
        fields = email_to_khal.parse_structured_fields("Cost: $25\nh Qzeman")
        self.assertNotIn("duration_min", fields)

    def test_remote_image_policy_rejects_unsafe_targets(self):
        self.assertTrue(email_to_khal.public_https_image_url(
            "https://cdn.example/flyer.jpg",
            public_resolver,
        ))
        self.assertFalse(email_to_khal.public_https_image_url(
            "http://cdn.example/flyer.jpg",
            public_resolver,
        ))
        self.assertFalse(email_to_khal.public_https_image_url(
            "https://127.0.0.1/flyer.jpg",
            private_resolver,
        ))
        self.assertFalse(email_to_khal.public_https_image_url(
            "https://cdn.example:bad/flyer.jpg",
            public_resolver,
        ))

    def test_remote_image_fetch_is_single_and_bounded(self):
        opener = FakeOpener(FakeResponse(body=b"jpeg"))
        result = email_to_khal.fetch_remote_image(
            "https://cdn.example/flyer.jpg",
            resolver=public_resolver,
            opener=opener,
        )
        self.assertEqual(result, b"jpeg")
        self.assertEqual(len(opener.calls), 1)
        self.assertEqual(
            opener.calls[0][1],
            email_to_khal.REMOTE_IMAGE_TIMEOUT_SECONDS,
        )

        oversized = FakeOpener(FakeResponse(
            length=email_to_khal.MAX_REMOTE_IMAGE_BYTES + 1,
        ))
        with self.assertRaisesRegex(ValueError, "larger than 8 MiB"):
            email_to_khal.fetch_remote_image(
                "https://cdn.example/flyer.jpg",
                resolver=public_resolver,
                opener=oversized,
            )
        self.assertEqual(len(oversized.calls), 1)

    def test_redirect_handler_refuses_redirects(self):
        handler = email_to_khal.NoRedirect()
        self.assertIsNone(handler.redirect_request(
            None, None, 302, "Found", {}, "https://other.example/",
        ))


if __name__ == "__main__":
    unittest.main()
