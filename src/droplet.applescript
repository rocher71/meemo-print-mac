property T : "MEEMO Print"
property SITE : "https://rocher71.github.io/meemo-print-mac/"

-- Korean if the Mac's first language is Korean, English otherwise.
on L(ko, en)
	try
		if (do shell script "defaults read -g AppleLanguages | sed -n 2p") contains "ko" then return ko
	end try
	return en
end L

on run
	display dialog L("인쇄할 PDF 파일을 이 아이콘 위에 끌어다 놓으세요." & return & "(프린터 전원 켜기 · 용지 방향 확인)", "Drag a PDF file onto this icon to print it." & return & "(Turn the printer on · check the paper direction)") buttons {"OK"} default button 1 with title T
end run

on open theFiles
	repeat with f in theFiles
		set p to POSIX path of f
		if p does not end with ".pdf" and p does not end with ".PDF" then
			display dialog L("PDF 파일만 인쇄할 수 있어요: ", "Only PDF files can be printed: ") & p buttons {"OK"} default button 1 with title T
		else
			my printOne(p)
		end if
	end repeat
end open

on printOne(p)
	set S to quoted form of ((POSIX path of (path to me)) & "Contents/Resources/")
	set fname to do shell script "basename " & quoted form of p
	-- Check driver, Rosetta, pairing and the PDF before asking anything.
	try
		set total to do shell script "VALIDATE=1 " & S & "print_pdf.sh " & quoted form of p
	on error errMsg number errNum
		my explain(errMsg, errNum)
		return
	end try
	set allItem to L("전체 인쇄 (" & total & "쪽)", "Print all (" & total & " pages)")
	set someItem to L("쪽 지정…", "Choose pages…")
	set pick to choose from list {allItem, someItem} with title T with prompt fname & return & L("어떻게 인쇄할까요?", "What would you like to print?") default items {allItem} OK button name L("인쇄", "Print") cancel button name L("취소", "Cancel")
	if pick is false then return
	set spec to "all"
	set n to total
	if item 1 of pick is someItem then
		try
			set spec to text returned of (display dialog L("인쇄할 쪽 (전체 " & total & "쪽)" & return & "예: 3  /  1-3  /  1,4,6-8", "Pages to print (of " & total & ")" & return & "Examples: 3  /  1-3  /  1,4,6-8") default answer "1" buttons {L("취소", "Cancel"), L("인쇄", "Print")} default button 2 cancel button 1 with title T)
			set n to do shell script "VALIDATE=1 " & S & "print_pdf.sh " & quoted form of p & " " & quoted form of spec
		on error errMsg number errNum
			if errNum is not -128 then my explain(errMsg, errNum)
			return
		end try
	end if
	do shell script S & "bg_print.sh " & quoted form of p & " " & quoted form of spec & " > /dev/null 2>&1 &"
	display notification L(n & "장 인쇄 시작 (한 장에 약 1분)", "Printing " & n & " sheet(s), about a minute each") with title T
end printOne

-- Exit codes come from print_pdf.sh: 3 = driver missing, 4 = Rosetta missing.
on explain(errMsg, errNum)
	if errNum is 3 then
		set b to L("설치 방법 보기", "Show me how")
		if button returned of (display dialog errMsg buttons {"OK", b} default button 2 with title T) is b then open location SITE & "#driver"
	else if errNum is 4 then
		set b to L("Rosetta 설치", "Install Rosetta")
		if button returned of (display dialog errMsg & return & return & L("프린터 드라이버를 돌리려면 Apple의 Rosetta가 필요해요. 지금 설치할까요? (맥 암호를 물어봅니다)", "The printer driver needs Apple's Rosetta. Install it now? (You'll be asked for your Mac password)") buttons {L("취소", "Cancel"), b} default button 2 with title T) is b then
			try
				do shell script "/usr/sbin/softwareupdate --install-rosetta --agree-to-license" with administrator privileges
				display dialog L("설치했어요. PDF를 다시 끌어다 놓아 주세요.", "Installed. Drag your PDF onto the icon again.") buttons {"OK"} default button 1 with title T
			on error e
				display dialog e buttons {"OK"} default button 1 with title T
			end try
		end if
	else
		display dialog errMsg buttons {"OK"} default button 1 with title T
	end if
end explain
