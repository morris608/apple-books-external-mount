-- One-click safe eject for the Books media drive.
on run
	set sh to "/Users/davidmorris/GitHub/apple-books-external-mount/scripts/books-media.sh"
	set statusFile to "/tmp/books-media.eject-status"
	set logFile to "/Users/davidmorris/Library/Logs/books-media/eject-app.log"
	
	-- Immediate feedback so it doesn't look like a no-op
	display dialog "Stopping Time Machine if needed, then ejecting 25External…" buttons {"Working…"} giving up after 1 with title "Eject Books Drive" with icon note
	
	try
		do shell script "rm -f " & quoted form of statusFile & "; /usr/bin/nohup /bin/zsh " & quoted form of sh & " eject >" & quoted form of logFile & " 2>&1 & echo $!"
		
		set done to false
		set finalStatus to ""
		repeat with i from 1 to 180 -- up to ~6 minutes
			delay 2
			try
				set finalStatus to do shell script "/bin/cat " & quoted form of statusFile
				if finalStatus is "ok" or finalStatus is "partial" then
					set done to true
					exit repeat
				end if
			end try
		end repeat
		
		if not done then
			display alert "Books drive eject timed out" message "Time Machine may still be busy. Open Time Machine settings, wait for the spinner to stop, then try again. Log: ~/Library/Logs/books-media/eject-app.log" buttons {"OK"} default button "OK"
			return
		end if
		
		if finalStatus is "ok" then
			display alert "Safe to unplug" message "25External (and Time Machine on that disk) have been ejected. You can unplug the drive." buttons {"OK"} default button "OK"
		else
			display alert "Eject incomplete" message "Books media was unmounted, but the disk is still busy — usually Time Machine (spinner next to Time Machine in Finder). Wait for that to finish, then click Eject Books Drive again." buttons {"OK"} default button "OK"
		end if
	on error errMsg number errNum
		display alert "Books drive eject failed" message errMsg as critical buttons {"OK"} default button "OK"
	end try
end run
