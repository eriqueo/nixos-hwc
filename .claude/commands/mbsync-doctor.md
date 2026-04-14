Diagnose mbsync mail sync issues. Run these checks and report findings:

1. Check mbsync service status: `systemctl --user status mbsync.service mbsync.timer`
2. Check Proton Bridge status: `systemctl --user status protonmail-bridge.service`
3. Get recent mbsync logs: `journalctl --user -u mbsync.service --since "1 hour ago" | tail -60`
4. Get Proton Bridge error logs: `journalctl --user -u protonmail-bridge.service --since "1 hour ago" | grep -i 'erro\|warn' | tail -20`
5. Count messages stuck in Labels new/ dirs: `find ~/400_mail/Maildir/proton/Labels -path '*/new/*' -type f | wc -l`
6. Show per-label breakdown of stuck messages: `find ~/400_mail/Maildir/proton/Labels -path '*/new/*' -type f | sed 's|.*/Labels/||;s|/new/.*||' | sort | uniq -c | sort -rn`

Report: service status, any errors, stuck message counts, and recommended actions.
