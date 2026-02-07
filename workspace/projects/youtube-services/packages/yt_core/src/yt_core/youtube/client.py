"""YouTube Data API client"""

from typing import List, Dict, Optional
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError
import structlog

logger = structlog.get_logger()


class YouTubeClient:
    """
    YouTube Data API v3 client.

    Handles playlist expansion, video metadata fetching,
    and channel discovery.
    """

    def __init__(self, api_key: str):
        self.api_key = api_key
        self.youtube = build("youtube", "v3", developerKey=api_key)

    async def get_video_metadata(self, video_id: str) -> Optional[Dict]:
        """
        Fetch metadata for a single video.

        Args:
            video_id: YouTube video ID

        Returns:
            Dict with video metadata or None if not found

        Quota cost: 1 unit
        """
        try:
            request = self.youtube.videos().list(
                part="snippet,contentDetails", id=video_id
            )
            response = request.execute()

            if not response.get("items"):
                logger.warning("youtube.video_not_found", video_id=video_id)
                return None

            item = response["items"][0]
            snippet = item["snippet"]
            content_details = item["contentDetails"]

            # Parse ISO 8601 duration (e.g., "PT4M13S" -> 253 seconds)
            duration = self._parse_duration(content_details["duration"])

            metadata = {
                "video_id": video_id,
                "title": snippet["title"],
                "channel_id": snippet["channelId"],
                "channel_name": snippet["channelTitle"],
                "published_at": snippet["publishedAt"],
                "duration_seconds": duration,
            }

            logger.info("youtube.video_metadata_fetched", video_id=video_id)
            return metadata

        except HttpError as e:
            logger.error(
                "youtube.api_error",
                video_id=video_id,
                status=e.resp.status,
                error=str(e),
            )
            raise

    async def get_playlist_videos(
        self, playlist_id: str, max_results: int = 500
    ) -> List[str]:
        """
        Get all video IDs from a playlist.

        Args:
            playlist_id: YouTube playlist ID
            max_results: Maximum number of videos to fetch

        Returns:
            List of video IDs

        Quota cost: 1 unit per 50 videos (uses pagination)
        """
        video_ids = []
        next_page_token = None

        try:
            while len(video_ids) < max_results:
                request = self.youtube.playlistItems().list(
                    part="contentDetails",
                    playlistId=playlist_id,
                    maxResults=min(50, max_results - len(video_ids)),
                    pageToken=next_page_token,
                )
                response = request.execute()

                for item in response.get("items", []):
                    video_id = item["contentDetails"]["videoId"]
                    video_ids.append(video_id)

                next_page_token = response.get("nextPageToken")
                if not next_page_token:
                    break

            logger.info(
                "youtube.playlist_expanded",
                playlist_id=playlist_id,
                video_count=len(video_ids),
            )
            return video_ids

        except HttpError as e:
            logger.error(
                "youtube.api_error",
                playlist_id=playlist_id,
                status=e.resp.status,
                error=str(e),
            )
            raise

    async def get_channel_uploads_playlist(self, channel_id: str) -> Optional[str]:
        """
        Get the uploads playlist ID for a channel.

        Args:
            channel_id: YouTube channel ID

        Returns:
            Uploads playlist ID or None if not found

        Quota cost: 1 unit
        """
        try:
            request = self.youtube.channels().list(
                part="contentDetails", id=channel_id
            )
            response = request.execute()

            if not response.get("items"):
                logger.warning("youtube.channel_not_found", channel_id=channel_id)
                return None

            uploads_playlist_id = response["items"][0]["contentDetails"][
                "relatedPlaylists"
            ]["uploads"]

            logger.info(
                "youtube.channel_uploads_found",
                channel_id=channel_id,
                uploads_playlist_id=uploads_playlist_id,
            )
            return uploads_playlist_id

        except HttpError as e:
            logger.error(
                "youtube.api_error",
                channel_id=channel_id,
                status=e.resp.status,
                error=str(e),
            )
            raise

    def _parse_duration(self, iso_duration: str) -> int:
        """
        Parse ISO 8601 duration to seconds.

        Args:
            iso_duration: ISO 8601 duration string (e.g., "PT4M13S")

        Returns:
            Duration in seconds
        """
        # Simple parser for PT format
        # PT4M13S -> 4*60 + 13 = 253 seconds
        duration = iso_duration.replace("PT", "")
        hours = 0
        minutes = 0
        seconds = 0

        if "H" in duration:
            hours_str, duration = duration.split("H")
            hours = int(hours_str)

        if "M" in duration:
            minutes_str, duration = duration.split("M")
            minutes = int(minutes_str)

        if "S" in duration:
            seconds_str = duration.replace("S", "")
            seconds = int(seconds_str)

        return hours * 3600 + minutes * 60 + seconds
